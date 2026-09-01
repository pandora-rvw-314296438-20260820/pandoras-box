-- Pandora Live-Build Protocol V2 — Chat E execution-event retention/safety extension.
-- Lifecycle evidence remains a durable projection. Raw customer-safe stdout/stderr
-- excerpts are ephemeral theatre data and are not permanent debugging authority.

create or replace function private.pandora_assign_build_stream_event_v2()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
      when new.event_type in ('file_started','file_completed','stdout_chunk','stderr_chunk') then 'ephemeral'
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

  if new.event_type in ('stdout_chunk','stderr_chunk') then
    if jsonb_typeof(new.safe_payload->'text') is distinct from 'string'
       or octet_length(coalesce(new.safe_payload->>'text','')) > 8192 then
      raise exception 'BUILD_STREAM_LOG_CHUNK_INVALID' using errcode='22023';
    end if;
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
$$;
