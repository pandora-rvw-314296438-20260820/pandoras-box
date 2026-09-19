-- Pandora Worker I: exact ProjectSpec primitive selection receipts.
-- Trust remains Worker E authority; this migration cannot promote a primitive to TRUSTED.
create table if not exists public.pandora_primitive_catalog_entries(
  primitive_name text not null,
  primitive_version text not null,
  source_commit text not null,
  source_manifest_path text not null,
  source_digest text not null,
  trust_state text not null default 'EXPERIMENTAL',
  worker_e_evidence_ref text null,
  required_dependencies text[] not null default '{}'::text[],
  supported_project_types text[] not null,
  registered_at timestamptz not null default now(),
  primary key(primitive_name,primitive_version),
  constraint pandora_primitive_catalog_name_check check(primitive_name~'^pandora-[a-z0-9-]+$'),
  constraint pandora_primitive_catalog_version_check check(primitive_version~'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'),
  constraint pandora_primitive_catalog_commit_check check(source_commit~'^[0-9a-f]{40}$'),
  constraint pandora_primitive_catalog_manifest_check check(source_manifest_path~'^packages/primitives/[a-z0-9-]+/SOURCE_MANIFEST\.json$'),
  constraint pandora_primitive_catalog_digest_check check(source_digest~'^sha256:[0-9a-f]{64}$'),
  constraint pandora_primitive_catalog_trust_check check(trust_state in('EXPERIMENTAL','TRUSTED','DEPRECATED','BLOCKED')),
  constraint pandora_primitive_catalog_trusted_evidence_check check(trust_state<>'TRUSTED' or worker_e_evidence_ref is not null),
  constraint pandora_primitive_catalog_project_types_check check(cardinality(supported_project_types)>0)
);

create table if not exists public.pandora_project_spec_primitive_resolutions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete cascade,
  require_trusted boolean not null,
  state text not null,
  required_names text[] not null default '{}'::text[],
  blocked_names text[] not null default '{}'::text[],
  primitive_count integer not null default 0,
  selection_digest text not null,
  resolved_at timestamptz not null default now(),
  unique(project_spec_id),
  constraint pandora_project_spec_primitive_resolution_state_check check(state in('READY','BLOCKED')),
  constraint pandora_project_spec_primitive_resolution_count_check check(primitive_count between 0 and 256),
  constraint pandora_project_spec_primitive_resolution_digest_check check(selection_digest~'^sha256:[0-9a-f]{64}$')
);

create table if not exists public.pandora_project_spec_primitive_selections(
  id uuid primary key default gen_random_uuid(),
  resolution_id uuid not null references public.pandora_project_spec_primitive_resolutions(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete cascade,
  primitive_name text not null,
  primitive_version text not null,
  trust_state text not null,
  source_commit text not null,
  source_manifest_path text not null,
  source_digest text not null,
  worker_e_evidence_ref text null,
  selection_reason text not null default 'project_spec_inference',
  created_at timestamptz not null default now(),
  unique(project_spec_id,primitive_name),
  constraint pandora_project_spec_primitive_selection_name_check check(primitive_name~'^pandora-[a-z0-9-]+$'),
  constraint pandora_project_spec_primitive_selection_version_check check(primitive_version~'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'),
  constraint pandora_project_spec_primitive_selection_trust_check check(trust_state in('EXPERIMENTAL','TRUSTED','DEPRECATED')),
  constraint pandora_project_spec_primitive_selection_commit_check check(source_commit~'^[0-9a-f]{40}$'),
  constraint pandora_project_spec_primitive_selection_digest_check check(source_digest~'^sha256:[0-9a-f]{64}$'),
  constraint pandora_project_spec_primitive_selection_trusted_evidence_check check(trust_state<>'TRUSTED' or worker_e_evidence_ref is not null)
);

insert into public.pandora_primitive_catalog_entries(primitive_name,primitive_version,source_commit,source_manifest_path,source_digest,required_dependencies,supported_project_types)
values
('pandora-auth','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/auth/SOURCE_MANIFEST.json','sha256:f06d34a7aabd1fd1ab94fdc0374efa88d093bc8211f70ccd769d78c9e1e6849c','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-rbac','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/rbac/SOURCE_MANIFEST.json','sha256:7ce794620e444755ac9701677ca58821178b9ea0e0e0ebf4e33048e0f68388c4',array['pandora-auth'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-admin','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/admin/SOURCE_MANIFEST.json','sha256:5f48184a6579dd0550a6d05d8e5413e192de6b326b36562b45e8c54d87c7b441',array['pandora-rbac','pandora-audit'],array['website','web_application','mobile_application','system']),
('pandora-audit','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/audit/SOURCE_MANIFEST.json','sha256:23e04d2256d2bb9231fe43cf4469fa2ddd479ff64fe135fed7954908ea49cb1e',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-notifications','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/notifications/SOURCE_MANIFEST.json','sha256:446bcbb4d197d6709f73c7045880eaac052cb206259d67805284f20823ff06f6','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-analytics','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/analytics/SOURCE_MANIFEST.json','sha256:4a2f838a5a7c0a0e9e562cd38a553cafcd27dc20003ae92bc13d00c1a3adc774','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-booking','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/booking/SOURCE_MANIFEST.json','sha256:51465976ab10d5fe7882f1b59e5b90edb2debb64a4518e01f7e034089e1c12ad','{}',array['website','web_application','mobile_application','system']),
('pandora-commerce','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/commerce/SOURCE_MANIFEST.json','sha256:036157e688c199bf61f4a851e13d525653ca27af76568e8d3bc684632636371e','{}',array['website','web_application','mobile_application','system']),
('pandora-billing','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/billing/SOURCE_MANIFEST.json','sha256:a33262d419b16b2ca5cd3013a5252f0a94fbdae7b0475940909b747b9e70e43b','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-crm','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/crm/SOURCE_MANIFEST.json','sha256:737166cb39bb3b8aba4cca3b1353be09873d0f96c97654cfdaaa0e2fbf98e4c9',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-forms','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/forms/SOURCE_MANIFEST.json','sha256:2d1a4a084e953ebf1223c26018da17230e24c0f38d17dd225bbf24e5c73d6e0c','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-files','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/files/SOURCE_MANIFEST.json','sha256:a7a1525dd2becd8c979180d733d6ddfb976c2d056c70244e49843b7aa42fb3b1',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-search','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/search/SOURCE_MANIFEST.json','sha256:ebc7498d684de962cb8d583eeb463b84b5c4c672f1db896c42a87d9b6bf57299','{}',array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-content','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/content/SOURCE_MANIFEST.json','sha256:ddcc7c8b38c72d109595a8afca33f6ebe24f8e4f02ce42d46e768ea875e50dbf',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-scheduling','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/scheduling/SOURCE_MANIFEST.json','sha256:feb5a35d2de97c4dfdff32dc34bdf5d300af9033051b3e1a4569bdaf6d77e43e',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-customer-profile','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/customer-profile/SOURCE_MANIFEST.json','sha256:301003c5c76eccf794e09a0bb244328b4f0f48c0f5e17269471617929780158f',array['pandora-auth','pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-settings','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/settings/SOURCE_MANIFEST.json','sha256:082b563ddadce124068d5943b30d06393c904684956d12f85057f673d7507f28',array['pandora-rbac'],array['website','web_application','mobile_application','system','api','automation','other']),
('pandora-feature-flags','1.0.0','7154542091faffd86026633094ba11fb487ff0e1','packages/primitives/feature-flags/SOURCE_MANIFEST.json','sha256:83ffd7d4522cbc34e21a7c1fb322ec3b0a01dfdc9972ec22c0f78ec722995636',array['pandora-rbac','pandora-audit'],array['website','web_application','mobile_application','system','api','automation','other'])
on conflict(primitive_name,primitive_version) do update set
 source_commit=excluded.source_commit,source_manifest_path=excluded.source_manifest_path,source_digest=excluded.source_digest,
 required_dependencies=excluded.required_dependencies,supported_project_types=excluded.supported_project_types;

create or replace function private.pandora_worker_i_required_primitives_20260831(p_project_spec_id uuid)
returns text[] language plpgsql stable security definer set search_path='' as $$
declare v_product jsonb;v_integrations jsonb;v_business text;v_text text;v_names text[]:='{}'::text[];v_result text[];
begin
 select product_scope,integration_scope,coalesce(business_summary,'') into v_product,v_integrations,v_business
 from public.pandora_project_specs where id=p_project_spec_id;
 if not found then raise exception 'project spec not found' using errcode='22023'; end if;
 if jsonb_array_length(case when jsonb_typeof(v_product->'roles')='array' then v_product->'roles' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-auth','pandora-rbac'];end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'payment')='array' then v_integrations->'payment' else '[]'::jsonb end)>0 then v_names:=v_names||array['pandora-commerce','pandora-billing'];end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'messaging')='array' then v_integrations->'messaging' else '[]'::jsonb end)>0 then v_names:=v_names||'pandora-notifications';end if;
 if jsonb_array_length(case when jsonb_typeof(v_integrations->'analytics')='array' then v_integrations->'analytics' else '[]'::jsonb end)>0 then v_names:=v_names||'pandora-analytics';end if;
 select lower(concat_ws(' ',v_business,coalesce(string_agg(value,' '),''))) into v_text from(
   select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'features')='array' then v_product->'features' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'workflows')='array' then v_product->'workflows' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'screens')='array' then v_product->'screens' else '[]'::jsonb end)
   union all select value from jsonb_array_elements_text(case when jsonb_typeof(v_product->'userStories')='array' then v_product->'userStories' else '[]'::jsonb end)
 ) q;
 if v_text~'\m(auth(entication)?|sign[ -]?in|log[ -]?in|password reset|magic link|account access)\M' then v_names:=v_names||'pandora-auth';end if;
 if v_text~'\m(role|permission|access control|rbac)\M' then v_names:=v_names||array['pandora-auth','pandora-rbac'];end if;
 if v_text~'\m(admin|back office|operations console)\M' then v_names:=v_names||'pandora-admin';end if;
 if v_text~'\m(audit|activity log|change log)\M' then v_names:=v_names||'pandora-audit';end if;
 if v_text~'\m(notification|push message|in-app message|email notification|sms notification)\M' then v_names:=v_names||'pandora-notifications';end if;
 if v_text~'\m(analytics|product metric|business metric|event tracking)\M' then v_names:=v_names||'pandora-analytics';end if;
 if v_text~'\m(booking|reservation|availability|capacity)\M' then v_names:=v_names||'pandora-booking';end if;
 if v_text~'\m(commerce|cart|checkout|catalog|inventory|order|storefront|shop)\M' then v_names:=v_names||'pandora-commerce';end if;
 if v_text~'\m(payment|billing|refund|invoice|subscription charge)\M' then v_names:=v_names||'pandora-billing';end if;
 if v_text~'\m(crm|lead pipeline|sales pipeline|customer interaction)\M' then v_names:=v_names||'pandora-crm';end if;
 if v_text~'\m(form submission|intake form|survey form|application form)\M' then v_names:=v_names||'pandora-forms';end if;
 if v_text~'\m(file upload|attachment|object storage|signed file|image upload)\M' then v_names:=v_names||'pandora-files';end if;
 if v_text~'\m(search|filterable search)\M' then v_names:=v_names||'pandora-search';end if;
 if v_text~'\m(cms|content management|article|faq|page editor)\M' then v_names:=v_names||'pandora-content';end if;
 if v_text~'\m(schedule|calendar|recurrence|time slot)\M' then v_names:=v_names||'pandora-scheduling';end if;
 if v_text~'\m(customer profile|user profile|preferences|consent)\M' then v_names:=v_names||'pandora-customer-profile';end if;
 if v_text~'\m(settings|timezone|currency|locale|branding settings)\M' then v_names:=v_names||'pandora-settings';end if;
 if v_text~'\m(feature flag|feature toggle|runtime flag)\M' then v_names:=v_names||'pandora-feature-flags';end if;
 select coalesce(array_agg(distinct x order by x),'{}'::text[]) into v_result from unnest(v_names) x;
 return v_result;
end;$$;

create or replace function private.pandora_worker_i_resolve_project_spec_primitives_20260831(p_project_spec_id uuid,p_require_trusted boolean default true)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_org uuid;v_project uuid;v_type text;v_required text[];v_expanded text[];v_blocked text[];v_resolution uuid;v_digest text;v_count int;v_rows jsonb;
begin
 select organization_id,project_id,project_type into v_org,v_project,v_type from public.pandora_project_specs where id=p_project_spec_id;
 if not found then raise exception 'project spec not found' using errcode='22023';end if;
 v_required:=private.pandora_worker_i_required_primitives_20260831(p_project_spec_id);
 if cardinality(v_required)=0 then v_expanded:='{}'::text[]; else
   with recursive dep(name) as(
     select unnest(v_required)
     union
     select u.name from dep d join public.pandora_primitive_catalog_entries c on c.primitive_name=d.name cross join lateral unnest(c.required_dependencies) u(name)
   ) select array_agg(distinct name order by name) into v_expanded from dep;
 end if;
 select coalesce(array_agg(r.name order by r.name),'{}'::text[]) into v_blocked
 from unnest(v_expanded) r(name)
 left join lateral(
   select c.* from public.pandora_primitive_catalog_entries c
   where c.primitive_name=r.name and v_type=any(c.supported_project_types) and c.trust_state<>'BLOCKED'
     and(not p_require_trusted or(c.trust_state='TRUSTED' and c.worker_e_evidence_ref is not null))
   order by split_part(c.primitive_version,'.',1)::int desc,split_part(c.primitive_version,'.',2)::int desc,split_part(split_part(c.primitive_version,'-',1),'.',3)::int desc limit 1
 ) c on true where c.primitive_name is null;
 v_digest:='sha256:'||encode(extensions.digest(convert_to(p_project_spec_id::text||'|'||p_require_trusted::text||'|'||array_to_string(v_expanded,',')||'|'||array_to_string(v_blocked,','),'UTF8'),'sha256'),'hex');
 insert into public.pandora_project_spec_primitive_resolutions(organization_id,project_id,project_spec_id,require_trusted,state,required_names,blocked_names,primitive_count,selection_digest,resolved_at)
 values(v_org,v_project,p_project_spec_id,p_require_trusted,case when cardinality(v_blocked)>0 then 'BLOCKED' else 'READY' end,v_expanded,v_blocked,0,v_digest,now())
 on conflict(project_spec_id) do update set require_trusted=excluded.require_trusted,state=excluded.state,required_names=excluded.required_names,blocked_names=excluded.blocked_names,primitive_count=0,selection_digest=excluded.selection_digest,resolved_at=now()
 returning id into v_resolution;
 delete from public.pandora_project_spec_primitive_selections where project_spec_id=p_project_spec_id;
 if cardinality(v_blocked)>0 then
   return jsonb_build_object('state','BLOCKED','projectSpecId',p_project_spec_id,'requireTrusted',p_require_trusted,'requiredPrimitives',to_jsonb(v_expanded),'blockedPrimitives',to_jsonb(v_blocked),'selectionDigest',v_digest,'selections','[]'::jsonb);
 end if;
 insert into public.pandora_project_spec_primitive_selections(resolution_id,organization_id,project_id,project_spec_id,primitive_name,primitive_version,trust_state,source_commit,source_manifest_path,source_digest,worker_e_evidence_ref)
 select v_resolution,v_org,v_project,p_project_spec_id,r.name,c.primitive_version,c.trust_state,c.source_commit,c.source_manifest_path,c.source_digest,c.worker_e_evidence_ref
 from unnest(v_expanded) r(name) join lateral(
   select c.* from public.pandora_primitive_catalog_entries c where c.primitive_name=r.name and v_type=any(c.supported_project_types) and c.trust_state<>'BLOCKED'
     and(not p_require_trusted or(c.trust_state='TRUSTED' and c.worker_e_evidence_ref is not null))
   order by split_part(c.primitive_version,'.',1)::int desc,split_part(c.primitive_version,'.',2)::int desc,split_part(split_part(c.primitive_version,'-',1),'.',3)::int desc limit 1
 ) c on true;
 get diagnostics v_count=row_count;
 update public.pandora_project_spec_primitive_resolutions set primitive_count=v_count where id=v_resolution;
 select coalesce(jsonb_agg(jsonb_build_object('name',primitive_name,'version',primitive_version,'trustState',trust_state,'sourceCommit',source_commit,'sourceManifestPath',source_manifest_path,'sourceDigest',source_digest,'workerEEvidenceRef',worker_e_evidence_ref) order by primitive_name),'[]'::jsonb) into v_rows from public.pandora_project_spec_primitive_selections where resolution_id=v_resolution;
 return jsonb_build_object('state','READY','projectSpecId',p_project_spec_id,'requireTrusted',p_require_trusted,'requiredPrimitives',to_jsonb(v_expanded),'blockedPrimitives','[]'::jsonb,'primitiveCount',v_count,'selectionDigest',v_digest,'selections',v_rows);
end;$$;

create or replace function public.pandora_worker_i_resolve_project_spec_primitives_20260831(p_project_spec_id uuid,p_require_trusted boolean default true)
returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_i_resolve_project_spec_primitives_20260831(p_project_spec_id,p_require_trusted);$$;

create or replace function private.pandora_validate_project_spec_primitive_selection_20260831() returns trigger language plpgsql security definer set search_path='' as $$
declare v_org uuid;v_project uuid;v_catalog record;begin
 select organization_id,project_id into v_org,v_project from public.pandora_project_specs where id=new.project_spec_id;
 if v_org is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'primitive selection ProjectSpec lineage mismatch' using errcode='23514';end if;
 if tg_table_name='pandora_project_spec_primitive_selections' then
   select * into v_catalog from public.pandora_primitive_catalog_entries where primitive_name=new.primitive_name and primitive_version=new.primitive_version;
   if v_catalog.primitive_name is null or v_catalog.source_commit<>new.source_commit or v_catalog.source_manifest_path<>new.source_manifest_path or v_catalog.source_digest<>new.source_digest or v_catalog.trust_state<>new.trust_state or coalesce(v_catalog.worker_e_evidence_ref,'')<>coalesce(new.worker_e_evidence_ref,'') then raise exception 'primitive selection catalog identity mismatch' using errcode='23514';end if;
 end if;return new;end;$$;

drop trigger if exists pandora_project_spec_primitive_resolutions_lineage_guard on public.pandora_project_spec_primitive_resolutions;
create trigger pandora_project_spec_primitive_resolutions_lineage_guard before insert or update on public.pandora_project_spec_primitive_resolutions for each row execute function private.pandora_validate_project_spec_primitive_selection_20260831();
drop trigger if exists pandora_project_spec_primitive_selections_lineage_guard on public.pandora_project_spec_primitive_selections;
create trigger pandora_project_spec_primitive_selections_lineage_guard before insert or update on public.pandora_project_spec_primitive_selections for each row execute function private.pandora_validate_project_spec_primitive_selection_20260831();

alter table public.pandora_primitive_catalog_entries enable row level security;alter table public.pandora_primitive_catalog_entries force row level security;
alter table public.pandora_project_spec_primitive_resolutions enable row level security;alter table public.pandora_project_spec_primitive_resolutions force row level security;
alter table public.pandora_project_spec_primitive_selections enable row level security;alter table public.pandora_project_spec_primitive_selections force row level security;
revoke all on public.pandora_primitive_catalog_entries from public,anon,authenticated;
revoke all on public.pandora_project_spec_primitive_resolutions from public,anon,authenticated;
revoke all on public.pandora_project_spec_primitive_selections from public,anon,authenticated;
revoke all on function private.pandora_worker_i_required_primitives_20260831(uuid) from public,anon,authenticated;
revoke all on function private.pandora_worker_i_resolve_project_spec_primitives_20260831(uuid,boolean) from public,anon,authenticated;
revoke all on function private.pandora_validate_project_spec_primitive_selection_20260831() from public,anon,authenticated;
revoke all on function public.pandora_worker_i_resolve_project_spec_primitives_20260831(uuid,boolean) from public,anon,authenticated;
grant execute on function public.pandora_worker_i_resolve_project_spec_primitives_20260831(uuid,boolean) to service_role;
