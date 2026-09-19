-- Pandora self-healing projection state patch v2.
-- The Build Theatre owner_state constraint uses "building", not "working".
-- Keep background source convergence inside the established owner-state taxonomy.

CREATE OR REPLACE FUNCTION private.pandora_refresh_source_generation_queue_20260831()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_active_inserted integer := 0;
  v_repairs_inserted integer := 0;
  v_reset integer := 0;
begin
  update public.pandora_source_generation_queue
     set status='queued',
         dispatched_at=null,
         request_id=null,
         last_error_code='DISPATCH_TIMEOUT',
         updated_at=clock_timestamp()
   where status='dispatching'
     and dispatched_at < clock_timestamp() - interval '3 minutes'
     and dispatch_count < 5;
  get diagnostics v_reset = row_count;

  with eligible as (
    select
      s.organization_id,
      s.project_id,
      s.id as project_spec_id,
      i.requester_id as requested_by,
      (
        select pv.id
        from public.pandora_project_versions pv
        where pv.organization_id=s.organization_id
          and pv.project_id=s.project_id
          and pv.lifecycle_status in ('verified','preview_ready','live')
        order by pv.created_at desc
        limit 1
      ) as base_version_id
    from public.pandora_project_specs s
    join public.pandora_project_intents i
      on i.id=s.source_intent_id
     and i.organization_id=s.organization_id
     and i.project_id=s.project_id
    join public.projectos_projects p
      on p.id=s.project_id
     and p.organization_id=s.organization_id
     and p.status='active'
    where s.status='active'
      and i.intent_kind in ('build','change')
      and s.created_at <= clock_timestamp() - interval '15 seconds'
      -- Owner questions belong to Intelligence/inspection, not mutation.
      and not (
        lower(trim(i.intent_text)) ~ '^(continue[[:space:]]+)?(does|do|is|are|what|why|how|where|when|who)[[:space:]]'
        and lower(i.intent_text) !~ '(add|change|build|create|fix|make|optimize|remove|replace|redesign|update|implement|connect|publish)'
      )
      and not exists (
        select 1
        from public.pandora_build_jobs j
        where j.organization_id=s.organization_id
          and j.project_id=s.project_id
          and j.project_spec_id=s.id
      )
      and not exists (
        select 1
        from public.pandora_source_generation_queue q
        where q.organization_id=s.organization_id
          and q.project_id=s.project_id
          and q.project_spec_id=s.id
          and q.reason='active_spec'
          and q.status in ('queued','dispatching','succeeded')
      )
  )
  insert into public.pandora_source_generation_queue(
    organization_id,project_id,project_spec_id,requested_by,reason,
    base_version_id,attempt_no,status,idempotency_key
  )
  select
    e.organization_id,e.project_id,e.project_spec_id,e.requested_by,'active_spec',
    e.base_version_id,0,'queued',
    'pandora-auto-spec:'||e.project_id::text||':'||e.project_spec_id::text
  from eligible e
  on conflict (idempotency_key) do nothing;
  get diagnostics v_active_inserted = row_count;

  with failure_candidates as (
    select
      j.organization_id,
      j.project_id,
      j.project_spec_id,
      j.requested_by,
      j.id as build_job_id,
      j.target_project_version_id as base_version_id,
      vr.id as verification_run_id,
      (
        select count(*)
        from public.pandora_source_generation_queue prior
        where prior.organization_id=j.organization_id
          and prior.project_id=j.project_id
          and prior.project_spec_id=j.project_spec_id
          and prior.reason='acceptance_repair'
      ) as prior_repairs
    from public.pandora_build_jobs j
    join public.pandora_project_specs s
      on s.id=j.project_spec_id
     and s.organization_id=j.organization_id
     and s.project_id=j.project_id
     and s.status='active'
    join lateral (
      select r.*
      from public.pandora_verification_runs r
      where r.organization_id=j.organization_id
        and r.project_id=j.project_id
        and r.build_job_id=j.id
        and upper(r.status)='FAIL'
        and r.required_check_profile='static_site'
      order by r.created_at desc
      limit 1
    ) vr on true
    where j.job_kind='build'
      and j.status='failed'
      and j.error_code='VERIFICATION_FAILED'
      and j.target_project_version_id is not null
      and not exists (
        select 1
        from public.pandora_build_jobs newer
        where newer.organization_id=j.organization_id
          and newer.project_id=j.project_id
          and newer.project_spec_id=j.project_spec_id
          and newer.created_at > j.created_at
          and newer.status <> 'cancelled'
      )
      and not exists (
        select 1
        from public.pandora_source_generation_queue q
        where q.repair_of_build_job_id=j.id
      )
      and (
        select count(*)
        from public.pandora_verification_checks c
        where c.verification_run_id=vr.id
          and c.status='FAIL'
      ) = 1
      and exists (
        select 1
        from public.pandora_verification_checks c
        where c.verification_run_id=vr.id
          and c.check_key='acceptance_requirements'
          and c.status='FAIL'
      )
  ), bounded as (
    select *
    from failure_candidates
    where prior_repairs < 2
  )
  insert into public.pandora_source_generation_queue(
    organization_id,project_id,project_spec_id,requested_by,reason,
    repair_of_build_job_id,repair_of_verification_run_id,base_version_id,
    attempt_no,status,idempotency_key
  )
  select
    b.organization_id,b.project_id,b.project_spec_id,b.requested_by,'acceptance_repair',
    b.build_job_id,b.verification_run_id,b.base_version_id,
    b.prior_repairs+1,'queued',
    'pandora-auto-repair:'||b.build_job_id::text
  from bounded b
  on conflict (idempotency_key) do nothing;
  get diagnostics v_repairs_inserted = row_count;

  with latest_queue as (
    select distinct on (q.project_id)
      q.project_id,q.reason,q.created_at
    from public.pandora_source_generation_queue q
    join public.pandora_project_specs s
      on s.id=q.project_spec_id
     and s.status='active'
    where q.status in ('queued','dispatching')
    order by q.project_id,q.created_at desc
  )
  update public.pandora_build_theatre_projection p
     set owner_state='building',
         owner_stage=case when q.reason='acceptance_repair' then 'fixing' else 'building' end,
         progress_percent=case
           when q.reason='acceptance_repair' then greatest(p.progress_percent,70)
           else greatest(p.progress_percent,20)
         end,
         public_message=case
           when q.reason='acceptance_repair'
             then 'Pandora found the issue and is repairing this version.'
           else 'Pandora is continuing this project in the background.'
         end,
         needs_you=false,
         retry_available=false,
         updated_at=clock_timestamp(),
         last_event_at=clock_timestamp()
    from latest_queue q
   where q.project_id=p.project_id;

  return jsonb_build_object(
    'activeSpecsQueued',v_active_inserted,
    'repairsQueued',v_repairs_inserted,
    'dispatchesReset',v_reset
  );
end
$function$;
