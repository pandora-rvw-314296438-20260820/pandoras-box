-- FB-014: generation-fenced local Meta disconnect.
-- This operation disables Pandora's local runtime authority only. It never calls Meta,
-- deletes Vault material, widens scopes, or claims provider-side token revocation.

create or replace function public.pandora_meta_disconnect_local_v1(
  p_organization_id uuid,
  p_installation_id uuid,
  p_expected_key_version integer,
  p_actor_id uuid,
  p_evidence_ref text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth','pg_temp'
as $fn$
declare
  v_install public.connector_installations%rowtype;
  v_credential public.credential_refs%rowtype;
  v_connection private.pandora_meta_connections%rowtype;
  v_now timestamptz := clock_timestamp();
  v_other_active integer := 0;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_DISCONNECT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_organization_id is null or p_installation_id is null or p_actor_id is null
     or p_expected_key_version is null or p_expected_key_version < 1
     or nullif(btrim(coalesce(p_evidence_ref,'')),'') is null
     or length(p_evidence_ref) > 500
     or p_evidence_ref ~* '(authorization|bearer|api[_-]?key|secret[_-]?value|token=)' then
    raise exception 'PANDORA_META_DISCONNECT_INPUT_INVALID' using errcode='22023';
  end if;

  perform 1
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=p_actor_id
    and m.status='active'
    and m.role in ('owner','admin')
  for share;
  if not found then
    raise exception 'PANDORA_META_DISCONNECT_OWNER_REQUIRED' using errcode='42501';
  end if;

  select * into v_install
  from public.connector_installations i
  where i.id=p_installation_id
    and i.organization_id=p_organization_id
    and i.provider='meta'
  for update;
  if not found or v_install.status<>'active'::public.connector_status then
    raise exception 'PANDORA_META_DISCONNECT_INSTALLATION_FENCED' using errcode='42501';
  end if;

  select * into v_credential
  from public.credential_refs c
  where c.organization_id=p_organization_id
    and c.installation_id=p_installation_id
    and c.rotation_state='current'::public.rotation_status
  order by c.key_version desc
  limit 1
  for update;
  if not found or v_credential.key_version is distinct from p_expected_key_version then
    raise exception 'PANDORA_META_DISCONNECT_GENERATION_FENCED' using errcode='40001';
  end if;

  select * into v_connection
  from private.pandora_meta_connections c
  where c.organization_id=p_organization_id
  for update;
  if not found or v_connection.status<>'connected' then
    raise exception 'PANDORA_META_DISCONNECT_CONNECTION_FENCED' using errcode='42501';
  end if;

  select count(*) into v_other_active
  from public.connector_installations i
  where i.organization_id=p_organization_id
    and i.provider='meta'
    and i.id<>p_installation_id
    and i.status='active'::public.connector_status;
  if v_other_active<>0 then
    raise exception 'PANDORA_META_DISCONNECT_MULTI_INSTALLATION_REQUIRES_EXPLICIT_SCOPE'
      using errcode='42501';
  end if;

  update public.credential_refs
     set rotation_state='revoked'::public.rotation_status,
         updated_at=v_now
   where id=v_credential.id
     and organization_id=p_organization_id
     and installation_id=p_installation_id
     and key_version=p_expected_key_version
     and rotation_state='current'::public.rotation_status;
  if not found then
    raise exception 'PANDORA_META_DISCONNECT_GENERATION_FENCED' using errcode='40001';
  end if;

  update public.connector_installations
     set status='revoked'::public.connector_status,
         last_health_check_at=v_now,
         configuration=coalesce(configuration,'{}'::jsonb) || jsonb_build_object(
           'local_disconnect',jsonb_build_object(
             'credentialGeneration',p_expected_key_version,
             'evidenceRef',p_evidence_ref,
             'occurredAt',v_now
           )
         ),
         updated_at=v_now
   where id=p_installation_id
     and organization_id=p_organization_id
     and provider='meta'
     and status='active'::public.connector_status;
  if not found then
    raise exception 'PANDORA_META_DISCONNECT_INSTALLATION_FENCED' using errcode='40001';
  end if;

  update private.pandora_meta_connections
     set status='revoked',
         last_verified_at=v_now,
         last_http_status=null,
         last_error='locally_disconnected',
         updated_at=v_now
   where organization_id=p_organization_id
     and status='connected';
  if not found then
    raise exception 'PANDORA_META_DISCONNECT_CONNECTION_FENCED' using errcode='40001';
  end if;

  return jsonb_build_object(
    'ok',true,
    'provider','meta',
    'organizationId',p_organization_id,
    'installationId',p_installation_id,
    'state','revoked',
    'credentialGeneration',p_expected_key_version,
    'providerRevocationAttempted',false,
    'vaultMaterialDeleted',false,
    'evidenceRef',p_evidence_ref,
    'occurredAt',v_now
  );
end;
$fn$;

revoke all on function public.pandora_meta_disconnect_local_v1(uuid,uuid,integer,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_disconnect_local_v1(uuid,uuid,integer,uuid,text)
  to service_role;

comment on function public.pandora_meta_disconnect_local_v1(uuid,uuid,integer,uuid,text) is
  'FB-014 service-only, owner/admin-bound, credential-generation-fenced local Meta disconnect. Revokes Pandora runtime authority atomically without provider mutation or Vault deletion. Reconnect remains a fresh OAuth commit that restores active/current/connected state and increments credential generation.';
