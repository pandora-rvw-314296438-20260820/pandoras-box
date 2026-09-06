-- Verify the current Meta Page connection through the exact Vault-backed
-- credential reference bound to the connector installation. No credential
-- material is returned, logged, or persisted outside Vault.
create or replace function public.pandora_verify_meta_connection_20260906(
  p_organization_id uuid,
  p_installation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'vault', 'extensions'
as $$
declare
  v_installation public.connector_installations%rowtype;
  v_credential public.credential_refs%rowtype;
  v_secret_id uuid;
  v_token text;
  v_page_id text;
  v_response extensions.http_response;
  v_body jsonb;
  v_now timestamptz := timezone('utc', now());
begin
  select *
  into v_installation
  from public.connector_installations
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta'
  for update;

  if not found then
    raise exception 'Meta installation not found' using errcode = '22023';
  end if;

  v_page_id := btrim(coalesce(v_installation.external_account_id, ''));
  if v_page_id !~ '^[0-9]+$' then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'reason', 'page_identity_missing'
    );
  end if;

  select *
  into v_credential
  from public.credential_refs
  where organization_id = p_organization_id
    and installation_id = p_installation_id
    and rotation_state = 'current'
    and (expires_at is null or expires_at > v_now)
  order by key_version desc, updated_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'credential_missing'
    );
  end if;

  if v_credential.secret_ref !~ '^vault://[0-9a-fA-F-]{36}$' then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'credential_reference_invalid'
    );
  end if;

  begin
    v_secret_id := substring(v_credential.secret_ref from 9)::uuid;
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'credential_reference_invalid'
    );
  end;

  select decrypted_secret
  into v_token
  from vault.decrypted_secrets
  where id = v_secret_id
  limit 1;

  if nullif(btrim(coalesce(v_token, '')), '') is null then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'credential_unavailable'
    );
  end if;

  select *
  into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/' || v_page_id || '?fields=id,name')::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('user-agent', 'Pandora-Meta-Connection-Verify/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  begin
    v_body := coalesce(nullif(v_response.content, '')::jsonb, '{}'::jsonb);
  exception when others then
    v_body := '{}'::jsonb;
  end;

  v_token := null;

  if v_response.status <> 200 or v_body ? 'error' then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'provider_rejected',
      'httpStatus', v_response.status
    );
  end if;

  if coalesce(v_body->>'id', '') <> v_page_id then
    return jsonb_build_object(
      'ok', false,
      'provider', 'meta',
      'pageId', v_page_id,
      'reason', 'page_identity_mismatch'
    );
  end if;

  update public.connector_installations
  set status = 'active'::public.connector_status,
      last_health_check_at = v_now,
      configuration = coalesce(configuration, '{}'::jsonb) || jsonb_build_object(
        'credential_status', 'verified',
        'provider_network_enabled', true,
        'page_access_verified', true
      ),
      updated_at = v_now
  where id = p_installation_id
    and organization_id = p_organization_id
    and provider = 'meta';

  return jsonb_build_object(
    'ok', true,
    'provider', 'meta',
    'status', 'ACTIVE_HEALTHY',
    'pageId', v_page_id,
    'pageName', nullif(v_body->>'name', ''),
    'checkedAt', v_now,
    'appOwnershipVerified',
      coalesce((v_installation.configuration->>'app_ownership_verified')::boolean, false)
  );
end;
$$;

revoke all on function public.pandora_verify_meta_connection_20260906(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pandora_verify_meta_connection_20260906(uuid, uuid)
  to service_role;
