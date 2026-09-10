begin;

-- Source generator emits impact_classified immediately after stream_started.
-- Without this allowlist entry, inserts fail and the build dies as
-- SOURCE_STREAM_WRITE_FAILED / INVALID_GENERATED_SOURCE before any files land.

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
    'stream_error',
    'command_started',
    'stdout_chunk',
    'stderr_chunk',
    'command_completed',
    'compile_started',
    'compile_diagnostic',
    'compile_completed',
    'test_started',
    'test_result',
    'test_completed',
    'repair_started',
    'repair_completed',
    'impact_classified'
  ));

comment on constraint pandora_build_stream_events_event_type_check on public.pandora_build_stream_events is
  'Protocol V2 event types plus impact_classified emitted by pandora-project-source-generator after stream_started.';

commit;
