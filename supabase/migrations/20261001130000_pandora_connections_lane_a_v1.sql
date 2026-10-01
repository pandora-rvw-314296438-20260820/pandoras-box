-- Pandora Universal Connections, Lane A (Phase 0 + Phase 1 P0)
-- Fail closed: a catalog row or credential reference never implies Connected.

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

create table if not exists private.pandora_connection_oauth_states_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_key text not null,
  state_hash text not null unique check (state_hash ~ '^[0-9a-f]{64}$'),
  nonce_hash text not null check (nonce_hash ~ '^[0-9a-f]{64}$'),
  code_verifier text not null check (length(code_verifier) between 43 and 128),
  callback_mode text not null check (callback_mode in ('web','mobile')),
  return_uri text not null,
  required_scopes text[] not null,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (expires_at > created_at)
);

create table if not exists private.pandora_connection_accounts_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null,
  manifest_version text not null,
  connected_by uuid not null references auth.users(id),
  account_subject_hash text not null check (account_subject_hash ~ '^[0-9a-f]{64}$'),
  account_label text not null check (length(account_label) between 1 and 320),
  tenant_key text not null check (length(tenant_key) between 1 and 320),
  tenant_label text,
  credential_secret_id uuid not null,
  credential_version integer not null default 1 check (credential_version > 0),
  granted_scopes text[] not null default array[]::text[],
  granted_capabilities text[] not null default array[]::text[],
  status text not null default 'connected'
    check (status in ('connected','needs_attention','revoked')),
  health_state text not null default 'unknown'
    check (health_state in ('healthy','degraded','unhealthy','unknown')),
  last_verified_at timestamptz,
  credential_expires_at timestamptz,
  rotation_due_at timestamptz,
  revoked_at timestamptz,
  failure_code text,
  provider_readback_hash text check (provider_readback_hash is null or provider_readback_hash ~ '^[0-9a-f]{64}$'),
  metadata_redacted jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata_redacted)='object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (provider_key, manifest_version)
    references private.pandora_connection_manifest_contracts_v1(provider_key, manifest_version),
  unique (organization_id, provider_key, account_subject_hash, tenant_key),
  unique (id, organization_id, provider_key, tenant_key)
);

create table if not exists private.pandora_connection_active_accounts_v1 (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null,
  connection_id uuid not null references private.pandora_connection_accounts_v1(id) on delete cascade,
  tenant_key text not null check (length(tenant_key) between 1 and 320),
  selected_by uuid not null references auth.users(id),
  selected_at timestamptz not null default clock_timestamp(),
  primary key (organization_id, provider_key),
  foreign key (connection_id, organization_id, provider_key, tenant_key)
    references private.pandora_connection_accounts_v1(id, organization_id, provider_key, tenant_key)
);

create table if not exists private.pandora_connection_write_approvals_v1 (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_key text not null check (provider_key in ('supabase','vercel')),
  connection_id uuid not null,
  tenant_key text not null check (length(tenant_key) between 1 and 320),
  requested_by uuid not null references auth.users(id),
  operation text not null check (operation ~ '^[a-z][a-z0-9_.-]{2,79}$'),
  target_preview jsonb not null check (jsonb_typeof(target_preview)='object'),
  target_hash text not null check (target_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check (status in ('pending','approved','consumed','expired','revoked')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  consumed_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id, provider_key, connection_id, tenant_key, target_hash, status),
  foreign key (connection_id, organization_id, provider_key, tenant_key)
    references private.pandora_connection_accounts_v1(id, organization_id, provider_key, tenant_key),
  check (octet_length(target_preview::text) <= 8192)
);

create index if not exists pandora_connection_accounts_org_provider_v1
  on private.pandora_connection_accounts_v1(organization_id,provider_key,status,last_verified_at desc);
create index if not exists pandora_connection_oauth_expiry_v1
  on private.pandora_connection_oauth_states_v1(expires_at) where consumed_at is null;
create index if not exists pandora_connection_write_approval_expiry_v1
  on private.pandora_connection_write_approvals_v1(expires_at) where consumed_at is null;

alter table private.pandora_connection_manifest_contracts_v1 enable row level security;
alter table private.pandora_connection_oauth_states_v1 enable row level security;
alter table private.pandora_connection_accounts_v1 enable row level security;
alter table private.pandora_connection_active_accounts_v1 enable row level security;
alter table private.pandora_connection_write_approvals_v1 enable row level security;

revoke all on private.pandora_connection_manifest_contracts_v1 from public, anon, authenticated;
revoke all on private.pandora_connection_oauth_states_v1 from public, anon, authenticated;
revoke all on private.pandora_connection_accounts_v1 from public, anon, authenticated;
revoke all on private.pandora_connection_active_accounts_v1 from public, anon, authenticated;
revoke all on private.pandora_connection_write_approvals_v1 from public, anon, authenticated;

create or replace function private.pandora_connection_contract_immutable_v1()
returns trigger language plpgsql set search_path='' as $$
begin
  raise exception 'pandora_connection_manifest_contracts_are_immutable' using errcode='55000';
end; $$;

drop trigger if exists pandora_connection_contract_immutable_v1 on private.pandora_connection_manifest_contracts_v1;
create trigger pandora_connection_contract_immutable_v1
before update or delete on private.pandora_connection_manifest_contracts_v1
for each row execute function private.pandora_connection_contract_immutable_v1();

insert into private.pandora_connection_manifest_contracts_v1(
  provider_key,manifest_version,auth,scopes,callback,health,capabilities,risk_class,
  account_identity,credential_policy,write_authorization,residency_policy,recovery
) values
(
  'google_workspace','1.0.0',
  '{"type":"oidc","pkce":"S256","state":true,"nonce":true}'::jsonb,
  '{"required":["openid","email","profile","https://www.googleapis.com/auth/drive.metadata.readonly","https://www.googleapis.com/auth/spreadsheets.readonly"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":"https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-google-workspace-oauth/callback","mobile":{"launch":"secure_custom_tab","return":["app_link","universal_link"]}}'::jsonb,
  '{"probe":"drive.about.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"drive.metadata.read","mode":"read"},{"key":"sheets.values.read","mode":"read"}]'::jsonb,
  'medium','{"subject":"oidc.sub","label":"email","tenant":"hd","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":true,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"provider_managed","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"deniedScope":"show_missing_scopes","cancel":"no_state_change"}'::jsonb
),
(
  'posthog','1.0.0',
  '{"type":"api_key","credential":"personal_api_key"}'::jsonb,
  '{"required":["project.read"],"optional":[],"leastPrivilege":"read-first","ingestTokenIsNotQueryAuthority":true}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"projects.get","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"project.read","mode":"read"},{"key":"insights.read","mode":"read"}]'::jsonb,
  'medium','{"subject":"project.id","label":"project.name","tenant":"host","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":false,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"tenant_selected","allowedHosts":["https://us.posthog.com","https://eu.posthog.com"]}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'meta','1.0.0',
  '{"type":"oauth2","pkce":"S256","state":true,"nonce":true}'::jsonb,
  '{"required":["pages_show_list","pages_read_engagement","ads_read"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":"https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-meta-oauth/callback","mobile":{"launch":"secure_custom_tab","return":["app_link","universal_link"]}}'::jsonb,
  '{"probe":"me.accounts.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"pages.read","mode":"read"},{"key":"ads.read","mode":"read"}]'::jsonb,
  'high','{"subject":"user.id","label":"user.name","tenant":"page_or_ad_account","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":true,"revoke":true,"rotationDays":60}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"provider_managed","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"expired":"reconnect","revoked":"reconnect","deniedScope":"show_missing_scopes"}'::jsonb
),
(
  'openai','1.0.0',
  '{"type":"api_key"}'::jsonb,
  '{"required":["models.read","inference.test"],"optional":[],"leastPrivilege":"test-only"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"models.list","maxAgeSeconds":900,"test":"responses.create_minimal"}'::jsonb,
  '[{"key":"models.read","mode":"read"},{"key":"inference.test","mode":"execute"}]'::jsonb,
  'high','{"subject":"credential.fingerprint","label":"provider","tenant":"organization","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":false,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"provider_managed","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'gemini','1.0.0',
  '{"type":"api_key"}'::jsonb,
  '{"required":["models.read","inference.test"],"optional":[],"leastPrivilege":"test-only"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"models.list","maxAgeSeconds":900,"test":"generateContent_minimal"}'::jsonb,
  '[{"key":"models.read","mode":"read"},{"key":"inference.test","mode":"execute"}]'::jsonb,
  'high','{"subject":"credential.fingerprint","label":"provider","tenant":"project","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":false,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"provider_managed","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'kimi','1.0.0',
  '{"type":"api_key"}'::jsonb,
  '{"required":["models.read","inference.test"],"optional":[],"leastPrivilege":"test-only"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"models.list","maxAgeSeconds":900,"test":"chat.completions_minimal"}'::jsonb,
  '[{"key":"models.read","mode":"read"},{"key":"inference.test","mode":"execute"}]'::jsonb,
  'high','{"subject":"credential.fingerprint","label":"provider","tenant":"account","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":false,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":true,"mode":"exact_target_preview","forModes":["write"]}'::jsonb,
  '{"mode":"provider_managed","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'supabase','1.0.0',
  '{"type":"service_identity","workloadIdentityPreferred":true}'::jsonb,
  '{"required":["projects.read"],"optional":["management.write"],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"projects.get","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"projects.read","mode":"read"},{"key":"management.write","mode":"write"}]'::jsonb,
  'critical','{"subject":"account.id","label":"organization.name","tenant":"project.ref","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":false,"revoke":true,"rotationDays":60}'::jsonb,
  '{"required":true,"mode":"exact_target_preview_and_step_up","forModes":["write"],"ttlSeconds":600}'::jsonb,
  '{"mode":"project_region","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'vercel','1.0.0',
  '{"type":"oidc_or_token","workloadIdentityPreferred":true}'::jsonb,
  '{"required":["projects.read","deployments.read"],"optional":["deployments.write"],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"projects.get","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"projects.read","mode":"read"},{"key":"deployments.read","mode":"read"},{"key":"deployments.write","mode":"write"}]'::jsonb,
  'critical','{"subject":"user.id","label":"team.name","tenant":"project.id","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"refresh":true,"revoke":true,"rotationDays":60}'::jsonb,
  '{"required":true,"mode":"exact_target_preview_and_step_up","forModes":["write"],"ttlSeconds":600}'::jsonb,
  '{"mode":"team_and_project","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"reconnect"}'::jsonb
)
on conflict do nothing;

create or replace function private.pandora_connection_required_scopes_v1(p_provider_key text)
returns text[] language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(value order by ord),array[]::text[])
  from private.pandora_connection_manifest_contracts_v1 c,
       jsonb_array_elements_text(c.scopes->'required') with ordinality s(value,ord)
  where c.provider_key=p_provider_key and c.manifest_version='1.0.0';
$$;

create or replace function private.pandora_connection_store_verified_credential_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_actor_user_id uuid,
  p_credential text,
  p_provider_subject text,
  p_account_label text,
  p_tenant_key text,
  p_tenant_label text,
  p_granted_scopes text[],
  p_granted_capabilities text[],
  p_verified_at timestamptz,
  p_expires_at timestamptz,
  p_provider_readback jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','private','vault','auth','extensions','pg_temp' as $$
declare
  v_account private.pandora_connection_accounts_v1%rowtype;
  v_subject_hash text;
  v_readback_hash text;
  v_secret_name text;
  v_secret_id uuid;
  v_required text[];
  v_now timestamptz:=clock_timestamp();
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if p_provider_key not in ('google_workspace','posthog','openai','gemini','kimi')
     or length(trim(coalesce(p_credential,''))) not between 16 and 8192
     or length(trim(coalesce(p_provider_subject,''))) not between 1 and 512
     or length(trim(coalesce(p_account_label,''))) not between 1 and 320
     or length(trim(coalesce(p_tenant_key,''))) not between 1 and 320
     or p_verified_at is null or p_verified_at < v_now-interval '5 minutes'
     or p_verified_at > v_now+interval '1 minute'
     or p_provider_readback is null or jsonb_typeof(p_provider_readback)<>'object'
     or octet_length(p_provider_readback::text)>8192 then
    raise exception 'pandora_connection_verified_credential_invalid' using errcode='22023';
  end if;
  if private.pandora_control_plane_json_has_secret_keys(p_provider_readback) then
    raise exception 'pandora_connection_readback_contains_secret_keys' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=p_actor_user_id
      and m.status='active' and m.role in ('owner','admin')
  ) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  v_required:=private.pandora_connection_required_scopes_v1(p_provider_key);
  if not (v_required <@ coalesce(p_granted_scopes,array[]::text[])) then
    raise exception 'pandora_connection_required_scopes_missing' using errcode='42501';
  end if;
  v_subject_hash:=encode(extensions.digest(convert_to(p_provider_key||':'||trim(p_provider_subject),'UTF8'),'sha256'),'hex');
  v_readback_hash:=encode(extensions.digest(convert_to(p_provider_readback::text,'UTF8'),'sha256'),'hex');
  select * into v_account
  from private.pandora_connection_accounts_v1 a
  where a.organization_id=p_organization_id and a.provider_key=p_provider_key
    and a.account_subject_hash=v_subject_hash and a.tenant_key=trim(p_tenant_key)
  for update;
  v_secret_name:='pandora_connection_'||p_provider_key||'_'||replace(p_organization_id::text,'-','')||'_'||left(v_subject_hash,16)||'_'||left(encode(extensions.digest(convert_to(trim(p_tenant_key),'UTF8'),'sha256'),'hex'),8);
  if v_account.id is null then
    v_secret_id:=vault.create_secret(p_credential,v_secret_name,'Pandora connection credential; server-side use only');
    insert into private.pandora_connection_accounts_v1(
      organization_id,provider_key,manifest_version,connected_by,account_subject_hash,
      account_label,tenant_key,tenant_label,credential_secret_id,granted_scopes,
      granted_capabilities,status,health_state,last_verified_at,credential_expires_at,
      rotation_due_at,provider_readback_hash,metadata_redacted
    ) values (
      p_organization_id,p_provider_key,'1.0.0',p_actor_user_id,v_subject_hash,
      trim(p_account_label),trim(p_tenant_key),nullif(trim(p_tenant_label),''),v_secret_id,
      coalesce(p_granted_scopes,array[]::text[]),coalesce(p_granted_capabilities,array[]::text[]),
      'connected','healthy',p_verified_at,p_expires_at,v_now+interval '90 days',v_readback_hash,
      p_provider_readback||jsonb_build_object('verifiedBy','provider_readback','verifiedAt',p_verified_at)
    ) returning * into v_account;
  else
    perform vault.update_secret(v_account.credential_secret_id,p_credential,v_secret_name,'Pandora connection credential; server-side use only');
    update private.pandora_connection_accounts_v1 set
      account_label=trim(p_account_label),tenant_label=nullif(trim(p_tenant_label),''),
      connected_by=p_actor_user_id,credential_version=credential_version+1,
      granted_scopes=coalesce(p_granted_scopes,array[]::text[]),
      granted_capabilities=coalesce(p_granted_capabilities,array[]::text[]),
      status='connected',health_state='healthy',last_verified_at=p_verified_at,
      credential_expires_at=p_expires_at,rotation_due_at=v_now+interval '90 days',
      revoked_at=null,failure_code=null,provider_readback_hash=v_readback_hash,
      metadata_redacted=p_provider_readback||jsonb_build_object('verifiedBy','provider_readback','verifiedAt',p_verified_at),
      updated_at=v_now
    where id=v_account.id returning * into v_account;
  end if;
  insert into private.pandora_connection_active_accounts_v1(organization_id,provider_key,connection_id,tenant_key,selected_by)
  values(p_organization_id,p_provider_key,v_account.id,v_account.tenant_key,p_actor_user_id)
  on conflict(organization_id,provider_key) do update set
    connection_id=excluded.connection_id,tenant_key=excluded.tenant_key,selected_by=excluded.selected_by,selected_at=v_now;
  perform private.append_audit_event(
    p_organization_id,null,null,'provider'::public.audit_actor_type,p_actor_user_id,
    'connection.provider_verified',jsonb_build_object(
      'provider',p_provider_key,'connection_id',v_account.id,'account_subject_hash',v_subject_hash,
      'tenant',trim(p_tenant_key),'readback_hash',v_readback_hash
    )
  );
  return jsonb_build_object(
    'ok',true,'connectionId',v_account.id,'provider',p_provider_key,'accountLabel',v_account.account_label,
    'tenantId',p_organization_id,'tenantKey',v_account.tenant_key,'tenantLabel',v_account.tenant_label,
    'health','healthy','verifiedAt',p_verified_at,
    'credentialStored',true,'credentialReturned',false
  );
end; $$;

create or replace function public.pandora_connection_commit_verified_credential_v1(
  p_organization_id uuid,p_provider_key text,p_actor_user_id uuid,p_credential text,
  p_provider_subject text,p_account_label text,p_tenant_key text,p_tenant_label text,
  p_granted_scopes text[],p_granted_capabilities text[],p_verified_at timestamptz,
  p_expires_at timestamptz,p_provider_readback jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  return private.pandora_connection_store_verified_credential_v1(
    p_organization_id,p_provider_key,p_actor_user_id,p_credential,p_provider_subject,
    p_account_label,p_tenant_key,p_tenant_label,p_granted_scopes,p_granted_capabilities,
    p_verified_at,p_expires_at,p_provider_readback
  );
end; $$;

create or replace function public.pandora_connection_oauth_prepare_v1(
  p_organization_id uuid,p_provider_key text,p_callback_mode text,p_return_uri text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare
  v_uid uuid:=auth.uid(); v_state text; v_nonce text; v_verifier text; v_challenge text;
  v_expires timestamptz:=clock_timestamp()+interval '10 minutes'; v_scopes text[];
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if p_callback_mode not in ('web','mobile') or length(trim(coalesce(p_return_uri,''))) not between 8 and 1024 then
    raise exception 'pandora_connection_callback_invalid' using errcode='22023';
  end if;
  if not exists(
    select 1 from private.pandora_connection_manifest_contracts_v1 c
    where c.provider_key=p_provider_key and c.auth->>'type' in ('oauth2','oidc','oidc_or_token')
      and c.auth->>'pkce'='S256' and c.auth->'state'='true'::jsonb and c.auth->'nonce'='true'::jsonb
  ) then
    raise exception 'pandora_connection_oauth_manifest_not_supported' using errcode='22023';
  end if;
  if p_callback_mode='mobile' and p_return_uri !~ '^(https://|[a-z][a-z0-9+.-]*://)' then
    raise exception 'pandora_connection_mobile_return_invalid' using errcode='22023';
  end if;
  v_scopes:=private.pandora_connection_required_scopes_v1(p_provider_key);
  v_state:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_nonce:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_verifier:=rtrim(translate(encode(extensions.gen_random_bytes(64),'base64'),'+/','-_'),'=');
  v_challenge:=rtrim(translate(encode(extensions.digest(convert_to(v_verifier,'UTF8'),'sha256'),'base64'),'+/','-_'),'=');
  delete from private.pandora_connection_oauth_states_v1
  where organization_id=p_organization_id and user_id=v_uid and (expires_at<=clock_timestamp() or consumed_at is not null);
  insert into private.pandora_connection_oauth_states_v1(
    organization_id,user_id,provider_key,state_hash,nonce_hash,code_verifier,callback_mode,
    return_uri,required_scopes,expires_at
  ) values (
    p_organization_id,v_uid,p_provider_key,
    encode(extensions.digest(convert_to(v_state,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(v_nonce,'UTF8'),'sha256'),'hex'),
    v_verifier,p_callback_mode,trim(p_return_uri),v_scopes,v_expires
  );
  return jsonb_build_object(
    'ok',true,'provider',p_provider_key,'state',v_state,'nonce',v_nonce,
    'codeChallenge',v_challenge,'codeChallengeMethod','S256','callbackMode',p_callback_mode,
    'returnUri',trim(p_return_uri),'scopes',to_jsonb(v_scopes),'expiresAt',v_expires,
    'mobileLaunch',case when p_callback_mode='mobile' then 'secure_custom_tab' else null end
  );
end; $$;

create or replace function public.pandora_connection_oauth_claim_v1(p_state text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare v_row private.pandora_connection_oauth_states_v1%rowtype; v_hash text;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if length(coalesce(p_state,'')) not between 32 and 256 then raise exception 'pandora_connection_oauth_state_invalid' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
  update private.pandora_connection_oauth_states_v1 set claimed_at=clock_timestamp()
  where state_hash=v_hash and claimed_at is null and consumed_at is null and expires_at>clock_timestamp()
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_oauth_state_invalid_or_replayed' using errcode='42501'; end if;
  return jsonb_build_object(
    'organizationId',v_row.organization_id,'userId',v_row.user_id,'provider',v_row.provider_key,
    'codeVerifier',v_row.code_verifier,'nonceHash',v_row.nonce_hash,'callbackMode',v_row.callback_mode,
    'returnUri',v_row.return_uri,'requiredScopes',to_jsonb(v_row.required_scopes),'expiresAt',v_row.expires_at
  );
end; $$;

create or replace function public.pandora_connection_oauth_consume_v1(p_state text,p_provider_nonce text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare v_row private.pandora_connection_oauth_states_v1%rowtype; v_hash text; v_nonce_hash text;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  v_hash:=encode(extensions.digest(convert_to(coalesce(p_state,''),'UTF8'),'sha256'),'hex');
  v_nonce_hash:=encode(extensions.digest(convert_to(coalesce(p_provider_nonce,''),'UTF8'),'sha256'),'hex');
  update private.pandora_connection_oauth_states_v1 set consumed_at=clock_timestamp()
  where state_hash=v_hash and nonce_hash=v_nonce_hash and claimed_at is not null
    and consumed_at is null and expires_at>clock_timestamp()
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_oauth_nonce_or_state_invalid' using errcode='42501'; end if;
  return jsonb_build_object('ok',true,'provider',v_row.provider_key,'organizationId',v_row.organization_id,'userId',v_row.user_id);
end; $$;

create or replace function public.pandora_connection_catalog_v1()
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'provider',c.provider_key,'version',c.manifest_version,'displayName',m.display_name,
    'lifecycle',m.lifecycle_state,'auth',c.auth,'scopes',c.scopes,'callback',c.callback,
    'health',c.health,'capabilities',c.capabilities,'riskClass',c.risk_class,
    'accountIdentity',c.account_identity,'credentialPolicy',c.credential_policy,
    'writeAuthorization',c.write_authorization,'residencyPolicy',c.residency_policy,'recovery',c.recovery
  ) order by c.provider_key),'[]'::jsonb)
  from private.pandora_connection_manifest_contracts_v1 c
  join public.pandora_provider_manifests m using(provider_key,manifest_version)
  where m.lifecycle_state='active';
$$;

create or replace function public.pandora_live_connections_v1(p_organization_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','private','vault','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_rows jsonb;
begin
  if v_uid is null or not private.is_org_member(p_organization_id) then
    raise exception 'pandora_connection_membership_required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(row_json order by row_json->>'provider'),'[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'provider',c.provider_key,'displayName',m.display_name,'riskClass',c.risk_class,
      'state',case
        when a.id is null then 'Needs authorization'
        when a.revoked_at is not null or a.status='revoked' then 'Needs attention'
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp() then 'Needs attention'
        when a.health_state<>'healthy' then 'Needs attention'
        when a.last_verified_at is null or a.last_verified_at < clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900)) then 'Needs attention'
        when not (private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes) then 'Needs attention'
        when not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id) then 'Needs attention'
        else 'Connected' end,
      'connected',coalesce(
        a.id is not null and a.revoked_at is null and a.status='connected' and a.health_state='healthy'
        and (a.credential_expires_at is null or a.credential_expires_at>clock_timestamp())
        and a.last_verified_at>=clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
        and private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
        and exists(select 1 from vault.secrets s where s.id=a.credential_secret_id),false),
      'activeAccount',case when a.id is null then null else jsonb_build_object(
        'id',a.id,'label',a.account_label,'tenantId',a.organization_id,'tenantKey',a.tenant_key,
        'tenant',a.tenant_label,'scopes',to_jsonb(a.granted_scopes),
        'capabilities',to_jsonb(a.granted_capabilities),'lastVerifiedAt',a.last_verified_at,
        'expiresAt',a.credential_expires_at,'health',a.health_state,'failureCode',a.failure_code
      ) end,
      'accounts',coalesce((select jsonb_agg(jsonb_build_object(
        'id',aa.id,'label',aa.account_label,'tenantId',aa.organization_id,'tenantKey',aa.tenant_key,
        'tenant',aa.tenant_label,'selected',aa.id=a.id and aa.tenant_key=s.tenant_key,
        'health',aa.health_state,'lastVerifiedAt',aa.last_verified_at,'expiresAt',aa.credential_expires_at
      ) order by aa.account_label)
      from private.pandora_connection_accounts_v1 aa
      where aa.organization_id=p_organization_id and aa.provider_key=c.provider_key and aa.revoked_at is null),'[]'::jsonb),
      'requiredScopes',c.scopes->'required','healthContract',c.health,'recovery',c.recovery,
      'writeAuthorization',c.write_authorization,
      'authority','live_provider_readback'
    ) row_json
    from private.pandora_connection_manifest_contracts_v1 c
    join public.pandora_provider_manifests m using(provider_key,manifest_version)
    left join private.pandora_connection_active_accounts_v1 s
      on s.organization_id=p_organization_id and s.provider_key=c.provider_key
    left join private.pandora_connection_accounts_v1 a
      on a.id=s.connection_id and a.organization_id=s.organization_id
      and a.provider_key=s.provider_key and a.tenant_key=s.tenant_key
    where m.lifecycle_state='active'
  ) projected;
  return jsonb_build_object(
    'contractVersion','pandora-live-connections-v1','organizationId',p_organization_id,
    'observedAt',clock_timestamp(),'authority','live_connections_not_catalog','providers',v_rows
  );
end; $$;

create or replace function public.pandora_connection_select_account_v1(
  p_organization_id uuid,p_connection_id uuid,p_tenant_key text
)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_account private.pandora_connection_accounts_v1%rowtype;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  select * into v_account from private.pandora_connection_accounts_v1
  where id=p_connection_id and organization_id=p_organization_id
    and tenant_key=trim(p_tenant_key) and revoked_at is null for update;
  if v_account.id is null then raise exception 'pandora_connection_account_not_found' using errcode='22023'; end if;
  insert into private.pandora_connection_active_accounts_v1(organization_id,provider_key,connection_id,tenant_key,selected_by)
  values(p_organization_id,v_account.provider_key,v_account.id,v_account.tenant_key,v_uid)
  on conflict(organization_id,provider_key) do update set
    connection_id=excluded.connection_id,tenant_key=excluded.tenant_key,
    selected_by=excluded.selected_by,selected_at=clock_timestamp();
  perform private.append_audit_event(
    p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,'connection.account_selected',
    jsonb_build_object('provider',v_account.provider_key,'connection_id',v_account.id,
      'tenant_id',v_account.organization_id,'tenant_key',v_account.tenant_key,'account_subject_hash',v_account.account_subject_hash)
  );
  return jsonb_build_object('ok',true,'provider',v_account.provider_key,'connectionId',v_account.id,
    'tenantId',v_account.organization_id,'tenantKey',v_account.tenant_key,'accountLabel',v_account.account_label);
end; $$;

create or replace function public.pandora_connection_revoke_v1(
  p_organization_id uuid,p_connection_id uuid,p_tenant_key text
)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_account private.pandora_connection_accounts_v1%rowtype;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  select * into v_account from private.pandora_connection_accounts_v1
  where id=p_connection_id and organization_id=p_organization_id
    and tenant_key=trim(p_tenant_key) for update;
  if v_account.id is null then raise exception 'pandora_connection_account_not_found' using errcode='22023'; end if;
  delete from vault.secrets where id=v_account.credential_secret_id;
  update private.pandora_connection_accounts_v1 set status='revoked',health_state='unhealthy',
    revoked_at=clock_timestamp(),failure_code='CREDENTIAL_REVOKED',updated_at=clock_timestamp()
  where id=v_account.id;
  delete from private.pandora_connection_active_accounts_v1 where connection_id=v_account.id;
  perform private.append_audit_event(
    p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,'connection.credential_revoked',
    jsonb_build_object('provider',v_account.provider_key,'connection_id',v_account.id,'credential_deleted',true)
  );
  return jsonb_build_object('ok',true,'provider',v_account.provider_key,'connectionId',v_account.id,
    'tenantId',v_account.organization_id,'tenantKey',v_account.tenant_key,
    'revoked',true,'credentialDeleted',true);
end; $$;

create or replace function public.pandora_connection_runtime_credential_v1(
  p_organization_id uuid,p_provider_key text,p_connection_id uuid,p_tenant_key text
)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','private','vault','auth','pg_temp' as $$
declare v_account private.pandora_connection_accounts_v1%rowtype; v_secret text;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  select a.* into v_account
  from private.pandora_connection_accounts_v1 a
  join private.pandora_connection_active_accounts_v1 s
    on s.connection_id=a.id and s.organization_id=a.organization_id
    and s.provider_key=a.provider_key and s.tenant_key=a.tenant_key
  where a.id=p_connection_id and a.organization_id=p_organization_id
    and a.provider_key=p_provider_key and a.tenant_key=trim(p_tenant_key)
    and a.status='connected' and a.revoked_at is null;
  if v_account.id is null then raise exception 'pandora_connection_runtime_unavailable' using errcode='42501'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where id=v_account.credential_secret_id;
  if nullif(v_secret,'') is null then raise exception 'pandora_connection_runtime_credential_missing' using errcode='55000'; end if;
  return jsonb_build_object(
    'provider',v_account.provider_key,'organizationId',v_account.organization_id,
    'tenantId',v_account.organization_id,'connectionId',v_account.id,
    'credential',v_secret,'tenantKey',v_account.tenant_key,'metadata',v_account.metadata_redacted
  );
end; $$;

create or replace function public.pandora_connection_health_commit_v1(
  p_organization_id uuid,p_provider_key text,p_connection_id uuid,p_tenant_key text,
  p_healthy boolean,p_verified_at timestamptz,p_failure_code text default null
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_account private.pandora_connection_accounts_v1%rowtype;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if p_verified_at is null or p_verified_at<clock_timestamp()-interval '5 minutes' or p_verified_at>clock_timestamp()+interval '1 minute' then
    raise exception 'pandora_connection_health_timestamp_invalid' using errcode='22023';
  end if;
  update private.pandora_connection_accounts_v1 set
    health_state=case when p_healthy then 'healthy' else 'unhealthy' end,
    status=case when p_healthy then 'connected' else 'needs_attention' end,
    last_verified_at=p_verified_at,failure_code=case when p_healthy then null else coalesce(nullif(trim(p_failure_code),''),'PROVIDER_HEALTH_FAILED') end,
    updated_at=clock_timestamp()
  where id=p_connection_id and organization_id=p_organization_id
    and provider_key=p_provider_key and tenant_key=trim(p_tenant_key)
    and revoked_at is null returning * into v_account;
  if v_account.id is null then raise exception 'pandora_connection_account_not_found' using errcode='22023'; end if;
  perform private.append_audit_event(
    v_account.organization_id,null,null,'provider'::public.audit_actor_type,null,'connection.health_verified',
    jsonb_build_object('provider',v_account.provider_key,'connection_id',v_account.id,'healthy',p_healthy,'failure_code',v_account.failure_code)
  );
  return jsonb_build_object('ok',true,'connectionId',v_account.id,
    'tenantId',v_account.organization_id,'tenantKey',v_account.tenant_key,
    'healthy',p_healthy,'verifiedAt',p_verified_at,'failureCode',v_account.failure_code);
end; $$;

create or replace function public.pandora_connection_write_preview_v1(
  p_organization_id uuid,p_provider_key text,p_connection_id uuid,p_tenant_key text,
  p_operation text,p_exact_target jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare
  v_uid uuid:=auth.uid(); v_hash text; v_id uuid;
  v_expires timestamptz:=clock_timestamp()+interval '10 minutes';
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if p_provider_key not in ('supabase','vercel') or p_operation !~ '^[a-z][a-z0-9_.-]{2,79}$'
     or p_exact_target is null or jsonb_typeof(p_exact_target)<>'object' or p_exact_target='{}'::jsonb
     or octet_length(p_exact_target::text)>8192 then
    raise exception 'pandora_connection_write_preview_invalid' using errcode='22023';
  end if;
  if private.pandora_control_plane_json_has_secret_keys(p_exact_target) then
    raise exception 'pandora_connection_write_preview_contains_secret_keys' using errcode='22023';
  end if;
  if not exists(
    select 1
    from private.pandora_connection_active_accounts_v1 s
    join private.pandora_connection_accounts_v1 a
      on a.id=s.connection_id and a.organization_id=s.organization_id
      and a.provider_key=s.provider_key and a.tenant_key=s.tenant_key
    where s.organization_id=p_organization_id and s.provider_key=p_provider_key
      and s.connection_id=p_connection_id and s.tenant_key=trim(p_tenant_key)
      and a.status='connected' and a.health_state='healthy' and a.revoked_at is null
  ) then
    raise exception 'pandora_connection_account_tenant_mismatch' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='expired'
  where organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key)
    and status='pending' and expires_at<=clock_timestamp();
  v_hash:=encode(extensions.digest(convert_to(
    p_organization_id::text||'|'||p_provider_key||'|'||p_connection_id::text||'|'||trim(p_tenant_key)||'|'||p_operation||'|'||p_exact_target::text,
    'UTF8'),'sha256'),'hex');
  insert into private.pandora_connection_write_approvals_v1(
    organization_id,provider_key,connection_id,tenant_key,requested_by,operation,target_preview,target_hash,expires_at
  ) values(p_organization_id,p_provider_key,p_connection_id,trim(p_tenant_key),v_uid,p_operation,p_exact_target,v_hash,v_expires)
  returning id into v_id;
  perform private.append_audit_event(
    p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,'connection.write_previewed',
    jsonb_build_object('provider',p_provider_key,'approval_id',v_id,'operation',p_operation,'target_hash',v_hash)
  );
  return jsonb_build_object(
    'ok',true,'approvalId',v_id,'provider',p_provider_key,'connectionId',p_connection_id,
    'tenantId',p_organization_id,'tenantKey',trim(p_tenant_key),'operation',p_operation,
    'exactTargetPreview',p_exact_target,'targetHash',v_hash,'status','pending','expiresAt',v_expires,
    'stepUpRequired',true,'confirmationText',v_hash
  );
end; $$;

create or replace function public.pandora_connection_write_approve_v1(
  p_organization_id uuid,p_approval_id uuid,p_provider_key text,
  p_connection_id uuid,p_tenant_key text,p_confirmation_hash text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_row private.pandora_connection_write_approvals_v1%rowtype;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set
    status='approved',approved_by=v_uid,approved_at=clock_timestamp()
  where id=p_approval_id and organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key) and status='pending'
    and expires_at>clock_timestamp() and target_hash=p_confirmation_hash
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_write_approval_invalid_or_expired' using errcode='42501'; end if;
  perform private.append_audit_event(
    p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,'connection.write_approved',
    jsonb_build_object('provider',v_row.provider_key,'approval_id',v_row.id,'operation',v_row.operation,'target_hash',v_row.target_hash)
  );
  return jsonb_build_object('ok',true,'approvalId',v_row.id,'provider',v_row.provider_key,
    'connectionId',v_row.connection_id,'tenantId',v_row.organization_id,'tenantKey',v_row.tenant_key,
    'operation',v_row.operation,'targetHash',v_row.target_hash,'status','approved','expiresAt',v_row.expires_at);
end; $$;

create or replace function public.pandora_connection_write_consume_v1(
  p_organization_id uuid,p_approval_id uuid,p_provider_key text,p_connection_id uuid,
  p_tenant_key text,p_operation text,p_target_hash text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_row private.pandora_connection_write_approvals_v1%rowtype;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='consumed',consumed_at=clock_timestamp()
  where id=p_approval_id and organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key)
    and operation=p_operation and target_hash=p_target_hash and status='approved'
    and expires_at>clock_timestamp() returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_write_approval_not_consumable' using errcode='42501'; end if;
  perform private.append_audit_event(
    p_organization_id,null,null,'system'::public.audit_actor_type,null,'connection.write_approval_consumed',
    jsonb_build_object('provider',v_row.provider_key,'approval_id',v_row.id,'operation',v_row.operation,'target_hash',v_row.target_hash)
  );
  return jsonb_build_object('ok',true,'approvalId',v_row.id,'provider',v_row.provider_key,
    'connectionId',v_row.connection_id,'tenantId',v_row.organization_id,'tenantKey',v_row.tenant_key,
    'operation',v_row.operation,'exactTarget',v_row.target_preview,
    'targetHash',v_row.target_hash,'status','consumed');
end; $$;

-- Google Workspace is read-first and OIDC nonce-bound. Existing in-flight states
-- without a nonce fail closed and must be restarted.
alter table private.pandora_google_workspace_oauth_states
  add column if not exists nonce_hash text check (nonce_hash is null or nonce_hash ~ '^[0-9a-f]{64}$');

create or replace function private.pandora_google_workspace_required_scopes_v1()
returns text[] language sql immutable set search_path='pg_catalog' as $$
  select array[
    'openid','email','profile',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
    'https://www.googleapis.com/auth/spreadsheets.readonly'
  ]::text[];
$$;

create or replace function public.pandora_google_workspace_oauth_prepare_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','auth','extensions','pg_temp' as $$
declare
  v_uid uuid:=auth.uid(); v_client_id text; v_secret_ok boolean;
  v_state text; v_nonce text; v_verifier text; v_challenge text; v_state_hash text;
  v_redirect text:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-google-workspace-oauth/callback';
  v_scopes text[]:=private.pandora_google_workspace_required_scopes_v1();
  v_expires timestamptz:=clock_timestamp()+interval '10 minutes';
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_google_oauth_owner_required' using errcode='42501';
  end if;
  select decrypted_secret into v_client_id from vault.decrypted_secrets
    where name='pandora_google_workspace_oauth_client_id' and nullif(trim(decrypted_secret),'') is not null limit 1;
  select exists(select 1 from vault.decrypted_secrets where name='pandora_google_workspace_oauth_client_secret' and nullif(trim(decrypted_secret),'') is not null) into v_secret_ok;
  if nullif(trim(v_client_id),'') is null or not v_secret_ok then
    return jsonb_build_object('ok',false,'provider','google_workspace','state','needs_authorization_configuration','reason','google_workspace_oauth_not_configured','needsYou',true,'redirectUri',v_redirect);
  end if;
  delete from private.pandora_google_workspace_oauth_states
  where organization_id=p_organization_id and user_id=v_uid and (expires_at<=clock_timestamp() or consumed_at is not null);
  v_state:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_nonce:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_verifier:=rtrim(translate(encode(extensions.gen_random_bytes(64),'base64'),'+/','-_'),'=');
  v_state_hash:=encode(extensions.digest(convert_to(v_state,'UTF8'),'sha256'),'hex');
  v_challenge:=rtrim(translate(encode(extensions.digest(convert_to(v_verifier,'UTF8'),'sha256'),'base64'),'+/','-_'),'=');
  insert into private.pandora_google_workspace_oauth_states(
    organization_id,user_id,state_hash,nonce_hash,code_verifier,redirect_uri,required_scopes,expires_at
  ) values(
    p_organization_id,v_uid,v_state_hash,encode(extensions.digest(convert_to(v_nonce,'UTF8'),'sha256'),'hex'),
    v_verifier,v_redirect,v_scopes,v_expires
  );
  return jsonb_build_object(
    'ok',true,'provider','google_workspace','state','authorization_required','redirectUri',v_redirect,
    'expiresAt',v_expires,'scopes',to_jsonb(v_scopes),
    'authorizationUrl','https://accounts.google.com/o/oauth2/v2/auth?'||extensions.urlencode(jsonb_build_object(
      'client_id',v_client_id,'redirect_uri',v_redirect,'response_type','code','scope',array_to_string(v_scopes,' '),
      'access_type','offline','prompt','consent','include_granted_scopes','true','state',v_state,'nonce',v_nonce,
      'code_challenge',v_challenge,'code_challenge_method','S256'))
  );
end; $$;

create or replace function public.pandora_google_workspace_oauth_commit_v1(
  p_state text,p_provider_subject text,p_account_email text,p_display_name text,
  p_refresh_token text,p_granted_scopes text[]
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  raise exception 'pandora_google_oauth_oidc_nonce_required' using errcode='42501';
end; $$;

create or replace function public.pandora_google_workspace_oauth_commit_v1(
  p_state text,p_provider_subject text,p_account_email text,p_display_name text,
  p_refresh_token text,p_granted_scopes text[],p_oidc_nonce text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','extensions','pg_temp' as $$
declare v_hash text; v_nonce_hash text; v_row private.pandora_google_workspace_oauth_states%rowtype; v_result jsonb;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'pandora_google_oauth_service_role_required' using errcode='42501';
  end if;
  if p_state is null or length(trim(coalesce(p_refresh_token,'')))<16 or length(trim(coalesce(p_oidc_nonce,'')))<16 then
    raise exception 'pandora_google_oauth_commit_invalid' using errcode='22023';
  end if;
  v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
  v_nonce_hash:=encode(extensions.digest(convert_to(p_oidc_nonce,'UTF8'),'sha256'),'hex');
  select * into v_row from private.pandora_google_workspace_oauth_states
  where state_hash=v_hash and nonce_hash=v_nonce_hash and consumed_at is null and claimed_at is not null
    and expires_at>clock_timestamp() for update;
  if v_row.id is null then raise exception 'pandora_google_oauth_state_or_nonce_invalid' using errcode='42501'; end if;
  if not (v_row.required_scopes<@coalesce(p_granted_scopes,array[]::text[])) then
    raise exception 'pandora_google_oauth_required_scopes_missing' using errcode='42501';
  end if;
  v_result:=private.pandora_connection_store_verified_credential_v1(
    v_row.organization_id,'google_workspace',v_row.user_id,p_refresh_token,trim(p_provider_subject),
    lower(trim(p_account_email)),coalesce(nullif(split_part(lower(trim(p_account_email)),'@',2),''),'consumer'),
    coalesce(nullif(split_part(lower(trim(p_account_email)),'@',2),''),'Consumer Google account'),
    p_granted_scopes,array['drive.metadata.read','sheets.values.read'],
    clock_timestamp(),null,jsonb_build_object('probe','drive.about.read','httpStatus',200,'identityVerified',true,'nonceVerified',true)
  );
  update private.pandora_google_workspace_oauth_states set consumed_at=clock_timestamp() where id=v_row.id;
  insert into private.pandora_google_workspace_connections(
    organization_id,user_id,refresh_token_secret_id,provider_subject,account_email,display_name,
    scopes,status,last_verified_at,last_http_status,last_error,updated_at
  ) select v_row.organization_id,v_row.user_id,a.credential_secret_id,trim(p_provider_subject),lower(trim(p_account_email)),
      nullif(trim(p_display_name),''),p_granted_scopes,'connected',clock_timestamp(),200,null,clock_timestamp()
    from private.pandora_connection_accounts_v1 a where a.id=(v_result->>'connectionId')::uuid
  on conflict(organization_id,user_id) do update set
    refresh_token_secret_id=excluded.refresh_token_secret_id,provider_subject=excluded.provider_subject,
    account_email=excluded.account_email,display_name=excluded.display_name,scopes=excluded.scopes,
    status='connected',last_verified_at=excluded.last_verified_at,last_http_status=200,last_error=null,updated_at=excluded.updated_at;
  return v_result||jsonb_build_object('organizationId',v_row.organization_id,'userId',v_row.user_id,'accountEmail',lower(trim(p_account_email)));
end; $$;

create or replace function public.pandora_google_workspace_connection_v1(p_organization_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_row private.pandora_google_workspace_connections%rowtype; v_fresh boolean;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_google_connection_owner_required' using errcode='42501';
  end if;
  select * into v_row from private.pandora_google_workspace_connections
    where organization_id=p_organization_id and user_id=v_uid;
  if v_row.organization_id is null then
    return jsonb_build_object('ok',true,'provider','google_workspace','connected',false,'state','Needs authorization','canUseNow',false);
  end if;
  v_fresh:=v_row.status='connected' and v_row.last_verified_at>=clock_timestamp()-interval '15 minutes'
    and private.pandora_google_workspace_required_scopes_v1()<@v_row.scopes;
  return jsonb_build_object(
    'ok',true,'provider','google_workspace','connected',v_fresh,
    'state',case when v_fresh then 'Connected' else 'Needs attention' end,'canUseNow',v_fresh,
    'account',jsonb_build_object('label',v_row.account_email,'verified',v_fresh),
    'scopes',to_jsonb(v_row.scopes),'scopesVerified',private.pandora_google_workspace_required_scopes_v1()<@v_row.scopes,
    'lastVerifiedAt',v_row.last_verified_at,'rawStatus',v_row.status,
    'recovery',case when v_fresh then null else jsonb_build_object('action','reconnect','reason','health_or_scopes_stale') end
  );
end; $$;

revoke all on function public.pandora_connection_commit_verified_credential_v1(uuid,text,uuid,text,text,text,text,text,text[],text[],timestamptz,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_connection_oauth_claim_v1(text) from public,anon,authenticated;
revoke all on function public.pandora_connection_oauth_consume_v1(text,text) from public,anon,authenticated;
revoke all on function public.pandora_connection_runtime_credential_v1(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.pandora_connection_health_commit_v1(uuid,text,uuid,text,boolean,timestamptz,text) from public,anon,authenticated;
revoke all on function public.pandora_connection_write_consume_v1(uuid,uuid,text,uuid,text,text,text) from public,anon,authenticated;

grant execute on function public.pandora_connection_catalog_v1() to authenticated;
grant execute on function public.pandora_live_connections_v1(uuid) to authenticated;
grant execute on function public.pandora_connection_oauth_prepare_v1(uuid,text,text,text) to authenticated;
grant execute on function public.pandora_connection_select_account_v1(uuid,uuid,text) to authenticated;
grant execute on function public.pandora_connection_revoke_v1(uuid,uuid,text) to authenticated;
grant execute on function public.pandora_connection_write_preview_v1(uuid,text,uuid,text,text,jsonb) to authenticated;
grant execute on function public.pandora_connection_write_approve_v1(uuid,uuid,text,uuid,text,text) to authenticated;

comment on function public.pandora_live_connections_v1(uuid) is
  'Authoritative fail-closed connection projection. Catalog presence and credential presence alone never imply Connected.';
comment on function public.pandora_connection_write_preview_v1(uuid,text,uuid,text,text,jsonb) is
  'Creates an exact-account, tenant-bound, target-hash-bound, short-lived Supabase/Vercel write step-up preview; it does not execute the write.';
