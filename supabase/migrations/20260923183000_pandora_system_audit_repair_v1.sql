-- Pandora system-audit repair v1.
-- PLP intentionally remains on the existing demo/staging organization.
-- This migration does not bind or migrate the workspace to the unpaid customer tenant.

create or replace view public.pandora_projects
with (security_invoker=true)
as select * from public.projectos_projects;
create or replace view public.pandora_phases
with (security_invoker=true)
as select * from public.projectos_phases;
create or replace view public.pandora_tasks
with (security_invoker=true)
as select * from public.projectos_tasks;
create or replace view public.pandora_evidence
with (security_invoker=true)
as select * from public.projectos_evidence;
create or replace view public.pandora_projections
with (security_invoker=true)
as select * from public.projectos_projections;

grant select,insert,update,delete on public.pandora_projects to authenticated,service_role;
grant select,insert,update,delete on public.pandora_phases to authenticated,service_role;
grant select,insert,update,delete on public.pandora_tasks to authenticated,service_role;
grant select,insert,update,delete on public.pandora_evidence to authenticated,service_role;
grant select,insert,update,delete on public.pandora_projections to authenticated,service_role;

create or replace function public.pandora_intelligence_touch_thread_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
begin
  update public.pandora_intelligence_threads
  set last_message_at=greatest(coalesce(last_message_at,new.created_at),new.created_at),
      updated_at=greatest(updated_at,new.created_at)
  where id=new.thread_id
    and organization_id=new.organization_id;
  return new;
end;
$$;

drop trigger if exists pandora_intelligence_touch_thread_v1
  on public.pandora_intelligence_messages;
create trigger pandora_intelligence_touch_thread_v1
after insert on public.pandora_intelligence_messages
for each row execute function public.pandora_intelligence_touch_thread_v1();

update public.pandora_intelligence_threads t
set last_message_at=q.actual_last,
    updated_at=greatest(t.updated_at,q.actual_last)
from (
  select thread_id,max(created_at) actual_last
  from public.pandora_intelligence_messages
  group by thread_id
) q
where q.thread_id=t.id
  and (t.last_message_at is null or t.last_message_at < q.actual_last);

do $repair$
declare
  j public.pandora_activity_jobs%rowtype;
  seq bigint;
  now_at timestamptz;
  at_text text;
  event_id text;
  evt jsonb;
begin
  for j in
    select *
    from public.pandora_activity_jobs
    where execution_state='complete'
      and execution_effect_state='verified'
      and execution_result is not null
      and terminal_state is null
    order by created_at,id
    for update
  loop
    seq := j.last_sequence + 1;
    now_at := clock_timestamp();
    at_text := to_char(now_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    event_id := 'audit-repair-result:' || j.id::text;
    evt := jsonb_build_object(
      'schemaVersion',1,'eventId',event_id,'jobId',j.id,'sequence',seq,
      'writerEpoch',j.writer_epoch,'admittedBy',j.writer_id,'admissionMode','online',
      'state','result','message','Pandora recovered the verified persisted result.',
      'occurredAt',at_text,'admittedAt',at_text,
      'provenance',jsonb_build_object(
        'sourceType','runtime','sourceId','pandora-activity-recovery',
        'sourceEventId',event_id,'observedAt',at_text
      ),
      'evidence',jsonb_build_array(jsonb_build_object(
        'type','verification_receipt','relation','verification',
        'ref','execution-result:' || j.id::text
      )),
      'domain','chat','capability','intelligence.chat','executionId',j.id,
      'transition',null,'blocker',null,'control',null,
      'outcome',jsonb_build_object(
        'summary','Recovered verified execution result.','physicalDevice',false
      )
    );
    insert into public.pandora_activity_events(
      job_id,organization_id,sequence,event_id,writer_epoch,state,message,
      event,occurred_at,admitted_at
    ) values (
      j.id,j.organization_id,seq,event_id,j.writer_epoch,'result',
      'Pandora recovered the verified persisted result.',evt,now_at,now_at
    );
    update public.pandora_activity_jobs
    set last_sequence=seq,terminal_state='result',
        controls_sealed_at=coalesce(controls_sealed_at,now_at),updated_at=now_at
    where id=j.id;
  end loop;
end
$repair$;

create or replace function private.pandora_activity_expire_stale_ready_v1()
returns integer
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare
  j public.pandora_activity_jobs%rowtype;
  seq bigint;
  now_at timestamptz;
  at_text text;
  event_id text;
  evt jsonb;
  changed integer := 0;
begin
  for j in
    select *
    from public.pandora_activity_jobs
    where execution_state='ready'
      and execution_claim_id is null
      and terminal_state is null
      and updated_at < clock_timestamp()-interval '1 hour'
    order by updated_at,id
    for update skip locked
  loop
    seq := j.last_sequence + 1;
    now_at := clock_timestamp();
    at_text := to_char(now_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    event_id := 'expired-ready:' || j.id::text;
    evt := jsonb_build_object(
      'schemaVersion',1,'eventId',event_id,'jobId',j.id,'sequence',seq,
      'writerEpoch',j.writer_epoch,'admittedBy',j.writer_id,'admissionMode','online',
      'state','cancelled','message','Request expired before execution started.',
      'occurredAt',at_text,'admittedAt',at_text,
      'provenance',jsonb_build_object(
        'sourceType','runtime','sourceId','pandora-activity-recovery',
        'sourceEventId',event_id,'observedAt',at_text
      ),
      'evidence',jsonb_build_array(jsonb_build_object(
        'type','runtime_event','relation','authoritative_cancellation',
        'ref','stale-ready:' || j.id::text
      )),
      'domain','chat','capability','intelligence.chat','executionId',j.id,
      'transition',null,'blocker',null,'control',null,'outcome',null
    );
    insert into public.pandora_activity_events(
      job_id,organization_id,sequence,event_id,writer_epoch,state,message,
      event,occurred_at,admitted_at
    ) values (
      j.id,j.organization_id,seq,event_id,j.writer_epoch,'cancelled',
      'Request expired before execution started.',evt,now_at,now_at
    );
    update public.pandora_activity_jobs
    set last_sequence=seq,terminal_state='cancelled',execution_state='cancelled',
        execution_checkpoint='expired_before_claim',
        execution_error_code='ACTIVITY_REQUEST_EXPIRED',
        execution_updated_at=now_at,
        controls_sealed_at=coalesce(controls_sealed_at,now_at),updated_at=now_at
    where id=j.id;
    changed := changed + 1;
  end loop;
  return changed;
end;
$$;

revoke all on function private.pandora_activity_expire_stale_ready_v1()
  from public,anon,authenticated;
grant execute on function private.pandora_activity_expire_stale_ready_v1()
  to service_role;

select private.pandora_activity_expire_stale_ready_v1();

do $cron$
declare
  jid bigint;
begin
  select jobid into jid from cron.job
  where jobname='pandora-expire-stale-ready-v1'
  limit 1;
  if jid is not null then
    perform cron.unschedule(jid);
  end if;
  perform cron.schedule(
    'pandora-expire-stale-ready-v1',
    '*/15 * * * *',
    $job$select private.pandora_activity_expire_stale_ready_v1();$job$
  );
end
$cron$;

update public.enterprise_properties
set source_status='stale',
    source_message='Demo/staging PLP data. Customer production tenant is not connected; QA/mock and stale feeds must not be presented as live.',
    updated_at=clock_timestamp()
where slug='plp-boracay'
  and organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;

-- Security hardening discovered during the second audit pass.
-- Anonymous execution is not required for provider-backed or enterprise SECURITY DEFINER RPCs.
-- Guard with to_regprocedure so isolated PGlite replay (where Euro-Fish / Vision
-- RPCs are absent) remains portable; production still hardens when present.
do $hardening$
begin
  if to_regprocedure('public.pandora_eurofish_github_request_v1(text,text,jsonb)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_github_request_v1(text,text,jsonb) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_github_request_v1(text,text,jsonb) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_memory_github_request_v1(text,text,jsonb)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_memory_github_request_v1(text,text,jsonb) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_memory_github_request_v1(text,text,jsonb) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_github_ci_dispatch_v1()') is not null then
    execute 'revoke execute on function public.pandora_eurofish_github_ci_dispatch_v1() from public,anon';
    execute 'grant execute on function public.pandora_eurofish_github_ci_dispatch_v1() to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_github_ci_read_v1(text)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_github_ci_read_v1(text) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_github_ci_read_v1(text) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_github_ci_rerun_v1(bigint)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_github_ci_rerun_v1(bigint) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_github_ci_rerun_v1(bigint) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_github_run_read_v1(bigint,text)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_github_run_read_v1(bigint,text) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_github_run_read_v1(bigint,text) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_eurofish_workspace_v1(text)') is not null then
    execute 'revoke execute on function public.pandora_eurofish_workspace_v1(text) from public,anon';
    execute 'grant execute on function public.pandora_eurofish_workspace_v1(text) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_vision_overview_v1(uuid)') is not null then
    execute 'revoke execute on function public.pandora_vision_overview_v1(uuid) from public,anon';
    execute 'grant execute on function public.pandora_vision_overview_v1(uuid) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_vision_ack_alert_v1(uuid,uuid,text)') is not null then
    execute 'revoke execute on function public.pandora_vision_ack_alert_v1(uuid,uuid,text) from public,anon';
    execute 'grant execute on function public.pandora_vision_ack_alert_v1(uuid,uuid,text) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_vision_request_clip_v1(uuid,uuid,timestamptz,timestamptz,text,uuid)') is not null then
    execute 'revoke execute on function public.pandora_vision_request_clip_v1(uuid,uuid,timestamptz,timestamptz,text,uuid) from public,anon';
    execute 'grant execute on function public.pandora_vision_request_clip_v1(uuid,uuid,timestamptz,timestamptz,text,uuid) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_vision_search_v1(uuid,text,uuid,timestamptz,timestamptz,integer)') is not null then
    execute 'revoke execute on function public.pandora_vision_search_v1(uuid,text,uuid,timestamptz,timestamptz,integer) from public,anon';
    execute 'grant execute on function public.pandora_vision_search_v1(uuid,text,uuid,timestamptz,timestamptz,integer) to authenticated,service_role';
  end if;
  if to_regprocedure('public.pandora_vision_verify_observation_v1(uuid,uuid,text)') is not null then
    execute 'revoke execute on function public.pandora_vision_verify_observation_v1(uuid,uuid,text) from public,anon';
    execute 'grant execute on function public.pandora_vision_verify_observation_v1(uuid,uuid,text) to authenticated,service_role';
  end if;
end;
$hardening$;
