-- Explicit server-owned grants for canonical provider resources.
create table if not exists private.pandora_provider_resource_grants (
 organization_id uuid not null references public.organizations(id),
 provider text not null check(provider in ('github','supabase','vercel')),
 resource_key text not null check(length(resource_key) between 1 and 240),
 write_allowed boolean not null default false,
 active boolean not null default true,
 provenance text not null,
 created_at timestamptz not null default now(),
 primary key(organization_id,provider,resource_key)
);
alter table private.pandora_provider_resource_grants enable row level security;
revoke all on private.pandora_provider_resource_grants from public,anon,authenticated;
grant select,insert,update,delete on private.pandora_provider_resource_grants to service_role;

-- Resolve database identities from the verified canonical project binding.
-- Do not infer a grant from a caller-controlled organization or repository name.
insert into private.pandora_provider_resource_grants(organization_id,provider,resource_key,write_allowed,provenance)
select distinct p.organization_id,'github',r.resource_key,r.resource_key='pandora-rvw-314296438-20260820/plp',
 'audit-20260925:canonical-active-platform-project-binding'
from public.pandora_projects p
cross join (values('pandora-rvw-314296438-20260820/pandoras-box'),('pandora-rvw-314296438-20260820/pandoras-box-memory'),('pandora-rvw-314296438-20260820/plp')) r(resource_key)
where p.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
 and p.project_key='mcpmaster' and p.repository='pandora-rvw-314296438-20260820/pandoras-box' and p.status='active'
on conflict do nothing;
insert into private.pandora_provider_resource_grants(organization_id,provider,resource_key,write_allowed,provenance)
select o.id,'github','pandora-rvw-314296438-20260820/plp',true,'audit-20260925:PLP-customer-workspace-binding'
from public.organizations o where o.slug='plp-boracay' and o.status='active'
on conflict do nothing;
insert into private.pandora_provider_resource_grants(organization_id,provider,resource_key,provenance)
select distinct p.organization_id,'supabase',r.resource_key,'audit-20260925:canonical-platform-project-refs'
from public.pandora_projects p cross join (values('jcyqixttuebxqqfkjonq'),('ivmvufhcsezyhczzondn')) r(resource_key)
where p.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
 and p.project_key='mcpmaster' and p.repository='pandora-rvw-314296438-20260820/pandoras-box' and p.status='active'
on conflict do nothing;
insert into private.pandora_provider_resource_grants(organization_id,provider,resource_key,provenance)
select distinct p.organization_id,'vercel',c.config_value,'audit-20260925:active-canonical-vercel-runtime-config'
from public.pandora_projects p cross join public.pandora_runtime_provider_configs c
where p.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
 and p.project_key='mcpmaster' and p.repository='pandora-rvw-314296438-20260820/pandoras-box' and p.status='active'
 and c.provider='vercel' and c.config_key='mcpmaster_project_id' and c.active=true and nullif(trim(c.config_value),'') is not null
on conflict do nothing;

create or replace function private.pandora_require_provider_resource_v1(
 p_organization_id uuid,p_provider text,p_resource_key text,p_write boolean default false
) returns void language plpgsql security invoker set search_path=''
as $guard$
begin
 if not private.pandora_is_active_org_admin_v1(p_organization_id) then
  raise exception 'pandora_provider_active_org_admin_required' using errcode='42501';
 end if;
 if p_provider is null or p_resource_key is null or p_write is null then
  raise exception 'pandora_provider_resource_not_authorized' using errcode='42501';
 end if;
 if exists(select 1 from private.pandora_provider_resource_grants g
   where g.organization_id=p_organization_id and g.provider=p_provider
    and g.resource_key=p_resource_key and g.active and (not p_write or g.write_allowed)) then return; end if;
 -- Noncanonical customer repository reads retain their existing project binding.
 -- Canonical resources can never be granted by adding a lookalike project row.
 if p_provider='github' and not p_write and p_resource_key not in (
  'pandora-rvw-314296438-20260820/pandoras-box',
  'pandora-rvw-314296438-20260820/pandoras-box-memory',
  'pandora-rvw-314296438-20260820/plp') and exists(
   select 1 from public.pandora_projects p where p.organization_id=p_organization_id
    and p.repository=p_resource_key and p.status='active') then return; end if;
 raise exception 'pandora_provider_resource_not_authorized' using errcode='42501';
end;
$guard$;
revoke all on function private.pandora_require_provider_resource_v1(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function private.pandora_require_provider_resource_v1(uuid,text,text,boolean) to service_role;

do $patch$
declare r record; b text; a text; token text;
begin
 for r in select p.oid,p.proname,p.oid::regprocedure::text identity
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('pandora_enterprise_direct_github_v1','pandora_chat_capability_dispatch_native_v1','pandora_chat_repository_snapshot_v1')
 loop
  b:=pg_get_functiondef(r.oid); a:=b;
  if position('private.pandora_require_provider_resource_v1(' in b)>0 then continue; end if;
  if r.proname='pandora_enterprise_direct_github_v1' then
   token:='if v_method not in (''GET'',''POST'',''PATCH'') then';
   if position(token in a)=0 then raise exception 'Direct GitHub patch anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''github'',''pandora-rvw-314296438-20260820/plp'',v_method<>''GET'');'||E'\n  '||token);
  elsif r.proname='pandora_chat_capability_dispatch_native_v1' then
   token:='v_env := private.pandora_integration_github_api_20260825(';
   if position(token in a)=0 then raise exception 'Native GitHub patch anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''github'',v_repo,false);'||E'\n        '||token);
   token:='select decrypted_secret into v_token';
   if position(token in a)=0 then raise exception 'Native Supabase patch anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''supabase'',v_project_ref,false);'||E'\n      '||token);
   token:='v_env := private.pandora_worker_f_vercel_api_20260829(';
   if position(token in a)=0 then raise exception 'Native Vercel patch anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''vercel'',v_project_id,false);'||E'\n      '||token);
  else
   token:='v_repo_response := private.pandora_project_github_read_v1(';
   if position(token in a)=0 then raise exception 'Repository snapshot patch anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''github'',v_project.repository,false);'||E'\n  '||token);
  end if;
  if a=b then raise exception 'Tenant guard patch did not change %',r.identity; end if;
  execute a;
  insert into private.pandora_security_patch_receipts(migration_key,function_identity,before_sha256,after_sha256,before_definition,after_definition)
  values('pandora_provider_tenant_binding_v1',r.identity,encode(extensions.digest(b,'sha256'),'hex'),encode(extensions.digest(a,'sha256'),'hex'),b,a)
  on conflict do nothing;
 end loop;
end;
$patch$;
