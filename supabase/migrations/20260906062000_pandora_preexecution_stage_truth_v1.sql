-- VIDEO 4419: pre-execution builds must not present as active building work.
-- Guard canonical job/session state and projection until a real execution attempt begins.

begin;

create or replace function private.pandora_enforce_preexecution_build_stage_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status = 'queued'
     and coalesce(new.attempt_count, 0) = 0
     and new.started_at is null
     and new.current_stage = 'building' then
    new.current_stage := 'understanding';
  end if;
  return new;
end
$function$;

drop trigger if exists pandora_enforce_preexecution_build_stage_v1 on public.pandora_build_jobs;
create trigger pandora_enforce_preexecution_build_stage_v1
before insert or update of status,current_stage,attempt_count,started_at
on public.pandora_build_jobs
for each row execute function private.pandora_enforce_preexecution_build_stage_v1();

create or replace function private.pandora_enforce_preexecution_stream_status_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status = 'building'
     and new.build_job_id is not null
     and exists (
       select 1 from public.pandora_build_jobs j
       where j.id = new.build_job_id
         and j.status = 'queued'
         and coalesce(j.attempt_count, 0) = 0
         and j.started_at is null
     ) then
    new.status := 'queued';
  end if;
  return new;
end
$function$;

drop trigger if exists pandora_enforce_preexecution_stream_status_v1 on public.pandora_build_stream_sessions;
create trigger pandora_enforce_preexecution_stream_status_v1
before insert or update of status,build_job_id
on public.pandora_build_stream_sessions
for each row execute function private.pandora_enforce_preexecution_stream_status_v1();

create or replace function private.pandora_sync_build_theatre_from_job()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_preexecution boolean;
  v_preexecution_terminal boolean;
  v_owner_stage text;
  v_progress smallint;
  v_message text;
begin
  if exists (
    select 1 from public.pandora_build_jobs newer
    where newer.organization_id = new.organization_id
      and newer.project_id = new.project_id
      and newer.job_kind = 'build'
      and (newer.created_at > new.created_at or (newer.created_at = new.created_at and newer.id::text > new.id::text))
  ) then
    return new;
  end if;

  v_preexecution := coalesce(new.attempt_count, 0) = 0 and new.started_at is null;
  v_preexecution_terminal := v_preexecution and new.status in ('failed','cancelled');
  v_owner_stage := case when v_preexecution then 'understanding' else private.pandora_build_theatre_owner_stage(new.current_stage,new.status) end;
  v_progress := case when v_preexecution then 0 else private.pandora_build_theatre_progress(new.current_stage,new.status) end;
  v_message := case
    when not v_preexecution then private.pandora_build_theatre_message(new.current_stage,new.status)
    when v_preexecution_terminal and new.error_code = 'BUILD_DEADLINE_EXCEEDED' then 'Pandora could not start this build before its execution window ended.'
    when v_preexecution_terminal and new.error_code = 'BUILD_BUDGET_EXHAUSTED' then 'Pandora did not start this build because its build budget was unavailable.'
    when v_preexecution_terminal then 'Pandora did not start this build. You can try again.'
    else 'Pandora is preparing this build.'
  end;

  insert into public.pandora_build_theatre_projection(
    project_id,organization_id,build_job_id,project_spec_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,needs_you,retry_available,last_event_at,updated_at
  ) values (
    new.project_id,new.organization_id,new.id,new.project_spec_id,new.target_project_version_id,
    private.pandora_build_theatre_owner_state(case when v_preexecution then 'understanding' else new.current_stage end,new.status),
    v_owner_stage,v_progress,v_message,
    new.status = 'waiting_approval' or new.current_stage in ('awaiting_approval','needs_you'),
    new.status in ('failed','cancelled'),now(),now()
  )
  on conflict (project_id) do update set
    organization_id=excluded.organization_id,build_job_id=excluded.build_job_id,project_spec_id=excluded.project_spec_id,
    project_version_id=coalesce(excluded.project_version_id,pandora_build_theatre_projection.project_version_id),
    owner_state=excluded.owner_state,owner_stage=excluded.owner_stage,progress_percent=excluded.progress_percent,
    public_message=excluded.public_message,needs_you=excluded.needs_you,retry_available=excluded.retry_available,
    last_event_at=excluded.last_event_at,updated_at=excluded.updated_at;
  return new;
end
$function$;

update public.pandora_build_jobs
set current_stage='understanding',updated_at=clock_timestamp()
where status='queued' and coalesce(attempt_count,0)=0 and started_at is null and current_stage='building';

update public.pandora_build_stream_sessions s
set status='queued',updated_at=clock_timestamp()
where s.status='building' and exists (
  select 1 from public.pandora_build_jobs j
  where j.id=s.build_job_id and j.status='queued' and coalesce(j.attempt_count,0)=0 and j.started_at is null
);

update public.pandora_build_jobs
set updated_at=clock_timestamp()
where status='queued' and coalesce(attempt_count,0)=0 and started_at is null;

commit;
