begin;

create table if not exists public.pandora_change_impact_assessments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  project_spec_id uuid not null,
  previous_project_spec_id uuid,
  project_spec_sha256 text not null,
  previous_project_spec_sha256 text,
  impact_tier smallint not null,
  impact_class text not null,
  build_scope text not null,
  verification_scope text not null,
  changed_scopes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint pandora_change_impact_assessments_spec_uq unique (organization_id, project_id, project_spec_id),
  constraint pandora_change_impact_assessments_tier_ck check (impact_tier between 0 and 4),
  constraint pandora_change_impact_assessments_class_ck check (impact_class in ('visual','component','app_logic','backend','database')),
  constraint pandora_change_impact_assessments_build_scope_ck check (build_scope in ('visual_incremental','component_incremental','full_candidate')),
  constraint pandora_change_impact_assessments_verification_scope_ck check (verification_scope in ('visual_plus_global','component_plus_global','app_plus_global','backend_plus_global','database_plus_global')),
  constraint pandora_change_impact_assessments_changed_scopes_ck check (jsonb_typeof(changed_scopes) = 'object')
);

create index if not exists pandora_change_impact_assessments_project_idx on public.pandora_change_impact_assessments(organization_id, project_id, created_at desc);
alter table public.pandora_change_impact_assessments enable row level security;
drop policy if exists pandora_change_impact_assessments_project_read on public.pandora_change_impact_assessments;
create policy pandora_change_impact_assessments_project_read on public.pandora_change_impact_assessments for select to authenticated using (exists (select 1 from public.memberships m where m.organization_id = pandora_change_impact_assessments.organization_id and m.user_id = auth.uid() and m.status::text = 'active'));
revoke insert, update, delete on public.pandora_change_impact_assessments from public, anon, authenticated;
grant select on public.pandora_change_impact_assessments to authenticated;

create or replace function private.pandora_project_spec_impact_v1(p_project_spec_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_spec public.pandora_project_specs%rowtype;
  v_prev public.pandora_project_specs%rowtype;
  v_existing public.pandora_change_impact_assessments%rowtype;
  v_tier smallint := 2;
  v_class text := 'app_logic';
  v_build_scope text := 'full_candidate';
  v_verification_scope text := 'app_plus_global';
  v_changed jsonb := '{}'::jsonb;
  v_has_previous boolean := false;
  v_data_changed boolean := false;
  v_database_deployment_changed boolean := false;
  v_integration_changed boolean := false;
  v_non_database_deployment_changed boolean := false;
  v_product_logic_changed boolean := false;
  v_component_changed boolean := false;
  v_brand_changed boolean := false;
  v_other_changed boolean := false;
begin
  if p_project_spec_id is null then raise exception 'PROJECT_SPEC_IMPACT_REQUEST_INVALID' using errcode='22023'; end if;
  select * into v_spec from public.pandora_project_specs s where s.id = p_project_spec_id;
  if not found then raise exception 'PROJECT_SPEC_IMPACT_NOT_FOUND' using errcode='P0002'; end if;
  if v_spec.previous_spec_id is not null then
    select * into v_prev from public.pandora_project_specs p where p.id = v_spec.previous_spec_id and p.organization_id = v_spec.organization_id and p.project_id = v_spec.project_id;
    if not found then raise exception 'PROJECT_SPEC_IMPACT_PREVIOUS_LINEAGE_INVALID' using errcode='23514'; end if;
    v_has_previous := true;
  end if;
  select * into v_existing from public.pandora_change_impact_assessments a where a.organization_id = v_spec.organization_id and a.project_id = v_spec.project_id and a.project_spec_id = v_spec.id;
  if found then
    if v_existing.project_spec_sha256 <> v_spec.content_sha256 or v_existing.previous_project_spec_id is distinct from v_spec.previous_spec_id or (v_has_previous and v_existing.previous_project_spec_sha256 is distinct from v_prev.content_sha256) then raise exception 'PROJECT_SPEC_IMPACT_COLLISION' using errcode='23505'; end if;
    return jsonb_build_object('assessmentId',v_existing.id,'projectSpecId',v_existing.project_spec_id,'previousProjectSpecId',v_existing.previous_project_spec_id,'projectSpecSha256',v_existing.project_spec_sha256,'impactTier',v_existing.impact_tier,'impactClass',v_existing.impact_class,'buildScope',v_existing.build_scope,'verificationScope',v_existing.verification_scope,'changedScopes',v_existing.changed_scopes,'authoritative',true);
  end if;
  if not v_has_previous then
    v_data_changed := coalesce(v_spec.data_scope,'{}'::jsonb) <> '{}'::jsonb;
    v_database_deployment_changed := coalesce(v_spec.deployment_scope->'database','null'::jsonb) <> 'null'::jsonb;
    v_integration_changed := coalesce(v_spec.integration_scope,'{}'::jsonb) <> '{}'::jsonb;
    v_non_database_deployment_changed := (coalesce(v_spec.deployment_scope,'{}'::jsonb)-'database') <> '{}'::jsonb;
    v_product_logic_changed := true; v_component_changed := coalesce(v_spec.experience_scope,'{}'::jsonb) <> '{}'::jsonb; v_brand_changed := coalesce(v_spec.experience_scope->'brandRequirements','null'::jsonb) <> 'null'::jsonb; v_other_changed := true;
  else
    v_data_changed := coalesce(v_spec.data_scope,'{}'::jsonb) is distinct from coalesce(v_prev.data_scope,'{}'::jsonb);
    v_database_deployment_changed := coalesce(v_spec.deployment_scope->'database','null'::jsonb) is distinct from coalesce(v_prev.deployment_scope->'database','null'::jsonb);
    v_integration_changed := coalesce(v_spec.integration_scope,'{}'::jsonb) is distinct from coalesce(v_prev.integration_scope,'{}'::jsonb);
    v_non_database_deployment_changed := (coalesce(v_spec.deployment_scope,'{}'::jsonb)-'database') is distinct from (coalesce(v_prev.deployment_scope,'{}'::jsonb)-'database');
    v_product_logic_changed := v_spec.project_type is distinct from v_prev.project_type or v_spec.target_user_summary is distinct from v_prev.target_user_summary or v_spec.business_summary is distinct from v_prev.business_summary or coalesce(v_spec.product_scope->'features','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'features','null'::jsonb) or coalesce(v_spec.product_scope->'projectType','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'projectType','null'::jsonb) or coalesce(v_spec.product_scope->'roles','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'roles','null'::jsonb) or coalesce(v_spec.product_scope->'users','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'users','null'::jsonb) or coalesce(v_spec.product_scope->'userStories','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'userStories','null'::jsonb) or coalesce(v_spec.product_scope->'workflows','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'workflows','null'::jsonb) or coalesce(v_spec.acceptance_scope,'{}'::jsonb) is distinct from coalesce(v_prev.acceptance_scope,'{}'::jsonb);
    v_component_changed := coalesce(v_spec.product_scope->'screens','null'::jsonb) is distinct from coalesce(v_prev.product_scope->'screens','null'::jsonb) or coalesce(v_spec.experience_scope->'accessibility','null'::jsonb) is distinct from coalesce(v_prev.experience_scope->'accessibility','null'::jsonb) or coalesce(v_spec.experience_scope->'platforms','null'::jsonb) is distinct from coalesce(v_prev.experience_scope->'platforms','null'::jsonb) or coalesce(v_spec.experience_scope->'responsive','null'::jsonb) is distinct from coalesce(v_prev.experience_scope->'responsive','null'::jsonb);
    v_brand_changed := coalesce(v_spec.experience_scope->'brandRequirements','null'::jsonb) is distinct from coalesce(v_prev.experience_scope->'brandRequirements','null'::jsonb);
    v_other_changed := v_spec.schema_version is distinct from v_prev.schema_version or (coalesce(v_spec.product_scope,'{}'::jsonb)-'features'-'projectType'-'roles'-'users'-'userStories'-'workflows'-'screens') is distinct from (coalesce(v_prev.product_scope,'{}'::jsonb)-'features'-'projectType'-'roles'-'users'-'userStories'-'workflows'-'screens') or (coalesce(v_spec.experience_scope,'{}'::jsonb)-'accessibility'-'platforms'-'responsive'-'brandRequirements') is distinct from (coalesce(v_prev.experience_scope,'{}'::jsonb)-'accessibility'-'platforms'-'responsive'-'brandRequirements');
  end if;
  v_changed := jsonb_strip_nulls(jsonb_build_object('initialSpec',case when not v_has_previous then true else null end,'data',case when v_data_changed then true else null end,'databaseDeployment',case when v_database_deployment_changed then true else null end,'integrations',case when v_integration_changed then true else null end,'deployment',case when v_non_database_deployment_changed then true else null end,'appLogic',case when v_product_logic_changed then true else null end,'component',case when v_component_changed then true else null end,'brand',case when v_brand_changed then true else null end,'other',case when v_other_changed then true else null end));
  if v_data_changed or v_database_deployment_changed then v_tier:=4; v_class:='database'; v_build_scope:='full_candidate'; v_verification_scope:='database_plus_global';
  elsif v_integration_changed or v_non_database_deployment_changed then v_tier:=3; v_class:='backend'; v_build_scope:='full_candidate'; v_verification_scope:='backend_plus_global';
  elsif v_product_logic_changed or v_other_changed or not v_has_previous then v_tier:=2; v_class:='app_logic'; v_build_scope:='full_candidate'; v_verification_scope:='app_plus_global';
  elsif v_component_changed then v_tier:=1; v_class:='component'; v_build_scope:='component_incremental'; v_verification_scope:='component_plus_global';
  elsif v_brand_changed then v_tier:=0; v_class:='visual'; v_build_scope:='visual_incremental'; v_verification_scope:='visual_plus_global';
  else v_tier:=2; v_class:='app_logic'; v_build_scope:='full_candidate'; v_verification_scope:='app_plus_global'; v_changed:=jsonb_build_object('conservativeFallback',true); end if;
  insert into public.pandora_change_impact_assessments(organization_id,project_id,project_spec_id,previous_project_spec_id,project_spec_sha256,previous_project_spec_sha256,impact_tier,impact_class,build_scope,verification_scope,changed_scopes) values (v_spec.organization_id,v_spec.project_id,v_spec.id,v_spec.previous_spec_id,v_spec.content_sha256,case when v_has_previous then v_prev.content_sha256 else null end,v_tier,v_class,v_build_scope,v_verification_scope,v_changed) returning * into v_existing;
  return jsonb_build_object('assessmentId',v_existing.id,'projectSpecId',v_existing.project_spec_id,'previousProjectSpecId',v_existing.previous_project_spec_id,'projectSpecSha256',v_existing.project_spec_sha256,'impactTier',v_existing.impact_tier,'impactClass',v_existing.impact_class,'buildScope',v_existing.build_scope,'verificationScope',v_existing.verification_scope,'changedScopes',v_existing.changed_scopes,'authoritative',true);
end;$function$;

create or replace function public.pandora_project_change_impact_service_v1(p_project_spec_id uuid) returns jsonb language sql security definer set search_path='' as $function$ select private.pandora_project_spec_impact_v1(p_project_spec_id) $function$;
revoke all on function public.pandora_project_change_impact_service_v1(uuid) from public, anon, authenticated;
grant execute on function public.pandora_project_change_impact_service_v1(uuid) to service_role;

alter table public.pandora_build_authorization_receipts add column if not exists impact_assessment_id uuid;
do $block$ begin if not exists (select 1 from pg_constraint where conname='pandora_build_authorization_receipts_impact_fk' and conrelid='public.pandora_build_authorization_receipts'::regclass) then alter table public.pandora_build_authorization_receipts add constraint pandora_build_authorization_receipts_impact_fk foreign key (impact_assessment_id) references public.pandora_change_impact_assessments(id); end if; end $block$;

create or replace function private.pandora_bind_build_impact_v1() returns trigger language plpgsql security definer set search_path='' as $function$ declare v_impact jsonb; begin if new.impact_assessment_id is null then v_impact:=private.pandora_project_spec_impact_v1(new.project_spec_id); new.impact_assessment_id:=(v_impact->>'assessmentId')::uuid; end if; return new; end;$function$;
drop trigger if exists pandora_bind_build_impact_v1 on public.pandora_build_authorization_receipts;
create trigger pandora_bind_build_impact_v1 before insert or update of project_spec_id on public.pandora_build_authorization_receipts for each row execute function private.pandora_bind_build_impact_v1();

do $block$ declare v_row record; v_impact jsonb; begin for v_row in select r.id,r.project_spec_id from public.pandora_build_authorization_receipts r where r.impact_assessment_id is null loop v_impact:=private.pandora_project_spec_impact_v1(v_row.project_spec_id); update public.pandora_build_authorization_receipts set impact_assessment_id=(v_impact->>'assessmentId')::uuid where id=v_row.id and impact_assessment_id is null; end loop; end $block$;

commit;