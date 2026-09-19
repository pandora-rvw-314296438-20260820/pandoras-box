-- Pandora native project registry surface v1
-- Removes Pandora naming from the active chat/activity read path while preserving historical storage for audit compatibility.

create or replace view public.pandora_projects with (security_invoker = true) as 
select id, organization_id, project_key, name, repository, workspace_path, status, objective, roadmap_version, current_phase_key, current_task_key, progress_percent, config, created_by, last_reconciled_at, created_at, updated_at
from public.pandora_projects;

revoke all on public.pandora_projects from public, anon;
grant select on public.pandora_projects to authenticated, service_role;
comment on view public.pandora_projects is 'Pandora-native project registry compatibility surface. The historical pandora_projects table remains only as storage/audit compatibility; active Pandora runtime must query this neutral surface.';

CREATE OR REPLACE FUNCTION public.pandora_activity_job_begin_v1(p_organization_id uuid, p_request_id text, p_thread_id uuid DEFAULT NULL::uuid, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
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
    select 1 from public.pandora_projects p
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
$function$;


do $contract$
declare v_activity text;
begin
  select pg_get_functiondef('public.pandora_activity_job_begin_v1(uuid,text,uuid,uuid)'::regprocedure) into v_activity;
  if position('pandora_projects' in lower(v_activity)) > 0 or position('pandora_projects' in lower(v_activity)) = 0 then
    raise exception 'pandora_project_registry_runtime_contract_failed' using errcode='55000';
  end if;
end
$contract$;
