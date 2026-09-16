-- Pandora Universal Activity stream v1.
-- Neutral Universal Chat transport: turn -> job admission, ordered public Activity
-- projections, authenticated replay, and realtime table delivery.
begin;

create table if not exists public.pandora_activity_jobs (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  thread_id uuid not null references public.pandora_intelligence_threads(id) on delete cascade,
  turn_message_id uuid not null references public.pandora_intelligence_messages(id) on delete cascade,
  project_id uuid null references public.projectos_projects(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active',
  writer_epoch bigint not null default 1,
  last_sequence bigint not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz null,
  constraint pandora_activity_jobs_turn_uq unique(turn_message_id),
  constraint pandora_activity_jobs_status_check check (status in ('active','needs_you','result','failed','cancelled')),
  constraint pandora_activity_jobs_writer_epoch_check check (writer_epoch > 0),
  constraint pandora_activity_jobs_last_sequence_check check (last_sequence >= 0)
);
create index if not exists pandora_activity_jobs_owner_updated_idx
  on public.pandora_activity_jobs(created_by, updated_at desc);
create index if not exists pandora_activity_jobs_thread_updated_idx
  on public.pandora_activity_jobs(thread_id, updated_at desc);

create table if not exists public.pandora_activity_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  job_id uuid not null references public.pandora_activity_jobs(id) on delete cascade,
  event_id text not null,
  sequence bigint not null,
  writer_epoch bigint not null,
  state text not null,
  projection jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint pandora_activity_events_job_sequence_uq unique(job_id, sequence),
  constraint pandora_activity_events_job_event_uq unique(job_id, event_id),
  constraint pandora_activity_events_sequence_check check (sequence > 0),
  constraint pandora_activity_events_writer_epoch_check check (writer_epoch > 0),
  constraint pandora_activity_events_state_check check (state in (
    'understanding','planning','acting','checking','needs_you','retrying',
    'fallback','verifying','paused','resuming','result','failed','cancelled'
  )),
  constraint pandora_activity_events_projection_size_check
    check (octet_length(projection::text) <= 32768)
);
create index if not exists pandora_activity_events_job_sequence_idx
  on public.pandora_activity_events(job_id, sequence);

alter table public.pandora_activity_jobs enable row level security;
alter table public.pandora_activity_events enable row level security;

revoke all on public.pandora_activity_jobs from public, anon;
revoke all on public.pandora_activity_events from public, anon;
grant select on public.pandora_activity_jobs to authenticated;
grant select on public.pandora_activity_events to authenticated;
grant all on public.pandora_activity_jobs to service_role;
grant all on public.pandora_activity_events to service_role;
grant usage, select on sequence public.pandora_activity_events_id_seq to service_role;

drop policy if exists pandora_activity_jobs_owner_read_v1 on public.pandora_activity_jobs;
create policy pandora_activity_jobs_owner_read_v1
on public.pandora_activity_jobs for select to authenticated
using (
  created_by = auth.uid()
  and exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_activity_jobs.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);
drop policy if exists pandora_activity_events_owner_read_v1 on public.pandora_activity_events;
create policy pandora_activity_events_owner_read_v1
on public.pandora_activity_events for select to authenticated
using (
  exists (
    select 1
    from public.pandora_activity_jobs j
    where j.id = pandora_activity_events.job_id
      and j.organization_id = pandora_activity_events.organization_id
      and j.created_by = auth.uid()
      and exists (
        select 1 from public.memberships m
        where m.organization_id = j.organization_id
          and m.user_id = auth.uid()
          and m.status = 'active'
      )
  )
);

do $realtime$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'pandora_activity_events'
     ) then
    alter publication supabase_realtime add table public.pandora_activity_events;
  end if;
end
$realtime$;
create or replace function public.pandora_activity_admit_job_v1(
  p_job_id uuid,
  p_organization_id uuid,
  p_thread_id uuid,
  p_turn_message_id uuid,
  p_created_by uuid,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $fn$
declare
  v_job public.pandora_activity_jobs%rowtype;
begin
  if p_job_id is null or p_organization_id is null or p_thread_id is null
     or p_turn_message_id is null or p_created_by is null then
    raise exception 'PANDORA_ACTIVITY_ADMISSION_IDENTITY_REQUIRED' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.pandora_intelligence_threads t
    where t.id = p_thread_id
      and t.organization_id = p_organization_id
      and t.created_by = p_created_by
  ) then
    raise exception 'PANDORA_ACTIVITY_THREAD_SCOPE_MISMATCH' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.pandora_intelligence_messages m
    where m.id = p_turn_message_id
      and m.thread_id = p_thread_id
      and m.organization_id = p_organization_id
      and m.author_role = 'user'
  ) then
    raise exception 'PANDORA_ACTIVITY_TURN_SCOPE_MISMATCH' using errcode='42501';
  end if;
  if p_project_id is not null and not exists (
    select 1 from public.projectos_projects p
    where p.id = p_project_id
      and p.organization_id = p_organization_id
      and p.status <> 'archived'
  ) then
    raise exception 'PANDORA_ACTIVITY_PROJECT_SCOPE_MISMATCH' using errcode='42501';
  end if;

  insert into public.pandora_activity_jobs(
    id, organization_id, thread_id, turn_message_id, project_id, created_by
  ) values (
    p_job_id, p_organization_id, p_thread_id, p_turn_message_id, p_project_id, p_created_by
  ) on conflict (turn_message_id) do nothing;

  select * into strict v_job
  from public.pandora_activity_jobs j
  where j.turn_message_id = p_turn_message_id;
  if v_job.id <> p_job_id
     or v_job.organization_id <> p_organization_id
     or v_job.thread_id <> p_thread_id
     or v_job.created_by <> p_created_by
     or v_job.project_id is distinct from p_project_id then
    raise exception 'PANDORA_ACTIVITY_ADMISSION_COLLISION' using errcode='23505';
  end if;

  return jsonb_build_object(
    'contractVersion','pandora-activity-admission-v1',
    'jobId',v_job.id,
    'threadId',v_job.thread_id,
    'turnMessageId',v_job.turn_message_id,
    'projectId',v_job.project_id,
    'status',v_job.status,
    'writerEpoch',v_job.writer_epoch,
    'lastSequence',v_job.last_sequence,
    'createdAt',v_job.created_at
  );
end;
$fn$;

revoke all on function public.pandora_activity_admit_job_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.pandora_activity_admit_job_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  to service_role;
create or replace function public.pandora_activity_append_event_v1(
  p_job_id uuid,
  p_expected_sequence bigint,
  p_event_id text,
  p_writer_epoch bigint,
  p_projection jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_state text;
begin
  if p_job_id is null or p_expected_sequence < 1
     or nullif(trim(p_event_id),'') is null or p_writer_epoch < 1
     or p_projection is null then
    raise exception 'PANDORA_ACTIVITY_EVENT_INVALID' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_activity_jobs j
  where j.id = p_job_id
  for update;
  if not found then
    raise exception 'PANDORA_ACTIVITY_JOB_NOT_FOUND' using errcode='P0002';
  end if;
  if p_writer_epoch <> v_job.writer_epoch then
    raise exception 'PANDORA_ACTIVITY_WRITER_EPOCH_MISMATCH' using errcode='40001';
  end if;
  if p_expected_sequence <> v_job.last_sequence + 1 then
    raise exception 'PANDORA_ACTIVITY_SEQUENCE_MISMATCH' using errcode='40001';
  end if;
  if p_projection->>'eventId' <> trim(p_event_id)
     or p_projection->>'jobId' <> p_job_id::text
     or coalesce((p_projection->>'sequence')::bigint,0) <> p_expected_sequence
     or coalesce((p_projection->>'projectionVersion')::integer,0) <> 1 then
    raise exception 'PANDORA_ACTIVITY_PROJECTION_IDENTITY_MISMATCH' using errcode='22023';
  end if;

  v_state := nullif(trim(p_projection->>'state'),'');
  if v_state is null or v_state not in (
    'understanding','planning','acting','checking','needs_you','retrying',
    'fallback','verifying','paused','resuming','result','failed','cancelled'
  ) then
    raise exception 'PANDORA_ACTIVITY_STATE_INVALID' using errcode='22023';
  end if;

  insert into public.pandora_activity_events(
    organization_id, job_id, event_id, sequence, writer_epoch, state, projection
  ) values (
    v_job.organization_id, p_job_id, trim(p_event_id), p_expected_sequence,
    p_writer_epoch, v_state, p_projection
  );
  update public.pandora_activity_jobs
  set last_sequence = p_expected_sequence,
      status = case v_state
        when 'needs_you' then 'needs_you'
        when 'result' then 'result'
        when 'failed' then 'failed'
        when 'cancelled' then 'cancelled'
        else 'active'
      end,
      completed_at = case when v_state in ('result','failed','cancelled')
        then clock_timestamp() else completed_at end,
      updated_at = clock_timestamp()
  where id = p_job_id;

  return jsonb_build_object(
    'contractVersion','pandora-activity-append-v1',
    'jobId',p_job_id,
    'eventId',trim(p_event_id),
    'sequence',p_expected_sequence,
    'writerEpoch',p_writer_epoch,
    'state',v_state
  );
end;
$fn$;

revoke all on function public.pandora_activity_append_event_v1(uuid,bigint,text,bigint,jsonb)
  from public, anon, authenticated;
grant execute on function public.pandora_activity_append_event_v1(uuid,bigint,text,bigint,jsonb)
  to service_role;
create or replace function public.pandora_activity_replay_v1(
  p_job_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 250
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $fn$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_events jsonb;
  v_returned_max bigint;
  v_oldest bigint;
begin
  if p_job_id is null or p_after_sequence < 0 or p_limit < 1 or p_limit > 500 then
    raise exception 'PANDORA_ACTIVITY_REPLAY_REQUEST_INVALID' using errcode='22023';
  end if;
  if auth.uid() is null then
    raise exception 'PANDORA_ACTIVITY_NOT_AVAILABLE' using errcode='42501';
  end if;

  select * into v_job
  from public.pandora_activity_jobs j
  where j.id = p_job_id
    and j.created_by = auth.uid();
  if not found or not exists (
    select 1 from public.memberships m
    where m.organization_id = v_job.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  ) then
    raise exception 'PANDORA_ACTIVITY_NOT_AVAILABLE' using errcode='42501';
  end if;

  select min(e.sequence) into v_oldest
  from public.pandora_activity_events e
  where e.job_id = p_job_id;

  select coalesce(jsonb_agg(e.projection order by e.sequence), '[]'::jsonb),
         max(e.sequence)
  into v_events, v_returned_max
  from (
    select event_id, sequence, projection
    from public.pandora_activity_events
    where job_id = p_job_id
      and sequence > p_after_sequence
      and sequence <= v_job.last_sequence
    order by sequence
    limit p_limit
  ) e;

  return jsonb_build_object(
    'contractVersion','pandora-activity-replay-v1',
    'job',jsonb_build_object(
      'jobId',v_job.id,
      'threadId',v_job.thread_id,
      'turnMessageId',v_job.turn_message_id,
      'projectId',v_job.project_id,
      'status',v_job.status,
      'writerEpoch',v_job.writer_epoch,
      'createdAt',v_job.created_at,
      'updatedAt',v_job.updated_at,
      'completedAt',v_job.completed_at
    ),
    'events',v_events,
    'afterSequence',p_after_sequence,
    'watermarkSequence',v_job.last_sequence,
    'latestSequence',v_job.last_sequence,
    'oldestRetainedSequence',v_oldest,
    'historyGapDueToRetention',(
      p_after_sequence > 0
      and p_after_sequence < v_job.last_sequence
      and (v_oldest is null or p_after_sequence + 1 < v_oldest)
    ),
    'hasMore',coalesce(v_returned_max,p_after_sequence) < v_job.last_sequence
  );
end;
$fn$;

revoke all on function public.pandora_activity_replay_v1(uuid,bigint,integer)
  from public, anon;
grant execute on function public.pandora_activity_replay_v1(uuid,bigint,integer)
  to authenticated;
comment on table public.pandora_activity_jobs is
  'Neutral Universal Chat runtime job ledger. A job is admitted against one authenticated user turn.';
comment on table public.pandora_activity_events is
  'Ordered safe public Activity Theatre projections for Universal Chat replay and realtime delivery.';
comment on function public.pandora_activity_replay_v1(uuid,bigint,integer) is
  'Authenticated gap-aware replay for one owner-visible Universal Chat Activity job.';

do $contract$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='pandora_activity_events_job_sequence_uq'
  ) then
    raise exception 'PANDORA_ACTIVITY_SEQUENCE_CONTRACT_MISSING' using errcode='55000';
  end if;
  if has_function_privilege('authenticated',
       'public.pandora_activity_append_event_v1(uuid,bigint,text,bigint,jsonb)','EXECUTE') then
    raise exception 'PANDORA_ACTIVITY_APPEND_MUST_BE_SERVICE_ONLY' using errcode='55000';
  end if;
  if not has_function_privilege('authenticated',
       'public.pandora_activity_replay_v1(uuid,bigint,integer)','EXECUTE') then
    raise exception 'PANDORA_ACTIVITY_REPLAY_AUTH_GRANT_MISSING' using errcode='55000';
  end if;
end
$contract$;

commit;
