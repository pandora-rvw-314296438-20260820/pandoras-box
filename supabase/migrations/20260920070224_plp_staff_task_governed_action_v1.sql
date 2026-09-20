
create table if not exists private.plp_staff_task_action_receipts (
  request_id text primary key,
  organization_id uuid not null,
  user_id uuid not null,
  task_id uuid not null,
  activity_job_id uuid not null,
  request_sha256 text not null,
  provider_readback jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint plp_staff_task_action_receipts_request_id_check
    check (length(request_id) between 8 and 160),
  constraint plp_staff_task_action_receipts_request_sha256_check
    check (request_sha256 ~ '^[0-9a-f]{64}$')
);

revoke all on table private.plp_staff_task_action_receipts
  from public, anon, authenticated;

create or replace function public.plp_create_staff_task_v1(
  p_request_id text,
  p_booking_reference text,
  p_title text,
  p_note text default null,
  p_category text default 'admin',
  p_priority text default 'normal'
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  org_id uuid;
  profile_name text;
  normalized_request_id text := trim(coalesce(p_request_id,''));
  normalized_booking_reference text := trim(coalesce(p_booking_reference,''));
  normalized_title text := trim(coalesce(p_title,''));
  normalized_note text := nullif(trim(coalesce(p_note,'')),'');
  normalized_category text := lower(trim(coalesce(p_category,'admin')));
  normalized_priority text := lower(trim(coalesce(p_priority,'normal')));
  request_sha text;
  prior private.plp_staff_task_action_receipts%rowtype;
  job_info jsonb;
  job public.pandora_activity_jobs%rowtype;
  task plp_runtime.plp_staff_tasks%rowtype;
  readback jsonb;
  now_utc timestamptz;
  at_text text;
  executing_event jsonb;
  done_event jsonb;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if length(normalized_request_id) not between 8 and 160
     or normalized_request_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'invalid PLP staff task request id' using errcode='22023';
  end if;
  if length(normalized_booking_reference) not between 1 and 160 then
    raise exception 'booking or room reference required' using errcode='22023';
  end if;
  if length(normalized_title) not between 4 and 240 then
    raise exception 'task title must be between 4 and 240 characters' using errcode='22023';
  end if;
  if normalized_note is not null and length(normalized_note) > 2000 then
    raise exception 'task note too long' using errcode='22023';
  end if;
  if normalized_category not in ('concierge','housekeeping','payment','arrival','availability','admin') then
    raise exception 'unsupported PLP task category' using errcode='22023';
  end if;
  if normalized_priority not in ('high','medium','normal') then
    raise exception 'unsupported PLP task priority' using errcode='22023';
  end if;

  select p.organization_id into org_id
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if org_id is null then
    raise exception 'PLP organization is not configured' using errcode='55000';
  end if;

  if not exists (
    select 1 from public.memberships m
    where m.organization_id=org_id
      and m.user_id=uid
      and m.status::text='active'
  ) then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select nullif(trim(p.display_name),'') into profile_name
  from public.profiles p
  where p.id=uid;
  profile_name := coalesce(profile_name,'PLP administrator');

  request_sha := encode(
    extensions.digest(
      convert_to(
        concat_ws('|',
          'plp-create-staff-task-v1',
          org_id::text,
          uid::text,
          normalized_request_id,
          normalized_booking_reference,
          normalized_title,
          coalesce(normalized_note,''),
          normalized_category,
          normalized_priority
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into prior
  from private.plp_staff_task_action_receipts r
  where r.request_id=normalized_request_id;

  if prior.request_id is not null then
    if prior.organization_id<>org_id
       or prior.user_id<>uid
       or prior.request_sha256<>request_sha then
      raise exception 'PLP staff task request id collision' using errcode='23505';
    end if;

    select * into task
    from plp_runtime.plp_staff_tasks t
    where t.id=prior.task_id;

    if task.id is null then
      raise exception 'provider readback missing for prior PLP staff task' using errcode='55000';
    end if;

    return prior.provider_readback ||
      jsonb_build_object(
        'idempotentReplay',true,
        'providerReadbackVerified',true
      );
  end if;

  job_info := public.pandora_activity_job_begin_v1(
    org_id,
    'plp-staff-task:'||normalized_request_id,
    null,
    null
  );

  select * into job
  from public.pandora_activity_jobs j
  where j.id=(job_info->>'jobId')::uuid
  for update;

  now_utc := clock_timestamp();
  at_text := to_char(now_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');

  executing_event := jsonb_build_object(
    'schemaVersion',1,
    'eventId','plp-staff-task-executing:'||normalized_request_id,
    'jobId',job.id,
    'sequence',2,
    'writerEpoch',job.writer_epoch,
    'admittedBy',job.writer_id,
    'admissionMode','online',
    'state','executing',
    'message','PLP staff task mutation admitted at the Supabase provider boundary.',
    'occurredAt',at_text,
    'admittedAt',at_text,
    'provenance',jsonb_build_object(
      'sourceType','provider',
      'sourceId','supabase-plp-staff-task-v1',
      'sourceEventId','plp-staff-task-executing:'||normalized_request_id,
      'observedAt',at_text
    ),
    'evidence',jsonb_build_array(
      jsonb_build_object(
        'type','provider_action',
        'relation','execution',
        'ref','plp_staff_tasks:create'
      )
    ),
    'domain','plp-enterprise',
    'capability','plp.staff_task.create',
    'executionId',job.id,
    'blocker',null,
    'outcome',null
  );

  insert into public.pandora_activity_events(
    job_id,organization_id,sequence,event_id,writer_epoch,state,message,event,occurred_at,admitted_at
  ) values (
    job.id,org_id,2,
    'plp-staff-task-executing:'||normalized_request_id,
    job.writer_epoch,'executing',
    'PLP staff task mutation admitted at the Supabase provider boundary.',
    executing_event,now_utc,now_utc
  )
  on conflict (job_id,sequence) do nothing;

  update public.pandora_activity_jobs
  set last_sequence=greatest(last_sequence,2),
      execution_state='running',
      execution_started_at=coalesce(execution_started_at,now_utc),
      execution_updated_at=now_utc,
      updated_at=now_utc
  where id=job.id;

  insert into plp_runtime.plp_staff_tasks(
    booking_reference,kind,category,priority,status,title,note,source,actor
  ) values (
    normalized_booking_reference,
    'task',
    normalized_category,
    normalized_priority,
    'open',
    normalized_title,
    normalized_note,
    'pandora_plp_mobile',
    profile_name
  )
  returning * into task;

  select to_jsonb(t) into readback
  from plp_runtime.plp_staff_tasks t
  where t.id=task.id;

  if readback is null
     or readback->>'title'<>normalized_title
     or readback->>'status'<>'open'
     or readback->>'source'<>'pandora_plp_mobile' then
    raise exception 'PLP staff task provider readback verification failed' using errcode='55000';
  end if;

  readback := jsonb_build_object(
    'verified',true,
    'authority','PLP_STAFF_TASK_PROVIDER_V1',
    'provider','supabase',
    'capability','plp.staff_task.create',
    'requestId',normalized_request_id,
    'activityJobId',job.id,
    'taskId',task.id,
    'bookingReference',task.booking_reference,
    'title',task.title,
    'category',task.category,
    'priority',task.priority,
    'status',task.status,
    'source',task.source,
    'actor',task.actor,
    'createdAt',task.created_at,
    'providerReadbackVerified',true,
    'idempotentReplay',false
  );

  insert into private.plp_staff_task_action_receipts(
    request_id,organization_id,user_id,task_id,activity_job_id,request_sha256,provider_readback
  ) values (
    normalized_request_id,org_id,uid,task.id,job.id,request_sha,readback
  );

  now_utc := clock_timestamp();
  at_text := to_char(now_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');

  done_event := jsonb_build_object(
    'schemaVersion',1,
    'eventId','plp-staff-task-done:'||normalized_request_id,
    'jobId',job.id,
    'sequence',3,
    'writerEpoch',job.writer_epoch,
    'admittedBy',job.writer_id,
    'admissionMode','online',
    'state','done',
    'message','PLP staff task created and provider readback verified.',
    'occurredAt',at_text,
    'admittedAt',at_text,
    'provenance',jsonb_build_object(
      'sourceType','provider',
      'sourceId','supabase-plp-staff-task-v1',
      'sourceEventId','plp-staff-task-done:'||normalized_request_id,
      'observedAt',at_text
    ),
    'evidence',jsonb_build_array(
      jsonb_build_object(
        'type','provider_readback',
        'relation','verification',
        'ref','plp_staff_tasks:'||task.id::text,
        'verified',true
      )
    ),
    'domain','plp-enterprise',
    'capability','plp.staff_task.create',
    'executionId',job.id,
    'blocker',null,
    'outcome',jsonb_build_object(
      'status','result',
      'summary','PLP staff task created and provider readback verified.',
      'providerReadback',readback
    )
  );

  insert into public.pandora_activity_events(
    job_id,organization_id,sequence,event_id,writer_epoch,state,message,event,occurred_at,admitted_at
  ) values (
    job.id,org_id,3,
    'plp-staff-task-done:'||normalized_request_id,
    job.writer_epoch,'done',
    'PLP staff task created and provider readback verified.',
    done_event,now_utc,now_utc
  );

  update public.pandora_activity_jobs
  set last_sequence=3,
      terminal_state='result',
      execution_state='complete',
      execution_effect_state='verified',
      execution_result=jsonb_build_object(
        'intent','plp_staff_task_create',
        'providerReadback',readback
      ),
      execution_checkpoint='provider_readback_verified',
      execution_checkpoint_ref='plp_staff_tasks:'||task.id::text,
      execution_updated_at=now_utc,
      updated_at=now_utc
  where id=job.id;

  return readback;
end;
$$;

revoke all on function public.plp_create_staff_task_v1(text,text,text,text,text,text)
  from public, anon;
grant execute on function public.plp_create_staff_task_v1(text,text,text,text,text,text)
  to authenticated;
