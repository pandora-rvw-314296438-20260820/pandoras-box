-- Primary Edge capacity is full and the provider control account cannot delete
-- the already-retired tombstone function. The dedicated Worker-D broker and the
-- existing source convergence worker already share the same one-purpose internal
-- source-worker key and service-role boundary. Rebind Worker-D to the exact
-- buildJobId route hosted inside that existing internal runtime.

begin;

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_d_finalize_static_web_20260830(uuid)'::regprocedure
  ) into v_def;

  if position(
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-d-source-readback'
    in v_def
  ) > 0 then
    v_def := replace(
      v_def,
      'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-d-source-readback',
      'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker'
    );
    execute v_def;
  elsif position(
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker'
    in v_def
  ) = 0 then
    raise exception 'WORKER_D_READBACK_REBIND_ANCHOR_MISSING' using errcode='55000';
  end if;

  select pg_get_functiondef(
    'private.pandora_worker_d_finalize_static_web_20260830(uuid)'::regprocedure
  ) into v_def;

  if position(
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker'
    in v_def
  ) = 0 or position(
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-d-source-readback'
    in v_def
  ) > 0 then
    raise exception 'WORKER_D_READBACK_REBIND_VERIFY_FAILED' using errcode='55000';
  end if;
end
$migration$;

revoke all on function private.pandora_worker_d_finalize_static_web_20260830(uuid)
  from public, anon, authenticated;
grant execute on function private.pandora_worker_d_finalize_static_web_20260830(uuid)
  to service_role;

comment on function private.pandora_worker_d_finalize_static_web_20260830(uuid) is
'Static Worker-D finalization uses the existing source-worker internal trust boundary for exact source readback; the shared Edge runtime accepts a separate buildJobId route while preserving lease, lineage, digest, size, and secret-content checks.';

commit;
