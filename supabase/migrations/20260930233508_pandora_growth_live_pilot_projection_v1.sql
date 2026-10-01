
begin;

create or replace function private.pandora_growth_meta_connection_projection_v1(
  p_organization_id uuid
) returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
  select coalesce((
    select jsonb_build_object(
      'connected',c.status='connected',
      'status',c.status,
      'displayName',c.display_name,
      'providerUserId',c.provider_user_id,
      'scopes',c.scopes,
      'adAccounts',c.ad_accounts,
      'tokenExpiresAt',c.token_expires_at,
      'lastVerifiedAt',c.last_verified_at,
      'lastHttpStatus',c.last_http_status,
      'lastError',c.last_error
    )
    from private.pandora_meta_connections c
    where c.organization_id=p_organization_id
    order by c.updated_at desc
    limit 1
  ),jsonb_build_object('connected',false,'status','not_connected'));
$function$;

revoke all on function private.pandora_growth_meta_connection_projection_v1(uuid)
from public,anon,authenticated,service_role;

create or replace function private.pandora_growth_paid_pilot_projection_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  a private.pandora_meta_paid_pilot_authorizations%rowtype;
  r private.pandora_meta_paid_pilot_receipts%rowtype;
  v_delivery jsonb:='{}'::jsonb;
  v_impressions bigint;
  v_clicks bigint;
  v_spend_minor bigint;
  v_monitor_healthy boolean:=false;
begin
  select * into a
  from private.pandora_meta_paid_pilot_authorizations
  where organization_id=p_organization_id
    and project_id=p_project_id
  order by updated_at desc,created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'exists',false,
      'state','none',
      'authorizationGranted',false,
      'spendAuthorized',false,
      'deliveryAuthorized',false,
      'monitorHealthy',false
    );
  end if;

  select * into r
  from private.pandora_meta_paid_pilot_receipts
  where authorization_id=a.id
    and action='monitor'
  order by created_at desc
  limit 1;

  if found then
    v_spend_minor:=r.spend_minor_observed;
    v_monitor_healthy:=
      r.state='confirmed'
      and r.error_code is null
      and r.created_at >= clock_timestamp()-interval '10 minutes';

    if jsonb_typeof(r.after_state#>'{spend,body,data}')='array'
       and jsonb_array_length(r.after_state#>'{spend,body,data}')>0 then
      begin
        v_impressions:=nullif(r.after_state#>>'{spend,body,data,0,impressions}','')::bigint;
      exception when others then v_impressions:=null; end;
      begin
        v_clicks:=nullif(r.after_state#>>'{spend,body,data,0,clicks}','')::bigint;
      exception when others then v_clicks:=null; end;
      v_delivery:=r.after_state#>'{spend,body,data,0}';
    end if;
  end if;

  return jsonb_build_object(
    'exists',true,
    'authorizationId',a.id,
    'state',a.state,
    'authorizationGranted',a.state in ('approved','prepared','active','stopped','completed'),
    'spendAuthorized',a.state in ('approved','prepared','active'),
    'deliveryAuthorized',a.state='active',
    'currency',a.currency,
    'maxSpendMinor',a.max_spend_minor,
    'dailyBudgetMinor',a.daily_budget_minor,
    'spendMinor',v_spend_minor,
    'remainingSpendMinor',case
      when v_spend_minor is null then null
      else greatest(a.max_spend_minor-v_spend_minor,0)
    end,
    'durationSeconds',a.duration_seconds,
    'authorizedAt',a.authorized_at,
    'preparedAt',a.prepared_at,
    'activatedAt',a.activated_at,
    'endAt',a.end_at,
    'stoppedAt',a.stopped_at,
    'adAccountId',a.ad_account_id,
    'campaignId',a.meta_campaign_id,
    'adsetId',a.meta_adset_id,
    'adId',a.meta_ad_id,
    'stopConditions',a.stop_conditions,
    'approvedBy',a.approved_by,
    'evidenceRef',a.evidence_ref,
    'lastMonitorReceiptId',r.id,
    'lastMonitorAt',r.created_at,
    'lastMonitorState',r.state,
    'lastMonitorError',r.error_code,
    'monitorHealthy',v_monitor_healthy,
    'deliveryObserved',coalesce(v_impressions,0)>0 or coalesce(v_clicks,0)>0 or coalesce(v_spend_minor,0)>0,
    'impressions',v_impressions,
    'clicks',v_clicks,
    'delivery',v_delivery
  );
end;
$function$;

revoke all on function private.pandora_growth_paid_pilot_projection_v1(uuid,uuid)
from public,anon,authenticated,service_role;

do $patch$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.pandora_marketing_growth_command_center_v2(uuid)'::regprocedure)
  into v_def;

  if position($$'approvalGates',jsonb_build_array($$ in v_def)=0
     or position($$'spendAuthorized',false$$ in v_def)=0 then
    raise exception 'PANDORA_GROWTH_COMMAND_CENTER_PATCH_BASE_MISMATCH';
  end if;

  v_old := $$'approvalGates',jsonb_build_array(
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
    ),$$;

  v_new := $$'metaConnection',
      private.pandora_growth_meta_connection_projection_v1(p_organization_id),
    'paidPilot',
      private.pandora_growth_paid_pilot_projection_v1(p_organization_id,v_project_id),
    'approvalGates',jsonb_build_array(
      jsonb_build_object(
        'taskId','FB-046',
        'kind','owner_pilot_spend_authorization',
        'state',case
          when coalesce((private.pandora_growth_paid_pilot_projection_v1(
            p_organization_id,v_project_id
          )->>'authorizationGranted')::boolean,false)
          then 'granted' else 'not_granted' end,
        'evidenceRef',private.pandora_growth_paid_pilot_projection_v1(
          p_organization_id,v_project_id
        )->>'evidenceRef'
      ),
      jsonb_build_object(
        'taskId','FB-059',
        'kind','client_pilot_authorization',
        'state','not_granted',
        'evidenceRef',null
      )
    ),$$;

  if position(v_old in v_def)=0 then
    raise exception 'PANDORA_GROWTH_COMMAND_CENTER_APPROVAL_BLOCK_MISMATCH';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  v_def:=replace(
    v_def,
    $$'spendAuthorized',false,$$,
    $$'spendAuthorized',coalesce((
        private.pandora_growth_paid_pilot_projection_v1(
          p_organization_id,v_project_id
        )->>'spendAuthorized'
      )::boolean,false),
      'boundedCampaignMutationGranted',coalesce((
        private.pandora_growth_paid_pilot_projection_v1(
          p_organization_id,v_project_id
        )->>'deliveryAuthorized'
      )::boolean,false),
      'metaConnected',coalesce((
        private.pandora_growth_meta_connection_projection_v1(
          p_organization_id
        )->>'connected'
      )::boolean,false),$$
  );

  execute v_def;
end
$patch$;

do $assert$
declare
  v_def text;
begin
  select pg_get_functiondef('public.pandora_marketing_growth_command_center_v2(uuid)'::regprocedure)
  into v_def;
  if position('private.pandora_growth_paid_pilot_projection_v1' in v_def)=0
     or position('private.pandora_growth_meta_connection_projection_v1' in v_def)=0
     or position($$'state','not_granted'$$ in v_def)=0 then
    raise exception 'PANDORA_GROWTH_COMMAND_CENTER_PATCH_ASSERTION_FAILED';
  end if;
end
$assert$;

commit;
;
