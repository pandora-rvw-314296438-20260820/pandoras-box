-- Audit remediation: a missing membership is never an authorization grant.
-- Preserve existing signatures, provider behavior, and public RPC grants.
create or replace function private.pandora_is_active_org_admin_v1(p_organization_id uuid)
returns boolean
language sql stable security invoker
set search_path = ''
as $predicate$
  select auth.uid() is not null and p_organization_id is not null and exists (
    select 1 from public.memberships m
    join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_organization_id and m.user_id=auth.uid()
      and m.status::text='active' and m.role::text in ('owner','admin')
      and o.status='active'
  );
$predicate$;
revoke all on function private.pandora_is_active_org_admin_v1(uuid) from public,anon,authenticated;
grant execute on function private.pandora_is_active_org_admin_v1(uuid) to service_role;

create table if not exists private.pandora_security_patch_receipts (
  migration_key text not null,
  function_identity text not null,
  before_sha256 text not null,
  after_sha256 text not null,
  before_definition text not null,
  after_definition text not null,
  applied_at timestamptz not null default now(),
  primary key (migration_key,function_identity)
);
alter table private.pandora_security_patch_receipts enable row level security;
revoke all on private.pandora_security_patch_receipts from public,anon,authenticated;
grant select,insert on private.pandora_security_patch_receipts to service_role;

do $patch$
declare
  r record;
  v_before text;
  v_after text;
  v_key constant text := 'pandora_fail_closed_membership_guards_v1';
begin
  for r in
    select p.oid,p.oid::regprocedure::text as identity
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname=any(array[
      'pandora_chat_capability_registry_v1','pandora_chat_capability_registry_v3',
      'pandora_chat_capability_dispatch_native_v1',
      'pandora_chat_universal_dispatch_v1','pandora_chat_universal_dispatch_v2',
      'pandora_chat_universal_dispatch_v9','pandora_chat_repository_snapshot_v1',
      'pandora_enterprise_direct_github_v1','pandora_meta_connection_v1',
      'pandora_meta_oauth_prepare_v1','pandora_google_workspace_connection_v1',
      'pandora_google_workspace_oauth_prepare_v1'
    ])
  loop
    v_before:=pg_get_functiondef(r.oid);
    if position('private.pandora_is_active_org_admin_v1(p_organization_id)' in v_before)>0 then
      continue;
    end if;
    v_after:=regexp_replace(v_before,
      'if[[:space:]]+v_role[[:space:]]+not[[:space:]]+in[[:space:]]*\(''owner'',[[:space:]]*''admin''\)[[:space:]]+then',
      'if not private.pandora_is_active_org_admin_v1(p_organization_id) then','gi');
    if v_after=v_before then
      raise exception 'Expected membership guard not found in %; manual reconciliation required',r.identity;
    end if;
    execute v_after;
    insert into private.pandora_security_patch_receipts(
      migration_key,function_identity,before_sha256,after_sha256,before_definition,after_definition
    ) values(v_key,r.identity,
      encode(extensions.digest(convert_to(v_before,'UTF8'),'sha256'),'hex'),
      encode(extensions.digest(convert_to(v_after,'UTF8'),'sha256'),'hex'),v_before,v_after)
    on conflict (migration_key,function_identity) do nothing;
  end loop;
end;
$patch$;

-- Fail deployment if any authenticated public RPC still has the known unsafe guard.
do $assert$
begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and p.prosrc ~* 'if[[:space:]]+v_role[[:space:]]+not[[:space:]]+in') then
    raise exception 'An authenticated RPC still contains a nullable v_role authorization guard';
  end if;
end;
$assert$;
