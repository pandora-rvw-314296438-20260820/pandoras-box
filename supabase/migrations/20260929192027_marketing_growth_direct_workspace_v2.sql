
-- FB-031/FB-035/FB-037/FB-039: direct Marketing & Growth operational projection.
-- This path intentionally does not depend on Operations Room task/event state.
-- It remains read-only for authenticated clients and grants no campaign mutation,
-- publishing, activation, budget, or spend authority.
begin;

create table if not exists private.pandora_growth_lead_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  tracking_tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  outcome_receipt_id uuid not null references public.pandora_growth_outcome_receipts(id) on delete restrict,
  stage text not null check(stage in ('new','qualified','lost','paid','refunded')),
  evidence_ref text not null check(char_length(btrim(evidence_ref)) between 3 and 1000),
  reviewed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,outcome_receipt_id)
);
alter table private.pandora_growth_lead_reviews enable row level security;
revoke all on private.pandora_growth_lead_reviews from public,anon,authenticated,service_role;

create table if not exists private.pandora_growth_memory_retrieval_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  namespace text not null check(namespace='real_life'),
  memory_record_id text not null check(memory_record_id ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'),
  memory_version_id text not null check(memory_version_id ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'),
  review_item_id text not null check(review_item_id ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'),
  query_sha256 text not null check(query_sha256 ~ '^[0-9a-f]{64}$'),
  record_sha256 text not null check(record_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_ref text not null check(char_length(btrim(evidence_ref)) between 3 and 1000),
  status text not null check(status='approved_current'),
  observed_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(organization_id,project_id,memory_record_id,memory_version_id,query_sha256)
);
alter table private.pandora_growth_memory_retrieval_receipts enable row level security;
revoke all on private.pandora_growth_memory_retrieval_receipts from public,anon,authenticated,service_role;

create or replace function public.pandora_growth_set_lead_stage_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_outcome_receipt_id uuid,
  p_stage text,
  p_evidence_ref text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_receipt public.pandora_growth_outcome_receipts%rowtype;
  v_id uuid;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role' then
    raise exception 'PANDORA_GROWTH_LEAD_REVIEW_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_stage not in ('new','qualified','lost','paid','refunded')
     or char_length(coalesce(btrim(p_evidence_ref),'')) not between 3 and 1000 then
    raise exception 'PANDORA_GROWTH_LEAD_REVIEW_INVALID' using errcode='22023';
  end if;

  select * into v_receipt
  from public.pandora_growth_outcome_receipts r
  where r.id=p_outcome_receipt_id
    and r.organization_id=p_organization_id
    and r.project_id=p_project_id
    and r.is_test is false
  for share;
  if not found then
    raise exception 'PANDORA_GROWTH_LEAD_REVIEW_SCOPE_DENIED' using errcode='42501';
  end if;

  insert into private.pandora_growth_lead_reviews(
    organization_id,project_id,tracking_tenant_id,outcome_receipt_id,
    stage,evidence_ref,reviewed_at,updated_at
  ) values (
    p_organization_id,p_project_id,v_receipt.tracking_tenant_id,p_outcome_receipt_id,
    p_stage,btrim(p_evidence_ref),clock_timestamp(),clock_timestamp()
  )
  on conflict(organization_id,project_id,outcome_receipt_id) do update
  set stage=excluded.stage,
      evidence_ref=excluded.evidence_ref,
      reviewed_at=excluded.reviewed_at,
      updated_at=excluded.updated_at
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'reviewId',v_id,
    'outcomeReceiptId',p_outcome_receipt_id,
    'stage',p_stage,
    'testTraffic',false,
    'spendAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_growth_set_lead_stage_v1(uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_growth_set_lead_stage_v1(uuid,uuid,uuid,text,text)
  to service_role;

create or replace function public.pandora_growth_record_memory_retrieval_receipt_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_memory_record_id text,
  p_memory_version_id text,
  p_review_item_id text,
  p_query_sha256 text,
  p_record_sha256 text,
  p_evidence_ref text,
  p_observed_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private'
as $function$
declare
  v_id uuid;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role' then
    raise exception 'PANDORA_GROWTH_MEMORY_RECEIPT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_organization_id is null or p_project_id is null
     or coalesce(p_memory_record_id,'') !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'
     or coalesce(p_memory_version_id,'') !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'
     or coalesce(p_review_item_id,'') !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,255}$'
     or coalesce(p_query_sha256,'') !~ '^[0-9a-f]{64}$'
     or coalesce(p_record_sha256,'') !~ '^[0-9a-f]{64}$'
     or char_length(coalesce(btrim(p_evidence_ref),'')) not between 3 and 1000
     or p_observed_at is null
     or p_observed_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'PANDORA_GROWTH_MEMORY_RECEIPT_INVALID' using errcode='22023';
  end if;

  insert into private.pandora_growth_memory_retrieval_receipts(
    organization_id,project_id,namespace,memory_record_id,memory_version_id,
    review_item_id,query_sha256,record_sha256,evidence_ref,status,observed_at
  ) values (
    p_organization_id,p_project_id,'real_life',btrim(p_memory_record_id),
    btrim(p_memory_version_id),btrim(p_review_item_id),p_query_sha256,p_record_sha256,
    btrim(p_evidence_ref),'approved_current',p_observed_at
  )
  on conflict(organization_id,project_id,memory_record_id,memory_version_id,query_sha256)
  do update set
    review_item_id=excluded.review_item_id,
    record_sha256=excluded.record_sha256,
    evidence_ref=excluded.evidence_ref,
    observed_at=excluded.observed_at
  returning id into v_id;

  return jsonb_build_object(
    'ok',true,
    'receiptId',v_id,
    'status','approved_current',
    'canonicalMemoryWritten',false,
    'spendAuthorized',false
  );
end;
$function$;
revoke all on function public.pandora_growth_record_memory_retrieval_receipt_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_growth_record_memory_retrieval_receipt_v1(
  uuid,uuid,text,text,text,text,text,text,timestamptz
) to service_role;

create or replace function public.pandora_marketing_growth_command_center_v2(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_tenant public.pandora_tracking_tenants%rowtype;
  v_project_id uuid;
  v_role text;
begin
  if v_user_id is null then
    raise exception 'PANDORA_GROWTH_SIGN_IN_REQUIRED' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_user_id
    and m.status='active'
  limit 1;
  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'PANDORA_GROWTH_OWNER_ADMIN_REQUIRED' using errcode='42501';
  end if;

  select t.* into v_tenant
  from public.pandora_tracking_tenants t
  where t.organization_id=p_organization_id
    and t.workspace_key='pandora-platform'
    and t.status='active'
  order by t.created_at
  limit 1;
  if not found or v_tenant.project_id is null then
    raise exception 'PANDORA_GROWTH_TENANT_UNAVAILABLE' using errcode='P0002';
  end if;
  v_project_id:=v_tenant.project_id;

  return jsonb_build_object(
    'schemaVersion','pandora-marketing-growth-command-center-v2',
    'sourceMode','direct_github',
    'generatedAt',clock_timestamp(),
    'tenant',jsonb_build_object(
      'id',v_tenant.id,
      'workspaceKey',v_tenant.workspace_key,
      'displayName',v_tenant.display_name,
      'projectId',v_project_id,
      'status',v_tenant.status
    ),
    'campaigns',coalesce((
      select jsonb_agg(jsonb_build_object(
        'trackingCampaignId',c.id,
        'slug',c.slug,
        'name',c.name,
        'provider',c.provider,
        'providerCampaignId',c.provider_campaign_id,
        'providerAdsetId',c.provider_adset_id,
        'providerAdId',c.provider_ad_id,
        'status',c.status,
        'purpose',c.metadata->>'purpose',
        'businessKpi',case when c.metadata ? 'business_kpi'
          then c.metadata->'business_kpi' else 'true'::jsonb end,
        'bindingId',b.id,
        'bindingState',b.binding_state,
        'adAccountId',b.ad_account_id,
        'pixelId',b.pixel_id,
        'currency',b.account_currency,
        'timezone',b.account_timezone,
        'verifiedAt',b.verified_at,
        'lastCostSyncAt',b.last_cost_sync_at
      ) order by c.created_at)
      from public.pandora_tracking_campaigns c
      left join private.pandora_meta_measurement_bindings b
        on b.organization_id=p_organization_id
       and b.project_id=v_project_id
       and b.tracking_campaign_id=c.id
      where c.tenant_id=v_tenant.id
    ),'[]'::jsonb),
    'businessDaily',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.day desc)
      from (
        select day,campaign_id,slug,campaign_name,provider,provider_campaign_id,
               clicks,impressions,provider_clicks,leads,qualified_leads,bookings,
               sales,refunds,spend,net_revenue,cac,roas
        from public.pandora_tracking_campaign_daily_v1 d
        where d.tenant_id=v_tenant.id
        order by day desc
        limit 90
      ) x
    ),'[]'::jsonb),
    'outcomes',coalesce((
      select jsonb_agg(jsonb_build_object(
        'eventName',x.event_name,
        'count',x.count,
        'latestOccurredAt',x.latest_occurred_at,
        'currency',x.currency,
        'knownAmountMinor',x.known_amount_minor
      ) order by x.event_name)
      from (
        select r.event_name,count(*)::bigint as count,max(r.occurred_at) latest_occurred_at,
               case when count(distinct r.currency) filter(where r.currency is not null)=1
                 then max(r.currency) else null end currency,
               case when count(*) filter(where r.amount_minor is not null)=count(*)
                 then sum(r.amount_minor) else null end known_amount_minor
        from public.pandora_growth_outcome_receipts r
        where r.organization_id=p_organization_id
          and r.project_id=v_project_id
          and r.tracking_tenant_id=v_tenant.id
          and r.is_test is false
        group by r.event_name
      ) x
    ),'[]'::jsonb),
    'leadStages',coalesce((
      select jsonb_agg(jsonb_build_object(
        'reviewId',lr.id,
        'outcomeReceiptId',lr.outcome_receipt_id,
        'eventName',r.event_name,
        'stage',lr.stage,
        'occurredAt',r.occurred_at,
        'currency',r.currency,
        'amountKnown',r.amount_minor is not null,
        'evidenceRef',lr.evidence_ref,
        'reviewedAt',lr.reviewed_at
      ) order by lr.reviewed_at desc)
      from private.pandora_growth_lead_reviews lr
      join public.pandora_growth_outcome_receipts r on r.id=lr.outcome_receipt_id
      where lr.organization_id=p_organization_id
        and lr.project_id=v_project_id
        and lr.tracking_tenant_id=v_tenant.id
        and r.is_test is false
    ),'[]'::jsonb),
    'experimentRuns',coalesce((
      select jsonb_agg(jsonb_build_object(
        'runId',r.id,
        'experimentKey',r.experiment_key,
        'hypothesis',r.hypothesis,
        'intendedBusinessOutcome',r.intended_business_outcome,
        'status',r.status,
        'windowStart',r.window_start,
        'windowEnd',r.window_end,
        'attributionMethod',r.attribution_method,
        'denominator',r.denominator_count,
        'conversions',r.conversion_count,
        'spend',r.spend,
        'currency',r.spend_currency,
        'spendState',r.spend_state,
        'conversionDelaySeconds',r.conversion_delay_seconds,
        'conversionDelayState',r.conversion_delay_state,
        'comparisonConditions',r.comparison_conditions,
        'uncertainty',r.uncertainty,
        'result',r.result,
        'resultSha256',r.result_sha256,
        'completedAt',r.completed_at
      ) order by r.completed_at desc)
      from private.pandora_growth_experiment_runs r
      where r.organization_id=p_organization_id and r.project_id=v_project_id
      limit 100
    ),'[]'::jsonb),
    'approvedMemory',coalesce((
      select jsonb_agg(jsonb_build_object(
        'receiptId',m.id,
        'namespace',m.namespace,
        'memoryRecordId',m.memory_record_id,
        'memoryVersionId',m.memory_version_id,
        'reviewItemId',m.review_item_id,
        'querySha256',m.query_sha256,
        'recordSha256',m.record_sha256,
        'evidenceRef',m.evidence_ref,
        'status',m.status,
        'observedAt',m.observed_at
      ) order by m.observed_at desc)
      from private.pandora_growth_memory_retrieval_receipts m
      where m.organization_id=p_organization_id
        and m.project_id=v_project_id
        and m.status='approved_current'
    ),'[]'::jsonb),
    'testAcceptance',jsonb_build_object(
      'clicks',(select count(*) from public.pandora_tracking_clicks c
                where c.tenant_id=v_tenant.id and c.is_test is true),
      'events',(select count(*) from public.pandora_tracking_events e
                where e.tenant_id=v_tenant.id and e.is_test is true),
      'outcomes',(select count(*) from public.pandora_growth_outcome_receipts r
                  where r.organization_id=p_organization_id and r.project_id=v_project_id
                    and r.tracking_tenant_id=v_tenant.id and r.is_test is true),
      'includedInBusinessKpis',false
    ),
    'privacy',coalesce((
      select jsonb_agg(jsonb_build_object(
        'policyVersion',a.policy_version,
        'allowedFlows',a.allowed_flows,
        'evidenceRef',a.evidence_ref,
        'approvedAt',a.approved_at,
        'expiresAt',a.expires_at,
        'active',a.active
      ) order by a.approved_at desc)
      from public.pandora_growth_privacy_authorizations a
      where a.organization_id=p_organization_id and a.project_id=v_project_id
    ),'[]'::jsonb),
    'approvalGates',jsonb_build_array(
      jsonb_build_object(
        'taskId','FB-046',
        'kind','owner_pilot_spend_authorization',
        'state','not_granted',
        'evidenceRef',null
      ),
      jsonb_build_object(
        'taskId','FB-059',
        'kind','client_pilot_authorization',
        'state','not_granted',
        'evidenceRef',null
      )
    ),
    'activity',coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject',x.subject,
        'eventType',x.event_type,
        'occurredAt',x.occurred_at
      ) order by x.occurred_at desc)
      from (
        select r.experiment_key as subject,
               'experiment.'||r.status as event_type,
               r.completed_at as occurred_at
        from private.pandora_growth_experiment_runs r
        where r.organization_id=p_organization_id and r.project_id=v_project_id
        union all
        select lr.outcome_receipt_id::text,
               'lead.'||lr.stage,
               lr.reviewed_at
        from private.pandora_growth_lead_reviews lr
        where lr.organization_id=p_organization_id and lr.project_id=v_project_id
        union all
        select m.memory_record_id,
               'memory.approved_retrieval',
               m.observed_at
        from private.pandora_growth_memory_retrieval_receipts m
        where m.organization_id=p_organization_id and m.project_id=v_project_id
      ) x
      limit 80
    ),'[]'::jsonb),
    'authority',jsonb_build_object(
      'readOnly',true,
      'ownerAdminOnly',true,
      'staffAccess',false,
      'campaignMutationGranted',false,
      'spendAuthorized',false,
      'publishingAuthorized',false,
      'exportsAllowed',false,
      'rawPiiVisible',false,
      'memoryCanGrantSpend',false,
      'operationsRoomRequired',false,
      'directGithubSource',true,
      'testTrafficIncludedInBusinessKpis',false
    )
  );
end;
$function$;

revoke all on function public.pandora_marketing_growth_command_center_v2(uuid)
  from public,anon;
grant execute on function public.pandora_marketing_growth_command_center_v2(uuid)
  to authenticated;

comment on function public.pandora_marketing_growth_command_center_v2(uuid) is
  'Direct-GitHub Marketing & Growth owner/admin projection. No Operations Room dependency; read-only client surface, no raw PII, exports, provider mutation, publishing or spend authority.';

commit;

