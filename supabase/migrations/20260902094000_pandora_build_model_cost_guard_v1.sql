-- Pandora Visible Creation — Build/model cost guard v1.
-- Bounds source-generation provider spend before dispatch and settles provider-reported usage
-- against one ProjectSpec-scoped budget shared by build retries and acceptance repair.

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='pandora_build_jobs_spend_within_budget_check'
      and conrelid='public.pandora_build_jobs'::regclass
  ) then
    alter table public.pandora_build_jobs
      add constraint pandora_build_jobs_spend_within_budget_check
      check (spent_cents <= budget_cents) not valid;
    alter table public.pandora_build_jobs
      validate constraint pandora_build_jobs_spend_within_budget_check;
  end if;
end
$$;

alter table public.pandora_model_runs
  add column if not exists source_queue_id uuid null,
  add column if not exists source_dispatch_attempt integer null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='pandora_model_runs_source_queue_fk'
      and conrelid='public.pandora_model_runs'::regclass
  ) then
    alter table public.pandora_model_runs
      add constraint pandora_model_runs_source_queue_fk
      foreign key (source_queue_id)
      references public.pandora_source_generation_queue(id)
      on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='pandora_model_runs_source_dispatch_attempt_check'
      and conrelid='public.pandora_model_runs'::regclass
  ) then
    alter table public.pandora_model_runs
      add constraint pandora_model_runs_source_dispatch_attempt_check
      check (source_dispatch_attempt is null or source_dispatch_attempt between 1 and 10);
  end if;
end
$$;

insert into public.pandora_model_pricing_versions (
  provider, model, model_revision, pricing_version, currency,
  input_micros_per_million_tokens, cached_input_micros_per_million_tokens,
  output_micros_per_million_tokens, effective_at, expires_at,
  source_ref, source_verified_at, verification_status
) values (
  'gemini', 'gemini-3.5-flash-lite', null,
  'gemini-3.5-flash-lite-usd-2026-09-02', 'USD',
  300000, 30000, 2500000,
  '2026-09-02 00:00:00+08'::timestamptz, null,
  'https://ai.google.dev/gemini-api/docs/pricing',
  clock_timestamp(), 'verified'
)
on conflict (provider, model, pricing_version) do update
set input_micros_per_million_tokens=excluded.input_micros_per_million_tokens,
    cached_input_micros_per_million_tokens=excluded.cached_input_micros_per_million_tokens,
    output_micros_per_million_tokens=excluded.output_micros_per_million_tokens,
    source_ref=excluded.source_ref,
    source_verified_at=excluded.source_verified_at,
    verification_status=excluded.verification_status;

create table if not exists public.pandora_source_model_budget_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete cascade,
  queue_id uuid not null references public.pandora_source_generation_queue(id) on delete cascade,
  budget_limit_id uuid not null references public.pandora_budget_limits(id) on delete restrict,
  dispatch_attempt integer not null,
  reservation_micros bigint not null,
  estimated_cost_micros bigint null,
  model_run_id uuid null references public.pandora_model_runs(id) on delete set null,
  provider text null,
  model text null,
  model_revision text null,
  pricing_version text null,
  pricing_source text null,
  status text not null default 'reserved',
  created_at timestamptz not null default now(),
  settled_at timestamptz null,
  constraint pandora_source_model_budget_reservation_attempt_check
    check (dispatch_attempt between 1 and 10),
  constraint pandora_source_model_budget_reservation_amount_check
    check (reservation_micros > 0 and (estimated_cost_micros is null or estimated_cost_micros >= 0)),
  constraint pandora_source_model_budget_reservation_status_check
    check (status in ('reserved','settled','retained','denied')),
  constraint pandora_source_model_budget_reservation_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  constraint pandora_source_model_budget_reservation_unique
    unique (queue_id, dispatch_attempt)
);

create index if not exists pandora_source_model_budget_reservation_spec_idx
  on public.pandora_source_model_budget_reservations(project_spec_id, created_at desc);
create index if not exists pandora_source_model_budget_reservation_model_run_idx
  on public.pandora_source_model_budget_reservations(model_run_id)
  where model_run_id is not null;

alter table public.pandora_source_model_budget_reservations enable row level security;
revoke all on public.pandora_source_model_budget_reservations from public, anon, authenticated;
grant select, insert, update on public.pandora_source_model_budget_reservations to service_role;

create or replace function private.pandora_default_build_budget_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_spent_micros bigint := 0;
begin
  if new.job_kind in ('build','repair') then
    if new.budget_cents = 0 then new.budget_cents := 50; end if;
    select coalesce(b.spent_micros,0)
      into v_spent_micros
    from public.pandora_budget_limits b
    where b.organization_id=new.organization_id
      and b.project_id=new.project_id
      and b.project_spec_id=new.project_spec_id
      and b.budget_kind='model'
      and b.scope_key='source-generation:'||new.project_spec_id::text
    limit 1;
    new.spent_cents := greatest(
      new.spent_cents,
      ceil(coalesce(v_spent_micros,0)::numeric / 10000)::bigint
    );
    if new.spent_cents > new.budget_cents then new.spent_cents := new.budget_cents; end if;
  end if;
  return new;
end
$fn$;

drop trigger if exists pandora_build_jobs_default_budget_v1 on public.pandora_build_jobs;
create trigger pandora_build_jobs_default_budget_v1
before insert on public.pandora_build_jobs
for each row execute function private.pandora_default_build_budget_v1();

create or replace function private.pandora_source_budget_terminal_v1(
  p_queue_id uuid,
  p_code text
) returns void
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_queue public.pandora_source_generation_queue%rowtype;
  v_stream_id uuid;
begin
  select * into v_queue
  from public.pandora_source_generation_queue
  where id=p_queue_id
  for update;
  if not found then return; end if;

  update public.pandora_source_generation_queue
     set status='failed',
         dispatch_count=greatest(dispatch_count,5),
         last_error_code=left(p_code,120),
         completed_at=coalesce(completed_at,clock_timestamp()),
         updated_at=clock_timestamp()
   where id=p_queue_id;

  if v_queue.build_job_id is not null then
    update public.pandora_build_jobs
       set status='failed',
           current_stage='failed',
           error_code=left(p_code,120),
           public_error_summary=case
             when p_code='BUILD_DEADLINE_EXCEEDED'
               then 'Pandora stopped this build because its execution deadline was reached.'
             else 'Pandora stopped this build before additional model spend could occur.'
           end,
           completed_at=coalesce(completed_at,clock_timestamp()),
           updated_at=clock_timestamp()
     where id=v_queue.build_job_id
       and status in ('queued','claimed','running','waiting_approval','waiting_verification');

    select s.id into v_stream_id
    from public.pandora_build_stream_sessions s
    where s.build_job_id=v_queue.build_job_id
      and s.organization_id=v_queue.organization_id
      and s.project_id=v_queue.project_id
    order by s.created_at
    limit 1;

    if v_stream_id is not null then
      update public.pandora_build_stream_sessions
         set status='failed',
             public_error_code=left(p_code,120),
             updated_at=clock_timestamp()
       where id=v_stream_id;
      begin
        insert into public.pandora_build_stream_events(
          stream_id,organization_id,project_id,build_job_id,event_type,safe_payload
        ) values (
          v_stream_id,v_queue.organization_id,v_queue.project_id,v_queue.build_job_id,
          'stream_error',jsonb_build_object('code',left(p_code,120))
        );
      exception when others then null;
      end;
    end if;
  end if;
end
$fn$;

revoke all on function private.pandora_source_budget_terminal_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function private.pandora_source_budget_terminal_v1(uuid,text)
  to service_role;

create or replace function private.pandora_reserve_source_model_attempt_v1(
  p_queue_id uuid,
  p_terminalize boolean default true
) returns boolean
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_queue public.pandora_source_generation_queue%rowtype;
  v_budget_id uuid;
  v_attempt integer;
  v_reserved boolean;
  v_deadline timestamptz;
  v_existing public.pandora_source_model_budget_reservations%rowtype;
begin
  select * into v_queue
  from public.pandora_source_generation_queue
  where id=p_queue_id
  for update;
  if not found or v_queue.status <> 'queued' then return false; end if;

  if v_queue.build_job_id is not null then
    select deadline_at into v_deadline
    from public.pandora_build_jobs
    where id=v_queue.build_job_id
    for update;
    if v_deadline is not null and v_deadline <= clock_timestamp() then
      if p_terminalize then
        perform private.pandora_source_budget_terminal_v1(
          p_queue_id,'BUILD_DEADLINE_EXCEEDED'
        );
      end if;
      return false;
    end if;
  end if;

  if not exists (
    select 1
    from public.pandora_model_pricing_versions p
    where p.provider='gemini'
      and p.model='gemini-3.5-flash-lite'
      and p.verification_status='verified'
      and p.effective_at <= clock_timestamp()
      and (p.expires_at is null or clock_timestamp() < p.expires_at)
  ) then
    if p_terminalize then
      perform private.pandora_source_budget_terminal_v1(
        p_queue_id,'MODEL_PRICING_UNAVAILABLE'
      );
    end if;
    return false;
  end if;

  insert into public.pandora_budget_limits(
    organization_id,project_id,project_spec_id,build_job_id,
    budget_kind,scope_key,currency,warning_limit_micros,hard_limit_micros
  ) values (
    v_queue.organization_id,v_queue.project_id,v_queue.project_spec_id,null,
    'model','source-generation:'||v_queue.project_spec_id::text,'USD',
    400000,500000
  )
  on conflict (organization_id,project_id,budget_kind,scope_key)
  do update set
    warning_limit_micros=greatest(public.pandora_budget_limits.warning_limit_micros,400000),
    hard_limit_micros=greatest(public.pandora_budget_limits.hard_limit_micros,500000)
  returning id into v_budget_id;

  v_attempt := v_queue.dispatch_count + 1;
  select * into v_existing
  from public.pandora_source_model_budget_reservations
  where queue_id=p_queue_id and dispatch_attempt=v_attempt
  for update;

  if found then
    if v_existing.status in ('reserved','settled') then return true; end if;
    if p_terminalize and v_existing.status='denied' then
      perform private.pandora_source_budget_terminal_v1(
        p_queue_id,'BUILD_BUDGET_EXHAUSTED'
      );
    end if;
    return false;
  end if;

  v_reserved := private.pandora_reserve_budget(v_budget_id,160000);
  if not v_reserved then
    if not p_terminalize then return false; end if;
    insert into public.pandora_source_model_budget_reservations(
      organization_id,project_id,project_spec_id,queue_id,budget_limit_id,
      dispatch_attempt,reservation_micros,status
    ) values (
      v_queue.organization_id,v_queue.project_id,v_queue.project_spec_id,
      v_queue.id,v_budget_id,v_attempt,160000,'denied'
    )
    on conflict (queue_id,dispatch_attempt) do nothing;
    perform private.pandora_source_budget_terminal_v1(
      p_queue_id,'BUILD_BUDGET_EXHAUSTED'
    );
    return false;
  end if;

  insert into public.pandora_source_model_budget_reservations(
    organization_id,project_id,project_spec_id,queue_id,budget_limit_id,
    dispatch_attempt,reservation_micros,status
  ) values (
    v_queue.organization_id,v_queue.project_id,v_queue.project_spec_id,
    v_queue.id,v_budget_id,v_attempt,160000,'reserved'
  );
  return true;
end
$fn$;

revoke all on function private.pandora_reserve_source_model_attempt_v1(uuid,boolean)
  from public,anon,authenticated;
grant execute on function private.pandora_reserve_source_model_attempt_v1(uuid,boolean)
  to service_role;

create or replace function private.pandora_claim_source_fastpath_v1(
  p_queue_id uuid,
  p_build_job_id uuid
) returns boolean
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_claimed boolean:=false;
begin
  if not exists(
    select 1
    from public.pandora_source_generation_queue q
    join public.pandora_build_jobs j on j.id=q.build_job_id
    where q.id=p_queue_id
      and q.build_job_id=p_build_job_id
      and q.status='queued'
      and q.dispatch_count<5
      and j.organization_id=q.organization_id
      and j.project_id=q.project_id
      and j.project_spec_id=q.project_spec_id
      and j.status='queued'
      and j.target_project_version_id is null
      and j.cancel_requested_at is null
      and (j.deadline_at is null or j.deadline_at > clock_timestamp())
  ) then return false; end if;

  if not private.pandora_reserve_source_model_attempt_v1(p_queue_id,false) then
    return false;
  end if;

  update public.pandora_source_generation_queue q
     set status='dispatching',
         dispatch_count=dispatch_count+1,
         dispatched_at=clock_timestamp(),
         request_id=null,
         last_error_code=null,
         updated_at=clock_timestamp()
   where q.id=p_queue_id
     and q.build_job_id=p_build_job_id
     and q.status='queued'
     and q.dispatch_count<5;
  v_claimed:=found;
  return v_claimed;
end
$fn$;

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
    select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name='pandora_source_worker_internal_20260831'
    limit 1;
  exception when others then
    v_key := null;
  end;

  if nullif(v_key,'') is null then
    return v_refresh || jsonb_build_object(
      'dispatched',0,'workerKeyAvailable',false
    );
  end if;

  for v_row in
    select *
    from public.pandora_source_generation_queue
    where status='queued' and dispatch_count < 5
    order by created_at
    limit 3
    for update skip locked
  loop
    if not private.pandora_reserve_source_model_attempt_v1(v_row.id,true) then
      continue;
    end if;

    update public.pandora_source_generation_queue
       set status='dispatching',
           dispatch_count=dispatch_count+1,
           dispatched_at=clock_timestamp(),
           last_error_code=null,
           updated_at=clock_timestamp()
     where id=v_row.id and status='queued';

    if not found then continue; end if;

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
    'dispatched',v_dispatched,'workerKeyAvailable',true
  );
end
$function$;

create or replace function private.pandora_preserve_budget_terminal_queue_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if old.status='failed'
     and old.last_error_code in (
       'BUILD_BUDGET_EXHAUSTED',
       'MODEL_PRICING_UNAVAILABLE',
       'MODEL_COST_EXCEEDS_RESERVATION',
       'MODEL_BUDGET_RESERVATION_MISSING',
       'BUILD_DEADLINE_EXCEEDED'
     )
     and new.status is distinct from old.status then
    new.status := old.status;
    new.last_error_code := old.last_error_code;
    new.completed_at := old.completed_at;
  end if;
  return new;
end
$fn$;

drop trigger if exists pandora_preserve_budget_terminal_queue_v1
  on public.pandora_source_generation_queue;
create trigger pandora_preserve_budget_terminal_queue_v1
before update on public.pandora_source_generation_queue
for each row execute function private.pandora_preserve_budget_terminal_queue_v1();

create or replace function private.pandora_settle_source_model_run_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_queue public.pandora_source_generation_queue%rowtype;
  v_res public.pandora_source_model_budget_reservations%rowtype;
  v_count integer := 0;
  v_est jsonb;
  v_estimated bigint;
  v_remainder bigint;
  v_ok boolean;
begin
  if new.status <> 'succeeded'
     or new.provider <> 'gemini'
     or new.task not in ('generate_project_source','repair_code') then
    return new;
  end if;

  if new.build_job_id is not null then
    select count(*) into v_count
    from public.pandora_source_generation_queue q
    where q.organization_id=new.organization_id
      and q.project_id=new.project_id
      and q.project_spec_id=new.project_spec_id
      and q.build_job_id=new.build_job_id
      and q.status='dispatching';
    if v_count = 1 then
      select q.* into v_queue
      from public.pandora_source_generation_queue q
      where q.organization_id=new.organization_id
        and q.project_id=new.project_id
        and q.project_spec_id=new.project_spec_id
        and q.build_job_id=new.build_job_id
        and q.status='dispatching'
      limit 1;
    end if;
  else
    select count(*) into v_count
    from public.pandora_source_generation_queue q
    where q.organization_id=new.organization_id
      and q.project_id=new.project_id
      and q.project_spec_id=new.project_spec_id
      and q.status='dispatching'
      and q.dispatched_at >= clock_timestamp()-interval '5 minutes';
    if v_count = 1 then
      select q.* into v_queue
      from public.pandora_source_generation_queue q
      where q.organization_id=new.organization_id
        and q.project_id=new.project_id
        and q.project_spec_id=new.project_spec_id
        and q.status='dispatching'
        and q.dispatched_at >= clock_timestamp()-interval '5 minutes'
      limit 1;
    end if;
  end if;

  if v_count <> 1 or v_queue.id is null then
    raise exception 'MODEL_BUDGET_RESERVATION_MISSING' using errcode='55000';
  end if;

  select * into v_res
  from public.pandora_source_model_budget_reservations r
  where r.queue_id=v_queue.id
    and r.dispatch_attempt=v_queue.dispatch_count
    and r.status='reserved'
  for update;
  if not found then
    raise exception 'MODEL_BUDGET_RESERVATION_MISSING' using errcode='55000';
  end if;

  v_est := public.pandora_estimate_model_cost_v1(
    new.provider,
    new.model,
    new.input_tokens,
    coalesce(new.cached_input_tokens,0),
    new.output_tokens,
    coalesce(new.completed_at,clock_timestamp()),
    new.model_revision
  );

  if coalesce(v_est->>'status','') <> 'estimated'
     or (v_est->>'estimatedCostMicros') is null then
    raise exception 'MODEL_PRICING_UNAVAILABLE' using errcode='55000';
  end if;

  v_estimated := (v_est->>'estimatedCostMicros')::bigint;
  if v_estimated > v_res.reservation_micros then
    raise exception 'MODEL_COST_EXCEEDS_RESERVATION' using errcode='54000';
  end if;

  if v_estimated > 0 then
    v_ok := private.pandora_commit_budget(v_res.budget_limit_id,v_estimated);
    if not v_ok then
      raise exception 'BUILD_BUDGET_EXHAUSTED' using errcode='54000';
    end if;
  end if;

  v_remainder := v_res.reservation_micros-v_estimated;
  if v_remainder > 0 then
    perform private.pandora_release_budget(v_res.budget_limit_id,v_remainder);
  end if;

  update public.pandora_source_model_budget_reservations
     set status='settled',
         estimated_cost_micros=v_estimated,
         provider=new.provider,
         model=new.model,
         model_revision=new.model_revision,
         pricing_version=v_est->>'pricingVersion',
         pricing_source=v_est->>'pricingSource',
         settled_at=clock_timestamp()
   where id=v_res.id;

  new.source_queue_id := v_queue.id;
  new.source_dispatch_attempt := v_queue.dispatch_count;
  new.estimated_cost_micros := v_estimated;
  new.usage_source := 'provider_reported';
  new.cost_estimate_status := 'estimated';
  new.pricing_version := v_est->>'pricingVersion';
  new.pricing_source := v_est->>'pricingSource';
  new.billing_reconciliation_status := 'pending';

  return new;
end
$fn$;

drop trigger if exists pandora_settle_source_model_run_v1 on public.pandora_model_runs;
create trigger pandora_settle_source_model_run_v1
before insert on public.pandora_model_runs
for each row execute function private.pandora_settle_source_model_run_v1();

create or replace function private.pandora_record_source_model_cost_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_res public.pandora_source_model_budget_reservations%rowtype;
  v_spent_micros bigint := 0;
begin
  if new.status <> 'succeeded'
     or new.provider <> 'gemini'
     or new.task not in ('generate_project_source','repair_code')
     or new.cost_estimate_status <> 'estimated'
     or new.source_queue_id is null
     or new.source_dispatch_attempt is null then
    return new;
  end if;

  select * into v_res
  from public.pandora_source_model_budget_reservations
  where queue_id=new.source_queue_id
    and dispatch_attempt=new.source_dispatch_attempt
    and status='settled'
  for update;
  if not found then return new; end if;

  update public.pandora_source_model_budget_reservations
     set model_run_id=new.id
   where id=v_res.id and model_run_id is null;

  insert into public.pandora_cost_entries(
    organization_id,project_id,project_spec_id,build_job_id,model_run_id,
    budget_limit_id,cost_category,provider,environment,quantity,unit,
    estimated_cost_micros,billed_cost_micros,charged_cost_micros,credit_micros,
    currency,idempotency_key,metadata_redacted
  ) values (
    new.organization_id,new.project_id,new.project_spec_id,new.build_job_id,new.id,
    v_res.budget_limit_id,'model',new.provider,'production',
    new.total_tokens,'tokens',
    new.estimated_cost_micros,0,new.estimated_cost_micros,0,
    'USD','source-model:'||new.source_queue_id::text||':'||new.source_dispatch_attempt::text,
    jsonb_build_object(
      'model',new.model,
      'modelRevision',new.model_revision,
      'pricingVersion',new.pricing_version,
      'usageSource','provider_reported'
    )
  )
  on conflict (organization_id,idempotency_key) do nothing;

  if new.build_job_id is not null then
    select b.spent_micros into v_spent_micros
    from public.pandora_budget_limits b
    where b.id=v_res.budget_limit_id;
    update public.pandora_build_jobs
       set budget_cents=greatest(budget_cents,50),
           spent_cents=least(
             greatest(budget_cents,50),
             ceil(coalesce(v_spent_micros,0)::numeric/10000)::bigint
           ),
           updated_at=clock_timestamp()
     where id=new.build_job_id;
  end if;
  return new;
end
$fn$;

drop trigger if exists pandora_record_source_model_cost_v1 on public.pandora_model_runs;
create trigger pandora_record_source_model_cost_v1
after insert on public.pandora_model_runs
for each row execute function private.pandora_record_source_model_cost_v1();

create or replace function private.pandora_sync_model_cost_to_build_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_res public.pandora_source_model_budget_reservations%rowtype;
  v_spent_micros bigint := 0;
begin
  if old.build_job_id is null
     and new.build_job_id is not null
     and new.cost_estimate_status='estimated'
     and new.source_queue_id is not null
     and new.source_dispatch_attempt is not null then
    select * into v_res
    from public.pandora_source_model_budget_reservations
    where queue_id=new.source_queue_id
      and dispatch_attempt=new.source_dispatch_attempt
      and status='settled'
    limit 1;
    if found then
      select spent_micros into v_spent_micros
      from public.pandora_budget_limits
      where id=v_res.budget_limit_id;
      update public.pandora_build_jobs
         set budget_cents=greatest(budget_cents,50),
             spent_cents=least(
               greatest(budget_cents,50),
               ceil(coalesce(v_spent_micros,0)::numeric/10000)::bigint
             ),
             updated_at=clock_timestamp()
       where id=new.build_job_id;
    end if;
  end if;
  return new;
end
$fn$;

drop trigger if exists pandora_sync_model_cost_to_build_v1 on public.pandora_model_runs;
create trigger pandora_sync_model_cost_to_build_v1
after update of build_job_id on public.pandora_model_runs
for each row execute function private.pandora_sync_model_cost_to_build_v1();

commit;
