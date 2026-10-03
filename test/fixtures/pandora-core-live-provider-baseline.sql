-- PGlite-only provider baseline supplement, inspected 2026-10-03.
-- These tables exist in jcyqixttuebxqqfkjonq but their creating DDL is absent
-- from executable source history. Do not apply this fixture to production.
-- No customer rows are copied. Live Realtime delivery remains a provider gate.
create table public.enterprise_business_activity (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 property_id uuid not null references public.enterprise_properties(id) on delete cascade,
 activity_key text not null,
 category text not null default 'operations',
 title text not null,
 summary text,
 occurred_at timestamptz not null,
 source_label text,
 created_at timestamptz not null default now(),
 unique(property_id,activity_key)
);
create index enterprise_business_activity_org_idx
 on public.enterprise_business_activity(organization_id);
create index enterprise_business_activity_property_time_idx
 on public.enterprise_business_activity(property_id,occurred_at desc);
alter table public.enterprise_business_activity enable row level security;
create policy enterprise_business_activity_member_read
 on public.enterprise_business_activity for select to authenticated
 using(private.is_org_member(organization_id));
-- Match inspected legacy grants; RLS supplies the member read policy. The
-- candidate is responsible for any deliberate narrowing of these privileges.
grant all on public.enterprise_business_activity to authenticated;
grant all on public.enterprise_business_activity to service_role;

create table public.enterprise_source_connections (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 property_id uuid not null references public.enterprise_properties(id) on delete cascade,
 source_type text not null,
 display_name text not null,
 status text not null default 'not_connected'
   check(status in ('not_connected','connecting','healthy','stale','error')),
 last_success_at timestamptz,
 last_attempt_at timestamptz,
 customer_message text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(property_id,source_type)
);
create index enterprise_source_connections_org_idx
 on public.enterprise_source_connections(organization_id);
create index enterprise_source_connections_property_idx
 on public.enterprise_source_connections(property_id);
alter table public.enterprise_source_connections enable row level security;
create policy enterprise_source_connections_member_read
 on public.enterprise_source_connections for select to authenticated
 using(private.is_org_member(organization_id));
grant all on public.enterprise_source_connections to authenticated;
grant all on public.enterprise_source_connections to service_role;

-- Exact inspected live function baselines for bounded guard rewrites.
-- Historical replay contains older or absent definitions for some functions.
-- These bytes are source context, not provider execution or customer data.

-- pandora_eurofish_private_workspace_v1 body SHA-256: a2c84512551e689e204d8bc4b852bdb9d9d27ddf57dbc2c7440896e7356bba79
CREATE OR REPLACE FUNCTION public.pandora_eurofish_private_workspace_v1(p_surface text DEFAULT 'overview'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'eurofish'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select role into v_role
  from eurofish.access_memberships
  where user_id=v_uid and active=true;

  if v_role is null then
    raise exception 'eurofish access denied' using errcode='42501';
  end if;

  if v_surface not in ('overview','commercial','import_operations','aquaculture','floriculture','customers','suppliers','compliance','finance','evidence','integrations','admin') then
    v_surface := 'overview';
  end if;

  v_result := jsonb_build_object(
    'projectKey','enterprise-eurofish',
    'memoryNamespace','enterprise:eurofish',
    'surface',v_surface,
    'actorRole',v_role,
    'counts',jsonb_build_object(
      'customers',(select count(*) from eurofish.customers),
      'suppliers',(select count(*) from eurofish.suppliers),
      'shipments',(select count(*) from eurofish.shipments),
      'biologicalLots',(select count(*) from eurofish.biological_lots),
      'flowerLots',(select count(*) from eurofish.flower_lots),
      'quotes',(select count(*) from eurofish.quotes),
      'orders',(select count(*) from eurofish.orders),
      'receivables',(select count(*) from eurofish.receivables),
      'complianceCases',(select count(*) from eurofish.compliance_cases)
    ),
    'generatedAt',now()
  );

  return v_result;
end $function$;

-- pandora_eurofish_workspace_v1 body SHA-256: 01b1d2e621517b7e83350e8a885e568a693e57a5ddc6fb68fc5d6791503c6850
CREATE OR REPLACE FUNCTION public.pandora_eurofish_workspace_v1(p_surface text DEFAULT 'overview'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'eurofish', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_profile jsonb;
  v_facts jsonb;
  v_sources jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select role into v_role
  from eurofish.access_memberships
  where user_id=v_uid and active=true;

  if v_role is null then
    raise exception 'eurofish access denied' using errcode='42501';
  end if;

  if v_surface not in (
    'overview','commercial','import_operations','aquaculture','floriculture',
    'customers','suppliers','compliance','finance','evidence','integrations','admin'
  ) then
    v_surface := 'overview';
  end if;

  select jsonb_build_object(
    'businessKey',business_key,'displayName',display_name,'legalName',legal_name,'timezone',timezone,
    'currency',currency,'address',address_text,'status',profile_status,'observedAt',source_observed_at
  ) into v_profile
  from eurofish.business_profile where business_key='enterprise-eurofish' limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',fact_key,'label',label,'value',fact_value,'truthStatus',truth_status,'sourceKind',source_kind,
    'sourceName',source_name,'sourceUrl',source_url,'observedAt',observed_at,'verifiedAt',verified_at,'notes',notes
  ) order by fact_key),'[]'::jsonb)
  into v_facts from eurofish.business_facts;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',source_key,'name',display_name,'type',source_type,'status',status,'lastSuccessAt',last_success_at,
    'lastAttemptAt',last_attempt_at,'message',customer_message
  ) order by source_key),'[]'::jsonb)
  into v_sources from eurofish.source_connections;

  return jsonb_build_object(
    'projectKey','enterprise-eurofish',
    'memoryNamespace','real_life',
    'memoryProjectKey','enterprise-eurofish',
    'surface',v_surface,
    'actorRole',v_role,
    'profile',coalesce(v_profile,'{}'::jsonb),
    'facts',v_facts,
    'sources',v_sources,
    'dataTruth',jsonb_build_object(
      'live','source + sync time','verified','evidence-backed','manual','entered with provenance',
      'stale','last known state is old','notConnected','no authoritative operational source',
      'externalIntelligence','never silently merged into internal truth'
    ),
    'operatingModel',jsonb_build_array(
      'Demand','Quote','Commitment','Supplier','Purchase','Permit','Booking','Flight','Arrival','Inspection',
      'Clearance','Release','Receiving','Condition/Survival','Allocation','Delivery','Invoice','Collection','Outcome'
    ),
    'generatedAt',now()
  );
end;
$function$;

-- pandora_tax_workspace_v1 body SHA-256: c1da504253d6e00efe27f1ef2d13a14a2c4b32e44a966a4bce8b0c400b47721d
CREATE OR REPLACE FUNCTION public.pandora_tax_workspace_v1(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  uid uuid := auth.uid();
  open_exception_count integer := 0;
  critical_exception_count integer := 0;
  ready_count integer := 0;
  latest_period jsonb := null;
  next_obligation jsonb := null;
  ph_rules_ready boolean := false;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select count(*)::integer,
         count(*) filter (where severity='critical')::integer
  into open_exception_count,critical_exception_count
  from public.tax_exceptions
  where organization_id=p_organization_id
    and status in ('open','in_review');

  select count(*)::integer
  into ready_count
  from public.tax_periods
  where organization_id=p_organization_id
    and status in ('ready_for_approval','approved_for_filing');

  select to_jsonb(p) into latest_period
  from (
    select id,jurisdiction_code,period_type,period_start,period_end,status,
           source_sync_state,rule_pack_id,updated_at
    from public.tax_periods
    where organization_id=p_organization_id
    order by period_end desc,updated_at desc,id desc
    limit 1
  ) p;

  select to_jsonb(o) into next_obligation
  from (
    select id,obligation_key,due_date,amount_due,currency_code,status
    from public.tax_obligations
    where organization_id=p_organization_id
      and status not in ('paid','completed','superseded')
    order by due_date nulls last,created_at,id
    limit 1
  ) o;

  select exists(
    select 1 from public.tax_rule_packs rp
    where rp.jurisdiction_code='PH'
      and rp.status='approved'
      and (rp.effective_to is null or rp.effective_to>=current_date)
  ) into ph_rules_ready;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.workspace.v1',
    'generatedAt',clock_timestamp(),
    'organizationId',p_organization_id,
    'rules',jsonb_build_object(
      'philippinesApproved',ph_rules_ready,
      'calculationEnabled',ph_rules_ready
    ),
    'filing',jsonb_build_object(
      'enabled',false,
      'reason','No verified filing adapter is enabled by foundation v1.'
    ),
    'payments',jsonb_build_object(
      'enabled',false,
      'reason','Tax payment execution requires a separately verified adapter and explicit approval.'
    ),
    'summary',jsonb_build_object(
      'openExceptions',open_exception_count,
      'criticalExceptions',critical_exception_count,
      'readyForApproval',ready_count
    ),
    'latestPeriod',latest_period,
    'nextObligation',next_obligation
  );
end;
$function$;

-- plp_create_staff_task_v1 body SHA-256: eadfce73ab97b61ee556c3ef620bb72f2c3cdd56be0895f3facda6598692ce1b
CREATE OR REPLACE FUNCTION public.plp_create_staff_task_v1(p_request_id text, p_booking_reference text, p_title text, p_note text DEFAULT NULL::text, p_category text DEFAULT 'admin'::text, p_priority text DEFAULT 'normal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'state','acting',
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
    job.writer_epoch,'acting',
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
    'state','result',
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
    job.writer_epoch,'result',
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
$function$;

-- plp_enterprise_mobile_bootstrap_v1 body SHA-256: da7400c7f56ebde251e1c4cda622e051ad2e2d50760c1f446b08947151f34183
CREATE OR REPLACE FUNCTION public.plp_enterprise_mobile_bootstrap_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  profile public.profiles%rowtype;
  ctx jsonb;
  snap jsonb;
  business_date date;
  in_house jsonb := '[]'::jsonb;
  arrivals jsonb := '[]'::jsonb;
  departing jsonb := '[]'::jsonb;
  attention jsonb := '[]'::jsonb;
  team_members jsonb := '[]'::jsonb;
  team_activity jsonb := '[]'::jsonb;
  active_member_count integer := 0;
  total_member_count integer := 0;
  staff_identity_count integer := 0;
  has_mock boolean := false;
  source_age_hours numeric;
  effective_source_state text;
  effective_source_message text;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select * into profile
  from public.profiles p
  where p.id=uid;

  select to_jsonb(c) into ctx
  from plp_runtime.plp_ai_business_context c
  limit 1;

  select to_jsonb(s) into snap
  from public.enterprise_hospitality_snapshots s
  where s.organization_id=prop.organization_id
    and s.property_id=prop.id
  order by s.as_of desc, s.created_at desc, s.id desc
  limit 1;

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select coalesce(jsonb_agg(q.payload order by q.check_in, q.full_name),'[]'::jsonb)
  into in_house
  from (
    select
      b.check_in,
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',greatest(1,(business_date-b.check_in)+1),
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','In-house',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out > business_date
      and (
        b.check_in < business_date
        or upper(coalesce(b.status,'')) in ('CHECKED_IN','IN_HOUSE')
      )
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.full_name),'[]'::jsonb)
  into arrivals
  from (
    select
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',1,
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','Arriving',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_in=business_date
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.full_name),'[]'::jsonb)
  into departing
  from (
    select
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',b.nights,
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','Departing',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out=business_date
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.priority_rank, q.updated_at desc),
    '[]'::jsonb
  )
  into attention
  from (
    select
      case lower(coalesce(t.priority,''))
        when 'critical' then 0
        when 'high' then 1
        when 'medium' then 2
        else 3
      end as priority_rank,
      t.updated_at,
      jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'note',t.note,
        'priority',t.priority,
        'category',t.category,
        'status',t.status,
        'bookingReference',t.booking_reference,
        'fullName',g.full_name,
        'accommodationName',b.accommodation_name,
        'source',t.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(t.source,'')) like 'qa_%'
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_staff_tasks t
    left join plp_runtime.plp_bookings b
      on b.booking_reference=t.booking_reference
    left join plp_runtime.plp_guests g
      on g.id=b.guest_id
    where lower(coalesce(t.status,'')) not in
      ('done','completed','complete','cancelled','canceled','closed')
  ) q;

  select exists(
    select 1
    from plp_runtime.plp_bookings b
    left join plp_runtime.plp_guests g on g.id=b.guest_id
    where lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
       or lower(coalesce(b.source,'')) like 'qa_%'
  ) into has_mock;

  source_age_hours := case
    when prop.source_observed_at is null then null
    else extract(epoch from (clock_timestamp()-prop.source_observed_at))/3600.0
  end;
  effective_source_state := case
    when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid then 'stale'
    when has_mock then 'stale'
    when prop.source_observed_at is null then 'not_connected'
    when prop.source_observed_at < clock_timestamp()-interval '6 hours' then 'stale'
    else prop.source_status
  end;
  effective_source_message := case
    when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      then 'Demo/staging PLP data. Customer production tenant is not connected.'
    when has_mock
      then 'This workspace contains QA/mock hospitality records and is not verified as fully live.'
    when prop.source_observed_at is null
      then 'No verified source observation is available.'
    when prop.source_observed_at < clock_timestamp()-interval '6 hours'
      then 'Business source data is stale and should not be presented as current.'
    else coalesce(nullif(prop.source_message,''),'Source observation is current.')
  end;


  select count(*)::integer
  into active_member_count
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.status::text='active';

  select count(*)::integer
  into staff_identity_count
  from plp_runtime.plp_staff_identities s
  where s.active=true;

  with candidates as (
    select
      m.user_id,
      coalesce(nullif(trim(p.display_name),''),'PLP team member') as display_name,
      case lower(m.role::text)
        when 'owner' then 'Owner'
        when 'admin' then 'Administrator'
        else initcap(replace(m.role::text,'_',' '))
      end as role_label,
      m.role::text as access_role,
      m.status::text as access_status,
      m.status::text='active' as active,
      'membership'::text as source,
      m.updated_at,
      0 as source_rank
    from public.memberships m
    left join public.profiles p on p.id=m.user_id
    where m.organization_id=prop.organization_id
  ),
  ranked as (
    select
      c.*,
      row_number() over (
        partition by c.user_id
        order by c.source_rank, c.updated_at desc
      ) as rn
    from candidates c
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',r.user_id,
        'displayName',r.display_name,
        'roleLabel',r.role_label,
        'accessRole',r.access_role,
        'accessStatus',r.access_status,
        'active',r.active,
        'source',r.source,
        'isCurrentUser',r.user_id=uid
      )
      order by
        case lower(r.access_role)
          when 'owner' then 0
          when 'admin' then 1
          else 2
        end,
        r.display_name
    ),
    '[]'::jsonb
  )
  into team_members
  from ranked r
  where r.rn=1;

  total_member_count := jsonb_array_length(team_members);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'actor',coalesce(nullif(trim(t.actor),''),'PLP team'),
        'category',t.category,
        'status',t.status,
        'updatedAt',t.updated_at,
        'isMock',lower(coalesce(t.source,'')) like 'qa_%'
      )
      order by t.updated_at desc
    ),
    '[]'::jsonb
  )
  into team_activity
  from (
    select *
    from plp_runtime.plp_staff_tasks
    order by updated_at desc
    limit 12
  ) t;

  return jsonb_build_object(
    'schemaVersion','plp.enterprise.mobile-bootstrap.v6',
    'generatedAt',clock_timestamp(),
    'organization',jsonb_build_object(
      'id',prop.organization_id,
      'propertyId',prop.id,
      'propertySlug',prop.slug,
      'propertyName',prop.display_name,
      'businessIdentity','Luxury Resort',
      'timezone',prop.timezone,
      'currency',prop.currency
    ),
    'user',jsonb_build_object(
      'id',uid,
      'displayName',coalesce(nullif(trim(profile.display_name),''),'PLP administrator'),
      'role',member.role::text,
      'timezone',coalesce(profile.timezone,prop.timezone)
    ),
    'today',coalesce(ctx,'{}'::jsonb),
    'sourceHealth',jsonb_build_object(
      'state',effective_source_state,
      'rawState',prop.source_status,
      'observedAt',prop.source_observed_at,
      'ageHours',source_age_hours,
      'message',effective_source_message,
      'environment',case
        when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
          then 'demo_staging'
        else 'customer'
      end,
      'containsMockData',has_mock,
      'customerTenantConnected',
        prop.organization_id<>'2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
    ),
    'latestHospitalitySnapshot',snap,
    'guestExperience',jsonb_build_object(
      'businessDate',business_date,
      'snapshotBusinessDate',snap->>'business_date',
      'inHouse',in_house,
      'arrivals',arrivals,
      'departing',departing,
      'attention',attention,
      'containsMockData',has_mock
    ),
    'teamAccess',jsonb_build_object(
      'members',team_members,
      'recentActivity',team_activity,
      'activeMemberCount',active_member_count,
      'totalMemberCount',total_member_count,
      'staffIdentityCount',staff_identity_count,
      'currentUserRole',member.role::text,
      'canManageTeam',lower(member.role::text) in ('owner','admin'),
      'accessModel','organization_membership_all_statuses'
    ),
    'localAiContext',jsonb_build_object(
      'scope','plp-boracay-authorized-snapshot',
      'authoritativeAsOf',coalesce(ctx->>'generated_at',prop.source_observed_at::text),
      'payload',coalesce(ctx,'{}'::jsonb)
    )
  );
end;
$function$;

-- plp_pandora_activity_logs_v2 body SHA-256: 70f4fcda2c1adf5858f2b9266d37d8c3fed9536d65213f3b2aa40093e62f830d
CREATE OR REPLACE FUNCTION public.plp_pandora_activity_logs_v2(p_before_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_job_id uuid DEFAULT NULL::uuid, p_before_sequence bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 60, p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit,60),1),100);
  q text := nullif(trim(coalesce(p_query,'')),'');
  items jsonb := '[]'::jsonb;
  has_more boolean := false;
  next_before_at timestamptz := null;
  next_before_job_id uuid := null;
  next_before_sequence bigint := null;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if p_before_at is not null
     and (p_before_job_id is null or p_before_sequence is null) then
    raise exception 'complete activity cursor required' using errcode='22023';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  if lower(member.role::text) not in ('owner','admin') then
    raise exception 'PLP owner or admin access required' using errcode='42501';
  end if;

  with matched as (
    select
      a.event_id,
      a.job_id,
      a.sequence,
      a.state,
      a.message,
      coalesce(nullif(a.event->>'domain',''),'pandora') as domain,
      coalesce(nullif(a.event->>'capability',''),'activity') as capability,
      coalesce(nullif(a.event#>>'{provenance,sourceType}',''),'runtime') as source_type,
      j.request_id,
      coalesce(
        nullif(trim(p.display_name),''),
        case when j.requested_by is null then 'Pandora' else 'PLP user' end
      ) as actor_label,
      a.occurred_at
    from public.pandora_activity_events a
    left join public.pandora_activity_jobs j
      on j.id=a.job_id
     and j.organization_id=a.organization_id
    left join public.profiles p
      on p.id=j.requested_by
    where a.organization_id=prop.organization_id
      and (
        p_before_at is null
        or (a.occurred_at, a.job_id, a.sequence)
          < (p_before_at, p_before_job_id, p_before_sequence)
      )
      and (
        q is null
        or a.message ilike '%' || q || '%'
        or coalesce(a.state,'') ilike '%' || q || '%'
        or coalesce(a.event->>'domain','') ilike '%' || q || '%'
        or coalesce(a.event->>'capability','') ilike '%' || q || '%'
        or coalesce(a.event#>>'{provenance,sourceType}','') ilike '%' || q || '%'
        or coalesce(p.display_name,'') ilike '%' || q || '%'
        or coalesce(j.request_id,'') ilike '%' || q || '%'
        or a.job_id::text ilike '%' || q || '%'
      )
    order by a.occurred_at desc, a.job_id desc, a.sequence desc
    limit lim + 1
  ),
  page as (
    select *
    from matched
    order by occurred_at desc, job_id desc, sequence desc
    limit lim
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.event_id,
          'jobId',p.job_id,
          'sequence',p.sequence,
          'state',p.state,
          'status',p.state,
          'message',p.message,
          'domain',p.domain,
          'capability',p.capability,
          'sourceType',p.source_type,
          'requestId',p.request_id,
          'actorLabel',p.actor_label,
          'occurredAt',p.occurred_at
        )
        order by p.occurred_at desc, p.job_id desc, p.sequence desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > lim from matched),
    (select x.occurred_at from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1),
    (select x.job_id from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1),
    (select x.sequence from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1)
  into
    items,has_more,next_before_at,next_before_job_id,next_before_sequence
  from page p;

  if not coalesce(has_more,false) then
    next_before_at := null;
    next_before_job_id := null;
    next_before_sequence := null;
  end if;

  return jsonb_build_object(
    'schemaVersion','plp.pandora-activity-logs.v2',
    'items',items,
    'hasMore',coalesce(has_more,false),
    'nextBeforeAt',next_before_at,
    'nextBeforeJobId',next_before_job_id,
    'nextBeforeSequence',next_before_sequence
  );
end
$function$;

-- plp_recent_business_activity_v1 body SHA-256: de2b7187043157d4faf391fd74407562c3d8e6b86439792d351f9c7ef4defba9
CREATE OR REPLACE FUNCTION public.plp_recent_business_activity_v1(p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  items jsonb := '[]'::jsonb;
  has_mock boolean := false;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;
  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;
  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;
  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  with unified as (
    select
      'business:' || e.id::text as id,
      case
        when lower(coalesce(e.category,'')) in
          ('guest','guests','booking','bookings','arrival','arrivals','departure','departures','concierge','hospitality')
          then 'guests'
        when lower(coalesce(e.category,'')) in
          ('operations','team','staff','maintenance','housekeeping')
          then 'team'
        else 'all'
      end as audience,
      coalesce(nullif(trim(e.category),''),'activity') as category,
      e.title,
      e.summary,
      coalesce(nullif(trim(e.source_label),''),'PLP runtime') as source_label,
      e.occurred_at,
      lower(coalesce(e.source_label,'')) like '%mock%'
        or lower(coalesce(e.source_label,'')) like '%qa%' as is_mock
    from public.enterprise_business_activity e
    where e.organization_id=prop.organization_id
      and e.property_id=prop.id

    union all

    select
      'task:' || t.id::text as id,
      'team'::text as audience,
      coalesce(nullif(trim(t.category),''), nullif(trim(t.kind),''), 'team') as category,
      t.title,
      coalesce(nullif(trim(t.note),''), 'PLP staff task updated.') as summary,
      coalesce(nullif(trim(t.source),''),'PLP runtime') as source_label,
      coalesce(t.completed_at,t.updated_at,t.created_at) as occurred_at,
      lower(coalesce(t.source,'')) like 'qa_%'
        or lower(coalesce(t.actor,'')) like '%qa%' as is_mock
    from plp_runtime.plp_staff_tasks t

    union all

    select
      'booking:' || b.id::text as id,
      'guests'::text as audience,
      'booking'::text as category,
      case upper(coalesce(b.status,''))
        when 'CONFIRMED' then 'Booking confirmed'
        when 'CHECKED_IN' then 'Guest checked in'
        when 'IN_HOUSE' then 'Guest in house'
        when 'CHECKED_OUT' then 'Guest checked out'
        when 'CANCELLED' then 'Booking cancelled'
        when 'CANCELED' then 'Booking cancelled'
        else 'Booking updated'
      end as title,
      concat_ws(
        ' · ',
        nullif(trim(g.full_name),''),
        nullif(trim(b.accommodation_name),''),
        nullif(trim(b.booking_reference),'')
      ) as summary,
      coalesce(nullif(trim(b.source),''),'PLP runtime') as source_label,
      coalesce(b.confirmed_at,b.cancelled_at,b.updated_at,b.created_at) as occurred_at,
      lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
        or lower(coalesce(b.source,'')) like 'qa_%' as is_mock
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
  ),
  page as (
    select *
    from unified
    where occurred_at is not null
    order by occurred_at desc, id desc
    limit lim
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'audience',p.audience,
          'category',p.category,
          'title',p.title,
          'summary',p.summary,
          'sourceLabel',p.source_label,
          'occurredAt',p.occurred_at,
          'isMock',p.is_mock
        )
        order by p.occurred_at desc, p.id desc
      ),
      '[]'::jsonb
    ),
    coalesce(bool_or(p.is_mock),false)
  into items, has_mock
  from page p;

  return jsonb_build_object(
    'schemaVersion','plp.business-activity.v1',
    'items',items,
    'containsMockData',has_mock
  );
end
$function$;

-- plp_resort_audit_v1 body SHA-256: ebb478d4091c3473aa59296ead0825edad6dbf99562b1d38bd298c04adb5de71
CREATE OR REPLACE FUNCTION public.plp_resort_audit_v1(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  items jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc limit 1;
  if prop.id is null then raise exception 'active PLP membership required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(q.payload order by q.created_at desc),'[]'::jsonb)
  into items
  from (
    select a.created_at,
      jsonb_build_object(
        'id',a.id,'action',a.action,'entityKind',a.entity_kind,
        'entityId',a.entity_id,'actorRole',a.actor_role,
        'createdAt',a.created_at,
        'verified',coalesce((a.result->>'verified')::boolean,false),
        'providerReadbackVerified',
          coalesce((a.result->>'providerReadbackVerified')::boolean,false)
      ) as payload
    from plp_runtime.plp_resort_audit a
    where a.organization_id=prop.organization_id
    order by a.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),100))
  ) q;

  return jsonb_build_object(
    'schemaVersion','plp.resort.audit.v1',
    'generatedAt',clock_timestamp(),
    'items',items
  );
end;
$function$;

-- plp_resort_command_center_v1 body SHA-256: d78cb3ecb09b613ceb10e0058e410556327230ec097174aa2278f6311db7f8a4
CREATE OR REPLACE FUNCTION public.plp_resort_command_center_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  direct_active boolean:=false;
  d date;
  total integer:=0;
  occupied integer:=0;
  arriving integer:=0;
  departing integer:=0;
  open_work integer:=0;
  priority_work integer:=0;
  reservations integer:=0;
  stays integer:=0;
  housekeeping integer:=0;
  guests integer:=0;
  folios integer:=0;
  outstanding numeric:=0;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid
   and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select exists(
    select 1
    from private.plp_direct_source_bindings b
    where b.property_id=prop.id
      and b.organization_id=prop.organization_id
      and b.active=true
  ) into direct_active;

  if not direct_active then
    return public.plp_resort_command_center_legacy_20261001();
  end if;

  d:=(clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select
    count(*)::integer,
    count(*) filter(where lower(coalesce(room_state,''))='occupied')::integer
  into total,occupied
  from public.enterprise_hospitality_rooms
  where organization_id=prop.organization_id;

  select
    count(*) filter(where arrival_date=d and reservation_state in('held','confirmed'))::integer,
    count(*) filter(where departure_date=d and reservation_state in('confirmed','completed'))::integer,
    count(*)::integer
  into arriving,departing,reservations
  from public.enterprise_hospitality_reservations
  where organization_id=prop.organization_id;

  select count(*)::integer into stays
  from public.enterprise_hospitality_stays
  where organization_id=prop.organization_id;

  select count(*)::integer into housekeeping
  from public.enterprise_hospitality_housekeeping_jobs
  where organization_id=prop.organization_id;

  select count(*)::integer into guests
  from public.enterprise_hospitality_guest_profiles
  where organization_id=prop.organization_id;

  select
    count(*)::integer,
    coalesce(sum(balance_amount) filter(where folio_state='open'),0)
  into folios,outstanding
  from public.enterprise_hospitality_folios
  where organization_id=prop.organization_id;

  select
    count(*)::integer,
    count(*) filter(where task_state in('blocked','in_progress'))::integer
  into open_work,priority_work
  from public.enterprise_tasks
  where organization_id=prop.organization_id
    and task_state not in('completed','cancelled');

  return jsonb_build_object(
    'schemaVersion','plp.resort.command-center.direct.v1',
    'generatedAt',clock_timestamp(),
    'businessDate',d,
    'rooms','[]'::jsonb,
    'stays','[]'::jsonb,
    'experienceSignals','[]'::jsonb,
    'roomPulse',jsonb_build_object(
      'total',total,
      'occupied',occupied,
      'available',greatest(total-occupied,0),
      'arriving',arriving,
      'departing',departing
    ),
    'operations',jsonb_build_object(
      'openWork',open_work,
      'priorityWork',priority_work,
      'channelExceptions',0
    ),
    'finance',jsonb_build_object(
      'bookedValue30dPhp',null,
      'outstandingBalancePhp',outstanding,
      'paidValue30dPhp',null
    ),
    'universalHospitality',jsonb_build_object(
      'rooms',total,
      'reservations',reservations,
      'stays',stays,
      'housekeepingJobs',housekeeping,
      'guestProfiles',guests,
      'folios',folios
    ),
    'truth',jsonb_build_object(
      'projectionOnly',true,
      'contactDetailsExcluded',true,
      'liveOperationalDataAvailable',true,
      'source','Pandora Direct / tenant-scoped Universal Hospitality',
      'externalPmsOtaConnected',false
    )
  );
end;
$function$;

-- plp_resort_operating_manifest_v1 body SHA-256: d28d073857be81d383ae87da0aa66080d943bf289a080aad35aa70ae29ea53d0
CREATE OR REPLACE FUNCTION public.plp_resort_operating_manifest_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_property public.enterprise_properties%rowtype;
  v_allowed boolean := false;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select *
  into v_property
  from public.enterprise_properties p
  where p.slug = 'plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if v_property.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select exists(
    select 1
    from public.memberships m
    where m.organization_id = v_property.organization_id
      and m.user_id = v_uid
      and m.status::text = 'active'
  )
  into v_allowed;

  if not v_allowed then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'plp.resort-operating-system.v1',
    'workspaceSlug', 'plp-boracay',
    'workspaceName', v_property.display_name,
    'assistantIdentity', 'MFR',
    'design', jsonb_build_object(
      'contentPages', 'light_ivory_editorial_luxury',
      'navigationPanel', 'pure_black',
      'logoPlacement', 'workspace_selector_only'
    ),
    'truthContract', jsonb_build_object(
      'activityTheatre', 'verified_events_only',
      'completionRequiresEvidence', true,
      'fabricatedMetricsAllowed', false,
      'sourceHealthRequired', true
    ),
    'groups', '[{"group":"Guest & Stay","modules":["Reservations","Front Desk","Arrivals & Departures","In-House Guests","Guest Profiles & CRM","Concierge","Guest Requests & Recovery","VIP & Preferences","Lost & Found"]},{"group":"Rooms & Property","modules":["Rooms","Housekeeping","Laundry & Linen","Maintenance","Engineering","Security & Incidents","Transport & Fleet","Beach, Pool & Facilities","Utilities"]},{"group":"Hospitality & Experiences","modules":["Food & Beverage","Restaurants & Bars","Room Service","Spa & Wellness","Experiences & Activities","Weddings & Events"]},{"group":"Commercial","modules":["Rates & Availability","Sales & CRM","Marketing & Campaigns","Distribution & Channels","Reviews & Reputation"]},{"group":"Finance & Supply","modules":["Finance & Billing","Procurement","Suppliers","Inventory & Stock","Cash & Payments","CapEx & Assets"]},{"group":"People & Governance","modules":["Scheduling & Attendance","Training & SOPs","Documents & Compliance","Permits & Expiry","Sustainability"]},{"group":"Intelligence & System","modules":["Reports & Forecasts","Automations","Integrations","Notifications","Audit & Provenance"]}]'::jsonb,
    'moduleCount', 45,
    'generatedAt', clock_timestamp()
  );
end;
$function$;

-- plp_resort_operations_v1 body SHA-256: 15953f2daee88c73cecb0c8b45a3f9f99f6cbc19a68f1fb0d54f9c43789d719d
CREATE OR REPLACE FUNCTION public.plp_resort_operations_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  work_items jsonb := '[]'::jsonb;
  channel_conflicts jsonb := '[]'::jsonb;
  housekeeping_jobs jsonb := '[]'::jsonb;
  folios jsonb := '[]'::jsonb;
  allow_test_data boolean := false;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships resolver
    on resolver.organization_id=p.organization_id
   and resolver.user_id=uid
   and resolver.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id=prop.organization_id
      and m.user_id=uid
      and m.status::text='active'
  ) then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  allow_test_data := prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into work_items
  from (
    select
      t.updated_at,
      jsonb_build_object(
        'id',t.id,
        'bookingReference',t.booking_reference,
        'kind',t.kind,
        'category',t.category,
        'priority',t.priority,
        'status',t.status,
        'title',t.title,
        'note',t.note,
        'source',t.source,
        'actor',t.actor,
        'createdAt',t.created_at,
        'updatedAt',t.updated_at,
        'completedAt',t.completed_at,
        'isTestData',
          lower(coalesce(t.source,'')) like 'qa_%'
          or lower(coalesce(t.actor,'')) like '%qa%'
          or lower(coalesce(t.note,'')) like '%mock%'
      ) as payload
    from plp_runtime.plp_staff_tasks t
    where allow_test_data or not private.plp_task_is_test_v1(t.id)
    order by t.updated_at desc
    limit 80
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into channel_conflicts
  from (
    select
      c.updated_at,
      jsonb_build_object(
        'id',c.id,
        'channelKey',c.channel_key,
        'conflictType',c.conflict_type,
        'internalBookingReference',c.internal_booking_reference,
        'otaReservationReference',c.ota_reservation_reference,
        'accommodationName',c.accommodation_name,
        'startDate',c.start_date,
        'endDate',c.end_date,
        'severity',c.severity,
        'status',c.status,
        'resolutionNote',c.resolution_note,
        'resolutionStatus',c.resolution_status,
        'resolutionType',c.resolution_type,
        'createdAt',c.created_at,
        'updatedAt',c.updated_at,
        'isTestData',
          lower(coalesce(c.internal_booking_reference,'')) like 'mock-%'
          or lower(coalesce(c.ota_reservation_reference,'')) like 'mock-%'
      ) as payload
    from plp_runtime.plp_ota_conflicts c
    where allow_test_data or not private.plp_conflict_is_test_v1(c.id)
    order by c.updated_at desc
    limit 50
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.created_at desc),'[]'::jsonb)
  into housekeeping_jobs
  from (
    select
      h.created_at,
      jsonb_build_object(
        'taskEntityId',h.task_entity_id,
        'roomLocationEntityId',h.room_location_entity_id,
        'housekeepingType',h.housekeeping_type,
        'createdAt',h.created_at
      ) as payload
    from public.enterprise_hospitality_housekeeping_jobs h
    where h.organization_id=prop.organization_id
    order by h.created_at desc
    limit 50
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into folios
  from (
    select
      f.updated_at,
      jsonb_build_object(
        'entityId',f.entity_id,
        'stayEntityId',f.stay_entity_id,
        'currency',f.currency,
        'folioState',f.folio_state,
        'balanceAmount',f.balance_amount,
        'createdAt',f.created_at,
        'updatedAt',f.updated_at
      ) as payload
    from public.enterprise_hospitality_folios f
    where f.organization_id=prop.organization_id
    order by f.updated_at desc
    limit 50
  ) q;

  return jsonb_build_object(
    'schemaVersion','plp.resort.operations.v1',
    'generatedAt',clock_timestamp(),
    'workItems',work_items,
    'channelConflicts',channel_conflicts,
    'housekeepingJobs',housekeeping_jobs,
    'folios',folios,
    'truth',jsonb_build_object(
      'source','existing PLP runtime + Universal hospitality records',
      'projectionOnly',true,
      'noSyntheticRows',true,
      'testDataQuarantined',not allow_test_data
    )
  );
end;
$function$;

-- plp_resort_transaction_v1 body SHA-256: 9f5cb780269529db3374cdd91fc1acc12c9e29245e4792f5ec120706cfe43d74
CREATE OR REPLACE FUNCTION public.plp_resort_transaction_v1(p_request_id text, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  actor_role text;
  request_key text := btrim(coalesce(p_request_id,''));
  action_name text := lower(btrim(coalesce(p_action,'')));
  payload jsonb := coalesce(p_payload,'{}'::jsonb);
  payload_sha text;
  prior plp_runtime.plp_resort_write_receipts%rowtype;
  result jsonb;
  entity_kind text := 'unknown';
  entity_id text := '';
  room plp_runtime.plp_accommodations%rowtype;
  booking plp_runtime.plp_bookings%rowtype;
  guest_id uuid;
  task_row plp_runtime.plp_staff_tasks%rowtype;
  conflict_row plp_runtime.plp_ota_conflicts%rowtype;
  check_in_date date;
  check_out_date date;
  business_date date;
  guest_count_value integer;
  nights_count integer;
  rate_php numeric;
  total_php numeric;
  amount_php numeric;
  requested_state text;
  requested_status text;
  requested_priority text;
  booking_ref text;
  manual_ref text;
  force_action boolean := coalesce((payload->>'force')::boolean,false);
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if char_length(request_key) < 8 or char_length(request_key) > 160 then
    raise exception 'request_id must be 8 to 160 characters' using errcode='22023';
  end if;
  if action_name not in (
    'create_booking','update_booking','check_in','check_out','cancel_booking',
    'update_guest','set_room_state','set_room_rate','update_task',
    'resolve_conflict','record_manual_payment'
  ) then
    raise exception 'unsupported PLP resort action: %',action_name using errcode='22023';
  end if;
  if jsonb_typeof(payload) <> 'object' then
    raise exception 'payload must be an object' using errcode='22023';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid
   and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;
  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select m.role::text into actor_role
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if actor_role not in ('owner','admin','operator') then
    raise exception 'PLP operator access required' using errcode='42501';
  end if;

  payload_sha := encode(extensions.digest(payload::text,'sha256'),'hex');
  select r.* into prior
  from plp_runtime.plp_resort_write_receipts r
  where r.organization_id=prop.organization_id
    and r.request_id=request_key;
  if prior.request_id is not null then
    if prior.action<>action_name or prior.payload_sha256<>payload_sha then
      raise exception 'request_id already used with different PLP action or payload'
        using errcode='23505';
    end if;
    return prior.result || jsonb_build_object('idempotentReplay',true);
  end if;

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  if action_name='create_booking' then
    if coalesce(payload->>'guestFullName','')='' or coalesce(payload->>'guestEmail','')='' then
      raise exception 'guestFullName and guestEmail are required' using errcode='22023';
    end if;
    if coalesce(payload->>'checkIn','') !~ '^\d{4}-\d{2}-\d{2}$'
       or coalesce(payload->>'checkOut','') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'checkIn and checkOut must use YYYY-MM-DD' using errcode='22023';
    end if;
    check_in_date := (payload->>'checkIn')::date;
    check_out_date := (payload->>'checkOut')::date;
    if check_out_date<=check_in_date then
      raise exception 'checkOut must be after checkIn' using errcode='22023';
    end if;

    if nullif(payload->>'accommodationId','') is not null then
      select * into room from plp_runtime.plp_accommodations
      where id=(payload->>'accommodationId')::uuid and is_active=true;
    else
      select * into room from plp_runtime.plp_accommodations
      where lower(name)=lower(coalesce(payload->>'accommodationName','')) and is_active=true
      limit 1;
    end if;
    if room.id is null then
      raise exception 'active accommodation not found' using errcode='P0002';
    end if;

    guest_count_value := greatest(coalesce(nullif(payload->>'guestCount','')::integer,1),1);
    if guest_count_value>room.capacity then
      raise exception 'guest count exceeds room capacity' using errcode='22023';
    end if;
    if exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and daterange(b.check_in,b.check_out,'[)') &&
            daterange(check_in_date,check_out_date,'[)')
    ) then
      raise exception 'room is not available for the selected dates' using errcode='23P01';
    end if;

    insert into plp_runtime.plp_guests(
      full_name,email,phone,metadata,updated_at
    ) values (
      btrim(payload->>'guestFullName'),
      btrim(payload->>'guestEmail'),
      nullif(btrim(coalesce(payload->>'guestPhone','')),''),
      jsonb_build_object('source','pandora_plp_mobile'),
      clock_timestamp()
    )
    on conflict (normalized_email) do update set
      full_name=excluded.full_name,
      email=excluded.email,
      phone=coalesce(excluded.phone,plp_runtime.plp_guests.phone),
      updated_at=clock_timestamp()
    returning id into guest_id;

    if payload ? 'ratePerNightPhp' then
      if actor_role not in ('owner','admin') then
        raise exception 'only owner or admin may override room rate' using errcode='42501';
      end if;
      rate_php := (payload->>'ratePerNightPhp')::numeric;
      if rate_php < 0 then
        raise exception 'room rate cannot be negative' using errcode='22023';
      end if;
    else
      rate_php := room.nightly_rate_php;
    end if;
    nights_count := check_out_date-check_in_date;
    total_php := rate_php*nights_count;
    booking_ref := 'PLP-'||to_char(check_in_date,'YYMMDD')||'-'||
      upper(substr(md5(request_key),1,6));

    insert into plp_runtime.plp_bookings(
      booking_reference,guest_id,accommodation_id,accommodation_name,
      check_in,check_out,guest_count,nights,rate_per_night_php,total_amount_php,
      deposit_amount_php,balance_amount_php,status,payment_status,special_requests,
      source,confirmed_at,updated_at
    ) values (
      booking_ref,guest_id,room.id,room.name,
      check_in_date,check_out_date,guest_count_value,nights_count,rate_php,total_php,
      0,total_php,'CONFIRMED','PENDING',
      nullif(btrim(coalesce(payload->>'specialRequests','')),''),
      'pandora_plp_mobile',clock_timestamp(),clock_timestamp()
    )
    returning * into booking;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,
      'bookingId',booking.id,
      'guestId',booking.guest_id,
      'roomId',booking.accommodation_id,
      'roomName',booking.accommodation_name,
      'checkIn',booking.check_in,'checkOut',booking.check_out,
      'guestCount',booking.guest_count,'nights',booking.nights,
      'ratePerNightPhp',booking.rate_per_night_php,
      'totalAmountPhp',booking.total_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,
      'status',booking.status,'paymentStatus',booking.payment_status
    );

  elsif action_name='update_booking' then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;
    if upper(booking.status) in ('CANCELLED','CANCELED','CHECKED_OUT') then
      raise exception 'closed booking cannot be edited' using errcode='22023';
    end if;

    check_in_date:=coalesce(nullif(payload->>'checkIn','')::date,booking.check_in);
    check_out_date:=coalesce(nullif(payload->>'checkOut','')::date,booking.check_out);
    if check_out_date<=check_in_date then
      raise exception 'checkOut must be after checkIn' using errcode='22023';
    end if;
    guest_count_value:=coalesce(nullif(payload->>'guestCount','')::integer,booking.guest_count);

    if nullif(payload->>'accommodationId','') is not null then
      select * into room from plp_runtime.plp_accommodations
      where id=(payload->>'accommodationId')::uuid and is_active=true;
    else
      select * into room from plp_runtime.plp_accommodations
      where id=booking.accommodation_id;
    end if;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;
    if guest_count_value<1 or guest_count_value>room.capacity then
      raise exception 'guest count is outside room capacity' using errcode='22023';
    end if;
    if exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=room.id and b.id<>booking.id
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and daterange(b.check_in,b.check_out,'[)') &&
            daterange(check_in_date,check_out_date,'[)')
    ) then
      raise exception 'room is not available for the selected dates' using errcode='23P01';
    end if;

    rate_php:=booking.rate_per_night_php;
    if payload ? 'ratePerNightPhp' then
      if actor_role not in ('owner','admin') then
        raise exception 'only owner or admin may override room rate' using errcode='42501';
      end if;
      rate_php:=(payload->>'ratePerNightPhp')::numeric;
      if rate_php < 0 then
        raise exception 'room rate cannot be negative' using errcode='22023';
      end if;
    end if;
    nights_count:=check_out_date-check_in_date;
    total_php:=rate_php*nights_count;

    update plp_runtime.plp_bookings set
      accommodation_id=room.id,
      accommodation_name=room.name,
      check_in=check_in_date,
      check_out=check_out_date,
      guest_count=guest_count_value,
      nights=nights_count,
      rate_per_night_php=rate_php,
      total_amount_php=total_php,
      balance_amount_php=greatest(total_php-deposit_amount_php,0),
      payment_status=case
        when greatest(total_php-deposit_amount_php,0)=0 then 'PAID'
        when deposit_amount_php>0 then 'PARTIALLY_PAID'
        else payment_status
      end,
      special_requests=case
        when payload ? 'specialRequests'
          then nullif(btrim(coalesce(payload->>'specialRequests','')),'')
        else special_requests
      end,
      updated_at=clock_timestamp()
    where id=booking.id
    returning * into booking;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,'bookingId',booking.id,
      'roomId',booking.accommodation_id,'roomName',booking.accommodation_name,
      'checkIn',booking.check_in,'checkOut',booking.check_out,
      'guestCount',booking.guest_count,'nights',booking.nights,
      'ratePerNightPhp',booking.rate_per_night_php,
      'totalAmountPhp',booking.total_amount_php,
      'balanceAmountPhp',booking.balance_amount_php,
      'status',booking.status,'paymentStatus',booking.payment_status,
      'specialRequests',booking.special_requests
    );

  elsif action_name in ('check_in','check_out','cancel_booking') then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;

    if action_name='check_in' then
      if upper(booking.status)='CHECKED_IN' then null;
      elsif upper(booking.status) in ('CANCELLED','CANCELED','CHECKED_OUT') then
        raise exception 'closed booking cannot be checked in' using errcode='22023';
      elsif business_date<booking.check_in and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'booking is not due for check-in yet' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CHECKED_IN',updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    elsif action_name='check_out' then
      if upper(booking.status)='CHECKED_OUT' then null;
      elsif upper(booking.status)<>'CHECKED_IN'
        and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'booking must be checked in before check-out' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CHECKED_OUT',updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    else
      if upper(booking.status) in ('CANCELLED','CANCELED') then null;
      elsif upper(booking.status)='CHECKED_OUT' then
        raise exception 'checked-out booking cannot be cancelled' using errcode='22023';
      elsif upper(booking.status)='CHECKED_IN'
        and not (force_action and actor_role in ('owner','admin')) then
        raise exception 'checked-in stay must be checked out or owner-forced' using errcode='22023';
      else
        update plp_runtime.plp_bookings
        set status='CANCELLED',cancelled_at=clock_timestamp(),updated_at=clock_timestamp()
        where id=booking.id returning * into booking;
      end if;
    end if;

    entity_kind:='booking'; entity_id:=booking.id::text;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,'bookingId',booking.id,
      'status',booking.status,'paymentStatus',booking.payment_status,
      'balanceAmountPhp',booking.balance_amount_php
    );

  elsif action_name='update_guest' then
    if nullif(payload->>'guestId','') is not null then
      guest_id:=(payload->>'guestId')::uuid;
    else
      booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
      select b.guest_id into guest_id
      from plp_runtime.plp_bookings b
      where b.booking_reference=booking_ref;
    end if;
    if guest_id is null then raise exception 'guest not found' using errcode='P0002'; end if;

    if payload ? 'guestEmail' then
      if btrim(coalesce(payload->>'guestEmail',''))='' then raise exception 'guestEmail cannot be empty' using errcode='22023'; end if;
    end if;

    update plp_runtime.plp_guests g set
      full_name=case when payload ? 'guestFullName'
        then nullif(btrim(coalesce(payload->>'guestFullName','')),'') else g.full_name end,
      email=case when payload ? 'guestEmail'
        then btrim(payload->>'guestEmail') else g.email end,
      phone=case when payload ? 'guestPhone'
        then nullif(btrim(coalesce(payload->>'guestPhone','')),'') else g.phone end,
      updated_at=clock_timestamp()
    where g.id=guest_id;

    if payload ? 'specialRequests' and nullif(payload->>'bookingReference','') is not null then
      update plp_runtime.plp_bookings
      set special_requests=nullif(btrim(coalesce(payload->>'specialRequests','')),''),
          updated_at=clock_timestamp()
      where booking_reference=payload->>'bookingReference';
    end if;

    entity_kind:='guest'; entity_id:=guest_id::text;
    select jsonb_build_object(
      'guestId',g.id,'fullName',g.full_name,'email',g.email,'phone',g.phone
    ) into result
    from plp_runtime.plp_guests g where g.id=guest_id;

  elsif action_name='set_room_state' then
    select * into room from plp_runtime.plp_accommodations
    where id=(payload->>'accommodationId')::uuid and is_active=true;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;
    requested_state:=lower(btrim(coalesce(payload->>'state','')));
    if requested_state not in ('ready','cleaning','maintenance','out_of_order') then
      raise exception 'invalid room operational state' using errcode='22023';
    end if;
    if requested_state='out_of_order' and actor_role not in ('owner','admin') then
      raise exception 'only owner or admin may mark a room out of order' using errcode='42501';
    end if;

    insert into plp_runtime.plp_room_operations(
      accommodation_id,operational_state,note,updated_by,updated_at
    ) values (
      room.id,requested_state,
      nullif(btrim(coalesce(payload->>'note','')),''),
      uid,clock_timestamp()
    )
    on conflict (accommodation_id) do update set
      operational_state=excluded.operational_state,
      note=excluded.note,
      updated_by=excluded.updated_by,
      updated_at=excluded.updated_at;

    entity_kind:='room'; entity_id:=room.id::text;
    select jsonb_build_object(
      'accommodationId',r.accommodation_id,
      'roomName',room.name,
      'operationalState',r.operational_state,
      'note',r.note,'updatedAt',r.updated_at
    ) into result
    from plp_runtime.plp_room_operations r where r.accommodation_id=room.id;

  elsif action_name='set_room_rate' then
    if actor_role not in ('owner','admin') then
      raise exception 'only owner or admin may change room rates' using errcode='42501';
    end if;
    rate_php:=(payload->>'nightlyRatePhp')::numeric;
    if rate_php < 0 then
      raise exception 'room rate cannot be negative' using errcode='22023';
    end if;
    update plp_runtime.plp_accommodations
    set nightly_rate_php=rate_php,updated_at=clock_timestamp()
    where id=(payload->>'accommodationId')::uuid and is_active=true
    returning * into room;
    if room.id is null then raise exception 'active accommodation not found' using errcode='P0002'; end if;

    entity_kind:='room'; entity_id:=room.id::text;
    result:=jsonb_build_object(
      'accommodationId',room.id,'roomName',room.name,
      'nightlyRatePhp',room.nightly_rate_php
    );

  elsif action_name='update_task' then
    select * into task_row from plp_runtime.plp_staff_tasks
    where id=(payload->>'taskId')::uuid for update;
    if task_row.id is null then raise exception 'task not found' using errcode='P0002'; end if;
    requested_status:=lower(btrim(coalesce(payload->>'status',task_row.status)));
    requested_priority:=lower(btrim(coalesce(payload->>'priority',task_row.priority)));
    if requested_status not in ('open','in_progress','done','cancelled') then
      raise exception 'invalid task status' using errcode='22023';
    end if;
    if requested_priority not in ('normal','medium','high','critical') then
      raise exception 'invalid task priority' using errcode='22023';
    end if;
    update plp_runtime.plp_staff_tasks set
      status=requested_status,
      priority=requested_priority,
      note=case when payload ? 'note' then nullif(btrim(coalesce(payload->>'note','')),'') else note end,
      completed_at=case when requested_status='done' then clock_timestamp() else null end,
      updated_at=clock_timestamp()
    where id=task_row.id returning * into task_row;

    entity_kind:='task'; entity_id:=task_row.id::text;
    result:=jsonb_build_object(
      'taskId',task_row.id,'title',task_row.title,'status',task_row.status,
      'priority',task_row.priority,'completedAt',task_row.completed_at
    );

  elsif action_name='resolve_conflict' then
    select * into conflict_row from plp_runtime.plp_ota_conflicts
    where id=(payload->>'conflictId')::uuid for update;
    if conflict_row.id is null then raise exception 'channel conflict not found' using errcode='P0002'; end if;
    update plp_runtime.plp_ota_conflicts set
      status='resolved',
      resolution_status='resolved',
      resolution_type=coalesce(nullif(btrim(payload->>'resolutionType'),''),'manual'),
      resolution_note=nullif(btrim(coalesce(payload->>'note','')),''),
      resolved_by=uid::text,
      resolved_at=clock_timestamp(),
      updated_at=clock_timestamp()
    where id=conflict_row.id returning * into conflict_row;

    entity_kind:='channel_conflict'; entity_id:=conflict_row.id::text;
    result:=jsonb_build_object(
      'conflictId',conflict_row.id,'channelKey',conflict_row.channel_key,
      'status',conflict_row.status,'resolutionStatus',conflict_row.resolution_status,
      'resolutionType',conflict_row.resolution_type,'resolvedAt',conflict_row.resolved_at
    );

  elsif action_name='record_manual_payment' then
    booking_ref:=btrim(coalesce(payload->>'bookingReference',''));
    select * into booking from plp_runtime.plp_bookings
    where booking_reference=booking_ref for update;
    if booking.id is null then raise exception 'booking not found' using errcode='P0002'; end if;
    amount_php:=(payload->>'amountPhp')::numeric;
    if amount_php<=0 then raise exception 'payment amount must be positive' using errcode='22023'; end if;
    if amount_php>booking.balance_amount_php then
      raise exception 'payment amount exceeds outstanding balance' using errcode='22023';
    end if;
    manual_ref:=btrim(coalesce(payload->>'reference',''));
    if char_length(manual_ref)<3 then
      raise exception 'manual payment reference is required' using errcode='22023';
    end if;

    insert into plp_runtime.plp_payments(
      booking_id,provider,provider_reference_id,amount_php,currency,status,
      verification_status,raw_response,paid_at,updated_at
    ) values (
      booking.id,'manual',manual_ref,amount_php,'PHP','PAID','VERIFIED',
      jsonb_build_object(
        'recordedBy',uid,
        'note',nullif(btrim(coalesce(payload->>'note','')),''),
        'source','pandora_plp_mobile'
      ),
      clock_timestamp(),clock_timestamp()
    );

    update plp_runtime.plp_bookings set
      deposit_amount_php=least(total_amount_php,deposit_amount_php+amount_php),
      balance_amount_php=greatest(balance_amount_php-amount_php,0),
      payment_status=case
        when greatest(balance_amount_php-amount_php,0)=0 then 'PAID'
        else 'PARTIALLY_PAID'
      end,
      updated_at=clock_timestamp()
    where id=booking.id returning * into booking;

    entity_kind:='payment'; entity_id:=manual_ref;
    result:=jsonb_build_object(
      'bookingReference',booking.booking_reference,
      'amountPhp',amount_php,'reference',manual_ref,
      'paymentStatus',booking.payment_status,
      'balanceAmountPhp',booking.balance_amount_php
    );
  end if;

  result:=jsonb_build_object(
    'schemaVersion','plp.resort.transaction.v1',
    'requestId',request_key,
    'action',action_name,
    'verified',true,
    'providerReadbackVerified',true,
    'entityKind',entity_kind,
    'entityId',entity_id,
    'readback',coalesce(result,'{}'::jsonb)
  );

  insert into plp_runtime.plp_resort_audit(
    organization_id,actor_user_id,actor_role,request_id,action,entity_kind,entity_id,result
  ) values (
    prop.organization_id,uid,actor_role,request_key,action_name,entity_kind,entity_id,result
  );

  insert into plp_runtime.plp_resort_write_receipts(
    organization_id,request_id,actor_user_id,action,payload_sha256,result
  ) values (
    prop.organization_id,request_key,uid,action_name,payload_sha,result
  );

  return result;
end;
$function$;

-- plp_room_operations_v1 body SHA-256: adbc3aadde32d6ca66528e412bf20dc4176bf45d912320f96e5b5ef8c0a831ac
CREATE OR REPLACE FUNCTION public.plp_room_operations_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  items jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'authentication required' using errcode='42501'; end if;
  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc limit 1;
  if prop.id is null then raise exception 'active PLP membership required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'accommodationId',a.id,'roomName',a.name,
    'operationalState',coalesce(o.operational_state,'ready'),
    'note',o.note,'updatedAt',o.updated_at
  ) order by a.name),'[]'::jsonb)
  into items
  from plp_runtime.plp_accommodations a
  left join plp_runtime.plp_room_operations o on o.accommodation_id=a.id
  where a.is_active=true;

  return jsonb_build_object(
    'schemaVersion','plp.room.operations.v1',
    'generatedAt',clock_timestamp(),
    'rooms',items
  );
end;
$function$;

-- Raw activity admission baseline body SHA-256: 2c7bd0bcb0b030dfc5413a0396b19fc94f3eea814aab201fa4d70b1d88e3ac94
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

-- Existing composer control and replay baselines.

-- pandora_activity_control_request_v1 body SHA-256: 8d1cd80bfba19e67082b45f52cc7d2956b5e5bd08e3926494996f35c192cb792
CREATE OR REPLACE FUNCTION public.pandora_activity_control_request_v1(p_organization_id uuid, p_job_id uuid, p_request_id text, p_control_type text, p_instruction text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_job public.pandora_activity_jobs%rowtype;
  v_control public.pandora_activity_controls%rowtype;
  v_type text := lower(trim(coalesce(p_control_type,'')));
  v_instruction text := nullif(trim(coalesce(p_instruction,'')),'');
begin
  if v_uid is null then raise exception 'pandora_activity_sign_in_required' using errcode='42501'; end if;
  if p_request_id is null or length(trim(p_request_id)) not between 8 and 200 then raise exception 'pandora_activity_control_request_id_invalid' using errcode='22023'; end if;
  if v_type not in ('cancel','redirect','constraint') then raise exception 'pandora_activity_control_type_invalid' using errcode='22023'; end if;
  if (v_type in ('redirect','constraint') and (v_instruction is null or length(v_instruction)>2000)) or (v_type='cancel' and v_instruction is not null) then raise exception 'pandora_activity_control_instruction_invalid' using errcode='22023'; end if;
  if v_instruction is not null and v_instruction ~* '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(ql)?://[^[:space:]@:]+:[^[:space:]@]+@)' then raise exception 'pandora_activity_control_credential_material_rejected' using errcode='22023'; end if;
  if not exists (select 1 from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active') then raise exception 'pandora_activity_membership_required' using errcode='42501'; end if;

  select * into v_job from public.pandora_activity_jobs where id=p_job_id and organization_id=p_organization_id and requested_by=v_uid for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;

  select * into v_control from public.pandora_activity_controls where job_id=v_job.id and request_id=trim(p_request_id);
  if found then
    if v_control.control_type<>v_type or coalesce(v_control.instruction,'')<>coalesce(v_instruction,'') then raise exception 'pandora_activity_control_idempotency_conflict' using errcode='23505'; end if;
    return jsonb_build_object('controlId',v_control.id,'jobId',v_control.job_id,'requestId',v_control.request_id,'controlSequence',v_control.control_sequence,'controlType',v_control.control_type,'status',v_control.status,'requestedAt',v_control.requested_at);
  end if;
  if v_job.terminal_state is not null then raise exception 'pandora_activity_job_terminal' using errcode='55000'; end if;
  if v_job.controls_sealed_at is not null then raise exception 'pandora_activity_control_window_closed' using errcode='55000'; end if;

  insert into public.pandora_activity_controls(job_id,organization_id,requested_by,request_id,control_type,instruction)
  values (v_job.id,v_job.organization_id,v_uid,trim(p_request_id),v_type,v_instruction)
  on conflict (job_id,request_id) do update set request_id=excluded.request_id
  returning * into v_control;
  if v_control.control_type<>v_type or coalesce(v_control.instruction,'')<>coalesce(v_instruction,'') then raise exception 'pandora_activity_control_idempotency_conflict' using errcode='23505'; end if;

  return jsonb_build_object('controlId',v_control.id,'jobId',v_control.job_id,'requestId',v_control.request_id,'controlSequence',v_control.control_sequence,'controlType',v_control.control_type,'status',v_control.status,'requestedAt',v_control.requested_at);
end;
$function$;

-- pandora_activity_device_fact_v1 body SHA-256: ce966a29b43ef163df9b188dd60541a5cb1f74b75d3a75d2cea31e7accef15e3
CREATE OR REPLACE FUNCTION public.pandora_activity_device_fact_v1(p_organization_id uuid, p_job_id uuid, p_operation_id text, p_capability text, p_stage text, p_observed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_job public.pandora_activity_jobs%rowtype;
  v_existing public.pandora_activity_events%rowtype;
  v_operation text := trim(coalesce(p_operation_id,''));
  v_capability text := trim(coalesce(p_capability,''));
  v_stage text := trim(coalesce(p_stage,''));
  v_event_id text;
  v_sequence bigint;
  v_state text;
  v_message text;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_admitted timestamptz := now();
  v_at_text text;
  v_admitted_text text;
  v_ref text;
  v_evidence jsonb;
  v_blocker jsonb := null;
  v_outcome jsonb := null;
  v_event jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_uid
      and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;
  if v_operation !~ '^[A-Za-z0-9._:-]{8,128}$' then
    raise exception 'pandora_device_operation_id_invalid' using errcode='22023';
  end if;
  if v_capability not in ('calendar.events','reminder.local','communication.sms','communication.call') then
    raise exception 'pandora_device_capability_invalid' using errcode='22023';
  end if;
  if v_stage not in (
    'acting','verifying','result','failed','needs_permission',
    'needs_special_access','needs_choice'
  ) then
    raise exception 'pandora_device_stage_invalid' using errcode='22023';
  end if;
  if v_at > now() + interval '5 minutes'
     or v_at < now() - interval '30 days' then
    raise exception 'pandora_device_observed_at_invalid' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_activity_jobs
  where id=p_job_id
    and organization_id=p_organization_id
  for update;
  if not found or v_job.requested_by <> v_uid then
    raise exception 'pandora_activity_job_not_available' using errcode='42501';
  end if;

  v_event_id := 'device:' || replace(v_capability,'.','-') || ':' || v_operation || ':' || v_stage;
  select * into v_existing
  from public.pandora_activity_events
  where job_id=p_job_id and event_id=v_event_id;
  if found then
    return jsonb_build_object(
      'ok',true,'duplicate',true,'jobId',p_job_id,
      'eventId',v_existing.event_id,'sequence',v_existing.sequence,
      'state',v_existing.state
    );
  end if;

  if v_job.terminal_state is not null then
    raise exception 'pandora_activity_job_terminal' using errcode='55000';
  end if;

  case v_stage
    when 'acting' then
      v_state := 'acting';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar action started.'
        when 'reminder.local' then 'Android local reminder action started.'
        when 'communication.sms' then 'Android direct SMS action started.'
        when 'communication.call' then 'Android direct call action started.'
        else 'Android device action started.'
      end;
    when 'verifying' then
      v_state := 'verifying';
      v_message := case v_capability
        when 'calendar.events' then 'Pandora is verifying Android calendar provider readback.'
        when 'reminder.local' then 'Pandora is verifying the Android reminder schedule.'
        when 'communication.sms' then 'Pandora is verifying Android SMS native status.'
        when 'communication.call' then 'Pandora is verifying Android call launch status.'
        else 'Pandora is verifying Android device status.'
      end;
    when 'result' then
      v_state := 'result';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar result verified by provider readback.'
        when 'reminder.local' then 'Android local reminder schedule verified on-device.'
        when 'communication.sms' then 'Android SMS result verified from native callback/readback.'
        when 'communication.call' then 'Android call launch result verified from native readback; connection is not claimed.'
        else 'Android device result verified.'
      end;
      v_outcome := jsonb_build_object(
        'summary',v_message,
        'physicalDevice',false
      );
    when 'failed' then
      v_state := 'failed';
      v_message := case v_capability
        when 'calendar.events' then 'Android calendar action failed or could not be verified.'
        when 'reminder.local' then 'Android local reminder action failed or could not be verified.'
        when 'communication.sms' then 'Android SMS action failed or could not be verified.'
        when 'communication.call' then 'Android call launch failed or could not be verified.'
        else 'Android device action failed or could not be verified.'
      end;
    when 'needs_permission' then
      v_state := 'needs_you';
      v_message := 'Android permission is required before Pandora can continue.';
      v_blocker := jsonb_build_object(
        'reasonCode','authorization_required',
        'reason','Android has not granted the required runtime permission.',
        'requiredAction',case v_capability
          when 'calendar.events' then 'Grant Calendar permission to Pandora in Android app permissions.'
          when 'reminder.local' then 'Grant Notifications permission to Pandora in Android app permissions.'
          when 'communication.sms' then 'Grant SMS permission to Pandora in Android app permissions.'
          when 'communication.call' then 'Grant Phone permission to Pandora in Android app permissions.'
          else 'Grant the required Android permission to Pandora.'
        end,
        'approvalRequired',false,
        'policyRef','android-runtime-permission'
      );
    when 'needs_special_access' then
      v_state := 'needs_you';
      v_message := 'Android exact-alarm special access is required for this exact reminder.';
      v_blocker := jsonb_build_object(
        'reasonCode','external_blocker_only_user_can_resolve',
        'reason','Android controls exact-alarm special access outside normal runtime permissions.',
        'requiredAction','Enable Alarms & reminders special access for Pandora in Android settings.',
        'approvalRequired',false,
        'policyRef','android-exact-alarm-special-access'
      );
    when 'needs_choice' then
      v_state := 'needs_you';
      v_message := case v_capability
        when 'communication.sms' then 'Pandora needs one contact or SIM choice before sending the SMS.'
        when 'communication.call' then 'Pandora needs one contact or call-routing choice before placing the call.'
        else 'Pandora needs one calendar choice before making a consequential change.'
      end;
      v_blocker := jsonb_build_object(
        'reasonCode','missing_consequential_user_choice',
        'reason',case when v_capability like 'communication.%' then 'More than one safe communication target or route matches the request.' else 'More than one safe calendar target matches the request.' end,
        'requiredAction',case when v_capability like 'communication.%' then 'Choose the exact contact or system route to use.' else 'Choose the exact calendar or event to change.' end,
        'approvalRequired',false,
        'policyRef',case when v_capability like 'communication.%' then 'r061-communication-target-disambiguation' else 'm4-018-calendar-target-disambiguation' end
      );
  end case;

  v_sequence := v_job.last_sequence + 1;
  v_at_text := to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_admitted_text := to_char(v_admitted at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_ref := 'device://pandora/' || replace(v_capability,'.','-') || '/' || v_operation || '/' || v_stage;

  if v_state='result' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','verification','ref',v_ref),
      jsonb_build_object('type','verification_receipt','relation','verification','ref',v_ref || '/verified')
    );
  elsif v_state='failed' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','failure','ref',v_ref)
    );
  elsif v_state='verifying' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','readback','ref',v_ref)
    );
  else
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','source','ref',v_ref)
    );
  end if;

  v_event := jsonb_build_object(
    'schemaVersion',1,
    'eventId',v_event_id,
    'jobId',p_job_id,
    'sequence',v_sequence,
    'writerEpoch',v_job.writer_epoch,
    'admittedBy',v_job.writer_id,
    'admissionMode','online',
    'state',v_state,
    'message',v_message,
    'occurredAt',v_at_text,
    'admittedAt',v_admitted_text,
    'provenance',jsonb_build_object(
      'sourceType','device',
      'sourceId','pandora-android-device-v1',
      'sourceEventId',v_event_id,
      'observedAt',v_at_text
    ),
    'evidence',v_evidence,
    'domain','device',
    'capability',v_capability,
    'executionId',p_job_id,
    'blocker',v_blocker,
    'outcome',v_outcome
  );

  insert into public.pandora_activity_events(
    job_id,organization_id,sequence,event_id,writer_epoch,state,message,
    event,occurred_at,admitted_at
  ) values (
    p_job_id,p_organization_id,v_sequence,v_event_id,v_job.writer_epoch,
    v_state,v_message,v_event,v_at,v_admitted
  );

  update public.pandora_activity_jobs
  set last_sequence=v_sequence,
      terminal_state=case when v_state in ('result','failed','cancelled') then v_state else null end,
      updated_at=v_admitted
  where id=p_job_id;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'jobId',p_job_id,
    'eventId',v_event_id,'sequence',v_sequence,'state',v_state
  );
end;
$function$;

-- pandora_activity_replay_v1 body SHA-256: 209bdf969f5bc225546c6cc99cda964633d0a819b4c264e44331fc69559a6849
CREATE OR REPLACE FUNCTION public.pandora_activity_replay_v1(p_organization_id uuid, p_job_id uuid, p_after_sequence bigint DEFAULT 0, p_limit integer DEFAULT 250)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_oldest bigint;
  v_events jsonb;
  v_returned_max bigint;
  v_has_more boolean := false;
  v_gap boolean := false;
begin
  if auth.uid() is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;
  if p_after_sequence < 0 or p_limit < 1 or p_limit > 500 then
    raise exception 'pandora_activity_replay_invalid' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;

  select * into v_job from public.pandora_activity_jobs
  where id=p_job_id
    and organization_id=p_organization_id
    and requested_by=auth.uid();
  if not found then
    raise exception 'pandora_activity_job_not_found' using errcode='22023';
  end if;

  select min(e.sequence) into v_oldest
  from public.pandora_activity_events e
  where e.job_id=v_job.id and e.expires_at > now();

  v_gap := p_after_sequence < v_job.last_sequence
    and (v_oldest is null or p_after_sequence + 1 < v_oldest);

  select coalesce(jsonb_agg(e.event order by e.sequence),'[]'::jsonb),
         max(e.sequence)
  into v_events, v_returned_max
  from (
    select sequence, event
    from public.pandora_activity_events
    where job_id=v_job.id
      and sequence > p_after_sequence
      and sequence <= v_job.last_sequence
      and expires_at > now()
    order by sequence
    limit p_limit
  ) e;

  select exists (
    select 1 from public.pandora_activity_events e
    where e.job_id=v_job.id
      and e.sequence > coalesce(v_returned_max,p_after_sequence)
      and e.sequence <= v_job.last_sequence
      and e.expires_at > now()
  ) into v_has_more;
  return jsonb_build_object(
    'jobId',v_job.id,
    'threadId',v_job.thread_id,
    'projectId',v_job.project_id,
    'events',v_events,
    'afterSequence',p_after_sequence,
    'watermarkSequence',v_job.last_sequence,
    'oldestRetainedSequence',v_oldest,
    'historyGapDueToRetention',v_gap,
    'hasMore',v_has_more,
    'terminalState',v_job.terminal_state
  );
end;
$function$;

-- pandora_intelligence_thread_manage_v1 body SHA-256: c46199e37b568fb467061642f546ccd4514ff08e75da014e92c796b46d827993
CREATE OR REPLACE FUNCTION public.pandora_intelligence_thread_manage_v1(p_organization_id uuid, p_thread_id uuid, p_action text, p_title text DEFAULT NULL::text, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_action text := lower(trim(coalesce(p_action,'')));
  v_title text := nullif(trim(coalesce(p_title,'')), '');
  v_thread public.pandora_intelligence_threads%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = v_uid
      and m.status = 'active'
  ) then
    raise exception 'ORG_MEMBERSHIP_REQUIRED' using errcode = '42501';
  end if;

  select * into v_thread
  from public.pandora_intelligence_threads t
  where t.id = p_thread_id
    and t.organization_id = p_organization_id
    and t.created_by = v_uid
  for update;

  if not found then
    raise exception 'THREAD_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_action = 'rename' then
    if v_title is null or length(v_title) > 200 then
      raise exception 'INVALID_THREAD_TITLE' using errcode = '22023';
    end if;
    update public.pandora_intelligence_threads
    set title = v_title, updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'archive' then
    update public.pandora_intelligence_threads
    set status = 'archived', updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'restore' then
    update public.pandora_intelligence_threads
    set status = 'active', updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'associate_project' then
    if p_project_id is not null and not private.pandora_control_plane_project_org_matches(p_organization_id, p_project_id) then
      raise exception 'PROJECT_ORG_MISMATCH' using errcode = '22023';
    end if;
    update public.pandora_intelligence_threads
    set project_id = p_project_id, updated_at = now()
    where id = p_thread_id;
    update public.pandora_intelligence_messages
    set project_id = p_project_id
    where thread_id = p_thread_id
      and organization_id = p_organization_id;
  elsif v_action = 'delete' then
    delete from public.pandora_intelligence_threads where id = p_thread_id;
    return jsonb_build_object(
      'ok', true,
      'threadId', p_thread_id,
      'action', 'delete',
      'deleted', true
    );
  else
    raise exception 'UNSUPPORTED_THREAD_ACTION' using errcode = '22023';
  end if;

  select * into v_thread
  from public.pandora_intelligence_threads t
  where t.id = p_thread_id;

  return jsonb_build_object(
    'ok', true,
    'threadId', v_thread.id,
    'action', v_action,
    'title', v_thread.title,
    'status', v_thread.status,
    'projectId', v_thread.project_id,
    'updatedAt', v_thread.updated_at
  );
end;
$function$;

-- Active shared authorization helper baselines.

-- pandora_is_active_org_admin_v1 body SHA-256: e797e7fc5838100fe92eccee71d5ab007203bcac723c1fdfca92d41fdf52dc89
CREATE OR REPLACE FUNCTION private.pandora_is_active_org_admin_v1(p_organization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select auth.uid() is not null and p_organization_id is not null and exists (
    select 1 from public.memberships m
    join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_organization_id and m.user_id=auth.uid()
      and m.status::text='active' and m.role::text in ('owner','admin')
      and o.status='active'
  );
$function$;

-- pandora_tax_can_manage_org_v1 body SHA-256: a68a0c12fe71c30037d302b07be202ee2c239a1492317dee14601883b58af502
CREATE OR REPLACE FUNCTION public.pandora_tax_can_manage_org_v1(p_organization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select exists(
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
      and lower(m.role::text) in ('owner','admin')
  )
$function$;

-- pandora_tax_can_read_org_v1 body SHA-256: a68a0c12fe71c30037d302b07be202ee2c239a1492317dee14601883b58af502
CREATE OR REPLACE FUNCTION public.pandora_tax_can_read_org_v1(p_organization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select exists(
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
      and lower(m.role::text) in ('owner','admin')
  )
$function$;

-- Active model and evidence transport baselines.

-- pandora_action_evidence_v1 body SHA-256: 446473e10e609df63ce4be11b6988f6734876e8b7e0ad045f11277a7124ee5c8
CREATE OR REPLACE FUNCTION public.pandora_action_evidence_v1(p_organization_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid(); v_role text;
begin
  if v_uid is null then raise exception 'pandora_evidence_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role is null or v_role not in ('owner','admin') then raise exception 'pandora_evidence_owner_required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'projectId',e.project_id,'projectName',p.name,'projectKey',p.project_key,
      'evidenceType',e.evidence_type,'provider',e.provider,'externalId',e.external_id,
      'repository',e.repository,'headSha',e.head_sha,'status',e.status,'verdict',e.verdict,
      'details',e.payload_redacted,'observedAt',e.observed_at
    ) order by e.observed_at desc)
    from (
      select * from public.projectos_evidence
      where organization_id=p_organization_id and evidence_type='projectos_execution_outcome_v2' and invalidated_at is null
      order by observed_at desc limit least(greatest(coalesce(p_limit,100),1),500)
    ) e join public.projectos_projects p on p.id=e.project_id and p.organization_id=e.organization_id
  ),'[]'::jsonb);
end;
$function$;

-- pandora_chat_model_picker_v1 body SHA-256: 6d701a1006c4d60097e216097e8f55980385c71c9c0722679a5c397bddaca3d1
CREATE OR REPLACE FUNCTION public.pandora_chat_model_picker_v1(p_organization_id uuid, p_thread_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_selection jsonb;
  v_models jsonb;
begin
  if v_user_id is null then raise exception 'SIGN_IN_REQUIRED' using errcode='42501'; end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
      and m.role in ('owner','admin')
  ) then raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode='42501'; end if;
  if p_thread_id is not null then
    if not exists (
      select 1 from public.pandora_intelligence_threads t
      where t.id=p_thread_id and t.organization_id=p_organization_id and t.status='active'
    ) then raise exception 'THREAD_NOT_FOUND' using errcode='P0002'; end if;
    select jsonb_build_object(
      'selectionMode',r.selection_mode,
      'requestedProvider',r.requested_provider,
      'requestedModel',r.requested_model,
      'fallbackMode',r.fallback_mode,
      'reasoningMode',r.reasoning_mode
    ) into v_selection
    from private.pandora_intelligence_thread_routing_state r
    where r.thread_id=p_thread_id and r.organization_id=p_organization_id;
  end if;
  v_selection:=coalesce(v_selection,jsonb_build_object(
    'selectionMode','auto','requestedProvider',null,'requestedModel',null,
    'fallbackMode','allow_fallback','reasoningMode','auto'
  ));

  select coalesce(jsonb_agg(jsonb_build_object(
    'routingProvider','bedrock',
    'providerName',c.provider_name,
    'modelId',c.model_id,
    'modelName',c.model_name,
    'selectable',c.routable=true and c.conversational=true
      and c.present_in_latest_sync=true
      and c.runtime_verification_status='passed'
      and c.lifecycle_status='ACTIVE',
    'availability',case
      when c.routable=true and c.conversational=true
        and c.present_in_latest_sync=true
        and c.runtime_verification_status='passed'
        and c.lifecycle_status='ACTIVE' then 'available'
      when c.runtime_verification_status='failed' and (
        lower(coalesce(c.runtime_reason,'')) like '%signature we calculated does not match%'
        or lower(coalesce(c.runtime_reason,'')) like '%doesn''t support the temperature field%'
      ) then 'unverified'
      else 'unavailable'
    end,
    'unavailableReason',case
      when c.routable=true and c.runtime_verification_status='passed'
        and c.lifecycle_status='ACTIVE' then null
      when c.agreement_status<>'AVAILABLE' then 'Payment or provider agreement required'
      when c.authorization_status<>'AUTHORIZED' then 'Access denied'
      when c.entitlement_status<>'AVAILABLE' then 'Not entitled'
      when c.region_availability<>'AVAILABLE' then 'Unavailable in this region'
      when c.runtime_verification_status='failed' and (
        lower(coalesce(c.runtime_reason,'')) like '%signature we calculated does not match%'
        or lower(coalesce(c.runtime_reason,'')) like '%doesn''t support the temperature field%'
      ) then 'Unverified — Pandora runtime re-probe required'
      when c.runtime_verification_status='failed' and c.probe_http_status=403 then 'Access denied'
      when c.runtime_verification_status='failed' then 'Runtime verification failed'
      else 'Unavailable'
    end,
    'lastVerifiedAt',c.last_verified_at
  ) order by case when c.routable then 0 else 1 end,c.provider_name,c.model_name,c.model_id),'[]'::jsonb)
  into v_models
  from private.pandora_bedrock_reasoning_catalog c
  where c.conversational=true
    and c.present_in_latest_sync=true
    and c.lifecycle_status<>'REMOVED';

  return jsonb_build_object(
    'contractVersion','pandora-chat-model-picker-v1',
    'selection',v_selection,
    'models',v_models
  );
end;
$function$;

-- pandora_intelligence_model_catalog_v1 body SHA-256: 31039422ad9e587237f212563d82c4e9b4f0aa06be011900d5bd8105fb735b10
CREATE OR REPLACE FUNCTION public.pandora_intelligence_model_catalog_v1(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_models jsonb;
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = v_user_id
      and m.status = 'active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED';
  end if;

  with configs as (
    select
      provider,
      max(config_value) filter (where config_key='enabled') as enabled,
      max(config_value) filter (where config_key='routing_eligible') as routing_eligible,
      max(config_value) filter (where config_key='default_model') as default_model,
      max(config_value) filter (where config_key='allowed_models') as allowed_models
    from public.pandora_runtime_provider_configs
    where active = true
      and provider in ('gemini','openai','kimi','local')
    group by provider
  ),
  expanded as (
    select
      c.provider,
      model.value as model,
      c.default_model,
      case c.provider
        when 'gemini' then 10
        when 'openai' then 20
        when 'kimi' then 30
        when 'local' then 40
        else 90
      end as provider_order
    from configs c
    cross join lateral jsonb_array_elements_text(
      case
        when c.allowed_models is null or c.allowed_models = '' then jsonb_build_array(c.default_model)
        else c.allowed_models::jsonb
      end
    ) as model(value)
    where c.enabled = 'true'
      and c.routing_eligible = 'true'
      and model.value is not null
  ),
  decorated as (
    select
      e.provider,
      e.model,
      e.provider_order,
      e.model = e.default_model as is_default,
      case e.model
        when 'gemini-3.5-flash-lite' then 'Gemini 3.5 Flash Lite'
        when 'gemini-3.7-flash' then 'Gemini 3.7 Flash'
        when 'gemini-3.1-pro-preview' then 'Gemini 3.1 Pro Preview'
        when 'gpt-5.6-terra' then 'GPT-5.6 Terra'
        when 'gpt-5.6-luna' then 'GPT-5.6 Luna'
        when 'gpt-5.6-sol' then 'GPT-5.6 Sol'
        when 'kimi-k3' then 'Kimi K3'
        when 'Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M' then 'Qwen2.5 7B Local'
        else e.model
      end as label,
      case
        when e.provider <> 'local' then true
        else exists (
          select 1
          from public.pandora_local_ai_workers w
          where w.model = e.model
            and w.last_seen_at > now() - interval '45 seconds'
            and w.status in ('ready','busy')
        )
      end as available,
      case
        when e.provider <> 'local' then 'ready'
        else coalesce((
          select w.status
          from public.pandora_local_ai_workers w
          where w.model = e.model
          order by w.last_seen_at desc
          limit 1
        ), 'offline')
      end as state
    from expanded e
  ),
  all_models as (
    select
      0 as provider_order,
      0 as model_order,
      jsonb_build_object(
        'provider','auto',
        'model','auto',
        'label','Auto',
        'available',true,
        'state','ready',
        'local',false,
        'default',true
      ) as item
    union all
    select
      d.provider_order,
      row_number() over (partition by d.provider order by d.model)::integer as model_order,
      jsonb_build_object(
        'provider',d.provider,
        'model',d.model,
        'label',d.label,
        'available',d.available,
        'state',d.state,
        'local',d.provider='local',
        'default',d.is_default
      )
    from decorated d
  )
  select coalesce(jsonb_agg(item order by provider_order, model_order), '[]'::jsonb)
  into v_models
  from all_models;

  return jsonb_build_object(
    'models', v_models,
    'observedAt', now()
  );
end;
$function$;

-- pandora_plugin_runtime_registry_v3 body SHA-256: a99c398dc3091aebfd799e00971011ee74d14b4049801236aa9838c22d285022
CREATE OR REPLACE FUNCTION public.pandora_plugin_runtime_registry_v3(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'auth', 'extensions', 'pg_temp'
AS $function$
declare
  v_base jsonb;
  v_rows jsonb;
begin
  v_base := public.pandora_chat_capability_registry_v2(p_organization_id);

  select coalesce(
    jsonb_agg(
      p.item || jsonb_build_object(
        'account', jsonb_build_object(
          'label', null,
          'verified', false,
          'reason', 'Provider account identity is not exposed by current verified runtime evidence.'
        ),
        'scopes', '[]'::jsonb,
        'scopesVerified', false,
        'actions', coalesce(p.item->'capabilities', '[]'::jsonb),
        'health', jsonb_build_object(
          'state', coalesce(p.item->>'state', 'Unavailable'),
          'rawStatus', coalesce(p.item->>'status', 'unknown'),
          'canUseNow', coalesce((p.item->>'canUseNow')::boolean, false),
          'lastVerifiedAt', p.item->'lastVerifiedAt'
        ),
        'failure', case
          when coalesce(p.item->>'state','Unavailable') = 'Connected' then null
          when coalesce(p.item->>'state','Unavailable') = 'Needs authorization' then
            jsonb_build_object(
              'code','authorization_required',
              'message',coalesce(p.item->>'authorization','Provider authorization is required.')
            )
          when coalesce(p.item->>'state','Unavailable') = 'Problem' then
            jsonb_build_object(
              'code','runtime_problem',
              'message',format(
                '%s runtime evidence is not currently healthy (%s).',
                coalesce(p.item->>'label', initcap(replace(coalesce(p.item->>'provider','provider'),'_',' '))),
                coalesce(p.item->>'status','unknown')
              )
            )
          else
            jsonb_build_object(
              'code','unavailable',
              'message',coalesce(p.item->>'authorization','This provider is not currently available to Pandora.')
            )
        end,
        'readAvailable', exists(
          select 1
          from jsonb_array_elements(coalesce(p.item->'capabilities','[]'::jsonb)) c
          where c->>'mode' = 'read' and coalesce((c->>'available')::boolean,false)
        ),
        'writeAvailable', exists(
          select 1
          from jsonb_array_elements(coalesce(p.item->'capabilities','[]'::jsonb)) c
          where c->>'mode' = 'write' and coalesce((c->>'available')::boolean,false)
        )
      )
      order by p.ord
    ),
    '[]'::jsonb
  )
  into v_rows
  from jsonb_array_elements(coalesce(v_base->'providers','[]'::jsonb))
       with ordinality p(item, ord);

  return jsonb_build_object(
    'contractVersion','pandora-plugin-runtime-registry-v3',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'projectRequired',false,
    'providers',v_rows
  );
end;
$function$;

-- Active provider-write approval baseline.
-- body SHA-256: adea670bc841410d6d12ee5a8271fb83f5774f82e8c2c177b3160d661c39910a
CREATE OR REPLACE FUNCTION public.pandora_connection_write_approve_v1(p_organization_id uuid, p_approval_id uuid, p_provider_key text, p_connection_id uuid, p_tenant_key text, p_confirmation_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
AS $function$
declare v_uid uuid:=auth.uid(); v_row private.pandora_connection_write_approvals_v1%rowtype;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then
    raise exception 'pandora_connection_write_step_up_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='approved',approved_by=v_uid,approved_at=clock_timestamp()
  where id=p_approval_id and organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key) and status='pending'
    and expires_at>clock_timestamp() and target_hash=p_confirmation_hash
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_write_approval_invalid_or_expired' using errcode='42501'; end if;
  perform private.append_audit_event(p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,
    'connection.write_approved',jsonb_build_object('provider',v_row.provider_key,'approval_id',v_row.id,'connection_id',v_row.connection_id,'tenant_key',v_row.tenant_key,'operation',v_row.operation,'target_hash',v_row.target_hash,'aal','aal2'));
  return jsonb_build_object('ok',true,'approvalId',v_row.id,'provider',v_row.provider_key,'connectionId',v_row.connection_id,
    'tenantId',v_row.organization_id,'tenantKey',v_row.tenant_key,'operation',v_row.operation,'targetHash',v_row.target_hash,'status','approved','expiresAt',v_row.expires_at);
end; $function$;
