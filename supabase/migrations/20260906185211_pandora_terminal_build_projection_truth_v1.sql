begin;

create or replace function private.pandora_sync_build_theatre_from_job()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_preexecution_terminal boolean;
  v_terminal_failure boolean;
  v_owner_stage text;
  v_progress smallint;
  v_message text;
begin
  if exists (
    select 1
    from public.pandora_build_jobs newer
    where newer.organization_id = new.organization_id
      and newer.project_id = new.project_id
      and newer.job_kind = 'build'
      and (
        newer.created_at > new.created_at
        or (newer.created_at = new.created_at and newer.id::text > new.id::text)
      )
  ) then
    return new;
  end if;

  v_preexecution_terminal :=
    new.status in ('failed','cancelled')
    and coalesce(new.attempt_count, 0) = 0
    and new.started_at is null;
  v_terminal_failure := new.status = 'failed';

  v_owner_stage := case
    when v_preexecution_terminal then 'understanding'
    when v_terminal_failure then 'needs_you'
    else private.pandora_build_theatre_owner_stage(new.current_stage,new.status)
  end;
  v_progress := case
    when v_preexecution_terminal then 0
    else private.pandora_build_theatre_progress(new.current_stage,new.status)
  end;
  v_message := case
    when v_preexecution_terminal and new.error_code = 'BUILD_DEADLINE_EXCEEDED'
      then 'Pandora could not start this build before its execution window ended.'
    when v_preexecution_terminal and new.error_code = 'BUILD_BUDGET_EXHAUSTED'
      then 'Pandora did not start this build because its build budget was unavailable.'
    when v_preexecution_terminal
      then 'Pandora did not start this build. You can try again.'
    when v_terminal_failure
      then coalesce(nullif(trim(new.public_error_summary),''),
        'This build stopped before it was ready. You can retry.')
    else private.pandora_build_theatre_message(new.current_stage,new.status)
  end;

  insert into public.pandora_build_theatre_projection(
    project_id,organization_id,build_job_id,project_spec_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,needs_you,retry_available,
    last_event_at,updated_at
  ) values (
    new.project_id,new.organization_id,new.id,new.project_spec_id,new.target_project_version_id,
    private.pandora_build_theatre_owner_state(new.current_stage,new.status),
    v_owner_stage,
    v_progress,
    v_message,
    new.status = 'failed' or new.status = 'waiting_approval'
      or new.current_stage in ('awaiting_approval','needs_you'),
    new.status in ('failed','cancelled'),
    now(),now()
  )
  on conflict (project_id) do update set
    organization_id = excluded.organization_id,
    build_job_id = excluded.build_job_id,
    project_spec_id = excluded.project_spec_id,
    project_version_id = coalesce(excluded.project_version_id, pandora_build_theatre_projection.project_version_id),
    owner_state = excluded.owner_state,
    owner_stage = excluded.owner_stage,
    progress_percent = excluded.progress_percent,
    public_message = excluded.public_message,
    needs_you = excluded.needs_you,
    retry_available = excluded.retry_available,
    last_event_at = excluded.last_event_at,
    updated_at = excluded.updated_at;
  return new;
end
$function$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_compute_project_experience_v1(uuid)'::regprocedure
  ) into v_def;

  if position('n.current_version_id is null and n.latest_failure_is_relevant' in v_def) = 0 then
    v_old := $old$      when n.current_version_id is null
        and (
          n.active_build_job_id is not null
          or n.candidate_version_id is not null
          or n.latest_spec_id is not null
        )
        then 'BUILD'$old$;
    v_new := $new$      when n.current_version_id is null
        and n.latest_failure_is_relevant
        and n.active_build_job_id is null
        then 'UNDERSTAND'
      when n.current_version_id is null
        and (
          n.active_build_job_id is not null
          or n.candidate_version_id is not null
          or n.latest_spec_id is not null
        )
        then 'BUILD'$new$;
    if position(v_old in v_def) = 0 then
      raise exception 'PROJECT_EXPERIENCE_TERMINAL_STATE_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def := replace(v_def, v_old, v_new);
  end if;

  if position('This build stopped before it was ready. You can retry.' in v_def) = 0 then
    v_old := $old$  case
    when s.normalized_experience_state = 'START' then 'What do you want to build?'$old$;
    v_new := $new$  case
    when s.latest_failure_is_relevant
      and s.active_build_job_id is null
      and s.current_version_id is null
      then coalesce(
        nullif(trim(s.latest_job_public_error_summary),''),
        'This build stopped before it was ready. You can retry.'
      )
    when s.normalized_experience_state = 'START' then 'What do you want to build?'$new$;
    if position(v_old in v_def) = 0 then
      raise exception 'PROJECT_EXPERIENCE_TERMINAL_MESSAGE_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def := replace(v_def, v_old, v_new);
  end if;

  execute v_def;

  select pg_get_functiondef(
    'private.pandora_compute_project_experience_v1(uuid)'::regprocedure
  ) into v_def;
  if position('n.current_version_id is null' in v_def) = 0
     or position('This build stopped before it was ready. You can retry.' in v_def) = 0 then
    raise exception 'PROJECT_EXPERIENCE_TERMINAL_PATCH_VERIFY_FAILED' using errcode='55000';
  end if;
end
$migration$;

with latest_failed as (
  select distinct on (j.project_id)
    j.project_id,
    j.organization_id,
    j.id as build_job_id,
    j.project_spec_id,
    j.target_project_version_id,
    j.public_error_summary
  from public.pandora_build_jobs j
  where j.job_kind='build'
    and j.status='failed'
  order by j.project_id,j.created_at desc,j.id desc
)
update public.pandora_build_theatre_projection t
set
  organization_id=f.organization_id,
  build_job_id=f.build_job_id,
  project_spec_id=f.project_spec_id,
  project_version_id=coalesce(f.target_project_version_id,t.project_version_id),
  owner_state='blocked',
  owner_stage='needs_you',
  public_message=coalesce(nullif(trim(f.public_error_summary),''),
    'This build stopped before it was ready. You can retry.'),
  needs_you=true,
  retry_available=true,
  last_event_at=clock_timestamp(),
  updated_at=clock_timestamp()
from latest_failed f
where t.project_id=f.project_id;

do $refresh$
declare
  r record;
begin
  for r in
    select distinct project_id
    from public.pandora_build_jobs
    where job_kind='build' and status='failed'
  loop
    perform private.pandora_refresh_project_experience_projection_v1(r.project_id);
  end loop;
end
$refresh$;

comment on function private.pandora_sync_build_theatre_from_job() is
'Projects terminal failed builds truthfully as blocked/retryable owner action, never as active fixing work.';
comment on function private.pandora_compute_project_experience_v1(uuid) is
'Computes Simple Mode project experience; terminal failed builds with no current version are non-active retryable states, not BUILD.';

commit;
