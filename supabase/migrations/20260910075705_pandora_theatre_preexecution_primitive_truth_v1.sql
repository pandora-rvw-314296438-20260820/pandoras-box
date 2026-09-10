-- Theatre/Activity truth: pre-execution source failures must not stay "building".
-- Distinguishes TRUSTED_PRIMITIVE_UNAVAILABLE and MODEL_PRICING_UNAVAILABLE from spend budget.

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
    when v_preexecution_terminal and new.error_code = 'MODEL_PRICING_UNAVAILABLE'
      then 'Pandora could not start this build because pricing for the selected model is unavailable.'
    when v_preexecution_terminal and new.error_code = 'TRUSTED_PRIMITIVE_UNAVAILABLE'
      then 'Pandora could not start this build because required building blocks are not available yet. Nothing was published.'
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

create or replace function private.pandora_fail_preexecution_job_from_source_queue_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_code text;
  v_summary text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;
  if new.status is distinct from 'failed' then
    return new;
  end if;
  if old.status is not distinct from 'failed' then
    return new;
  end if;
  if new.build_job_id is null then
    return new;
  end if;

  v_code := left(coalesce(nullif(trim(new.last_error_code), ''), 'SOURCE_GENERATION_FAILED'), 120);
  v_summary := case v_code
    when 'TRUSTED_PRIMITIVE_UNAVAILABLE' then
      'Pandora could not start this build because required building blocks are not available yet. Nothing was published.'
    when 'BUILD_BUDGET_EXHAUSTED' then
      'Pandora did not start this build because its build budget was unavailable.'
    when 'MODEL_PRICING_UNAVAILABLE' then
      'Pandora could not start this build because pricing for the selected model is unavailable.'
    when 'BUILD_DEADLINE_EXCEEDED' then
      'Pandora could not start this build before its execution window ended.'
    else
      'Pandora could not start this build. Nothing was published.'
  end;

  update public.pandora_build_jobs j
     set status = 'failed',
         current_stage = 'understanding',
         error_code = v_code,
         public_error_summary = v_summary,
         completed_at = coalesce(j.completed_at, clock_timestamp()),
         updated_at = clock_timestamp()
   where j.id = new.build_job_id
     and j.status in ('queued','claimed','dispatching')
     and coalesce(j.attempt_count, 0) = 0
     and j.started_at is null;

  return new;
end
$function$;

drop trigger if exists pandora_fail_preexecution_job_from_source_queue_v1
  on public.pandora_source_generation_queue;
create trigger pandora_fail_preexecution_job_from_source_queue_v1
after update of status on public.pandora_source_generation_queue
for each row
execute function private.pandora_fail_preexecution_job_from_source_queue_v1();

revoke all on function private.pandora_fail_preexecution_job_from_source_queue_v1()
  from public, anon, authenticated;

-- Backfill currently lying pre-execution jobs linked to failed source queues.
with latest_failed as (
  select distinct on (q.project_id)
    q.project_id,
    q.build_job_id,
    q.last_error_code,
    q.updated_at
  from public.pandora_source_generation_queue q
  where q.status = 'failed'
    and q.build_job_id is not null
    and q.last_error_code in (
      'TRUSTED_PRIMITIVE_UNAVAILABLE',
      'BUILD_BUDGET_EXHAUSTED',
      'MODEL_PRICING_UNAVAILABLE',
      'BUILD_DEADLINE_EXCEEDED',
      'SOURCE_GENERATION_FAILED'
    )
  order by q.project_id, q.updated_at desc
)
update public.pandora_build_jobs j
   set status = 'failed',
       current_stage = 'understanding',
       error_code = left(coalesce(f.last_error_code, 'SOURCE_GENERATION_FAILED'), 120),
       public_error_summary = case f.last_error_code
         when 'TRUSTED_PRIMITIVE_UNAVAILABLE' then
           'Pandora could not start this build because required building blocks are not available yet. Nothing was published.'
         when 'BUILD_BUDGET_EXHAUSTED' then
           'Pandora did not start this build because its build budget was unavailable.'
         when 'MODEL_PRICING_UNAVAILABLE' then
           'Pandora could not start this build because pricing for the selected model is unavailable.'
         when 'BUILD_DEADLINE_EXCEEDED' then
           'Pandora could not start this build before its execution window ended.'
         else 'Pandora could not start this build. Nothing was published.'
       end,
       completed_at = coalesce(j.completed_at, clock_timestamp()),
       updated_at = clock_timestamp()
  from latest_failed f
 where j.id = f.build_job_id
   and j.status in ('queued','claimed','dispatching')
   and coalesce(j.attempt_count,0) = 0
   and j.started_at is null;

commit;
