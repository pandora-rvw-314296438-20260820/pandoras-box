
begin;

alter table public.pandora_build_stream_sessions
  add column if not exists protocol_version smallint not null default 2,
  add column if not exists last_sequence bigint not null default 0;

alter table public.pandora_build_stream_events
  add column if not exists sequence bigint,
  add column if not exists event_schema_version smallint not null default 2,
  add column if not exists retention_class text not null default 'ephemeral';

with ranked as (
  select id,
         row_number() over (partition by stream_id order by id) as assigned_sequence
  from public.pandora_build_stream_events
  where sequence is null
)
update public.pandora_build_stream_events e
set sequence = ranked.assigned_sequence
from ranked
where e.id = ranked.id;

update public.pandora_build_stream_sessions s
set last_sequence = greatest(
  s.last_sequence,
  coalesce((
    select max(e.sequence)
    from public.pandora_build_stream_events e
    where e.stream_id = s.id
  ), 0)
);

alter table public.pandora_build_stream_events
  alter column sequence set not null;

alter table public.pandora_build_stream_events
  drop constraint if exists pandora_build_stream_events_event_type_check;
alter table public.pandora_build_stream_events
  add constraint pandora_build_stream_events_event_type_check
  check (event_type in (
    'build_admitted',
    'stream_started',
    'file_started',
    'code_chunk',
    'file_completed',
    'generation_completed',
    'build_job_created',
    'job_state',
    'build_step',
    'verification',
    'preview_ready',
    'needs_you',
    'build_completed',
    'build_failed',
    'stream_error'
  ));

alter table public.pandora_build_stream_events
  drop constraint if exists pandora_build_stream_events_schema_version_check;
alter table public.pandora_build_stream_events
  add constraint pandora_build_stream_events_schema_version_check
  check (event_schema_version = 2);

alter table public.pandora_build_stream_events
  drop constraint if exists pandora_build_stream_events_retention_class_check;
alter table public.pandora_build_stream_events
  add constraint pandora_build_stream_events_retention_class_check
  check (retention_class in ('ephemeral','durable_projection'));

alter table public.pandora_build_stream_events
  drop constraint if exists pandora_build_stream_events_safe_payload_size_check;
alter table public.pandora_build_stream_events
  add constraint pandora_build_stream_events_safe_payload_size_check
  check (octet_length(safe_payload::text) <= 32768);

create unique index if not exists pandora_build_stream_events_stream_sequence_uq
  on public.pandora_build_stream_events(stream_id, sequence);

create index if not exists pandora_build_stream_events_stream_expiry_sequence_idx
  on public.pandora_build_stream_events(stream_id, expires_at, sequence);

create or replace function private.pandora_assign_build_stream_event_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_sequence bigint;
  v_session_build_job_id uuid;
begin
  if new.stream_id is null or new.organization_id is null or new.project_id is null then
    raise exception 'BUILD_STREAM_IDENTITY_REQUIRED' using errcode='22023';
  end if;

  if new.event_type = 'code_chunk' then
    if new.content_chunk is null or octet_length(new.content_chunk) = 0 then
      raise exception 'BUILD_STREAM_CODE_CHUNK_REQUIRED' using errcode='22023';
    end if;
    new.retention_class := 'ephemeral';
    new.expires_at := clock_timestamp() + interval '20 minutes';
  else
    if new.content_chunk is not null then
      raise exception 'BUILD_STREAM_NON_CODE_CONTENT_FORBIDDEN' using errcode='22023';
    end if;
    new.retention_class := case
      when new.event_type in ('file_started','file_completed') then 'ephemeral'
      else 'durable_projection'
    end;
    new.expires_at := clock_timestamp() + case
      when new.retention_class = 'ephemeral' then interval '20 minutes'
      else interval '30 days'
    end;
  end if;

  if new.file_path is not null and (
    length(new.file_path) > 512
    or new.file_path like '/%'
    or position(chr(92) in new.file_path) > 0
    or new.file_path like '%..%'
  ) then
    raise exception 'BUILD_STREAM_FILE_PATH_INVALID' using errcode='22023';
  end if;

  new.safe_payload := coalesce(new.safe_payload, '{}'::jsonb);
  if octet_length(new.safe_payload::text) > 32768 then
    raise exception 'BUILD_STREAM_SAFE_PAYLOAD_TOO_LARGE' using errcode='22023';
  end if;

  update public.pandora_build_stream_sessions s
     set last_sequence = s.last_sequence + 1,
         protocol_version = 2,
         updated_at = s.updated_at
   where s.id = new.stream_id
     and s.organization_id = new.organization_id
     and s.project_id = new.project_id
   returning s.last_sequence, s.build_job_id
        into v_sequence, v_session_build_job_id;

  if v_sequence is null then
    raise exception 'BUILD_STREAM_SESSION_MISMATCH' using errcode='23514';
  end if;
  if new.build_job_id is not null
     and v_session_build_job_id is not null
     and new.build_job_id <> v_session_build_job_id then
    raise exception 'BUILD_STREAM_JOB_MISMATCH' using errcode='23514';
  end if;

  new.sequence := v_sequence;
  new.event_schema_version := 2;
  return new;
end;
$fn$;

drop trigger if exists pandora_assign_build_stream_event_v2
  on public.pandora_build_stream_events;
create trigger pandora_assign_build_stream_event_v2
before insert on public.pandora_build_stream_events
for each row execute function private.pandora_assign_build_stream_event_v2();

create or replace function public.pandora_build_stream_replay_v2(
  p_stream_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 250
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_session public.pandora_build_stream_sessions%rowtype;
  v_watermark bigint;
  v_oldest_retained bigint;
  v_events jsonb;
  v_build jsonb := null;
  v_summary jsonb := '{}'::jsonb;
  v_returned_max bigint;
  v_gap boolean := false;
begin
  if p_stream_id is null
     or p_after_sequence < 0
     or p_limit < 1
     or p_limit > 500 then
    raise exception 'BUILD_STREAM_REPLAY_REQUEST_INVALID' using errcode='22023';
  end if;
  if auth.uid() is null then
    raise exception 'BUILD_STREAM_NOT_AVAILABLE' using errcode='42501';
  end if;

  select * into v_session
  from public.pandora_build_stream_sessions
  where id = p_stream_id;

  if not found or not exists (
    select 1
    from public.memberships m
    where m.organization_id = v_session.organization_id
      and m.user_id = auth.uid()
      and m.status::text = 'active'
  ) then
    raise exception 'BUILD_STREAM_NOT_AVAILABLE' using errcode='42501';
  end if;

  v_watermark := v_session.last_sequence;

  select min(e.sequence)
    into v_oldest_retained
  from public.pandora_build_stream_events e
  where e.stream_id = v_session.id
    and e.expires_at > now()
    and e.sequence <= v_watermark;

  v_gap := p_after_sequence > 0
    and p_after_sequence < v_watermark
    and (
      v_oldest_retained is null
      or p_after_sequence + 1 < v_oldest_retained
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'streamId', e.stream_id,
        'sequence', e.sequence,
        'eventSchemaVersion', e.event_schema_version,
        'eventType', e.event_type,
        'retentionClass', e.retention_class,
        'buildJobId', e.build_job_id,
        'filePath', e.file_path,
        'contentChunk', e.content_chunk,
        'safePayload', e.safe_payload,
        'createdAt', e.created_at,
        'expiresAt', e.expires_at
      )
      order by e.sequence
    ),
    '[]'::jsonb
  ),
  max(e.sequence)
  into v_events, v_returned_max
  from (
    select *
    from public.pandora_build_stream_events e
    where e.stream_id = v_session.id
      and e.sequence > p_after_sequence
      and e.sequence <= v_watermark
      and e.expires_at > now()
    order by e.sequence
    limit p_limit
  ) e;

  if v_session.build_job_id is not null then
    select jsonb_build_object(
      'buildJobId', j.id,
      'status', j.status,
      'stage', j.current_stage,
      'attemptCount', j.attempt_count,
      'maxAttempts', j.max_attempts,
      'projectVersionId', j.target_project_version_id,
      'errorCode', j.error_code,
      'publicErrorSummary', j.public_error_summary,
      'createdAt', j.created_at,
      'startedAt', j.started_at,
      'completedAt', j.completed_at
    )
    into v_build
    from public.pandora_build_jobs j
    where j.id = v_session.build_job_id
      and j.organization_id = v_session.organization_id
      and j.project_id = v_session.project_id;

    select jsonb_build_object(
      'completedSteps', count(*) filter (where s.status = 'succeeded'),
      'failedSteps', count(*) filter (where s.status = 'failed'),
      'latestStepSequence', coalesce(max(s.sequence), -1),
      'sourceReady', bool_or(s.step_kind = 'source_generation' and s.status = 'succeeded')
    )
    into v_summary
    from public.pandora_build_job_steps s
    where s.build_job_id = v_session.build_job_id;
  end if;

  return jsonb_build_object(
    'protocolVersion', 2,
    'session', jsonb_build_object(
      'streamId', v_session.id,
      'organizationId', v_session.organization_id,
      'projectId', v_session.project_id,
      'buildJobId', v_session.build_job_id,
      'projectVersionId', v_session.project_version_id,
      'status', v_session.status,
      'publicErrorCode', v_session.public_error_code,
      'createdAt', v_session.created_at,
      'updatedAt', v_session.updated_at
    ),
    'build', v_build,
    'durableSummary', coalesce(v_summary, '{}'::jsonb),
    'events', v_events,
    'afterSequence', p_after_sequence,
    'watermarkSequence', v_watermark,
    'latestSequence', v_watermark,
    'oldestRetainedSequence', v_oldest_retained,
    'historyGapDueToRetention', v_gap,
    'hasMore', coalesce(v_returned_max, p_after_sequence) < v_watermark
  );
end;
$fn$;

revoke all on function public.pandora_build_stream_replay_v2(uuid,bigint,integer)
  from public, anon;
grant execute on function public.pandora_build_stream_replay_v2(uuid,bigint,integer)
  to authenticated;

create or replace function private.pandora_cleanup_expired_build_stream_events_v2(
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_deleted integer;
begin
  if p_limit < 1 or p_limit > 20000 then
    raise exception 'BUILD_STREAM_CLEANUP_LIMIT_INVALID' using errcode='22023';
  end if;

  with expired as (
    select id
    from public.pandora_build_stream_events
    where expires_at <= clock_timestamp()
    order by expires_at, id
    limit p_limit
    for update skip locked
  )
  delete from public.pandora_build_stream_events e
  using expired x
  where e.id = x.id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$fn$;

do $do$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and not exists (
       select 1 from cron.job
       where jobname = 'pandora-build-stream-cleanup-v2'
     ) then
    perform cron.schedule(
      'pandora-build-stream-cleanup-v2',
      '*/15 * * * *',
      'select private.pandora_cleanup_expired_build_stream_events_v2(5000);'
    );
  end if;
end;
$do$;

commit;
