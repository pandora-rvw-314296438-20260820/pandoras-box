do $$
declare
  v_def text;
  nl text:=chr(10);
begin
  if to_regclass('public.pandora_source_generation_queue') is null then
    raise exception 'source generation queue missing';
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_commit_generated_build_intake_20260829';
  if v_def is null then raise exception 'build intake function missing'; end if;

  if position('v_parent_project_version_id uuid;' in v_def)=0 then
    v_def:=replace(v_def,'  v_source_intent_id uuid;','  v_source_intent_id uuid;'||nl||'  v_parent_project_version_id uuid;');
    v_def:=replace(v_def,'  v_source_intent_id := v_spec.source_intent_id;','  v_source_intent_id := v_spec.source_intent_id;'||nl||nl||
      '  select q.base_version_id into v_parent_project_version_id'||nl||
      '  from public.pandora_source_generation_queue q'||nl||
      '  where q.organization_id=p_organization_id and q.project_id=p_project_id and q.project_spec_id=p_project_spec_id'||nl||
      '    and q.idempotency_key=trim(p_idempotency_key)'||nl||
      '  order by q.created_at desc limit 1;'||nl||
      '  if v_parent_project_version_id is not null and not exists ('||nl||
      '    select 1 from public.pandora_project_versions pv where pv.id=v_parent_project_version_id and pv.organization_id=p_organization_id and pv.project_id=p_project_id'||nl||
      '  ) then raise exception ''BUILD_INTAKE_PARENT_VERSION_INVALID'' using errcode=''23514''; end if;');
    v_def:=replace(v_def,'    project_spec_id, root_artifact_version_id, lifecycle_status','    project_spec_id, parent_version_id, root_artifact_version_id, lifecycle_status');
    v_def:=replace(v_def,'    p_source_sha256, p_requested_by, p_project_spec_id, v_artifact_version_id, ''draft''','    p_source_sha256, p_requested_by, p_project_spec_id, v_parent_project_version_id, v_artifact_version_id, ''draft''');
    if position('project_spec_id, parent_version_id, root_artifact_version_id' in v_def)=0 then raise exception 'parent column patch failed'; end if;
    execute v_def;
  end if;
end $$;

update public.pandora_project_versions pv
set parent_version_id=q.base_version_id
from public.pandora_build_jobs j
join public.pandora_source_generation_queue q
  on q.organization_id=j.organization_id
 and q.project_id=j.project_id
 and q.project_spec_id=j.project_spec_id
 and q.idempotency_key=j.idempotency_key
where pv.id=j.target_project_version_id
  and pv.organization_id=j.organization_id
  and pv.project_id=j.project_id
  and pv.parent_version_id is null
  and q.base_version_id is not null
  and q.base_version_id<>pv.id
  and exists(select 1 from public.pandora_project_versions parent where parent.id=q.base_version_id and parent.organization_id=pv.organization_id and parent.project_id=pv.project_id);
