create or replace function public.pandora_build_stream_replay_v2(
  p_stream_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 250
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_session public.pandora_build_stream_sessions%rowtype;
  v_watermark bigint;
  v_oldest_retained bigint;
  v_events jsonb;
  v_build jsonb := null;
  v_summary jsonb := '{}'::jsonb;
  v_returned_max bigint;
  v_gap boolean := false;
  v_has_more boolean := false;
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

  v_gap := p_after_sequence < v_watermark
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

  select exists (
    select 1
    from public.pandora_build_stream_events e
    where e.stream_id = v_session.id
      and e.sequence > coalesce(v_returned_max, p_after_sequence)
      and e.sequence <= v_watermark
      and e.expires_at > now()
  ) into v_has_more;

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
    'hasMore', v_has_more
  );
end;
$function$;
