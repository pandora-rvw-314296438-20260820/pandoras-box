-- Refresh Meta readiness from existing grants only.
-- The existing owner test route keeps its RPC signature and response contract.
-- No OAuth state, token, permission, provider setting, spend, or write is created.

create or replace function private.pandora_meta_health_failure_v1(
  p_organization_id uuid,
  p_installation_id uuid,
  p_reason text,
  p_http_status integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $$
declare
  v_http_status integer := p_http_status;
  v_now timestamptz := clock_timestamp();
begin
  if p_reason not in (
    'credential_expired',
    'required_scopes_missing',
    'page_identity_missing',
    'page_identity_ambiguous',
    'page_identity_mismatch',
    'ad_account_identity_ambiguous',
    'ad_account_identity_invalid',
    'credential_missing',
    'credential_reference_invalid',
    'page_credential_binding_mismatch',
    'credential_unavailable',
    'provider_user_identity_missing',
    'provider_user_identity_mismatch',
    'provider_scope_readback_incomplete',
    'provider_scope_readback_invalid',
    'provider_scope_mismatch',
    'provider_unavailable',
    'provider_rejected',
    'ad_account_identity_mismatch'
  ) then
    raise exception 'pandora_meta_health_failure_reason_invalid'
      using errcode = '22023';
  end if;
  if v_http_status is not null
    and (v_http_status < 100 or v_http_status > 599) then
    v_http_status := null;
  end if;

  update public.connector_installations
  set status = 'degraded'::public.connector_status,
      configuration = coalesce(configuration, '{}'::jsonb)
        || jsonb_build_object(
          'credential_status', 'verification_failed',
          'provider_network_enabled', false,
          'health_error_code', p_reason
        ),
      updated_at = v_now
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta'
    and status in (
      'active'::public.connector_status,
      'degraded'::public.connector_status
    );
  if not found then
    raise exception 'pandora_meta_health_installation_lost'
      using errcode = '40001';
  end if;

  update private.pandora_meta_connections
  set status = 'problem',
      last_http_status = v_http_status,
      last_error = p_reason,
      updated_at = v_now
  where organization_id = p_organization_id
    and status in ('connected', 'problem');
  if not found then
    raise exception 'pandora_meta_health_connection_lost'
      using errcode = '40001';
  end if;

  return jsonb_build_object(
    'ok', false,
    'provider', 'meta',
    'reason', p_reason,
    'httpStatus', v_http_status
  );
end;
$$;

revoke all on function private.pandora_meta_health_failure_v1(
  uuid, uuid, text, integer
) from public, anon, authenticated, service_role;

create or replace function private.pandora_meta_health_finalize_v1(
  p_organization_id uuid,
  p_installation_id uuid,
  p_snapshot jsonb,
  p_reason text,
  p_http_status integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, extensions, pg_temp
as $$
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

  if v_expected_user_secret_id is not null then
    perform 1
    from vault.secrets
    where id = v_expected_user_secret_id
    for share;
  end if;

  if v_expected_page_secret_id is not null
    and v_expected_page_secret_id is distinct from v_expected_user_secret_id then
    perform 1
    from vault.secrets
    where id = v_expected_page_secret_id
    for share;
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
$$;

revoke all on function private.pandora_meta_health_finalize_v1(
  uuid, uuid, jsonb, text, integer
) from public, anon, authenticated, service_role;

create or replace function public.pandora_verify_meta_connection_20260906(
  p_organization_id uuid,
  p_installation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, extensions, auth, pg_temp
as $$
declare
  v_installation public.connector_installations%rowtype;
  v_connection private.pandora_meta_connections%rowtype;
  v_credential public.credential_refs%rowtype;
  v_page_material private.pandora_meta_page_tokens%rowtype;
  v_required text[] := private.pandora_meta_required_scopes_v1();
  v_page_secret_id uuid;
  v_page_token text;
  v_user_token text;
  v_page_id text;
  v_stored_page jsonb;
  v_stored_ad jsonb;
  v_ad_id text;
  v_account_id text;
  v_currency text;
  v_user_response extensions.http_response;
  v_permissions_response extensions.http_response;
  v_page_response extensions.http_response;
  v_ad_response extensions.http_response;
  v_user_body jsonb;
  v_permissions_body jsonb;
  v_page_body jsonb;
  v_ad_body jsonb;
  v_live_permissions jsonb;
  v_live_scope text;
  v_live_count integer;
  v_live_granted integer;
  v_snapshot jsonb;
  v_finalize jsonb;
  v_now timestamptz := clock_timestamp();
begin
  if session_user not in ('postgres', 'service_role', 'supabase_admin')
    and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception 'pandora_meta_verify_service_role_required'
      using errcode = '42501';
  end if;

  select *
  into v_installation
  from public.connector_installations
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta';

  if not found then
    raise exception 'Meta installation not found' using errcode = '22023';
  end if;

  if v_installation.status not in (
    'active'::public.connector_status,
    'degraded'::public.connector_status
  ) then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'installation_inactive'
    );
  end if;

  select *
  into v_connection
  from private.pandora_meta_connections
  where organization_id = p_organization_id;

  if not found or v_connection.status not in ('connected', 'problem') then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'connection_unavailable'
    );
  end if;

  v_page_id := btrim(coalesce(v_installation.external_account_id, ''));

  select *
  into v_credential
  from public.credential_refs
  where organization_id = p_organization_id
    and installation_id = p_installation_id
    and rotation_state = 'current'
  order by key_version desc, updated_at desc
  limit 1;

  select *
  into v_page_material
  from private.pandora_meta_page_tokens
  where organization_id = p_organization_id
    and page_id = v_page_id;

  v_page_secret_id := v_page_material.token_secret_id;

  if v_page_secret_id is not null then
    select decrypted_secret
    into v_page_token
    from vault.decrypted_secrets
    where id = v_page_secret_id
    limit 1;
  end if;

  if v_connection.user_token_secret_id is not null then
    select decrypted_secret
    into v_user_token
    from vault.decrypted_secrets
    where id = v_connection.user_token_secret_id
    limit 1;
  end if;

  v_snapshot := jsonb_build_object(
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

  if v_connection.token_expires_at is null
    or v_connection.token_expires_at <= v_now then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'credential_expired',
      null
    );
  end if;

  if not (
    v_required <@ coalesce(v_connection.scopes, array[]::text[])
    and v_required <@ coalesce(v_installation.scopes, array[]::text[])
  ) then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'required_scopes_missing',
      null
    );
  end if;
  v_page_id := btrim(coalesce(v_installation.external_account_id, ''));
  if v_page_id !~ '^[0-9]+$' then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'page_identity_missing',
      null
    );
  end if;

  if jsonb_typeof(v_connection.pages) <> 'array'
    or jsonb_array_length(v_connection.pages) <> 1 then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'page_identity_ambiguous',
      null
    );
  end if;

  v_stored_page := v_connection.pages->0;
  if jsonb_typeof(v_stored_page) <> 'object'
    or coalesce(v_stored_page->>'id', '') <> v_page_id then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'page_identity_mismatch',
      null
    );
  end if;

  if jsonb_typeof(v_connection.ad_accounts) <> 'array'
    or jsonb_array_length(v_connection.ad_accounts) <> 1 then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'ad_account_identity_ambiguous',
      null
    );
  end if;

  v_stored_ad := v_connection.ad_accounts->0;
  v_ad_id := btrim(coalesce(v_stored_ad->>'id', ''));
  v_account_id := case
    when v_ad_id ~ '^act_[0-9]+$' then substring(v_ad_id from 5)
    else ''
  end;
  v_currency := btrim(coalesce(v_stored_ad->>'currency', ''));
  if jsonb_typeof(v_stored_ad) <> 'object'
    or v_ad_id !~ '^act_[0-9]+$'
    or v_account_id !~ '^[0-9]+$'
    or (
      v_stored_ad ? 'account_id'
      and btrim(coalesce(v_stored_ad->>'account_id', '')) <> v_account_id
    )
    or v_currency !~ '^[A-Z]{3}$' then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'ad_account_identity_invalid',
      null
    );
  end if;

  if v_credential.id is null
    or (
      v_credential.expires_at is not null
      and v_credential.expires_at <= v_now
    ) then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'credential_missing',
      null
    );
  end if;

  if v_credential.secret_ref !~ '^vault://[0-9a-fA-F-]{36}$' then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'credential_reference_invalid',
      null
    );
  end if;

  begin
    v_page_secret_id := substring(v_credential.secret_ref from 9)::uuid;
  exception
    when others then
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'credential_reference_invalid',
        null
      );
  end;

  if v_page_material.organization_id is null
    or v_page_material.token_secret_id <> v_page_secret_id then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'page_credential_binding_mismatch',
      null
    );
  end if;

  if nullif(btrim(coalesce(v_page_token, '')), '') is null
    or nullif(btrim(coalesce(v_user_token, '')), '') is null then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'credential_unavailable',
      null
    );
  end if;

  if btrim(coalesce(v_connection.provider_user_id, '')) = '' then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_user_identity_missing',
      null
    );
  end if;

  begin
    select *
    into v_user_response
    from extensions.http((
      'GET'::extensions.http_method,
      'https://graph.facebook.com/v26.0/me?fields=id'::varchar,
      array[
        extensions.http_header('authorization', 'Bearer ' || v_user_token),
        extensions.http_header('accept', 'application/json'),
        extensions.http_header(
          'user-agent',
          'Pandora-Meta-Existing-Grants-Health/1.0'
        )
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
  exception
    when others then
      v_page_token := null;
      v_user_token := null;
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'provider_unavailable',
        null
      );
  end;

  begin
    v_user_body := nullif(v_user_response.content, '')::jsonb;
  exception
    when others then
      v_user_body := null;
  end;

  if v_user_response.status is distinct from 200
    or coalesce(jsonb_typeof(v_user_body), 'null') <> 'object'
    or coalesce(v_user_body ? 'error', false) then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_rejected',
      v_user_response.status
    );
  end if;

  if coalesce(v_user_body->>'id', '') <> v_connection.provider_user_id then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_user_identity_mismatch',
      v_user_response.status
    );
  end if;

  begin
    select *
    into v_permissions_response
    from extensions.http((
      'GET'::extensions.http_method,
      'https://graph.facebook.com/v26.0/me/permissions?limit=100'::varchar,
      array[
        extensions.http_header('authorization', 'Bearer ' || v_user_token),
        extensions.http_header('accept', 'application/json'),
        extensions.http_header(
          'user-agent',
          'Pandora-Meta-Existing-Grants-Health/1.0'
        )
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
  exception
    when others then
      v_page_token := null;
      v_user_token := null;
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'provider_unavailable',
        null
      );
  end;

  begin
    v_permissions_body := nullif(v_permissions_response.content, '')::jsonb;
  exception
    when others then
      v_permissions_body := null;
  end;

  if v_permissions_response.status is distinct from 200
    or coalesce(jsonb_typeof(v_permissions_body), 'null') <> 'object'
    or coalesce(v_permissions_body ? 'error', false)
    or coalesce(
      jsonb_typeof(v_permissions_body->'data'),
      'null'
    ) <> 'array' then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_rejected',
      v_permissions_response.status
    );
  end if;

  if nullif(v_permissions_body #>> '{paging,next}', '') is not null then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_scope_readback_incomplete',
      v_permissions_response.status
    );
  end if;

  v_live_permissions := v_permissions_body->'data';
  if exists (
    select 1
    from jsonb_array_elements(v_live_permissions) as item(value)
    where jsonb_typeof(item.value) <> 'object'
      or btrim(coalesce(item.value->>'permission', '')) = ''
      or btrim(coalesce(item.value->>'status', '')) = ''
  ) then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_scope_readback_invalid',
      v_permissions_response.status
    );
  end if;

  foreach v_live_scope in array v_required loop
    select
      count(*)::integer,
      count(*) filter (
        where permission.value->>'status' = 'granted'
      )::integer
    into v_live_count, v_live_granted
    from jsonb_array_elements(v_live_permissions) as permission(value)
    where permission.value->>'permission' = v_live_scope;

    if v_live_count <> 1 or v_live_granted <> 1 then
      v_page_token := null;
      v_user_token := null;
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'provider_scope_mismatch',
        v_permissions_response.status
      );
    end if;
  end loop;

  begin
    select *
    into v_page_response
    from extensions.http((
      'GET'::extensions.http_method,
      (
        'https://graph.facebook.com/v26.0/'
        || v_page_id
        || '?fields=id,name'
      )::varchar,
      array[
        extensions.http_header('authorization', 'Bearer ' || v_page_token),
        extensions.http_header('accept', 'application/json'),
        extensions.http_header(
          'user-agent',
          'Pandora-Meta-Existing-Grants-Health/1.0'
        )
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
  exception
    when others then
      v_page_token := null;
      v_user_token := null;
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'provider_unavailable',
        null
      );
  end;

  begin
    v_page_body := nullif(v_page_response.content, '')::jsonb;
  exception
    when others then
      v_page_body := null;
  end;

  if v_page_response.status is distinct from 200
    or coalesce(jsonb_typeof(v_page_body), 'null') <> 'object'
    or coalesce(v_page_body ? 'error', false) then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_rejected',
      v_page_response.status
    );
  end if;
  if coalesce(v_page_body->>'id', '') <> v_page_id then
    v_page_token := null;
    v_user_token := null;
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'page_identity_mismatch',
      v_page_response.status
    );
  end if;

  begin
    select *
    into v_ad_response
    from extensions.http((
      'GET'::extensions.http_method,
      (
        'https://graph.facebook.com/v26.0/'
        || v_ad_id
        || '?fields=id,account_id,name,currency'
      )::varchar,
      array[
        extensions.http_header('authorization', 'Bearer ' || v_user_token),
        extensions.http_header('accept', 'application/json'),
        extensions.http_header(
          'user-agent',
          'Pandora-Meta-Existing-Grants-Health/1.0'
        )
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
  exception
    when others then
      v_page_token := null;
      v_user_token := null;
      return private.pandora_meta_health_finalize_v1(
        p_organization_id,
        p_installation_id,
        v_snapshot,
        'provider_unavailable',
        null
      );
  end;

  begin
    v_ad_body := nullif(v_ad_response.content, '')::jsonb;
  exception
    when others then
      v_ad_body := null;
  end;
  v_page_token := null;
  v_user_token := null;

  if v_ad_response.status is distinct from 200
    or coalesce(jsonb_typeof(v_ad_body), 'null') <> 'object'
    or coalesce(v_ad_body ? 'error', false) then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'provider_rejected',
      v_ad_response.status
    );
  end if;

  if coalesce(v_ad_body->>'id', '') <> v_ad_id
    or coalesce(v_ad_body->>'account_id', '') <> v_account_id
    or coalesce(v_ad_body->>'currency', '') <> v_currency then
    return private.pandora_meta_health_finalize_v1(
      p_organization_id,
      p_installation_id,
      v_snapshot,
      'ad_account_identity_mismatch',
      v_ad_response.status
    );
  end if;

  v_finalize := private.pandora_meta_health_finalize_v1(
    p_organization_id,
    p_installation_id,
    v_snapshot,
    null,
    200
  );
  if coalesce((v_finalize->>'ok')::boolean, false) is not true then
    return v_finalize;
  end if;
  v_now := (v_finalize->>'lockedAt')::timestamptz;

  update public.connector_installations
  set status = 'active'::public.connector_status,
      last_health_check_at = v_now,
      configuration = (
        coalesce(configuration, '{}'::jsonb) - 'health_error_code'
      ) || jsonb_build_object(
          'credential_status', 'verified',
          'provider_network_enabled', true,
          'page_access_verified', true,
          'ad_account_access_verified', true
        ),
      updated_at = v_now
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta';

  update private.pandora_meta_connections
  set status = 'connected',
      last_verified_at = v_now,
      last_http_status = 200,
      last_error = null,
      updated_at = v_now
  where organization_id = p_organization_id
    and status in ('connected', 'problem');

  if not found then
    raise exception 'pandora_meta_connection_refresh_lost'
      using errcode = '40001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'provider', 'meta',
    'status', 'ACTIVE_HEALTHY',
    'pageId', v_page_id,
    'pageName', nullif(v_page_body->>'name', ''),
    'adAccountId', v_ad_id,
    'currency', v_currency,
    'checkedAt', v_now,
    'appOwnershipVerified',
      coalesce(
        v_installation.configuration->'app_ownership_verified' = 'true'::jsonb,
        false
      )
  );
end;
$$;

revoke all on function public.pandora_verify_meta_connection_20260906(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pandora_verify_meta_connection_20260906(uuid, uuid)
  to service_role;

comment on function public.pandora_verify_meta_connection_20260906(uuid, uuid)
is 'Service-only Meta health refresh from existing grants. Exact live user, complete required permissions, Page, ad-account, and unchanged state must pass before health timestamps advance.';

