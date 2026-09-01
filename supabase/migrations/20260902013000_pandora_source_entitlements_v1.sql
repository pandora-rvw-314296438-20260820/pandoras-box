
-- Pandora paid source entitlement boundary v1.
-- Explicit grants are the only authority for durable customer source access.
-- Organization membership or owner/admin role alone MUST NOT grant source access.

create table if not exists public.pandora_source_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  user_id uuid not null,
  capabilities text[] not null default array['read','search','diff','export']::text[],
  source text not null,
  source_reference text,
  granted_by uuid,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_source_entitlements_identity_key unique (organization_id, project_id, user_id),
  constraint pandora_source_entitlements_source_check check (source ~ '^[a-z][a-z0-9_-]{1,31}$'),
  constraint pandora_source_entitlements_capabilities_check check (
    cardinality(capabilities) between 1 and 4
    and capabilities <@ array['read','search','diff','export']::text[]
  ),
  constraint pandora_source_entitlements_expiry_check check (expires_at is null or expires_at > granted_at),
  constraint pandora_source_entitlements_revocation_shape_check check ((revoked_at is null and revoked_by is null) or revoked_at is not null)
);

comment on table public.pandora_source_entitlements is
  'Explicit project/user durable-source access. Membership, project ownership and preview permission do not imply source entitlement.';

create table if not exists public.pandora_source_access_audit (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  user_id uuid not null,
  entitlement_id uuid references public.pandora_source_entitlements(id) on delete set null,
  capability text not null,
  action text not null,
  resource_ref text,
  allowed boolean not null,
  reason text not null,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint pandora_source_access_audit_capability_check check (capability in ('read','search','diff','export')),
  constraint pandora_source_access_audit_action_check check (action ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  constraint pandora_source_access_audit_reason_check check (reason ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  constraint pandora_source_access_audit_request_check check (request_id is null or length(request_id) between 8 and 100),
  constraint pandora_source_access_audit_metadata_check check (jsonb_typeof(metadata)='object' and octet_length(metadata::text) <= 8192)
);

comment on table public.pandora_source_access_audit is
  'Append-only evidence for every server-side durable-source access decision or entitlement mutation.';

create or replace function private.pandora_validate_source_entitlement_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
begin
  if not private.pandora_control_plane_project_org_matches(new.organization_id, new.project_id) then
    raise exception 'source entitlement project/org mismatch' using errcode='23514';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=new.organization_id
      and m.user_id=new.user_id
      and m.status::text='active'
  ) then
    raise exception 'source entitlement requires active organization membership' using errcode='23514';
  end if;
  if tg_op='UPDATE' and (
    new.organization_id is distinct from old.organization_id
    or new.project_id is distinct from old.project_id
    or new.user_id is distinct from old.user_id
    or new.id is distinct from old.id
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'source entitlement identity is immutable' using errcode='55000';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists pandora_source_entitlements_validate_v1 on public.pandora_source_entitlements;
create trigger pandora_source_entitlements_validate_v1
before insert or update on public.pandora_source_entitlements
for each row execute function private.pandora_validate_source_entitlement_v1();

create or replace function private.pandora_validate_source_access_audit_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
begin
  if not private.pandora_control_plane_project_org_matches(new.organization_id,new.project_id) then
    raise exception 'source audit project/org mismatch' using errcode='23514';
  end if;
  if tg_op='UPDATE' or tg_op='DELETE' then
    raise exception 'source access audit is append-only' using errcode='55000';
  end if;
  return new;
end;
$function$;

drop trigger if exists pandora_source_access_audit_append_only_v1 on public.pandora_source_access_audit;
create trigger pandora_source_access_audit_append_only_v1
before insert or update or delete on public.pandora_source_access_audit
for each row execute function private.pandora_validate_source_access_audit_v1();

alter table public.pandora_source_entitlements enable row level security;
alter table public.pandora_source_access_audit enable row level security;

revoke all on public.pandora_source_entitlements from public, anon, authenticated;
revoke all on public.pandora_source_access_audit from public, anon, authenticated;
grant select,insert,update,delete on public.pandora_source_entitlements to service_role;
grant select,insert on public.pandora_source_access_audit to service_role;

create or replace function public.pandora_get_source_entitlement_v1(
  p_project_id uuid,
  p_capability text default 'read'
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_ent public.pandora_source_entitlements%rowtype;
  v_reason text;
begin
  if v_user is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode='42501';
  end if;
  if p_project_id is null or p_capability not in ('read','search','diff','export') then
    raise exception 'INVALID_SOURCE_ENTITLEMENT_REQUEST' using errcode='22023';
  end if;
  select p.organization_id into v_org from public.projectos_projects p where p.id=p_project_id;
  if v_org is null or not private.is_org_member(v_org) then
    raise exception 'PROJECT_ACCESS_REQUIRED' using errcode='42501';
  end if;

  select * into v_ent
  from public.pandora_source_entitlements e
  where e.organization_id=v_org and e.project_id=p_project_id and e.user_id=v_user;

  if not found then
    v_reason := 'NO_SOURCE_ENTITLEMENT';
  elsif v_ent.revoked_at is not null then
    v_reason := 'SOURCE_ENTITLEMENT_REVOKED';
  elsif v_ent.expires_at is not null and v_ent.expires_at <= now() then
    v_reason := 'SOURCE_ENTITLEMENT_EXPIRED';
  elsif not (p_capability = any(v_ent.capabilities)) then
    v_reason := 'SOURCE_CAPABILITY_NOT_GRANTED';
  else
    return jsonb_build_object(
      'allowed',true,
      'reason','SOURCE_ENTITLEMENT_ACTIVE',
      'organizationId',v_org,
      'projectId',p_project_id,
      'userId',v_user,
      'entitlementId',v_ent.id,
      'capability',p_capability,
      'capabilities',to_jsonb(v_ent.capabilities),
      'source',v_ent.source,
      'sourceReference',v_ent.source_reference,
      'grantedAt',v_ent.granted_at,
      'expiresAt',v_ent.expires_at
    );
  end if;

  return jsonb_build_object(
    'allowed',false,
    'reason',v_reason,
    'organizationId',v_org,
    'projectId',p_project_id,
    'userId',v_user,
    'capability',p_capability
  );
end;
$function$;

revoke all on function public.pandora_get_source_entitlement_v1(uuid,text) from public, anon;
grant execute on function public.pandora_get_source_entitlement_v1(uuid,text) to authenticated;

create or replace function public.pandora_grant_source_entitlement_service_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_user_id uuid,
  p_capabilities text[],
  p_source text,
  p_source_reference text default null,
  p_expires_at timestamptz default null,
  p_granted_by uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
declare
  v_ent public.pandora_source_entitlements%rowtype;
begin
  if p_organization_id is null or p_project_id is null or p_user_id is null
     or p_source !~ '^[a-z][a-z0-9_-]{1,31}$'
     or p_capabilities is null or cardinality(p_capabilities) not between 1 and 4
     or not (p_capabilities <@ array['read','search','diff','export']::text[])
     or (p_expires_at is not null and p_expires_at <= now()) then
    raise exception 'invalid source entitlement grant' using errcode='22023';
  end if;
  if not private.pandora_control_plane_project_org_matches(p_organization_id,p_project_id) then
    raise exception 'source entitlement project/org mismatch' using errcode='23514';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=p_user_id and m.status::text='active'
  ) then
    raise exception 'source entitlement user is not an active member' using errcode='23514';
  end if;

  insert into public.pandora_source_entitlements(
    organization_id,project_id,user_id,capabilities,source,source_reference,granted_by,granted_at,expires_at,revoked_at,revoked_by
  ) values (
    p_organization_id,p_project_id,p_user_id,p_capabilities,p_source,nullif(trim(coalesce(p_source_reference,'')),''),p_granted_by,now(),p_expires_at,null,null
  ) on conflict (organization_id,project_id,user_id) do update set
    capabilities=excluded.capabilities,
    source=excluded.source,
    source_reference=excluded.source_reference,
    granted_by=excluded.granted_by,
    granted_at=excluded.granted_at,
    expires_at=excluded.expires_at,
    revoked_at=null,
    revoked_by=null
  returning * into v_ent;

  insert into public.pandora_source_access_audit(
    organization_id,project_id,user_id,entitlement_id,capability,action,resource_ref,allowed,reason,metadata
  ) values (
    p_organization_id,p_project_id,p_user_id,v_ent.id,'read','entitlement.grant',p_source_reference,true,'SOURCE_ENTITLEMENT_GRANTED',
    jsonb_build_object('capabilities',to_jsonb(p_capabilities),'source',p_source,'expiresAt',p_expires_at,'grantedBy',p_granted_by)
  );

  return jsonb_build_object('granted',true,'entitlementId',v_ent.id,'projectId',p_project_id,'userId',p_user_id,'capabilities',to_jsonb(v_ent.capabilities),'expiresAt',v_ent.expires_at);
end;
$function$;

revoke all on function public.pandora_grant_source_entitlement_service_v1(uuid,uuid,uuid,text[],text,text,timestamptz,uuid) from public, anon, authenticated;
grant execute on function public.pandora_grant_source_entitlement_service_v1(uuid,uuid,uuid,text[],text,text,timestamptz,uuid) to service_role;

create or replace function public.pandora_revoke_source_entitlement_service_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_user_id uuid,
  p_revoked_by uuid default null,
  p_reason text default 'SOURCE_ENTITLEMENT_REVOKED'
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
declare
  v_ent public.pandora_source_entitlements%rowtype;
begin
  if p_reason !~ '^[A-Z][A-Z0-9_]{2,79}$' then raise exception 'invalid source entitlement revoke reason' using errcode='22023'; end if;
  update public.pandora_source_entitlements
  set revoked_at=now(),revoked_by=p_revoked_by
  where organization_id=p_organization_id and project_id=p_project_id and user_id=p_user_id
  returning * into v_ent;
  if not found then return jsonb_build_object('revoked',false,'reason','SOURCE_ENTITLEMENT_NOT_FOUND'); end if;
  insert into public.pandora_source_access_audit(
    organization_id,project_id,user_id,entitlement_id,capability,action,allowed,reason,metadata
  ) values (
    p_organization_id,p_project_id,p_user_id,v_ent.id,'read','entitlement.revoke',false,p_reason,jsonb_build_object('revokedBy',p_revoked_by)
  );
  return jsonb_build_object('revoked',true,'entitlementId',v_ent.id,'reason',p_reason);
end;
$function$;

revoke all on function public.pandora_revoke_source_entitlement_service_v1(uuid,uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.pandora_revoke_source_entitlement_service_v1(uuid,uuid,uuid,uuid,text) to service_role;

create or replace function public.pandora_record_source_access_audit_service_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_user_id uuid,
  p_entitlement_id uuid,
  p_capability text,
  p_action text,
  p_resource_ref text,
  p_allowed boolean,
  p_reason text,
  p_request_id text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $function$
declare v_id uuid;
begin
  if p_capability not in ('read','search','diff','export')
     or p_action !~ '^[a-z][a-z0-9_.-]{1,63}$'
     or p_reason !~ '^[A-Z][A-Z0-9_]{2,79}$'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' or octet_length(p_metadata::text)>8192 then
    raise exception 'invalid source access audit record' using errcode='22023';
  end if;
  if not private.pandora_control_plane_project_org_matches(p_organization_id,p_project_id) then
    raise exception 'source audit project/org mismatch' using errcode='23514';
  end if;
  insert into public.pandora_source_access_audit(
    organization_id,project_id,user_id,entitlement_id,capability,action,resource_ref,allowed,reason,request_id,metadata
  ) values (
    p_organization_id,p_project_id,p_user_id,p_entitlement_id,p_capability,p_action,nullif(trim(coalesce(p_resource_ref,'')),''),p_allowed,p_reason,nullif(trim(coalesce(p_request_id,'')),''),p_metadata
  ) returning id into v_id;
  return v_id;
end;
$function$;

revoke all on function public.pandora_record_source_access_audit_service_v1(uuid,uuid,uuid,uuid,text,text,text,boolean,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.pandora_record_source_access_audit_service_v1(uuid,uuid,uuid,uuid,text,text,text,boolean,text,text,jsonb) to service_role;
