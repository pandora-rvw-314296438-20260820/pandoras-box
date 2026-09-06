begin;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_finalize_renderable_preview_reverification_20260906(uuid,uuid)'::regprocedure
  ) into v_def;

  v_old :=
    '  return jsonb_build_object('||chr(10)||
    '    ''state'',''ready'','||chr(10)||
    '    ''deploymentId'',v_dep.id,'||chr(10)||
    '    ''projectVersionId'',v_ver.id,'||chr(10)||
    '    ''verificationRunId'',v_run.id,'||chr(10)||
    '    ''currentPreview'',v_current'||chr(10)||
    '  );';

  v_new :=
    '  update public.pandora_project_versions pv'||chr(10)||
    '  set lifecycle_status=''live'''||chr(10)||
    '  where pv.id=v_ver.id'||chr(10)||
    '    and pv.lifecycle_status=''verified'''||chr(10)||
    '    and exists ('||chr(10)||
    '      select 1 from public.pandora_runtime_environments pe'||chr(10)||
    '      where pe.organization_id=v_dep.organization_id'||chr(10)||
    '        and pe.project_id=v_dep.project_id'||chr(10)||
    '        and pe.environment=''production'''||chr(10)||
    '        and pe.current_version_id=v_ver.id'||chr(10)||
    '    );'||chr(10)||chr(10)||
    '  return jsonb_build_object('||chr(10)||
    '    ''state'',''ready'','||chr(10)||
    '    ''deploymentId'',v_dep.id,'||chr(10)||
    '    ''projectVersionId'',v_ver.id,'||chr(10)||
    '    ''verificationRunId'',v_run.id,'||chr(10)||
    '    ''currentPreview'',v_current'||chr(10)||
    '  );';

  if position('pe.current_version_id=v_ver.id' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PREVIEW_REVERIFY_LIFECYCLE_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
    execute v_def;
  end if;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_finalize_renderable_production_reverification_20260906(uuid,uuid)'::regprocedure
  ) into v_def;

  v_old := 'if not found or v_ver.lifecycle_status<>''live'' or v_ver.build_job_id is null then';
  v_new := 'if not found or v_ver.lifecycle_status not in (''live'',''verified'') or v_ver.build_job_id is null then';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_REVERIFY_LIFECYCLE_GUARD_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old :=
    '  update public.pandora_project_versions'||chr(10)||
    '  set verification_run_id=v_run.id,'||chr(10)||
    '      rollback_eligible=true'||chr(10)||
    '  where id=v_ver.id'||chr(10)||
    '    and lifecycle_status=''live'';';

  v_new :=
    '  update public.pandora_project_versions'||chr(10)||
    '  set verification_run_id=v_run.id,'||chr(10)||
    '      rollback_eligible=true,'||chr(10)||
    '      lifecycle_status=''live'''||chr(10)||
    '  where id=v_ver.id'||chr(10)||
    '    and lifecycle_status in (''live'',''verified'');';

  if position('lifecycle_status in (''live'',''verified'')' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'PRODUCTION_REVERIFY_LIFECYCLE_UPDATE_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end
$migration$;

comment on function private.pandora_finalize_renderable_preview_reverification_20260906(uuid,uuid) is
'Finalizes fresh transport-bound preview PASS evidence and preserves live lifecycle when the same exact version currently backs production.';
comment on function private.pandora_finalize_renderable_production_reverification_20260906(uuid,uuid) is
'Re-certifies the exact current production deployment after render-transport migration. Accepts temporary verified lifecycle only under exact current-production lineage and restores live after PASS.';

commit;
