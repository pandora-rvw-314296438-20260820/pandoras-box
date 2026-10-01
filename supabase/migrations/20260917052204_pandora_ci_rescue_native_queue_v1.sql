create table if not exists private.pandora_ci_rescue_jobs (
  id uuid primary key default gen_random_uuid(),
  external_event_id bigint not null unique references public.projectos_external_events(id) on delete cascade,
  organization_id uuid not null,
  repository text not null,
  branch text not null,
  origin_failing_sha text not null,
  current_failing_sha text not null,
  workflow_run_id bigint not null,
  workflow_name text,
  status text not null default 'queued',
  source_attempt_count integer not null default 0,
  transient_retry_count integer not null default 0,
  model_provider text,
  repair_commit_sha text,
  last_error_code text,
  evidence jsonb not null default '{}'::jsonb,
  lease_token uuid,
  lease_until timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint pandora_ci_rescue_repository_v1 check (repository = 'pandora-rvw-314296438-20260820/pandoras-box'),
  constraint pandora_ci_rescue_branch_v1 check (branch <> 'main' and branch ~ '^[A-Za-z0-9._/-]{1,220}$'),
  constraint pandora_ci_rescue_origin_sha_v1 check (origin_failing_sha ~ '^[0-9a-f]{40}$'),
  constraint pandora_ci_rescue_current_sha_v1 check (current_failing_sha ~ '^[0-9a-f]{40}$'),
  constraint pandora_ci_rescue_repair_sha_v1 check (repair_commit_sha is null or repair_commit_sha ~ '^[0-9a-f]{40}$'),
  constraint pandora_ci_rescue_source_attempts_v1 check (source_attempt_count between 0 and 2),
  constraint pandora_ci_rescue_transient_attempts_v1 check (transient_retry_count between 0 and 1),
  constraint pandora_ci_rescue_status_v1 check (status in ('queued','retrying','analyzing','repairing','verifying','completed','superseded','blocked','failed'))
);

create index if not exists pandora_ci_rescue_jobs_status_idx
  on private.pandora_ci_rescue_jobs(status, created_at);
create index if not exists pandora_ci_rescue_jobs_branch_idx
  on private.pandora_ci_rescue_jobs(repository, branch, created_at desc);

create or replace function private.pandora_enqueue_ci_rescue_from_external_event_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $$
declare
  v_branch text;
  v_sha text;
  v_run_id bigint;
  v_name text;
begin
  if new.event_type <> 'ci_failed'
     or new.repository is distinct from 'pandora-rvw-314296438-20260820/pandoras-box' then
    return new;
  end if;
  v_branch := trim(coalesce(new.payload_redacted->>'branch',''));
  v_sha := lower(trim(coalesce(new.payload_redacted->>'headSha','')));
  v_name := nullif(left(trim(coalesce(new.payload_redacted->>'workflowName','')),200),'');
  begin
    v_run_id := (new.payload_redacted->>'workflowRunId')::bigint;
  exception when others then
    v_run_id := null;
  end;
  if v_branch = '' or v_branch = 'main' or v_branch !~ '^[A-Za-z0-9._/-]{1,220}$'
     or v_sha !~ '^[0-9a-f]{40}$' or v_run_id is null or v_run_id < 1 then
    return new;
  end if;
  insert into private.pandora_ci_rescue_jobs(
    external_event_id, organization_id, repository, branch,
    origin_failing_sha, current_failing_sha, workflow_run_id, workflow_name,
    evidence
  ) values (
    new.id, new.organization_id, new.repository, v_branch,
    v_sha, v_sha, v_run_id, v_name,
    jsonb_build_object('deliveryId',new.delivery_id,'externalEventId',new.id,'receivedAt',new.received_at)
  )
  on conflict (external_event_id) do nothing;
  return new;
end;
$$;

drop trigger if exists pandora_ci_rescue_external_event_v1 on public.projectos_external_events;
create trigger pandora_ci_rescue_external_event_v1
after insert on public.projectos_external_events
for each row execute function private.pandora_enqueue_ci_rescue_from_external_event_v1();

insert into private.pandora_ci_rescue_jobs(
  external_event_id, organization_id, repository, branch,
  origin_failing_sha, current_failing_sha, workflow_run_id, workflow_name, evidence
)
select e.id, e.organization_id, e.repository,
       e.payload_redacted->>'branch', lower(e.payload_redacted->>'headSha'),
       lower(e.payload_redacted->>'headSha'), (e.payload_redacted->>'workflowRunId')::bigint,
       nullif(left(e.payload_redacted->>'workflowName',200),''),
       jsonb_build_object('deliveryId',e.delivery_id,'externalEventId',e.id,'receivedAt',e.received_at,'backfilled',true)
from public.projectos_external_events e
where e.event_type='ci_failed'
  and e.repository='pandora-rvw-314296438-20260820/pandoras-box'
  and coalesce(e.payload_redacted->>'branch','') <> 'main'
  and coalesce(e.payload_redacted->>'branch','') ~ '^[A-Za-z0-9._/-]{1,220}$'
  and coalesce(e.payload_redacted->>'headSha','') ~ '^[0-9a-f]{40}$'
  and coalesce(e.payload_redacted->>'workflowRunId','') ~ '^[0-9]+$'
on conflict (external_event_id) do nothing;

create or replace function public.pandora_ci_rescue_claim_v1(p_limit integer default 2)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $$
declare
  v_result jsonb;
begin
  perform private.assert_control_service_role();
  if p_limit < 1 or p_limit > 4 then
    raise exception 'invalid ci rescue claim limit' using errcode='22023';
  end if;
  with picked as (
    select j.id
    from private.pandora_ci_rescue_jobs j
    where j.status in ('queued','retrying','verifying')
      and (j.lease_until is null or j.lease_until < clock_timestamp())
    order by j.created_at
    for update skip locked
    limit p_limit
  ), leased as (
    update private.pandora_ci_rescue_jobs j
       set lease_token=gen_random_uuid(),
           lease_until=clock_timestamp()+interval '3 minutes',
           updated_at=clock_timestamp()
      from picked p
     where j.id=p.id
     returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,
    'externalEventId',external_event_id,
    'organizationId',organization_id,
    'repository',repository,
    'branch',branch,
    'originFailingSha',origin_failing_sha,
    'currentFailingSha',current_failing_sha,
    'workflowRunId',workflow_run_id,
    'workflowName',workflow_name,
    'status',status,
    'sourceAttemptCount',source_attempt_count,
    'transientRetryCount',transient_retry_count,
    'modelProvider',model_provider,
    'repairCommitSha',repair_commit_sha,
    'leaseToken',lease_token,
    'evidence',evidence
  ) order by created_at),'[]'::jsonb)
  into v_result from leased;
  return v_result;
end;
$$;

create or replace function public.pandora_ci_rescue_update_v1(
  p_id uuid,
  p_lease_token uuid,
  p_status text,
  p_patch jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $$
declare
  v_row private.pandora_ci_rescue_jobs%rowtype;
  v_patch jsonb := coalesce(p_patch,'{}'::jsonb);
  v_source_attempts integer;
  v_transient_attempts integer;
  v_current_sha text;
  v_run_id bigint;
  v_repair_sha text;
  v_provider text;
  v_error text;
  v_evidence jsonb;
begin
  perform private.assert_control_service_role();
  if p_status not in ('queued','retrying','analyzing','repairing','verifying','completed','superseded','blocked','failed') then
    raise exception 'invalid ci rescue status' using errcode='22023';
  end if;
  if (v_patch - array['sourceAttemptCount','transientRetryCount','currentFailingSha','workflowRunId','repairCommitSha','modelProvider','lastErrorCode','evidence']) <> '{}'::jsonb then
    raise exception 'invalid ci rescue patch keys' using errcode='22023';
  end if;
  select * into v_row from private.pandora_ci_rescue_jobs
   where id=p_id for update;
  if v_row.id is null or v_row.lease_token is distinct from p_lease_token
     or v_row.lease_until is null or v_row.lease_until < clock_timestamp() then
    raise exception 'ci rescue lease mismatch' using errcode='55000';
  end if;

  v_source_attempts := coalesce((v_patch->>'sourceAttemptCount')::integer,v_row.source_attempt_count);
  v_transient_attempts := coalesce((v_patch->>'transientRetryCount')::integer,v_row.transient_retry_count);
  v_current_sha := lower(coalesce(nullif(v_patch->>'currentFailingSha',''),v_row.current_failing_sha));
  v_run_id := coalesce((v_patch->>'workflowRunId')::bigint,v_row.workflow_run_id);
  v_repair_sha := case when v_patch ? 'repairCommitSha' then nullif(lower(v_patch->>'repairCommitSha'),'') else v_row.repair_commit_sha end;
  v_provider := case when v_patch ? 'modelProvider' then nullif(left(v_patch->>'modelProvider',40),'') else v_row.model_provider end;
  v_error := case when v_patch ? 'lastErrorCode' then nullif(left(v_patch->>'lastErrorCode',160),'') else v_row.last_error_code end;
  v_evidence := v_row.evidence || coalesce(v_patch->'evidence','{}'::jsonb);

  if v_source_attempts not between 0 and 2 or v_transient_attempts not between 0 and 1
     or v_current_sha !~ '^[0-9a-f]{40}$'
     or (v_repair_sha is not null and v_repair_sha !~ '^[0-9a-f]{40}$')
     or v_run_id < 1 then
    raise exception 'invalid ci rescue patch values' using errcode='22023';
  end if;

  update private.pandora_ci_rescue_jobs
     set status=p_status,
         source_attempt_count=v_source_attempts,
         transient_retry_count=v_transient_attempts,
         current_failing_sha=v_current_sha,
         workflow_run_id=v_run_id,
         repair_commit_sha=v_repair_sha,
         model_provider=v_provider,
         last_error_code=v_error,
         evidence=v_evidence,
         lease_token=null,
         lease_until=null,
         updated_at=clock_timestamp(),
         completed_at=case when p_status in ('completed','superseded','blocked','failed') then clock_timestamp() else null end
   where id=p_id
   returning * into v_row;

  return jsonb_build_object(
    'id',v_row.id,'status',v_row.status,'sourceAttemptCount',v_row.source_attempt_count,
    'transientRetryCount',v_row.transient_retry_count,'currentFailingSha',v_row.current_failing_sha,
    'workflowRunId',v_row.workflow_run_id,'repairCommitSha',v_row.repair_commit_sha,
    'updatedAt',v_row.updated_at,'completedAt',v_row.completed_at
  );
end;
$$;

revoke all on function public.pandora_ci_rescue_claim_v1(integer) from public;
revoke all on function public.pandora_ci_rescue_update_v1(uuid,uuid,text,jsonb) from public;
grant execute on function public.pandora_ci_rescue_claim_v1(integer) to service_role;
grant execute on function public.pandora_ci_rescue_update_v1(uuid,uuid,text,jsonb) to service_role;

create or replace function public.pandora_ci_rescue_internal_auth_v1(p_presented text)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','vault','extensions'
as $$
declare
  v_expected text;
begin
  if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then
    return false;
  end if;
  select decrypted_secret into v_expected
  from vault.decrypted_secrets where name='pandora_ci_rescue_internal_v1'
  order by created_at desc limit 1;
  if nullif(v_expected,'') is null or nullif(p_presented,'') is null then return false; end if;
  return extensions.digest(v_expected,'sha256') = extensions.digest(p_presented,'sha256');
end;
$$;
revoke all on function public.pandora_ci_rescue_internal_auth_v1(text) from public;
grant execute on function public.pandora_ci_rescue_internal_auth_v1(text) to service_role;

do $$
begin
  if not exists (select 1 from vault.secrets where name='pandora_ci_rescue_internal_v1') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'pandora_ci_rescue_internal_v1',
      'Internal one-purpose key for Pandora CI Rescue minute runner',
      null
    );
  end if;
end $$;

create or replace function private.pandora_ci_rescue_dispatch_tick_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_key text;
  v_request_id bigint;
  v_pending integer;
begin
  select count(*) into v_pending
  from private.pandora_ci_rescue_jobs
  where status in ('queued','retrying','verifying')
    and (lease_until is null or lease_until < clock_timestamp());
  if v_pending=0 then
    return jsonb_build_object('pending',0,'dispatched',false);
  end if;
  select decrypted_secret into v_key
  from vault.decrypted_secrets where name='pandora_ci_rescue_internal_v1'
  order by created_at desc limit 1;
  if nullif(v_key,'') is null then
    return jsonb_build_object('pending',v_pending,'dispatched',false,'error','INTERNAL_KEY_UNAVAILABLE');
  end if;
  execute 'select net.http_post($1,$2,$3,$4,$5)'
    into v_request_id
    using
      'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-ci-rescue-runner',
      jsonb_build_object('limit',least(v_pending,2)),
      '{}'::jsonb,
      jsonb_build_object('content-type','application/json','x-pandora-internal-key',v_key),
      120000;
  v_key := null;
  return jsonb_build_object('pending',v_pending,'dispatched',true,'requestId',v_request_id);
exception when others then
  v_key := null;
  return jsonb_build_object('pending',coalesce(v_pending,0),'dispatched',false,'error','DISPATCH_FAILED');
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname='pandora-ci-rescue-minute') then
    perform cron.unschedule('pandora-ci-rescue-minute');
  end if;
  perform cron.schedule('pandora-ci-rescue-minute','* * * * *','select private.pandora_ci_rescue_dispatch_tick_v1();');
end $$;
