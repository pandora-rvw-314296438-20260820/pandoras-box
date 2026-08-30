-- Pandora durable source convergence and bounded acceptance repair.
-- Active ProjectSpecs no longer depend on an open mobile screen to become builds.
-- Worker E remains authoritative: only acceptance-only failures are eligible for bounded repair.

create table if not exists public.pandora_source_generation_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  project_spec_id uuid not null,
  requested_by uuid not null,
  reason text not null check (reason in ('active_spec','acceptance_repair')),
  repair_of_build_job_id uuid,
  repair_of_verification_run_id uuid,
  base_version_id uuid,
  attempt_no integer not null default 0 check (attempt_no between 0 and 2),
  status text not null default 'queued'
    check (status in ('queued','dispatching','succeeded','failed','cancelled')),
  idempotency_key text not null unique,
  dispatch_count integer not null default 0 check (dispatch_count between 0 and 10),
  request_id bigint,
  build_job_id uuid,
  project_version_id uuid,
  last_error_code text,
  created_at timestamptz not null default now(),
  dispatched_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (reason='active_spec' and repair_of_build_job_id is null and repair_of_verification_run_id is null)
    or
    (reason='acceptance_repair' and repair_of_build_job_id is not null and repair_of_verification_run_id is not null)
  )
);

create index if not exists pandora_source_generation_queue_dispatch_idx
  on public.pandora_source_generation_queue(status,created_at);
create index if not exists pandora_source_generation_queue_project_idx
  on public.pandora_source_generation_queue(project_id,project_spec_id,created_at desc);
create unique index if not exists pandora_source_generation_queue_repair_job_uq
  on public.pandora_source_generation_queue(repair_of_build_job_id)
  where repair_of_build_job_id is not null;

alter table public.pandora_source_generation_queue enable row level security;
revoke all on public.pandora_source_generation_queue from public, anon, authenticated;
grant select,insert,update,delete on public.pandora_source_generation_queue to service_role;

do $secret$
begin
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is not null
     and not exists (
       select 1
       from vault.decrypted_secrets
       where name='pandora_source_worker_internal_20260831'
     ) then
    perform vault.create_secret(
      encode(gen_random_bytes(32),'hex'),
      'pandora_source_worker_internal_20260831',
      'One-purpose internal key for Pandora source convergence worker',
      null
    );
  end if;
exception when others then
  -- Local/replay databases may intentionally omit Vault. Production has Vault.
  null;
end
$secret$;

create or replace function public.pandora_validate_source_worker_key_20260831(p_token text)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_secret text;
begin
  if p_token is null or length(p_token)<48 or length(p_token)>256 then
    return false;
  end if;
  begin
    select decrypted_secret
      into v_secret
    from vault.decrypted_secrets
    where name='pandora_source_worker_internal_20260831'
    limit 1;
  exception when others then
    return false;
  end;
  if nullif(v_secret,'') is null then
    return false;
  end if;
  return encode(extensions.digest(convert_to(p_token,'utf8'),'sha256'),'hex')
       = encode(extensions.digest(convert_to(v_secret,'utf8'),'sha256'),'hex');
end
$function$;

revoke all on function public.pandora_validate_source_worker_key_20260831(text)
  from public, anon, authenticated;
grant execute on function public.pandora_validate_source_worker_key_20260831(text)
  to service_role;

create or replace function private.pandora_refresh_source_generation_queue_20260831()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
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
     set owner_state='working',
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

revoke all on function private.pandora_refresh_source_generation_queue_20260831()
  from public, anon, authenticated;
grant execute on function private.pandora_refresh_source_generation_queue_20260831()
  to service_role;

create or replace function private.pandora_dispatch_source_generation_tick_20260831()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row public.pandora_source_generation_queue%rowtype;
  v_key text;
  v_request_id bigint;
  v_dispatched integer := 0;
  v_refresh jsonb;
begin
  v_refresh := private.pandora_refresh_source_generation_queue_20260831();

  begin
    select decrypted_secret
      into v_key
    from vault.decrypted_secrets
    where name='pandora_source_worker_internal_20260831'
    limit 1;
  exception when others then
    v_key := null;
  end;

  if nullif(v_key,'') is null then
    return v_refresh || jsonb_build_object(
      'dispatched',0,
      'workerKeyAvailable',false
    );
  end if;

  for v_row in
    select *
    from public.pandora_source_generation_queue
    where status='queued'
      and dispatch_count < 5
    order by created_at
    limit 3
    for update skip locked
  loop
    update public.pandora_source_generation_queue
       set status='dispatching',
           dispatch_count=dispatch_count+1,
           dispatched_at=clock_timestamp(),
           last_error_code=null,
           updated_at=clock_timestamp()
     where id=v_row.id;

    begin
      execute 'select net.http_post($1,$2,$3,$4,$5)'
        into v_request_id
        using
          'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker',
          jsonb_build_object('queueId',v_row.id),
          '{}'::jsonb,
          jsonb_build_object(
            'content-type','application/json',
            'x-pandora-internal-key',v_key
          ),
          120000;

      update public.pandora_source_generation_queue
         set request_id=v_request_id,
             updated_at=clock_timestamp()
       where id=v_row.id;
      v_dispatched := v_dispatched + 1;
    exception when others then
      update public.pandora_source_generation_queue
         set status=case when dispatch_count < 5 then 'queued' else 'failed' end,
             last_error_code='DISPATCH_FAILED',
             dispatched_at=null,
             updated_at=clock_timestamp(),
             completed_at=case when dispatch_count >= 5 then clock_timestamp() else null end
       where id=v_row.id;
    end;
  end loop;

  v_key := null;
  return v_refresh || jsonb_build_object(
    'dispatched',v_dispatched,
    'workerKeyAvailable',true
  );
end
$function$;

revoke all on function private.pandora_dispatch_source_generation_tick_20260831()
  from public, anon, authenticated;
grant execute on function private.pandora_dispatch_source_generation_tick_20260831()
  to service_role;

do $cron$
declare
  v_job_id bigint;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    for v_job_id in
      select jobid
      from cron.job
      where jobname='pandora-source-generation-convergence-v1'
    loop
      perform cron.unschedule(v_job_id);
    end loop;
    perform cron.schedule(
      'pandora-source-generation-convergence-v1',
      '* * * * *',
      'select private.pandora_dispatch_source_generation_tick_20260831();'
    );
  end if;
exception when others then
  -- Replay/test databases may intentionally omit pg_cron.
  null;
end
$cron$;
