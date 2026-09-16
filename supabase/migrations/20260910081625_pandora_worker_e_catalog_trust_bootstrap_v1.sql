-- Worker E catalog trust bootstrap + Theatre blocked_names surfacing.
-- Callable post-deploy only: migration apply must not mutate catalog trust.

begin;

create or replace function public.pandora_worker_e_verify_catalog_experimental_20260910()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $fn$
declare
  v_row record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_pass integer := 0;
  v_fail integer := 0;
  v_skipped integer := 0;
  v_status text;
begin
  for v_row in
    select c.primitive_name, c.primitive_version, c.trust_state, c.worker_e_evidence_ref
    from public.pandora_primitive_catalog_entries c
    where not (
      c.trust_state = 'TRUSTED'
      and nullif(trim(c.worker_e_evidence_ref), '') is not null
    )
    and c.trust_state is distinct from 'BLOCKED'
    order by c.primitive_name, c.primitive_version
  loop
    begin
      v_result := private.pandora_worker_e_verify_primitive_20260831(
        v_row.primitive_name,
        v_row.primitive_version
      );
      v_status := coalesce(v_result->>'status', 'FAIL');
      if v_status = 'PASS' then
        v_pass := v_pass + 1;
      else
        v_fail := v_fail + 1;
      end if;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'name', v_row.primitive_name,
        'version', v_row.primitive_version,
        'status', v_status,
        'priorTrustState', v_row.trust_state,
        'evidenceId', v_result->>'evidenceId',
        'failure', v_result->>'failure'
      ));
    exception when others then
      v_fail := v_fail + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'name', v_row.primitive_name,
        'version', v_row.primitive_version,
        'status', 'FAIL',
        'priorTrustState', v_row.trust_state,
        'failure', left(sqlerrm, 500)
      ));
    end;
  end loop;

  select count(*)::integer into v_skipped
  from public.pandora_primitive_catalog_entries c
  where c.trust_state = 'TRUSTED'
    and nullif(trim(c.worker_e_evidence_ref), '') is not null;

  return jsonb_build_object(
    'ok', true,
    'passCount', v_pass,
    'failCount', v_fail,
    'alreadyTrustedCount', v_skipped,
    'results', v_results
  );
end;
$fn$;

revoke all on function public.pandora_worker_e_verify_catalog_experimental_20260910()
  from public, anon, authenticated;
grant execute on function public.pandora_worker_e_verify_catalog_experimental_20260910()
  to service_role;

-- Theatre: surface blocked_names for TRUSTED_PRIMITIVE_UNAVAILABLE (Needs You, not building).
create or replace function private.pandora_trusted_primitive_unavailable_message_20260910(
  p_project_spec_id uuid,
  p_public_error_summary text default null
)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_names text[];
  v_listed text;
  v_summary text := nullif(trim(coalesce(p_public_error_summary, '')), '');
begin
  if p_project_spec_id is not null then
    select r.blocked_names into v_names
    from public.pandora_project_spec_primitive_resolutions r
    where r.project_spec_id = p_project_spec_id;
  end if;

  if coalesce(cardinality(v_names), 0) > 0 then
    v_listed := array_to_string(v_names[1:20], ', ');
    return 'Pandora could not start this build because required building blocks are not available yet ('
      || v_listed
      || '). Nothing was published.';
  end if;

  if v_summary is not null and v_summary ~ 'building blocks' then
    return v_summary;
  end if;

  return 'Pandora could not start this build because required building blocks are not available yet. Nothing was published.';
end;
$fn$;

revoke all on function private.pandora_trusted_primitive_unavailable_message_20260910(uuid, text)
  from public, anon, authenticated;

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
      then private.pandora_trusted_primitive_unavailable_message_20260910(
        new.project_spec_id,
        new.public_error_summary
      )
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
  v_spec_id uuid;
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

drop trigger if exists pandora_fail_preexecution_job_from_source_queue_v1
  on public.pandora_source_generation_queue;
create trigger pandora_fail_preexecution_job_from_source_queue_v1
after update of status on public.pandora_source_generation_queue
for each row
execute function private.pandora_fail_preexecution_job_from_source_queue_v1();

revoke all on function private.pandora_fail_preexecution_job_from_source_queue_v1()
  from public, anon, authenticated;

commit;
