-- Theatre truth: mid-generation source failures must not look like "did not start".
-- Stream evidence or INVALID_GENERATED_SOURCE* / SOURCE_STREAM_WRITE_FAILED* means
-- generation already began; Simple mode must say Needs You / retry, not pre-execution.

begin;

create or replace function private.pandora_sync_build_theatre_from_job()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_generation_evidence boolean;
  v_mid_generation_error boolean;
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

  v_generation_evidence := exists (
    select 1
    from public.pandora_build_stream_events e
    where e.build_job_id = new.id
      and e.event_type in (
        'file_started',
        'code_chunk',
        'file_completed',
        'impact_classified',
        'generation_completed'
      )
  );

  v_mid_generation_error :=
    coalesce(new.error_code, '') like 'INVALID_GENERATED_SOURCE%'
    or coalesce(new.error_code, '') like 'SOURCE_STREAM_WRITE_FAILED%';

  v_preexecution_terminal :=
    new.status in ('failed','cancelled')
    and coalesce(new.attempt_count, 0) = 0
    and new.started_at is null
    and not v_generation_evidence
    and not v_mid_generation_error;

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
      then private.pandora_trusted_primitive_unavailable_message_20260910(
        new.project_spec_id,
        new.public_error_summary
      )
    when v_preexecution_terminal
      then 'Pandora did not start this build. You can try again.'
    when new.status in ('failed','cancelled')
      and (v_generation_evidence or v_mid_generation_error)
      then 'Pandora could not finish generating this project. You can try again.'
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
  v_spec_id uuid;
  v_generation_evidence boolean;
  v_mid_generation_error boolean;
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
  v_generation_evidence := exists (
    select 1
    from public.pandora_build_stream_events e
    where e.build_job_id = new.build_job_id
      and e.event_type in (
        'file_started',
        'code_chunk',
        'file_completed',
        'impact_classified',
        'generation_completed'
      )
  );
  v_mid_generation_error :=
    v_code like 'INVALID_GENERATED_SOURCE%'
    or v_code like 'SOURCE_STREAM_WRITE_FAILED%';

  -- Mid-generation failures are not pre-execution. Fail truthfully as Needs You.
  if v_generation_evidence or v_mid_generation_error then
    update public.pandora_build_jobs j
       set status = 'failed',
           current_stage = 'failed',
           error_code = v_code,
           public_error_summary =
             'Pandora could not finish generating this project. You can try again.',
           completed_at = coalesce(j.completed_at, clock_timestamp()),
           updated_at = clock_timestamp()
     where j.id = new.build_job_id
       and j.status in ('queued','claimed','dispatching')
       and coalesce(j.attempt_count, 0) = 0
       and j.started_at is null;
    return new;
  end if;

  select j.project_spec_id into v_spec_id
  from public.pandora_build_jobs j
  where j.id = new.build_job_id;

  v_summary := case v_code
    when 'TRUSTED_PRIMITIVE_UNAVAILABLE' then
      private.pandora_trusted_primitive_unavailable_message_20260910(v_spec_id, null)
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

-- Presentation-only backfill for latest jobs that already streamed generation
-- but still show the lying pre-execution "did not start" Theatre copy.
with latest_mid_generation as (
  select distinct on (j.project_id)
    j.id,
    j.project_id,
    j.error_code
  from public.pandora_build_jobs j
  where j.status in ('failed','cancelled')
    and coalesce(j.attempt_count, 0) = 0
    and j.started_at is null
    and (
      coalesce(j.error_code, '') like 'INVALID_GENERATED_SOURCE%'
      or coalesce(j.error_code, '') like 'SOURCE_STREAM_WRITE_FAILED%'
      or exists (
        select 1
        from public.pandora_build_stream_events e
        where e.build_job_id = j.id
          and e.event_type in (
            'file_started',
            'code_chunk',
            'file_completed',
            'impact_classified',
            'generation_completed'
          )
      )
    )
  order by j.project_id, j.created_at desc, j.id desc
)
update public.pandora_build_theatre_projection p
set owner_stage = 'needs_you',
    public_message = 'Pandora could not finish generating this project. You can try again.',
    needs_you = true,
    retry_available = true,
    last_event_at = now(),
    updated_at = now()
from latest_mid_generation l
where p.project_id = l.project_id
  and p.build_job_id = l.id
  and (
    p.owner_stage is distinct from 'needs_you'
    or p.public_message is distinct from
      'Pandora could not finish generating this project. You can try again.'
    or p.needs_you is distinct from true
    or p.retry_available is distinct from true
  );

comment on function private.pandora_sync_build_theatre_from_job() is
  'Projects Build Theatre from the latest job; mid-generation stream/source failures are Needs You, not pre-execution "did not start".';

commit;
