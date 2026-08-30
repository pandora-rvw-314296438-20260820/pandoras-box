create or replace function private.pandora_converge_static_builds_tick_20260830()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $function$
declare
  v_job record;
  v_result jsonb;
  v_processed integer := 0;
  v_ready integer := 0;
  v_errors integer := 0;
  v_last_error text := null;
  v_last_sqlstate text := null;
  v_last_job_id uuid := null;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('pandora-static-build-convergence-v1',0)) then
    return jsonb_build_object('state','busy','processed',0,'ready',0,'errors',0);
  end if;

  for v_job in
    select j.id,j.project_id
    from public.pandora_build_jobs j
    join public.pandora_project_versions v
      on v.id=j.target_project_version_id
     and v.organization_id=j.organization_id
     and v.project_id=j.project_id
    where j.job_kind='build'
      and j.status in ('queued','claimed','running','waiting_verification')
      and coalesce(v.source_payload->>'buildAdapter','')='static-web'
    order by j.created_at asc,j.id asc
    limit 5
  loop
    begin
      perform private.pandora_ensure_static_build_vercel_project_20260830(v_job.project_id);
      v_result:=private.pandora_converge_static_site_build_v2_20260830(v_job.id);
      v_processed:=v_processed+1;
      if coalesce(v_result->>'state','')='ready' then v_ready:=v_ready+1; end if;
    exception when others then
      v_processed:=v_processed+1;
      v_errors:=v_errors+1;
      v_last_job_id:=v_job.id;
      v_last_error:=sqlerrm;
      v_last_sqlstate:=sqlstate;
    end;
  end loop;

  return jsonb_build_object('state','ok','processed',v_processed,'ready',v_ready,'errors',v_errors,'lastBuildJobId',v_last_job_id,'lastSqlstate',v_last_sqlstate,'lastError',v_last_error);
end
$function$;