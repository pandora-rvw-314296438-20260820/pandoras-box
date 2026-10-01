-- Marketing & Growth owner command center.
-- Read-only tenant projection: no provider mutation, spend, export, secret or raw PII.
begin;

create or replace function public.pandora_marketing_growth_command_center_v1(
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
begin
  if v_user_id is null then
    raise exception 'PANDORA_GROWTH_SIGN_IN_REQUIRED' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
      and m.role in ('owner','admin')
  ) then
    raise exception 'PANDORA_GROWTH_OWNER_ROLE_REQUIRED' using errcode='42501';
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
    'schemaVersion','pandora-marketing-growth-command-center-v1',
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
    'approvalGates',coalesce((
      select jsonb_agg(jsonb_build_object(
        'taskId',g.task_key,
        'kind',g.gate_kind,
        'state',g.state,
        'evidenceRef',g.evidence_ref,
        'decidedAt',g.decided_at
      ) order by g.task_key)
      from private.pandora_ops_human_gates g
      where g.organization_id=p_organization_id and g.project_id=v_project_id
        and g.task_key in ('FB-046','FB-059')
    ),'[]'::jsonb),
    'tasks',coalesce((
      select jsonb_agg(jsonb_build_object(
        'taskId',t.task_key,
        'title',t.spec->>'title',
        'status',t.status,
        'lane',t.spec->>'lane',
        'risk',t.spec->>'risk',
        'headSha',t.head_sha,
        'generation',t.generation
      ) order by t.task_key)
      from private.pandora_ops_tasks t
      where t.organization_id=p_organization_id and t.project_id=v_project_id
        and t.task_key between 'FB-018' and 'FB-064'
    ),'[]'::jsonb),
    'activity',coalesce((
      select jsonb_agg(jsonb_build_object(
        'taskId',x.task_key,
        'eventType',x.event_type,
        'occurredAt',x.occurred_at
      ) order by x.occurred_at desc)
      from (
        select e.task_key,e.event_type,e.occurred_at
        from private.pandora_ops_events e
        where e.organization_id=p_organization_id and e.project_id=v_project_id
          and e.task_key like 'FB-%'
        order by e.occurred_at desc
        limit 80
      ) x
    ),'[]'::jsonb),
    'authority',jsonb_build_object(
      'readOnly',true,
      'campaignMutationGranted',false,
      'spendAuthorized',false,
      'publishingAuthorized',false,
      'exportsContainSecrets',false,
      'testTrafficIncludedInBusinessKpis',false
    )
  );
end;
$function$;

revoke all on function public.pandora_marketing_growth_command_center_v1(uuid)
  from public,anon;
grant execute on function public.pandora_marketing_growth_command_center_v1(uuid)
  to authenticated;

comment on function public.pandora_marketing_growth_command_center_v1(uuid) is
  'Authenticated owner/admin read-only Marketing & Growth command-center projection. Tenant scoped; no provider mutation, spend authority, secret export or raw customer PII.';

commit;
