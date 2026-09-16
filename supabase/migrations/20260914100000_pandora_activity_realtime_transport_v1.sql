-- Pandora universal Activity Theatre realtime transport v1
-- M1-004 owns durable transport/replay and turn-to-job correlation.
-- M2 remains authoritative for canonical event semantics and projection truth.

create table if not exists public.pandora_activity_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  requested_by uuid not null,
  thread_id uuid,
  project_id uuid,
  request_id text not null,
  writer_epoch bigint not null default 1 check (writer_epoch > 0),
  writer_id text not null default 'pandora-intelligence-chat',
  last_sequence bigint not null default 0 check (last_sequence >= 0),
  terminal_state text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  unique (organization_id, requested_by, request_id),
  check (terminal_state is null or terminal_state in ('result','failed','cancelled'))
);

create index if not exists pandora_activity_jobs_org_thread_created_idx
  on public.pandora_activity_jobs(organization_id, thread_id, created_at desc)
  where thread_id is not null;
create table if not exists public.pandora_activity_events (
  job_id uuid not null references public.pandora_activity_jobs(id) on delete cascade,
  organization_id uuid not null,
  sequence bigint not null check (sequence > 0),
  event_id text not null,
  writer_epoch bigint not null check (writer_epoch > 0),
  state text not null,
  message text not null,
  event jsonb not null,
  occurred_at timestamptz not null,
  admitted_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  primary key (job_id, sequence),
  unique (job_id, event_id),
  check (length(trim(event_id)) between 1 and 200),
  check (length(trim(message)) between 1 and 1000),
  check (state in (
    'understanding','planning','acting','checking','needs_you','retrying','fallback',
    'verifying','paused','resuming','result','failed','cancelled'
  ))
);

create index if not exists pandora_activity_events_org_job_seq_idx
  on public.pandora_activity_events(organization_id, job_id, sequence);
create index if not exists pandora_activity_events_expiry_idx
  on public.pandora_activity_events(expires_at);
alter table public.pandora_activity_jobs enable row level security;
alter table public.pandora_activity_events enable row level security;

revoke all on table public.pandora_activity_jobs from public, anon, authenticated;
revoke all on table public.pandora_activity_events from public, anon, authenticated;
grant select on table public.pandora_activity_jobs to authenticated;
grant select on table public.pandora_activity_events to authenticated;

drop policy if exists pandora_activity_jobs_member_read on public.pandora_activity_jobs;
drop policy if exists pandora_activity_jobs_owner_read on public.pandora_activity_jobs;
create policy pandora_activity_jobs_owner_read
on public.pandora_activity_jobs for select to authenticated
using (
  requested_by = auth.uid()
  and exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_activity_jobs.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);

drop policy if exists pandora_activity_events_member_read on public.pandora_activity_events;
drop policy if exists pandora_activity_events_owner_read on public.pandora_activity_events;
create policy pandora_activity_events_owner_read
on public.pandora_activity_events for select to authenticated
using (
  exists (
    select 1
    from public.pandora_activity_jobs j
    join public.memberships m on m.organization_id = j.organization_id
    where j.id = pandora_activity_events.job_id
      and j.organization_id = pandora_activity_events.organization_id
      and j.requested_by = auth.uid()
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);
create or replace function public.pandora_activity_job_begin_v1(
  p_organization_id uuid,
  p_request_id text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_uid uuid := auth.uid();
  v_job public.pandora_activity_jobs%rowtype;
  v_now timestamptz;
  v_at text;
  v_event jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;
  if p_request_id is null or length(trim(p_request_id)) not between 8 and 200 then
    raise exception 'pandora_activity_request_id_invalid' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;
  if p_thread_id is not null and not exists (
    select 1 from public.pandora_intelligence_threads t
    where t.id=p_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=v_uid
      and t.status='active'
  ) then
    raise exception 'pandora_activity_thread_not_available' using errcode='42501';
  end if;
  if p_project_id is not null and not exists (
    select 1 from public.projectos_projects p
    where p.id=p_project_id
      and p.organization_id=p_organization_id
      and p.status <> 'archived'
  ) then
    raise exception 'pandora_activity_project_not_available' using errcode='42501';
  end if;
  insert into public.pandora_activity_jobs(
    organization_id, requested_by, thread_id, project_id, request_id
  ) values (
    p_organization_id, v_uid, p_thread_id, p_project_id, trim(p_request_id)
  )
  on conflict (organization_id, requested_by, request_id)
  do update set updated_at=now()
  returning * into v_job;

  if v_job.last_sequence = 0 then
    v_now := now();
    v_at := to_char(v_now at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    v_event := jsonb_build_object(
      'schemaVersion',1,
      'eventId','job-begin:' || v_job.id::text,
      'jobId',v_job.id,
      'sequence',1,
      'writerEpoch',v_job.writer_epoch,
      'admittedBy',v_job.writer_id,
      'admissionMode','online',
      'state','understanding',
      'message','Request accepted by Pandora runtime.',
      'occurredAt',v_at,
      'admittedAt',v_at,
      'provenance',jsonb_build_object(
        'sourceType','runtime','sourceId','pandora-activity-runtime',
        'sourceEventId','job-begin:' || v_job.id::text,'observedAt',v_at
      ),
      'evidence',jsonb_build_array(jsonb_build_object(
        'type','runtime_event','relation','source','ref','activity-job:' || v_job.id::text
      )),
      'domain','chat',
      'capability','intelligence.chat',
      'executionId',v_job.id,
      'blocker',null,
      'outcome',null
    );
    insert into public.pandora_activity_events(
      job_id,organization_id,sequence,event_id,writer_epoch,state,message,
      event,occurred_at,admitted_at
    ) values (
      v_job.id,v_job.organization_id,1,'job-begin:' || v_job.id::text,
      v_job.writer_epoch,'understanding','Request accepted by Pandora runtime.',
      v_event,v_now,v_now
    );
    update public.pandora_activity_jobs
    set last_sequence=1,updated_at=v_now where id=v_job.id
    returning * into v_job;
  end if;

  return jsonb_build_object(
    'jobId',v_job.id,
    'requestId',v_job.request_id,
    'threadId',v_job.thread_id,
    'projectId',v_job.project_id,
    'writerEpoch',v_job.writer_epoch,
    'writerId',v_job.writer_id,
    'lastSequence',v_job.last_sequence,
    'terminalState',v_job.terminal_state
  );
end;
$body$;

revoke all on function public.pandora_activity_job_begin_v1(uuid,text,uuid,uuid)
  from public, anon;
grant execute on function public.pandora_activity_job_begin_v1(uuid,text,uuid,uuid)
  to authenticated;
create or replace function public.pandora_activity_admit_event_v1(
  p_job_id uuid,
  p_event jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_sequence bigint;
  v_event_id text;
  v_state text;
  v_message text;
  v_occurred_at timestamptz;
  v_admitted_at timestamptz;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'pandora_activity_service_role_required' using errcode='42501';
  end if;

  select * into v_job from public.pandora_activity_jobs
  where id=p_job_id for update;
  if not found then
    raise exception 'pandora_activity_job_not_found' using errcode='22023';
  end if;
  if v_job.terminal_state is not null then
    raise exception 'pandora_activity_job_terminal' using errcode='55000';
  end if;
  if coalesce((p_event->>'schemaVersion')::integer,0) <> 1
     or coalesce(p_event->>'jobId','') <> p_job_id::text
     or coalesce((p_event->>'writerEpoch')::bigint,0) <> v_job.writer_epoch
     or coalesce(p_event->>'admittedBy','') <> v_job.writer_id
     or coalesce(p_event->>'admissionMode','') <> 'online' then
    raise exception 'pandora_activity_event_identity_invalid' using errcode='22023';
  end if;

  v_sequence := coalesce((p_event->>'sequence')::bigint,0);
  v_event_id := trim(coalesce(p_event->>'eventId',''));
  v_state := trim(coalesce(p_event->>'state',''));
  v_message := trim(coalesce(p_event->>'message',''));
  v_occurred_at := (p_event->>'occurredAt')::timestamptz;
  v_admitted_at := (p_event->>'admittedAt')::timestamptz;

  if v_sequence <> v_job.last_sequence + 1 then
    raise exception 'pandora_activity_sequence_invalid' using errcode='22023';
  end if;
  if length(v_event_id) not between 1 and 200
     or length(v_message) not between 1 and 1000 then
    raise exception 'pandora_activity_event_invalid' using errcode='22023';
  end if;
  if v_admitted_at < v_occurred_at then
    raise exception 'pandora_activity_clock_invalid' using errcode='22023';
  end if;

  insert into public.pandora_activity_events(
    job_id,organization_id,sequence,event_id,writer_epoch,state,message,
    event,occurred_at,admitted_at
  ) values (
    v_job.id,v_job.organization_id,v_sequence,v_event_id,v_job.writer_epoch,
    v_state,v_message,p_event,v_occurred_at,v_admitted_at
  );
  update public.pandora_activity_jobs
  set last_sequence=v_sequence,
      terminal_state=case when v_state in ('result','failed','cancelled') then v_state else null end,
      updated_at=now()
  where id=v_job.id;

  return jsonb_build_object(
    'jobId',v_job.id,
    'sequence',v_sequence,
    'eventId',v_event_id,
    'state',v_state,
    'writerEpoch',v_job.writer_epoch
  );
end;
$body$;

revoke all on function public.pandora_activity_admit_event_v1(uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.pandora_activity_admit_event_v1(uuid,jsonb)
  to service_role;

create or replace function public.pandora_activity_replay_v1(
  p_organization_id uuid,
  p_job_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 250
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_oldest bigint;
  v_events jsonb;
  v_returned_max bigint;
  v_has_more boolean := false;
  v_gap boolean := false;
begin
  if auth.uid() is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;
  if p_after_sequence < 0 or p_limit < 1 or p_limit > 500 then
    raise exception 'pandora_activity_replay_invalid' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;

  select * into v_job from public.pandora_activity_jobs
  where id=p_job_id
    and organization_id=p_organization_id
    and requested_by=auth.uid();
  if not found then
    raise exception 'pandora_activity_job_not_found' using errcode='22023';
  end if;

  select min(e.sequence) into v_oldest
  from public.pandora_activity_events e
  where e.job_id=v_job.id and e.expires_at > now();

  v_gap := p_after_sequence < v_job.last_sequence
    and (v_oldest is null or p_after_sequence + 1 < v_oldest);

  select coalesce(jsonb_agg(e.event order by e.sequence),'[]'::jsonb),
         max(e.sequence)
  into v_events, v_returned_max
  from (
    select sequence, event
    from public.pandora_activity_events
    where job_id=v_job.id
      and sequence > p_after_sequence
      and sequence <= v_job.last_sequence
      and expires_at > now()
    order by sequence
    limit p_limit
  ) e;

  select exists (
    select 1 from public.pandora_activity_events e
    where e.job_id=v_job.id
      and e.sequence > coalesce(v_returned_max,p_after_sequence)
      and e.sequence <= v_job.last_sequence
      and e.expires_at > now()
  ) into v_has_more;
  return jsonb_build_object(
    'jobId',v_job.id,
    'threadId',v_job.thread_id,
    'projectId',v_job.project_id,
    'events',v_events,
    'afterSequence',p_after_sequence,
    'watermarkSequence',v_job.last_sequence,
    'oldestRetainedSequence',v_oldest,
    'historyGapDueToRetention',v_gap,
    'hasMore',v_has_more,
    'terminalState',v_job.terminal_state
  );
end;
$body$;

revoke all on function public.pandora_activity_replay_v1(uuid,uuid,bigint,integer)
  from public, anon;
grant execute on function public.pandora_activity_replay_v1(uuid,uuid,bigint,integer)
  to authenticated;

do $realtime$
begin
  if exists (
    select 1 from pg_publication
    where pubname='supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='pandora_activity_events'
  ) then
    alter publication supabase_realtime add table public.pandora_activity_events;
  end if;
end;
$realtime$;
