-- A cancelled build is terminal even when its last stage says live or publishing.
-- Preserve separately verified preview/live evidence and the current version.
-- Forward-only change: original migrations and historic projections are untouched.
begin;

alter table public.pandora_build_theatre_projection
  drop constraint pandora_build_theatre_projection_stage_check;
alter table public.pandora_build_theatre_projection
  add constraint pandora_build_theatre_projection_stage_check check (
    owner_stage in (
      'understanding','designing','building','connecting','checking','fixing',
      'preparing_preview','preview_ready','needs_you','publishing','live','cancelled'
    )
  );

create or replace function private.pandora_build_theatre_owner_stage(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) = 'cancelled' then 'cancelled'
    when lower(coalesce(p_status,'')) = 'failed' then 'fixing'
    when lower(coalesce(p_status,'')) = 'waiting_approval' then 'needs_you'
    when lower(coalesce(p_status,'')) = 'waiting_verification' then 'checking'
    when lower(coalesce(p_stage,'')) in ('received','understanding') then 'understanding'
    when lower(coalesce(p_stage,'')) in ('planning','designing') then 'designing'
    when lower(coalesce(p_stage,'')) = 'building' then 'building'
    when lower(coalesce(p_stage,'')) = 'connecting' then 'connecting'
    when lower(coalesce(p_stage,'')) in ('testing','verifying') then 'checking'
    when lower(coalesce(p_stage,'')) in ('repairing','failed','rolling_back') then 'fixing'
    when lower(coalesce(p_stage,'')) = 'previewing' then 'preparing_preview'
    when lower(coalesce(p_stage,'')) = 'preview_ready' then 'preview_ready'
    when lower(coalesce(p_stage,'')) in ('awaiting_approval','needs_you') then 'needs_you'
    when lower(coalesce(p_stage,'')) = 'publishing' then 'publishing'
    when lower(coalesce(p_stage,'')) = 'live' then 'live'
    else 'understanding'
  end
$$;

create or replace function private.pandora_build_theatre_owner_state(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) in ('failed','cancelled') then 'blocked'
    when lower(coalesce(p_status,'')) = 'waiting_approval'
      or lower(coalesce(p_stage,'')) in ('awaiting_approval','needs_you') then 'needs_you'
    when lower(coalesce(p_stage,'')) = 'live' then 'live'
    when lower(coalesce(p_stage,'')) = 'publishing' then 'publishing'
    when lower(coalesce(p_stage,'')) = 'preview_ready' then 'preview_ready'
    when lower(coalesce(p_stage,'')) in ('testing','verifying') or lower(coalesce(p_status,'')) = 'waiting_verification' then 'checking'
    when lower(coalesce(p_status,'')) = 'succeeded' then 'complete'
    when lower(coalesce(p_status,'')) in ('queued','claimed','running') then 'building'
    else 'draft'
  end
$$;

create or replace function private.pandora_build_theatre_progress(p_stage text, p_status text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) = 'cancelled' then null::smallint
    else (case private.pandora_build_theatre_owner_stage(p_stage,p_status)
      when 'understanding' then 10
      when 'designing' then 20
      when 'building' then 45
      when 'connecting' then 60
      when 'checking' then 75
      when 'fixing' then 65
      when 'preparing_preview' then 85
      when 'needs_you' then 85
      when 'publishing' then 95
      when 'preview_ready' then 100
      when 'live' then 100
      else 0
    end)::smallint
  end
$$;

create or replace function private.pandora_build_theatre_message(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) = 'cancelled' then 'This build was cancelled. You can retry.'
    else case private.pandora_build_theatre_owner_stage(p_stage,p_status)
      when 'understanding' then 'Pandora is confirming the result you asked for.'
      when 'designing' then 'Pandora is shaping the experience around your goal.'
      when 'building' then 'Pandora is creating the working version.'
      when 'connecting' then 'Pandora is joining the parts your project needs.'
      when 'checking' then 'Pandora is checking this version before the next step.'
      when 'fixing' then 'Pandora found something to fix and is working on it.'
      when 'preparing_preview' then 'Pandora is making this version available for you to inspect.'
      when 'preview_ready' then 'Your latest live preview is ready to open.'
      when 'needs_you' then 'Pandora needs your input before it can continue.'
      when 'publishing' then 'Pandora is making this verified version live.'
      when 'live' then 'Your verified project is live.'
      else 'Pandora is preparing your project.'
    end
  end
$$;

-- Retain the latest-job, generation-evidence, and preexecution failure logic
-- from 20260910161000. The cancelled path alone now has terminal presentation.
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
    when new.status = 'cancelled' then 'cancelled'
    when v_preexecution_terminal then 'understanding'
    when v_terminal_failure then 'needs_you'
    else private.pandora_build_theatre_owner_stage(new.current_stage,new.status)
  end;
  v_progress := case
    when new.status = 'cancelled' then null::smallint
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
    when new.status = 'cancelled'
      then 'This build was cancelled. You can retry.'
    when v_terminal_failure and (v_generation_evidence or v_mid_generation_error)
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
    new.project_id,new.organization_id,new.id,new.project_spec_id,
    case when new.status = 'cancelled' then null else new.target_project_version_id end,
    private.pandora_build_theatre_owner_state(new.current_stage,new.status),
    v_owner_stage,
    v_progress,
    v_message,
    new.status <> 'cancelled' and (
      new.status = 'failed' or new.status = 'waiting_approval'
      or new.current_stage in ('awaiting_approval','needs_you')
    ),
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

comment on function private.pandora_sync_build_theatre_from_job() is
  'Latest build job projects terminal cancelled truth without active progress; independently verified version and URL remain available.';

commit;
