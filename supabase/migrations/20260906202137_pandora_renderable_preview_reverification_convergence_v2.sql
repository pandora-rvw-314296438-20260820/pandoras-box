begin;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_converge_static_site_build_v2_20260830(uuid)'::regprocedure
  ) into v_def;

  v_old :=
    '  if v_job.status=''succeeded'' and v_ver.lifecycle_status in (''verified'',''preview_ready'',''live'') then'||chr(10)||
    '    return jsonb_build_object(''buildJobId'',v_job.id,''projectVersionId'',v_ver.id,''state'',''ready'',''replayed'',true);'||chr(10)||
    '  end if;';

  v_new :=
    '  if v_job.status=''succeeded'' and v_ver.lifecycle_status in (''verified'',''preview_ready'',''live'')'||chr(10)||
    '     and not exists ('||chr(10)||
    '       select 1 from public.pandora_project_deployments pending_dep'||chr(10)||
    '       where pending_dep.organization_id=v_job.organization_id'||chr(10)||
    '         and pending_dep.project_id=v_job.project_id'||chr(10)||
    '         and pending_dep.version_id=v_ver.id'||chr(10)||
    '         and pending_dep.environment=''preview'''||chr(10)||
    '         and pending_dep.provider=''supabase_preview'''||chr(10)||
    '         and pending_dep.provider_state=''READY'''||chr(10)||
    '         and pending_dep.status=''ready_for_verification'''||chr(10)||
    '         and pending_dep.verification_state=''ready_for_verification'''||chr(10)||
    '     ) then'||chr(10)||
    '    return jsonb_build_object(''buildJobId'',v_job.id,''projectVersionId'',v_ver.id,''state'',''ready'',''replayed'',true);'||chr(10)||
    '  end if;';

  if position('pending_dep.verification_state=''ready_for_verification''' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'RENDERABLE_PREVIEW_REVERIFY_GUARD_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
    execute v_def;
  end if;
end
$migration$;

comment on function private.pandora_converge_static_site_build_v2_20260830(uuid) is
'Static convergence may replay a succeeded build only when no exact Supabase preview deployment is pending render-transport re-verification.';

commit;
