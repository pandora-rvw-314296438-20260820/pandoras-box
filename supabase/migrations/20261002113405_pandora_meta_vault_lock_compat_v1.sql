-- Repair Meta live verification under Supabase Vault's read-only table ACL.
-- Preserve the verifier's TOCTOU protection without granting UPDATE on Vault.

CREATE OR REPLACE FUNCTION private.pandora_meta_health_finalize_v1(p_organization_id uuid, p_installation_id uuid, p_snapshot jsonb, p_reason text, p_http_status integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'extensions', 'pg_temp'
AS $function$
declare
  v_installation public.connector_installations%rowtype;
  v_connection private.pandora_meta_connections%rowtype;
  v_credential public.credential_refs%rowtype;
  v_page_material private.pandora_meta_page_tokens%rowtype;
  v_expected_user_secret_id uuid;
  v_expected_page_secret_id uuid;
  v_expected_credential_id uuid;
  v_expected_page_id text;
  v_page_token text;
  v_user_token text;
  v_current_snapshot jsonb;
  v_lock_now timestamptz;
begin
  begin
    v_expected_user_secret_id :=
      nullif(p_snapshot #>> '{connection,user_token_secret_id}', '')::uuid;
    v_expected_page_secret_id :=
      nullif(p_snapshot #>> '{pageMaterial,token_secret_id}', '')::uuid;
    v_expected_credential_id :=
      nullif(p_snapshot #>> '{credential,id}', '')::uuid;
    v_expected_page_id :=
      nullif(p_snapshot #>> '{installation,external_account_id}', '');
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'provider', 'meta',
        'reason', 'health_state_changed'
      );
  end;

  if v_expected_user_secret_id is not null
    or v_expected_page_secret_id is not null then
    -- Supabase Vault intentionally grants read-only access on vault.secrets
    -- to the function owner. Row-lock clauses require UPDATE privilege and
    -- therefore fail in production. A short table SHARE lock preserves the
    -- same no-rotation window without expanding Vault write privileges.
    lock table vault.secrets in share mode;
  end if;

  if v_expected_page_id is not null then
    select *
    into v_page_material
    from private.pandora_meta_page_tokens
    where organization_id = p_organization_id
      and page_id = v_expected_page_id
    for share;
  end if;

  select *
  into v_installation
  from public.connector_installations
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta'
    and status in (
      'active'::public.connector_status,
      'degraded'::public.connector_status
    )
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'health_state_changed'
    );
  end if;

  if v_expected_credential_id is not null then
    select *
    into v_credential
    from public.credential_refs
    where id = v_expected_credential_id
      and organization_id = p_organization_id
      and installation_id = p_installation_id
      and rotation_state = 'current'
    for share;
  else
    select *
    into v_credential
    from public.credential_refs
    where organization_id = p_organization_id
      and installation_id = p_installation_id
      and rotation_state = 'current'
    order by key_version desc, updated_at desc
    limit 1
    for share;
  end if;

  select *
  into v_connection
  from private.pandora_meta_connections
  where organization_id = p_organization_id
    and status in ('connected', 'problem')
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'health_state_changed'
    );
  end if;

  if v_page_material.organization_id is null
    and v_expected_page_id is not null then
    select *
    into v_page_material
    from private.pandora_meta_page_tokens
    where organization_id = p_organization_id
      and page_id = v_expected_page_id;
  end if;

  v_lock_now := clock_timestamp();

  if v_connection.user_token_secret_id is not null then
    select decrypted_secret
    into v_user_token
    from vault.decrypted_secrets
    where id = v_connection.user_token_secret_id
    limit 1;
  end if;

  if v_page_material.token_secret_id is not null then
    select decrypted_secret
    into v_page_token
    from vault.decrypted_secrets
    where id = v_page_material.token_secret_id
    limit 1;
  end if;

  v_current_snapshot := jsonb_build_object(
    'installation', to_jsonb(v_installation),
    'connection', to_jsonb(v_connection),
    'credential', to_jsonb(v_credential),
    'pageMaterial', to_jsonb(v_page_material),
    'pageTokenDigest', case
      when v_page_token is null then null
      else encode(
        extensions.digest(convert_to(v_page_token, 'UTF8'), 'sha256'),
        'hex'
      )
    end,
    'userTokenDigest', case
      when v_user_token is null then null
      else encode(
        extensions.digest(convert_to(v_user_token, 'UTF8'), 'sha256'),
        'hex'
      )
    end
  );
  v_page_token := null;
  v_user_token := null;

  if v_current_snapshot is distinct from p_snapshot then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'health_state_changed'
    );
  end if;

  if (
    v_credential.id is null
    or (
      v_credential.expires_at is not null
      and v_credential.expires_at <= v_lock_now
    )
  ) and p_reason is null then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'health_state_changed'
    );
  end if;

  if (
    v_connection.token_expires_at is null
    or v_connection.token_expires_at <= v_lock_now
  ) and p_reason is null then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'health_state_changed'
    );
  end if;

  if p_reason is not null then
    return private.pandora_meta_health_failure_v1(
      p_organization_id,
      p_installation_id,
      p_reason,
      p_http_status
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'provider', 'meta',
    'lockedAt', v_lock_now
  );
end;
$function$;

revoke all on function private.pandora_meta_health_finalize_v1(
  uuid, uuid, jsonb, text, integer
) from public, anon, authenticated, service_role;
