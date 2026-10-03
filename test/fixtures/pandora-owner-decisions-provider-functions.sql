-- Synthetic Vault marker IDs only; no secret column or credential material.
create schema vault;
create table vault.secrets(id uuid primary key);
-- Minimal canonical paid-pilot columns, used only to prove an old Operations
-- marker neither supersedes nor mutates a stopped commercial authorization.
create table private.pandora_meta_paid_pilot_authorizations(
 id uuid primary key,organization_id uuid not null,project_id uuid not null,
 state text not null check(state in ('approved','prepared','active','stopped','completed','failed'))
);
create table if not exists public.pandora_provider_manifests (
  provider_key text not null
    check (provider_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  manifest_version text not null
    check (manifest_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  display_name text not null check (char_length(display_name) between 1 and 200),
  lifecycle_state text not null default 'catalog'
    check (lifecycle_state in ('catalog','active','deprecated','retired')),
  auth_scheme text not null,
  regions text[] not null check (cardinality(regions)>0),
  data_residency text[] not null check (cardinality(data_residency)>0),
  data_handling jsonb not null check (jsonb_typeof(data_handling)='object'),
  deprecation_policy jsonb not null check (jsonb_typeof(deprecation_policy)='object'),
  runbook_ref text not null,
  escalation_ref text not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(provider_key,manifest_version)
);
create table if not exists private.pandora_connection_manifest_contracts_v1 (
  provider_key text not null,
  manifest_version text not null,
  auth jsonb not null,
  scopes jsonb not null,
  callback jsonb not null,
  health jsonb not null,
  capabilities jsonb not null,
  risk_class text not null check (risk_class in ('low','medium','high','critical')),
  account_identity jsonb not null,
  credential_policy jsonb not null,
  write_authorization jsonb not null,
  residency_policy jsonb not null,
  recovery jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  primary key (provider_key, manifest_version),
  foreign key (provider_key, manifest_version)
    references public.pandora_provider_manifests(provider_key, manifest_version),
  check (jsonb_typeof(auth)='object'),
  check (jsonb_typeof(scopes)='object'),
  check (jsonb_typeof(callback)='object'),
  check (jsonb_typeof(health)='object'),
  check (jsonb_typeof(capabilities)='array'),
  check (jsonb_typeof(account_identity)='object'),
  check (jsonb_typeof(credential_policy)='object'),
  check (jsonb_typeof(write_authorization)='object'),
  check (jsonb_typeof(residency_policy)='object'),
  check (jsonb_typeof(recovery)='object')
);
-- Exact provider function definitions read back 2026-10-03. Synthetic surrounding schema is declared by the test.
-- Body SHA256 77edcef4e95f1ac01fe7f4fb6bf09e0485a5a2abf1a34a88aa3fc567e0bbfcf6
CREATE OR REPLACE FUNCTION private.pandora_connection_reconcile_health_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'extensions', 'pg_temp'
AS $function$
declare
  v_row record;
  v_count integer:=0;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  for v_row in
    update private.pandora_connection_accounts_v1 a set
      status='needs_attention',
      health_state='unhealthy',
      failure_code=case
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp()
          then 'CREDENTIAL_EXPIRED'
        when a.rotation_due_at is null or a.rotation_due_at<=clock_timestamp()
          then 'CREDENTIAL_ROTATION_DUE'
        when a.last_verified_at is null
          or a.last_verified_at>clock_timestamp()+interval '1 minute'
          or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          then 'PROVIDER_READBACK_STALE'
        when not (
          private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)
        )
          then 'REQUIRED_SCOPES_MISSING'
        when not (
          private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)
        )
          then 'REQUIRED_CAPABILITIES_MISSING'
        when a.provider_readback_hash is null
          or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
          or a.metadata_redacted->>'probe'<>c.health->>'probe'
          or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
          then 'PROVIDER_READBACK_UNVERIFIED'
        else 'CREDENTIAL_UNAVAILABLE'
      end,
      updated_at=clock_timestamp()
    from private.pandora_connection_manifest_contracts_v1 c
    where a.provider_key=c.provider_key
      and a.manifest_version=c.manifest_version
      and a.status='connected'
      and a.revoked_at is null
      and (
        (a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp())
        or a.rotation_due_at is null
        or a.rotation_due_at<=clock_timestamp()
        or a.last_verified_at is null
        or a.last_verified_at>clock_timestamp()+interval '1 minute'
        or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
        or not (
          private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)
        )
        or not (
          private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)
        )
        or a.provider_readback_hash is null
        or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
        or a.metadata_redacted->>'probe'<>c.health->>'probe'
        or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
        or not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id)
      )
    returning a.*
  loop
    v_count:=v_count+1;
    perform private.append_audit_event(
      v_row.organization_id,null,null,'provider'::public.audit_actor_type,null,
      'connection.health_needs_attention',
      jsonb_build_object(
        'provider',v_row.provider_key,
        'connection_id',v_row.id,
        'tenant_key',v_row.tenant_key,
        'failure_code',v_row.failure_code
      )
    );
  end loop;
  return jsonb_build_object('ok',true,'reconciled',v_count,'observedAt',clock_timestamp());
end; $function$
;
-- Body SHA256 de27ca0d41e5b4b5ab00d6c1d82eefe88b66651a64872e0d1b4c9273cc12192c
CREATE OR REPLACE FUNCTION private.pandora_connection_required_capabilities_v1(p_provider_key text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(item->>'key' order by ord),array[]::text[])
  from private.pandora_connection_manifest_contracts_v1 c,
       jsonb_array_elements(c.capabilities) with ordinality x(item,ord)
  where c.provider_key=p_provider_key
    and c.manifest_version='1.0.0'
    and item->>'mode'<>'write';
$function$
;
-- Body SHA256 c700d4dd5dd1d545b6e9524e299595db7e2b773afc711b47461eb821d8629ac6
CREATE OR REPLACE FUNCTION private.pandora_connection_required_scopes_v1(p_provider_key text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(value order by ord),array[]::text[])
  from private.pandora_connection_manifest_contracts_v1 c,
       jsonb_array_elements_text(c.scopes->'required') with ordinality s(value,ord)
  where c.provider_key=p_provider_key and c.manifest_version='1.0.0';
$function$
;
-- Body SHA256 c1015337d57b16f02f7b715b0f7b70f401eca129b978a23fda26070ecdf1760c
CREATE OR REPLACE FUNCTION public.pandora_live_connections_v1(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'auth', 'pg_temp'
AS $function$
declare v_uid uuid:=auth.uid(); v_rows jsonb;
begin
  if v_uid is null or not private.is_org_member(p_organization_id) then
    raise exception 'pandora_connection_membership_required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(row_json order by row_json->>'provider'),'[]'::jsonb)
  into v_rows
  from (
    select jsonb_build_object(
      'provider',c.provider_key,
      'displayName',m.display_name,
      'riskClass',c.risk_class,
      'state',case
        when a.id is null then 'Needs authorization'
        when a.revoked_at is not null or a.status='revoked' then 'Needs attention'
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp() then 'Needs attention'
        when a.rotation_due_at is null or a.rotation_due_at<=clock_timestamp() then 'Needs attention'
        when a.health_state<>'healthy' then 'Needs attention'
        when a.last_verified_at is null
          or a.last_verified_at>clock_timestamp()+interval '1 minute'
          or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          then 'Needs attention'
        when not (
          private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        ) then 'Needs attention'
        when not (
          private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        ) then 'Needs attention'
        when a.provider_readback_hash is null
          or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
          or a.metadata_redacted->>'probe'<>c.health->>'probe'
          or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
          then 'Needs attention'
        when not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id) then 'Needs attention'
        else 'Connected'
      end,
      'connected',coalesce(
        a.id is not null
        and a.revoked_at is null
        and a.status='connected'
        and a.health_state='healthy'
        and (a.credential_expires_at is null or a.credential_expires_at>clock_timestamp())
        and a.rotation_due_at>clock_timestamp()
        and a.last_verified_at between
          clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          and clock_timestamp()+interval '1 minute'
        and private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
        and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        and private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
        and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        and cardinality(private.pandora_connection_required_capabilities_v1(c.provider_key))>0
        and a.provider_readback_hash is not null
        and a.metadata_redacted->>'verifiedBy'='provider_readback'
        and a.metadata_redacted->>'probe'=c.health->>'probe'
        and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
        and exists(select 1 from vault.secrets s where s.id=a.credential_secret_id),
        false
      ),
      'activeAccount',case when a.id is null then null else jsonb_build_object(
        'id',a.id,
        'label',a.account_label,
        'tenantId',a.organization_id,
        'tenantKey',a.tenant_key,
        'tenant',a.tenant_label,
        'scopes',to_jsonb(a.granted_scopes),
        'capabilities',to_jsonb(a.granted_capabilities),
        'lastVerifiedAt',a.last_verified_at,
        'expiresAt',a.credential_expires_at,
        'rotationDueAt',a.rotation_due_at,
        'health',a.health_state,
        'failureCode',a.failure_code,
        'providerReadbackVerified',
          a.provider_readback_hash is not null
          and a.metadata_redacted->>'verifiedBy'='provider_readback'
          and a.metadata_redacted->>'probe'=c.health->>'probe'
          and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
      ) end,
      'accounts',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',aa.id,
          'label',aa.account_label,
          'tenantId',aa.organization_id,
          'tenantKey',aa.tenant_key,
          'tenant',aa.tenant_label,
          'selected',aa.id=a.id and aa.tenant_key=s.tenant_key,
          'health',aa.health_state,
          'lastVerifiedAt',aa.last_verified_at,
          'expiresAt',aa.credential_expires_at,
          'rotationDueAt',aa.rotation_due_at
        ) order by aa.account_label)
        from private.pandora_connection_accounts_v1 aa
        where aa.organization_id=p_organization_id
          and aa.provider_key=c.provider_key
          and aa.revoked_at is null
      ),'[]'::jsonb),
      'requiredScopes',to_jsonb(private.pandora_connection_required_scopes_v1(c.provider_key)),
      'requiredCapabilities',to_jsonb(private.pandora_connection_required_capabilities_v1(c.provider_key)),
      'healthContract',c.health,
      'recovery',c.recovery,
      'writeAuthorization',c.write_authorization,
      'authority','live_provider_readback'
    ) row_json
    from private.pandora_connection_manifest_contracts_v1 c
    join public.pandora_provider_manifests m using(provider_key,manifest_version)
    left join private.pandora_connection_active_accounts_v1 s
      on s.organization_id=p_organization_id and s.provider_key=c.provider_key
    left join private.pandora_connection_accounts_v1 a
      on a.id=s.connection_id
      and a.organization_id=s.organization_id
      and a.provider_key=s.provider_key
      and a.tenant_key=s.tenant_key
    where m.lifecycle_state='active'
  ) projected;
  return jsonb_build_object(
    'contractVersion','pandora-live-connections-v1',
    'organizationId',p_organization_id,
    'observedAt',clock_timestamp(),
    'authority','live_connections_not_catalog',
    'providers',v_rows
  );
end; $function$
;
revoke all on function private.pandora_connection_reconcile_health_v1(),private.pandora_connection_required_capabilities_v1(text) from public,anon,authenticated,service_role;
revoke all on function public.pandora_live_connections_v1(uuid) from public,anon;
grant execute on function public.pandora_live_connections_v1(uuid) to authenticated,service_role;

-- Minimal canonical catalog projection columns, types read from production; no live model rows.
create table private.pandora_bedrock_reasoning_catalog(
 model_id text not null,
 model_name text not null,
 provider_name text not null,
 invocation_target text,
 input_modalities text[] not null,
 observed_at timestamp with time zone not null,
 runtime_reason text,
 region text default 'us-east-1'::text not null,
 lifecycle_status text default 'UNKNOWN'::text not null,
 conversational boolean default false not null,
 present_in_latest_sync boolean default true not null,
 runtime_verification_status text default 'untested'::text not null,
 runtime_tested_at timestamp with time zone,
 routable boolean default false not null
);
alter table private.pandora_bedrock_reasoning_catalog enable row level security;
CREATE OR REPLACE FUNCTION public.pandora_bedrock_chat_routing_config_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'pg_temp'
AS $function$
declare v_role text;v_models jsonb;v_image_models jsonb;v_default text;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
  select
    coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id),'[]'::jsonb),
    coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id) filter(where 'IMAGE'=any(c.input_modalities)),'[]'::jsonb),
    (array_agg(c.model_id order by c.provider_name,c.model_name,c.model_id))[1]
  into v_models,v_image_models,v_default
  from private.pandora_bedrock_reasoning_catalog c
  where c.routable=true and c.conversational=true and c.present_in_latest_sync=true
    and c.runtime_verification_status='passed' and c.lifecycle_status='ACTIVE'
    and nullif(c.invocation_target,'') is not null;
  return jsonb_build_object('enabled',v_default is not null,'routingEligible',v_default is not null,'fallbackEnabled',true,'model',v_default,'allowedModels',v_models,'imageModels',v_image_models,'policyVersion','bedrock-live-catalog-chat-v1','streamMode','buffered_v1');
end;$function$
;
revoke all on function public.pandora_bedrock_chat_routing_config_v1() from public,anon,authenticated;
grant execute on function public.pandora_bedrock_chat_routing_config_v1() to service_role;
