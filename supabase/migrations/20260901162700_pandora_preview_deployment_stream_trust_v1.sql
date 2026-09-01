
begin;

-- Chat E trust closure: admit every canonical execution event and bind visible preview
-- readiness to the exact provider deployment + ProjectVersion lineage. This extends
-- Protocol V2; it does not create a second event/state system.

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
    'repair_completed'
  ));

create or replace function private.pandora_mirror_build_job_to_stream_20260901()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_stream_id uuid;
  v_event_type text := 'job_state';
  v_payload jsonb;
  v_preview record;
begin
  select s.id into v_stream_id
  from public.pandora_build_stream_sessions s
  where s.build_job_id = new.id
    and s.organization_id = new.organization_id
    and s.project_id = new.project_id
  order by s.created_at desc
  limit 1;
  if v_stream_id is null then return new; end if;

  v_payload := jsonb_build_object('status', new.status, 'stage', new.current_stage);

  if new.current_stage = 'preview_ready' and new.status = 'succeeded' then
    select
      d.id as deployment_id,
      d.version_id,
      d.provider,
      d.provider_deployment_id,
      d.source_sha256,
      d.artifact_digest,
      d.source_commit_sha,
      d.status as deployment_status,
      d.verification_state
    into v_preview
    from public.pandora_project_versions v
    join public.pandora_project_deployments d
      on d.organization_id = v.organization_id
     and d.project_id = v.project_id
     and d.version_id = v.id
     and d.environment = 'preview'
    where v.organization_id = new.organization_id
      and v.project_id = new.project_id
      and v.build_job_id = new.id
      and nullif(d.provider_deployment_id, '') is not null
      and d.source_sha256 = v.source_sha256
      and d.artifact_digest is not null
      and d.artifact_digest = v.artifact_digest_sha256
      and d.source_commit_sha is not distinct from v.source_commit
      and lower(d.status) in ('ready','ready_for_verification')
      and d.verification_state in ('ready_for_verification','live_verified')
    order by d.created_at desc
    limit 1;

    if found then
      v_event_type := 'preview_ready';
      v_payload := jsonb_build_object(
        'status', new.status,
        'stage', new.current_stage,
        'projectVersionId', v_preview.version_id,
        'deploymentId', v_preview.deployment_id,
        'provider', v_preview.provider,
        'providerDeploymentId', v_preview.provider_deployment_id,
        'sourceDigest', v_preview.source_sha256,
        'artifactDigest', v_preview.artifact_digest,
        'sourceCommit', v_preview.source_commit_sha,
        'deploymentStatus', v_preview.deployment_status,
        'verificationState', v_preview.verification_state,
        'evidenceSource', 'exact_preview_deployment'
      );
    end if;
  elsif new.current_stage = 'verifying' or new.status = 'waiting_verification' then
    v_event_type := 'verification';
  end if;

  if tg_op = 'INSERT'
     or new.status is distinct from old.status
     or new.current_stage is distinct from old.current_stage then
    insert into public.pandora_build_stream_events(
      stream_id, organization_id, project_id, build_job_id, event_type, safe_payload
    ) values (
      v_stream_id, new.organization_id, new.project_id, new.id, v_event_type, v_payload
    );

    update public.pandora_build_stream_sessions
      set status = case
        when new.status = 'failed' then 'failed'
        when new.status = 'cancelled' then 'cancelled'
        when v_event_type = 'preview_ready' then 'completed'
        else 'building'
      end,
      project_version_id = case
        when v_event_type = 'preview_ready' then v_preview.version_id
        else project_version_id
      end,
      updated_at = now()
    where id = v_stream_id;
  end if;
  return new;
end;
$fn$;

create or replace function private.pandora_mirror_preview_deployment_to_stream_20260901()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_version public.pandora_project_versions%rowtype;
  v_stream public.pandora_build_stream_sessions%rowtype;
  v_ready boolean := false;
  v_event_type text := 'build_step';
begin
  if new.environment <> 'preview' then return new; end if;

  select v.* into v_version
  from public.pandora_project_versions v
  where v.id = new.version_id
    and v.organization_id = new.organization_id
    and v.project_id = new.project_id;
  if not found or v_version.build_job_id is null then return new; end if;

  -- Only exact lineage is allowed to become customer-visible preview evidence.
  if nullif(new.provider_deployment_id, '') is null
     or new.source_sha256 is distinct from v_version.source_sha256
     or new.artifact_digest is null
     or new.artifact_digest is distinct from v_version.artifact_digest_sha256
     or new.source_commit_sha is distinct from v_version.source_commit then
    return new;
  end if;

  select s.* into v_stream
  from public.pandora_build_stream_sessions s
  where s.build_job_id = v_version.build_job_id
    and s.organization_id = new.organization_id
    and s.project_id = new.project_id
    and (s.project_version_id is null or s.project_version_id = new.version_id)
  order by s.created_at desc
  limit 1;
  if v_stream.id is null then return new; end if;

  v_ready := lower(new.status) in ('ready','ready_for_verification')
             and new.verification_state in ('ready_for_verification','live_verified');
  if v_ready then v_event_type := 'preview_ready'; end if;

  insert into public.pandora_build_stream_events(
    stream_id, organization_id, project_id, build_job_id, event_type, safe_payload
  ) values (
    v_stream.id,
    new.organization_id,
    new.project_id,
    v_version.build_job_id,
    v_event_type,
    jsonb_build_object(
      'stepKey', 'preview:' || new.id::text,
      'stepKind', 'preview_deployment',
      'status', lower(new.status),
      'projectVersionId', new.version_id,
      'deploymentId', new.id,
      'provider', new.provider,
      'providerDeploymentId', new.provider_deployment_id,
      'sourceDigest', new.source_sha256,
      'artifactDigest', new.artifact_digest,
      'sourceCommit', new.source_commit_sha,
      'providerState', new.provider_state,
      'verificationState', new.verification_state,
      'evidenceSource', 'deployment_row'
    )
  );

  if v_ready then
    update public.pandora_build_stream_sessions
       set status = 'completed',
           project_version_id = new.version_id,
           updated_at = now()
     where id = v_stream.id
       and (project_version_id is null or project_version_id = new.version_id);
  end if;

  return new;
end;
$fn$;

drop trigger if exists pandora_mirror_preview_deployment_to_stream_20260901
  on public.pandora_project_deployments;
create trigger pandora_mirror_preview_deployment_to_stream_20260901
after insert or update of status, verification_state, provider_deployment_id,
  source_sha256, artifact_digest, source_commit_sha, provider_state
on public.pandora_project_deployments
for each row
execute function private.pandora_mirror_preview_deployment_to_stream_20260901();

commit;
