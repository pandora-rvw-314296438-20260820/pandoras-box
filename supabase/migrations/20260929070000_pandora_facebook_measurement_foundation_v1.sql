-- FB-018..FB-024: provider-bound Facebook measurement foundation.
-- Source may be deployed before privacy or campaign authorization because all
-- customer/provider delivery paths fail closed without explicit rows/verified IDs.

create table if not exists public.pandora_growth_privacy_authorizations (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null,
  policy_version text not null check (policy_version ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  allowed_flows text[] not null default '{}',
  approved_by uuid not null,
  evidence_ref text not null check (length(evidence_ref) between 1 and 500),
  approved_at timestamptz not null,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,policy_version),
  check (expires_at is null or expires_at>approved_at),
  check (allowed_flows <@ array[
    'redirect_measurement','browser_analytics','server_outcomes',
    'provider_matching','durable_learning'
  ]::text[])
);

create table if not exists public.pandora_growth_outcome_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tracking_tenant_id uuid not null references public.pandora_tracking_tenants(id) on delete cascade,
  project_id uuid,
  event_name text not null check (event_name ~ '^[a-z][a-z0-9_]{2,63}$'),
  event_id text not null check (event_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  outcome_id text not null check (outcome_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  acquisition_path text not null check (acquisition_path in ('self_serve','enterprise')),
  journey_id text not null check (journey_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  subject_id text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default clock_timestamp(),
  delivery_source text not null check (delivery_source='server'),
  evidence jsonb not null check (jsonb_typeof(evidence)='object'),
  attribution jsonb not null check (jsonb_typeof(attribution)='object'),
  amount_minor bigint,
  currency text,
  retention jsonb,
  claim_sha256 text not null check (claim_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  check ((amount_minor is null and currency is null) or
         (amount_minor>0 and currency ~ '^[A-Z]{3}$')),
  check (retention is null or jsonb_typeof(retention)='object'),
  unique (organization_id,tracking_tenant_id,event_name,event_id),
  unique (organization_id,tracking_tenant_id,event_name,outcome_id)
);

create table if not exists private.pandora_meta_measurement_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  tracking_tenant_id uuid not null,
  tracking_campaign_id uuid not null,
  installation_id uuid not null,
  ad_account_id text not null check (ad_account_id ~ '^act_[1-9][0-9]{0,63}$'),
  pixel_id text not null check (pixel_id ~ '^[1-9][0-9]{0,63}$'),
  meta_campaign_id text,
  meta_adset_id text,
  meta_ad_id text,
  account_currency text not null check (account_currency ~ '^[A-Z]{3}$'),
  account_timezone text,
  binding_state text not null check (binding_state in ('pixel_only','campaign_bound','verified')),
  verified_at timestamptz not null,
  provider_evidence jsonb not null check (jsonb_typeof(provider_evidence)='object'),
  last_cost_sync_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,tracking_campaign_id),
  check (meta_campaign_id is null or meta_campaign_id ~ '^[1-9][0-9]{0,63}$'),
  check (meta_adset_id is null or meta_adset_id ~ '^[1-9][0-9]{0,63}$'),
  check (meta_ad_id is null or meta_ad_id ~ '^[1-9][0-9]{0,63}$'),
  check (meta_adset_id is null or meta_campaign_id is not null),
  check (meta_ad_id is null or (meta_campaign_id is not null and meta_adset_id is not null))
);

create table if not exists private.pandora_meta_conversion_match_keys (
  tracking_event_id uuid primary key references public.pandora_tracking_events(id) on delete cascade,
  organization_id uuid not null,
  project_id uuid not null,
  policy_version text not null,
  em_sha256 text[] not null default '{}',
  ph_sha256 text[] not null default '{}',
  external_id_sha256 text[] not null default '{}',
  created_at timestamptz not null default clock_timestamp(),
  check (cardinality(em_sha256)<=10 and cardinality(ph_sha256)<=10 and cardinality(external_id_sha256)<=10),
  check (cardinality(em_sha256)+cardinality(ph_sha256)+cardinality(external_id_sha256)>0)
);

create table if not exists private.pandora_meta_conversion_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  tracking_event_id uuid not null references public.pandora_tracking_events(id) on delete cascade,
  binding_id uuid not null references private.pandora_meta_measurement_bindings(id) on delete restrict,
  policy_version text not null,
  event_id text not null,
  meta_event_name text not null check (meta_event_name in ('Lead','Schedule','Purchase')),
  state text not null default 'pending' check (state in ('pending','submitted','delivered','dead_letter')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 5),
  next_attempt_at timestamptz not null default clock_timestamp(),
  last_http_status integer,
  provider_receipt jsonb,
  last_error_code text,
  delivered_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,event_id)
);

alter table public.pandora_growth_privacy_authorizations enable row level security;
alter table public.pandora_growth_outcome_receipts enable row level security;
alter table private.pandora_meta_measurement_bindings enable row level security;
alter table private.pandora_meta_conversion_match_keys enable row level security;
alter table private.pandora_meta_conversion_outbox enable row level security;

revoke all on public.pandora_growth_privacy_authorizations from public,anon,authenticated;
revoke all on public.pandora_growth_outcome_receipts from public,anon,authenticated;
revoke all on private.pandora_meta_measurement_bindings from public,anon,authenticated,service_role;
revoke all on private.pandora_meta_conversion_match_keys from public,anon,authenticated,service_role;
revoke all on private.pandora_meta_conversion_outbox from public,anon,authenticated,service_role;
grant select on public.pandora_growth_privacy_authorizations to service_role;
grant select on public.pandora_growth_outcome_receipts to service_role;

create or replace function private.pandora_growth_privacy_active_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_policy_version text,
  p_flow text
) returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public'
as $function$
select exists(
  select 1
  from public.pandora_growth_privacy_authorizations a
  where a.organization_id=p_organization_id
    and a.project_id=p_project_id
    and a.policy_version=p_policy_version
    and a.active is true
    and (a.expires_at is null or a.expires_at>clock_timestamp())
    and p_flow=any(a.allowed_flows)
);
$function$;
revoke all on function private.pandora_growth_privacy_active_v1(uuid,uuid,text,text)
  from public,anon,authenticated,service_role;

create or replace function private.pandora_meta_measurement_graph_get_v1(
  p_token text,
  p_path text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','extensions'
as $function$
declare
  v_response extensions.http_response;
  v_body jsonb;
begin
  if nullif(btrim(coalesce(p_token,'')),'') is null
     or length(p_path) not between 1 and 1000
     or p_path !~ '^[A-Za-z0-9_?&=,./%:~-]+
    raise exception 'PANDORA_META_MEASUREMENT_PROVIDER_REQUEST_INVALID' using errcode='22023';
  end if;
  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||p_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||p_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Facebook-Measurement/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);
  begin
    v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb);
  exception when others then
    v_body:='{}'::jsonb;
  end;
  if v_response.status<>200 or v_body ? 'error' then
    raise exception 'PANDORA_META_MEASUREMENT_PROVIDER_READ_FAILED' using errcode='58000';
  end if;
  return v_body;
end;
$function$;
revoke all on function private.pandora_meta_measurement_graph_get_v1(text,text)
  from public,anon,authenticated,service_role;

create or replace function public.pandora_meta_verify_measurement_binding_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_campaign_id uuid,
  p_installation_id uuid,
  p_ad_account_id text,
  p_pixel_id text,
  p_meta_campaign_id text default null,
  p_meta_adset_id text default null,
  p_meta_ad_id text default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_tenant public.pandora_tracking_tenants%rowtype;
  v_campaign public.pandora_tracking_campaigns%rowtype;
  v_runtime jsonb;
  v_token text;
  v_account jsonb;
  v_pixels jsonb;
  v_pixel jsonb;
  v_provider_campaign jsonb;
  v_provider_adset jsonb;
  v_provider_ad jsonb;
  v_numeric_account text;
  v_state text;
  v_binding_id uuid;
  v_now timestamptz:=clock_timestamp();
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_MEASUREMENT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_ad_account_id !~ '^act_[1-9][0-9]{0,63}$'
    or p_pixel_id !~ '^[1-9][0-9]{0,63}$'
    or (p_meta_campaign_id is not null and p_meta_campaign_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_adset_id is not null and p_meta_adset_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_ad_id is not null and p_meta_ad_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_adset_id is not null and p_meta_campaign_id is null)
    or (p_meta_ad_id is not null and (p_meta_campaign_id is null or p_meta_adset_id is null)) then
    raise exception 'PANDORA_META_MEASUREMENT_IDENTITY_INVALID' using errcode='22023';
  end if;

  select t.* into v_tenant
  from public.pandora_tracking_tenants t
  where t.organization_id=p_organization_id
    and t.project_id=p_project_id
    and t.status='active'
    and exists(
      select 1 from public.pandora_tracking_campaigns c
      where c.id=p_tracking_campaign_id and c.tenant_id=t.id
    )
  for share;
  if not found then
    raise exception 'PANDORA_META_MEASUREMENT_TENANT_SCOPE_DENIED' using errcode='42501';
  end if;

  select * into v_campaign
  from public.pandora_tracking_campaigns c
  where c.id=p_tracking_campaign_id
    and c.tenant_id=v_tenant.id
    and c.status='active'
    and c.provider='meta'
  for update;
  if not found then
    raise exception 'PANDORA_META_MEASUREMENT_CAMPAIGN_SCOPE_DENIED' using errcode='42501';
  end if;

  if (v_campaign.provider_campaign_id is not null and
      v_campaign.provider_campaign_id is distinct from p_meta_campaign_id)
    or (v_campaign.provider_adset_id is not null and
      v_campaign.provider_adset_id is distinct from p_meta_adset_id)
    or (v_campaign.provider_ad_id is not null and
      v_campaign.provider_ad_id is distinct from p_meta_ad_id) then
    raise exception 'PANDORA_META_MEASUREMENT_REBIND_DENIED' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(
    p_organization_id,p_installation_id,'marketing'
  );
  v_token:=v_runtime->>'token';
  v_account:=private.pandora_meta_measurement_graph_get_v1(
    v_token,p_ad_account_id||'?fields=id,account_id,name,currency,account_status,timezone_name'
  );
  v_numeric_account:=replace(p_ad_account_id,'act_','');
  if v_account->>'id' is distinct from p_ad_account_id
    or v_account->>'account_id' is distinct from v_numeric_account
    or coalesce((v_account->>'account_status')::integer,0)<>1
    or coalesce(v_account->>'currency','') !~ '^[A-Z]{3}$' then
    raise exception 'PANDORA_META_MEASUREMENT_ACCOUNT_MISMATCH' using errcode='42501';
  end if;

  v_pixels:=private.pandora_meta_measurement_graph_get_v1(
    v_token,p_ad_account_id||'/adspixels?fields=id,name&limit=100'
  );
  select value into v_pixel
  from jsonb_array_elements(coalesce(v_pixels->'data','[]'::jsonb))
  where value->>'id'=p_pixel_id
  limit 1;
  if v_pixel is null then
    raise exception 'PANDORA_META_MEASUREMENT_PIXEL_MISMATCH' using errcode='42501';
  end if;

  if p_meta_campaign_id is not null then
    v_provider_campaign:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_campaign_id||'?fields=id,account_id,name,status'
    );
    if v_provider_campaign->>'id' is distinct from p_meta_campaign_id
      or v_provider_campaign->>'account_id' is distinct from v_numeric_account then
      raise exception 'PANDORA_META_MEASUREMENT_CAMPAIGN_MISMATCH' using errcode='42501';
    end if;
  end if;
  if p_meta_adset_id is not null then
    v_provider_adset:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_adset_id||'?fields=id,account_id,campaign_id,name,status'
    );
    if v_provider_adset->>'id' is distinct from p_meta_adset_id
      or v_provider_adset->>'account_id' is distinct from v_numeric_account
      or v_provider_adset->>'campaign_id' is distinct from p_meta_campaign_id then
      raise exception 'PANDORA_META_MEASUREMENT_ADSET_MISMATCH' using errcode='42501';
    end if;
  end if;
  if p_meta_ad_id is not null then
    v_provider_ad:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_ad_id||'?fields=id,account_id,campaign_id,adset_id,name,status'
    );
    if v_provider_ad->>'id' is distinct from p_meta_ad_id
      or v_provider_ad->>'account_id' is distinct from v_numeric_account
      or v_provider_ad->>'campaign_id' is distinct from p_meta_campaign_id
      or v_provider_ad->>'adset_id' is distinct from p_meta_adset_id then
      raise exception 'PANDORA_META_MEASUREMENT_AD_MISMATCH' using errcode='42501';
    end if;
  end if;
  v_token:=null;

  v_state:=case
    when p_meta_ad_id is not null then 'verified'
    when p_meta_campaign_id is not null then 'campaign_bound'
    else 'pixel_only'
  end;

  insert into private.pandora_meta_measurement_bindings(
    organization_id,project_id,tracking_tenant_id,tracking_campaign_id,
    installation_id,ad_account_id,pixel_id,meta_campaign_id,meta_adset_id,meta_ad_id,
    account_currency,account_timezone,binding_state,verified_at,provider_evidence,
    updated_at
  ) values (
    p_organization_id,p_project_id,v_tenant.id,p_tracking_campaign_id,
    p_installation_id,p_ad_account_id,p_pixel_id,p_meta_campaign_id,p_meta_adset_id,p_meta_ad_id,
    v_account->>'currency',nullif(v_account->>'timezone_name',''),v_state,v_now,
    jsonb_build_object(
      'account',jsonb_build_object('id',v_account->>'id','name',v_account->>'name',
        'currency',v_account->>'currency','status',v_account->>'account_status'),
      'pixel',jsonb_build_object('id',v_pixel->>'id','name',v_pixel->>'name'),
      'campaign',case when v_provider_campaign is null then null else
        jsonb_build_object('id',v_provider_campaign->>'id','name',v_provider_campaign->>'name',
          'status',v_provider_campaign->>'status') end,
      'adset',case when v_provider_adset is null then null else
        jsonb_build_object('id',v_provider_adset->>'id','name',v_provider_adset->>'name',
          'status',v_provider_adset->>'status') end,
      'ad',case when v_provider_ad is null then null else
        jsonb_build_object('id',v_provider_ad->>'id','name',v_provider_ad->>'name',
          'status',v_provider_ad->>'status') end
    ),
    v_now
  )
  on conflict(organization_id,tracking_campaign_id) do update
  set installation_id=excluded.installation_id,
      ad_account_id=excluded.ad_account_id,
      pixel_id=excluded.pixel_id,
      meta_campaign_id=excluded.meta_campaign_id,
      meta_adset_id=excluded.meta_adset_id,
      meta_ad_id=excluded.meta_ad_id,
      account_currency=excluded.account_currency,
      account_timezone=excluded.account_timezone,
      binding_state=excluded.binding_state,
      verified_at=excluded.verified_at,
      provider_evidence=excluded.provider_evidence,
      updated_at=excluded.updated_at
  returning id into v_binding_id;

  if p_meta_campaign_id is not null then
    update public.pandora_tracking_campaigns
    set provider_campaign_id=p_meta_campaign_id,
        provider_adset_id=p_meta_adset_id,
        provider_ad_id=p_meta_ad_id,
        updated_at=v_now
    where id=p_tracking_campaign_id and tenant_id=v_tenant.id;
  end if;

  return jsonb_build_object(
    'ok',true,'bindingId',v_binding_id,'bindingState',v_state,
    'trackingTenantId',v_tenant.id,'trackingCampaignId',p_tracking_campaign_id,
    'adAccountId',p_ad_account_id,'pixelId',p_pixel_id,
    'campaignId',p_meta_campaign_id,'adsetId',p_meta_adset_id,'adId',p_meta_ad_id,
    'currency',v_account->>'currency','timezone',v_account->>'timezone_name',
    'verifiedAt',v_now
  );
end;
$function$;
revoke all on function public.pandora_meta_verify_measurement_binding_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_meta_verify_measurement_binding_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text
) to service_role;

create or replace function public.pandora_ingest_growth_outcome_v1(
  p_event jsonb,
  p_claim_sha256 text,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_org uuid;
  v_tenant uuid;
  v_project uuid;
  v_existing public.pandora_growth_outcome_receipts%rowtype;
  v_receipt_id uuid;
  v_campaign_id uuid;
  v_click_id text;
  v_event_type text;
  v_tracking_event_id uuid;
  v_amount bigint;
  v_currency text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_GROWTH_OUTCOME_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if jsonb_typeof(p_event) is distinct from 'object'
    or p_claim_sha256 !~ '^[0-9a-f]{64}$'
    or p_policy_version !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception 'PANDORA_GROWTH_OUTCOME_INPUT_INVALID' using errcode='22023';
  end if;

  begin
    v_org:=(p_event->>'organization_id')::uuid;
    v_tenant:=(p_event->>'tracking_tenant_id')::uuid;
    v_project:=case when p_event->>'project_id' is null then null
      else (p_event->>'project_id')::uuid end;
  exception when others then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_INVALID' using errcode='22023';
  end;

  if v_project is null or not exists(
    select 1 from public.pandora_tracking_tenants t
    where t.id=v_tenant and t.organization_id=v_org and t.project_id=v_project
      and t.status='active'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_DENIED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    v_org,v_project,p_policy_version,'server_outcomes'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_PRIVACY_HOLD' using errcode='42501';
  end if;

  select * into v_existing
  from public.pandora_growth_outcome_receipts
  where organization_id=v_org and tracking_tenant_id=v_tenant
    and event_name=p_event->>'event_name' and outcome_id=p_event->>'outcome_id'
  for update;
  if found then
    if v_existing.claim_sha256 is distinct from p_claim_sha256
      or v_existing.event_id is distinct from p_event->>'event_id' then
      raise exception 'PANDORA_GROWTH_OUTCOME_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'duplicate',true,'receiptId',v_existing.id,
      'trackingEventId',(
        select e.id from public.pandora_tracking_events e
        where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
          and e.external_event_id=p_event->>'event_id' limit 1
      )
    );
  end if;

  if p_event#>>'{attribution,kind}'='observed' then
    v_click_id:=p_event#>>'{attribution,click_id}';
    select c.campaign_id into v_campaign_id
    from public.pandora_tracking_clicks c
    where c.tenant_id=v_tenant and c.click_id=v_click_id;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_CLICK_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}' in ('platform_reported','inferred') then
    select c.id into v_campaign_id
    from public.pandora_tracking_campaigns c
    where c.tenant_id=v_tenant and c.status='active'
      and c.provider='meta'
      and c.provider_campaign_id=p_event#>>'{attribution,campaign_id}'
      and (not (p_event#>'{attribution}') ? 'adset_id'
        or c.provider_adset_id=p_event#>>'{attribution,adset_id}')
      and (not (p_event#>'{attribution}') ? 'ad_id'
        or c.provider_ad_id=p_event#>>'{attribution,ad_id}')
    limit 1;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_PROVIDER_ATTRIBUTION_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}'<>'unattributed' then
    raise exception 'PANDORA_GROWTH_OUTCOME_ATTRIBUTION_INVALID' using errcode='22023';
  end if;

  v_amount:=case when p_event ? 'money' then
    (p_event#>>'{money,amount_minor}')::bigint else null end;
  v_currency:=case when p_event ? 'money' then
    p_event#>>'{money,currency}' else null end;

  insert into public.pandora_growth_outcome_receipts(
    organization_id,tracking_tenant_id,project_id,event_name,event_id,outcome_id,
    acquisition_path,journey_id,subject_id,occurred_at,delivery_source,evidence,
    attribution,amount_minor,currency,retention,claim_sha256
  ) values (
    v_org,v_tenant,v_project,p_event->>'event_name',p_event->>'event_id',
    p_event->>'outcome_id',p_event->>'acquisition_path',p_event->>'journey_id',
    p_event->>'subject_id',(p_event->>'occurred_at')::timestamptz,
    p_event->>'delivery_source',p_event->'evidence',p_event->'attribution',
    v_amount,v_currency,p_event->'retention',p_claim_sha256
  ) returning id into v_receipt_id;

  v_event_type:=case p_event->>'event_name'
    when 'lead_submitted' then 'lead'
    when 'lead_qualified' then 'qualified_lead'
    when 'demo_completed' then 'booking'
    when 'payment_settled' then 'sale'
    when 'refund_settled' then 'refund'
    else 'event'
  end;

  insert into public.pandora_tracking_events(
    tenant_id,campaign_id,click_id,event_type,event_name,source,
    external_event_id,value,currency,occurred_at,metadata,
    schema_version,consent,is_test
  ) values (
    v_tenant,v_campaign_id,v_click_id,v_event_type,p_event->>'event_name','server',
    p_event->>'event_id',null,null,(p_event->>'occurred_at')::timestamptz,
    '{}'::jsonb,1,'{"analytics":false,"marketing":false}'::jsonb,false
  )
  on conflict (tenant_id,event_name,external_event_id)
    where external_event_id is not null do nothing;

  select e.id into v_tracking_event_id
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
    and e.external_event_id=p_event->>'event_id'
  limit 1;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'receiptId',v_receipt_id,
    'trackingEventId',v_tracking_event_id,
    'moneyProjection','minor_units_only'
  );
end;
$function$;
revoke all on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  to service_role;

create or replace function public.pandora_meta_import_campaign_costs_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_binding_id uuid,
  p_since date,
  p_until date
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_runtime jsonb;
  v_token text;
  v_body jsonb;
  v_row jsonb;
  v_imported integer:=0;
  v_omitted integer:=0;
  v_day date;
  v_spend numeric;
  v_impressions bigint;
  v_clicks bigint;
  v_external text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_COST_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_since is null or p_until is null or p_since>p_until
    or p_until-p_since>31 then
    raise exception 'PANDORA_META_COST_WINDOW_INVALID' using errcode='22023';
  end if;
  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.id=p_binding_id and b.organization_id=p_organization_id
    and b.project_id=p_project_id and b.meta_campaign_id is not null
    and b.binding_state in ('campaign_bound','verified')
  for update;
  if not found then
    raise exception 'PANDORA_META_COST_BINDING_REQUIRED' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(
    p_organization_id,v_binding.installation_id,'marketing'
  );
  v_token:=v_runtime->>'token';
  v_body:=private.pandora_meta_measurement_graph_get_v1(
    v_token,
    v_binding.meta_campaign_id||
      '?fields=id&limit=1'
  );
  if v_body->>'id' is distinct from v_binding.meta_campaign_id then
    raise exception 'PANDORA_META_COST_CAMPAIGN_MISMATCH' using errcode='42501';
  end if;
  v_body:=private.pandora_meta_measurement_graph_get_v1(
    v_token,
    v_binding.meta_campaign_id||
      '/insights?fields=spend,impressions,clicks,date_start,date_stop&time_increment=1&limit=100&time_range=%7B%22since%22%3A%22'||
      p_since::text||'%22%2C%22until%22%3A%22'||p_until::text||'%22%7D'
  );
  v_token:=null;

  for v_row in select value from jsonb_array_elements(coalesce(v_body->'data','[]'::jsonb))
  loop
    if coalesce(v_row->>'date_start','') !~ '^\d{4}-\d{2}-\d{2}$'
      or coalesce(v_row->>'spend','') !~ '^\d+(\.\d+)?$'
      or coalesce(v_row->>'impressions','') !~ '^\d+$'
      or coalesce(v_row->>'clicks','') !~ '^\d+$' then
      v_omitted:=v_omitted+1;
      continue;
    end if;
    v_day:=(v_row->>'date_start')::date;
    v_spend:=(v_row->>'spend')::numeric;
    v_impressions:=(v_row->>'impressions')::bigint;
    v_clicks:=(v_row->>'clicks')::bigint;
    v_external:='meta:'||v_binding.meta_campaign_id||':'||v_day::text||':'||
      v_binding.account_currency;

    insert into public.pandora_tracking_costs(
      tenant_id,campaign_id,provider,external_record_id,bucket_date,spend,
      impressions,provider_clicks,currency,metadata
    ) values (
      v_binding.tracking_tenant_id,v_binding.tracking_campaign_id,'meta',
      v_external,v_day,v_spend,v_impressions,v_clicks,
      v_binding.account_currency,'{}'::jsonb
    )
    on conflict(tenant_id,provider,external_record_id) do update
    set campaign_id=excluded.campaign_id,bucket_date=excluded.bucket_date,
        spend=excluded.spend,impressions=excluded.impressions,
        provider_clicks=excluded.provider_clicks,currency=excluded.currency,
        metadata='{}'::jsonb,updated_at=clock_timestamp();
    v_imported:=v_imported+1;
  end loop;

  update private.pandora_meta_measurement_bindings
  set last_cost_sync_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_binding.id;

  return jsonb_build_object(
    'ok',true,'importedDays',v_imported,'omittedUnknownRows',v_omitted,
    'currency',v_binding.account_currency,'since',p_since,'until',p_until,
    'missingIsZero',false
  );
end;
$function$;
revoke all on function public.pandora_meta_import_campaign_costs_v1(uuid,uuid,uuid,date,date)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_import_campaign_costs_v1(uuid,uuid,uuid,date,date)
  to service_role;

create or replace function public.pandora_meta_register_conversion_match_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_event_id uuid,
  p_policy_version text,
  p_em_sha256 text[] default '{}',
  p_ph_sha256 text[] default '{}',
  p_external_id_sha256 text[] default '{}'
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare v_value text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_MATCH_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,p_policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_MATCH_PRIVACY_HOLD' using errcode='42501';
  end if;
  if cardinality(coalesce(p_em_sha256,'{}'))+
     cardinality(coalesce(p_ph_sha256,'{}'))+
     cardinality(coalesce(p_external_id_sha256,'{}'))<1 then
    raise exception 'PANDORA_META_MATCH_KEY_REQUIRED' using errcode='22023';
  end if;
  foreach v_value in array coalesce(p_em_sha256,'{}')||coalesce(p_ph_sha256,'{}')||
    coalesce(p_external_id_sha256,'{}')
  loop
    if v_value !~ '^[0-9a-f]{64}$' then
      raise exception 'PANDORA_META_MATCH_KEY_INVALID' using errcode='22023';
    end if;
  end loop;
  if not exists(
    select 1 from public.pandora_tracking_events e
    join public.pandora_tracking_tenants t on t.id=e.tenant_id
    where e.id=p_tracking_event_id and t.organization_id=p_organization_id
      and t.project_id=p_project_id and e.source='server'
  ) then
    raise exception 'PANDORA_META_MATCH_EVENT_SCOPE_DENIED' using errcode='42501';
  end if;

  insert into private.pandora_meta_conversion_match_keys(
    tracking_event_id,organization_id,project_id,policy_version,
    em_sha256,ph_sha256,external_id_sha256
  ) values (
    p_tracking_event_id,p_organization_id,p_project_id,p_policy_version,
    coalesce(p_em_sha256,'{}'),coalesce(p_ph_sha256,'{}'),
    coalesce(p_external_id_sha256,'{}')
  )
  on conflict(tracking_event_id) do update
  set policy_version=excluded.policy_version,em_sha256=excluded.em_sha256,
      ph_sha256=excluded.ph_sha256,external_id_sha256=excluded.external_id_sha256;
  return jsonb_build_object('ok',true,'trackingEventId',p_tracking_event_id);
end;
$function$;
revoke all on function public.pandora_meta_register_conversion_match_v1(
  uuid,uuid,uuid,text,text[],text[],text[]
) from public,anon,authenticated;
grant execute on function public.pandora_meta_register_conversion_match_v1(
  uuid,uuid,uuid,text,text[],text[],text[]
) to service_role;

create or replace function public.pandora_meta_enqueue_conversion_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_event_id uuid,
  p_binding_id uuid,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_event public.pandora_tracking_events%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_match private.pandora_meta_conversion_match_keys%rowtype;
  v_meta_name text;
  v_id uuid;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_CONVERSION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,p_policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_CONVERSION_PRIVACY_HOLD' using errcode='42501';
  end if;

  select e.* into v_event
  from public.pandora_tracking_events e
  join public.pandora_tracking_tenants t on t.id=e.tenant_id
  where e.id=p_tracking_event_id and t.organization_id=p_organization_id
    and t.project_id=p_project_id and e.source='server'
    and e.external_event_id is not null
    and e.is_test is false
    and coalesce((e.consent->>'marketing')::boolean,false) is true
    and e.event_type in ('lead','qualified_lead','booking','sale')
  for update of e;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_EVENT_INELIGIBLE' using errcode='42501';
  end if;

  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.id=p_binding_id and b.organization_id=p_organization_id
    and b.project_id=p_project_id and b.tracking_tenant_id=v_event.tenant_id
  for share;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_BINDING_DENIED' using errcode='42501';
  end if;

  select * into v_match
  from private.pandora_meta_conversion_match_keys m
  where m.tracking_event_id=v_event.id and m.organization_id=p_organization_id
    and m.project_id=p_project_id and m.policy_version=p_policy_version;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_MATCH_REQUIRED' using errcode='42501';
  end if;

  v_meta_name:=case v_event.event_type
    when 'lead' then 'Lead'
    when 'qualified_lead' then 'Lead'
    when 'booking' then 'Schedule'
    when 'sale' then 'Purchase'
  end;

  insert into private.pandora_meta_conversion_outbox(
    organization_id,project_id,tracking_event_id,binding_id,policy_version,
    event_id,meta_event_name
  ) values (
    p_organization_id,p_project_id,v_event.id,v_binding.id,p_policy_version,
    v_event.external_event_id,v_meta_name
  )
  on conflict(organization_id,event_id) do update
  set updated_at=private.pandora_meta_conversion_outbox.updated_at
  returning id into v_id;
  return jsonb_build_object('ok',true,'outboxId',v_id,'state','pending');
end;
$function$;
revoke all on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
  to service_role;

create or replace function public.pandora_meta_dispatch_conversion_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_outbox_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_outbox private.pandora_meta_conversion_outbox%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_event public.pandora_tracking_events%rowtype;
  v_match private.pandora_meta_conversion_match_keys%rowtype;
  v_runtime jsonb;
  v_token text;
  v_user_data jsonb:='{}'::jsonb;
  v_event_payload jsonb;
  v_response extensions.http_response;
  v_body jsonb:='{}'::jsonb;
  v_success boolean:=false;
  v_attempt integer;
  v_next_state text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_CONVERSION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  select * into v_outbox
  from private.pandora_meta_conversion_outbox o
  where o.id=p_outbox_id and o.organization_id=p_organization_id
    and o.project_id=p_project_id
  for update;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_OUTBOX_NOT_FOUND' using errcode='P0002';
  end if;
  if v_outbox.state='delivered' then
    return jsonb_build_object('ok',true,'state','delivered','duplicate',true);
  end if;
  if v_outbox.state='dead_letter' or v_outbox.attempt_count>=5
    or v_outbox.next_attempt_at>clock_timestamp() then
    raise exception 'PANDORA_META_CONVERSION_NOT_DISPATCHABLE' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,v_outbox.policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_CONVERSION_PRIVACY_HOLD' using errcode='42501';
  end if;

  select * into v_binding
  from private.pandora_meta_measurement_bindings
  where id=v_outbox.binding_id and organization_id=p_organization_id
    and project_id=p_project_id;
  select * into v_event from public.pandora_tracking_events
  where id=v_outbox.tracking_event_id;
  select * into v_match from private.pandora_meta_conversion_match_keys
  where tracking_event_id=v_event.id and organization_id=p_organization_id
    and project_id=p_project_id and policy_version=v_outbox.policy_version;
  if v_binding.id is null or v_event.id is null or v_match.tracking_event_id is null then
    raise exception 'PANDORA_META_CONVERSION_LINEAGE_INVALID' using errcode='42501';
  end if;

  if cardinality(v_match.em_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('em',to_jsonb(v_match.em_sha256)); end if;
  if cardinality(v_match.ph_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('ph',to_jsonb(v_match.ph_sha256)); end if;
  if cardinality(v_match.external_id_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('external_id',to_jsonb(v_match.external_id_sha256)); end if;

  v_event_payload:=jsonb_build_object(
    'event_name',v_outbox.meta_event_name,
    'event_time',floor(extract(epoch from v_event.occurred_at))::bigint,
    'action_source','website',
    'event_id',v_outbox.event_id,
    'user_data',v_user_data
  );
  if v_event.event_type='sale' and v_event.value is not null and v_event.currency is not null then
    v_event_payload:=v_event_payload||jsonb_build_object(
      'custom_data',jsonb_build_object('value',v_event.value,'currency',v_event.currency)
    );
  end if;

  v_attempt:=v_outbox.attempt_count+1;
  update private.pandora_meta_conversion_outbox
  set state='submitted',attempt_count=v_attempt,updated_at=clock_timestamp()
  where id=v_outbox.id;

  begin
    v_runtime:=public.pandora_meta_runtime_secret_v1(
      p_organization_id,v_binding.installation_id,'marketing'
    );
    v_token:=v_runtime->>'token';
    select * into v_response
    from extensions.http((
      'POST'::extensions.http_method,
      ('https://graph.facebook.com/v26.0/'||v_binding.pixel_id||'/events')::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('content-type','application/json'),
        extensions.http_header('user-agent','Pandora-Facebook-Conversion/1.0')
      ]::extensions.http_header[],
      'application/json'::varchar,
      jsonb_build_object('data',jsonb_build_array(v_event_payload))::text::varchar
    )::extensions.http_request);
    v_token:=null;
    begin
      v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb);
    exception when others then
      v_body:='{}'::jsonb;
    end;
    v_success:=v_response.status=200
      and coalesce((v_body->>'events_received')::integer,0)>=1
      and not (v_body ? 'error');
  exception when others then
    v_token:=null;
    v_success:=false;
    v_body:='{}'::jsonb;
    v_response.status:=null;
  end;

  v_next_state:=case when v_success then 'delivered'
    when v_attempt>=5 then 'dead_letter' else 'pending' end;
  update private.pandora_meta_conversion_outbox
  set state=v_next_state,
      last_http_status=v_response.status,
      provider_receipt=case when v_success then jsonb_build_object(
        'eventsReceived',coalesce((v_body->>'events_received')::integer,0),
        'traceId',nullif(v_body->>'fbtrace_id','')
      ) else null end,
      last_error_code=case when v_success then null else 'provider_delivery_failed' end,
      next_attempt_at=case when v_success or v_attempt>=5 then next_attempt_at
        else clock_timestamp()+make_interval(secs=>least(3600,60*(2^(v_attempt-1)))) end,
      delivered_at=case when v_success then clock_timestamp() else null end,
      updated_at=clock_timestamp()
  where id=v_outbox.id;

  return jsonb_build_object(
    'ok',v_success,'state',v_next_state,'attempt',v_attempt,
    'httpStatus',v_response.status,'eventId',v_outbox.event_id
  );
end;
$function$;
revoke all on function public.pandora_meta_dispatch_conversion_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_dispatch_conversion_v1(uuid,uuid,uuid)
  to service_role;

create or replace view public.pandora_facebook_measurement_status_v1 as
select
  t.organization_id,t.project_id,t.id as tracking_tenant_id,
  c.id as tracking_campaign_id,c.slug,c.name as tracking_campaign_name,
  c.provider_campaign_id,c.provider_adset_id,c.provider_ad_id,
  b.id as binding_id,b.ad_account_id,b.pixel_id,b.binding_state,
  b.account_currency,b.account_timezone,b.verified_at,b.last_cost_sync_at,
  exists(
    select 1 from public.pandora_growth_privacy_authorizations a
    where a.organization_id=t.organization_id and a.project_id=t.project_id
      and a.active is true and (a.expires_at is null or a.expires_at>clock_timestamp())
      and 'server_outcomes'=any(a.allowed_flows)
  ) as server_outcomes_authorized,
  exists(
    select 1 from public.pandora_growth_privacy_authorizations a
    where a.organization_id=t.organization_id and a.project_id=t.project_id
      and a.active is true and (a.expires_at is null or a.expires_at>clock_timestamp())
      and 'provider_matching'=any(a.allowed_flows)
  ) as provider_matching_authorized
from public.pandora_tracking_tenants t
join public.pandora_tracking_campaigns c on c.tenant_id=t.id
left join private.pandora_meta_measurement_bindings b
  on b.organization_id=t.organization_id and b.tracking_campaign_id=c.id
where c.provider='meta';

revoke all on public.pandora_facebook_measurement_status_v1 from public,anon,authenticated;
grant select on public.pandora_facebook_measurement_status_v1 to service_role;

comment on table public.pandora_growth_privacy_authorizations is
  'Explicit owner/privacy approval ledger. No row is seeded by the Facebook measurement release.';
comment on table public.pandora_growth_outcome_receipts is
  'Authoritative normalized FB003 outcome receipts; monetary values remain integer minor units.';
comment on table private.pandora_meta_conversion_outbox is
  'Consent/privacy-gated Meta CAPI delivery queue. Stable event_id provides provider deduplication; five attempts dead-letter.';
 then
    raise exception 'PANDORA_META_MEASUREMENT_PROVIDER_REQUEST_INVALID' using errcode='22023';
  end if;
  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://graph.facebook.com/v26.0/'||p_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||p_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Facebook-Measurement/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);
  begin
    v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb);
  exception when others then
    v_body:='{}'::jsonb;
  end;
  if v_response.status<>200 or v_body ? 'error' then
    raise exception 'PANDORA_META_MEASUREMENT_PROVIDER_READ_FAILED' using errcode='58000';
  end if;
  return v_body;
end;
$function$;
revoke all on function private.pandora_meta_measurement_graph_get_v1(text,text)
  from public,anon,authenticated,service_role;

create or replace function public.pandora_meta_verify_measurement_binding_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_campaign_id uuid,
  p_installation_id uuid,
  p_ad_account_id text,
  p_pixel_id text,
  p_meta_campaign_id text default null,
  p_meta_adset_id text default null,
  p_meta_ad_id text default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_tenant public.pandora_tracking_tenants%rowtype;
  v_campaign public.pandora_tracking_campaigns%rowtype;
  v_runtime jsonb;
  v_token text;
  v_account jsonb;
  v_pixels jsonb;
  v_pixel jsonb;
  v_provider_campaign jsonb;
  v_provider_adset jsonb;
  v_provider_ad jsonb;
  v_numeric_account text;
  v_state text;
  v_binding_id uuid;
  v_now timestamptz:=clock_timestamp();
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_MEASUREMENT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_ad_account_id !~ '^act_[1-9][0-9]{0,63}$'
    or p_pixel_id !~ '^[1-9][0-9]{0,63}$'
    or (p_meta_campaign_id is not null and p_meta_campaign_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_adset_id is not null and p_meta_adset_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_ad_id is not null and p_meta_ad_id !~ '^[1-9][0-9]{0,63}$')
    or (p_meta_adset_id is not null and p_meta_campaign_id is null)
    or (p_meta_ad_id is not null and (p_meta_campaign_id is null or p_meta_adset_id is null)) then
    raise exception 'PANDORA_META_MEASUREMENT_IDENTITY_INVALID' using errcode='22023';
  end if;

  select t.* into v_tenant
  from public.pandora_tracking_tenants t
  where t.organization_id=p_organization_id
    and t.project_id=p_project_id
    and t.status='active'
    and exists(
      select 1 from public.pandora_tracking_campaigns c
      where c.id=p_tracking_campaign_id and c.tenant_id=t.id
    )
  for share;
  if not found then
    raise exception 'PANDORA_META_MEASUREMENT_TENANT_SCOPE_DENIED' using errcode='42501';
  end if;

  select * into v_campaign
  from public.pandora_tracking_campaigns c
  where c.id=p_tracking_campaign_id
    and c.tenant_id=v_tenant.id
    and c.status='active'
    and c.provider='meta'
  for update;
  if not found then
    raise exception 'PANDORA_META_MEASUREMENT_CAMPAIGN_SCOPE_DENIED' using errcode='42501';
  end if;

  if (v_campaign.provider_campaign_id is not null and
      v_campaign.provider_campaign_id is distinct from p_meta_campaign_id)
    or (v_campaign.provider_adset_id is not null and
      v_campaign.provider_adset_id is distinct from p_meta_adset_id)
    or (v_campaign.provider_ad_id is not null and
      v_campaign.provider_ad_id is distinct from p_meta_ad_id) then
    raise exception 'PANDORA_META_MEASUREMENT_REBIND_DENIED' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(
    p_organization_id,p_installation_id,'marketing'
  );
  v_token:=v_runtime->>'token';
  v_account:=private.pandora_meta_measurement_graph_get_v1(
    v_token,p_ad_account_id||'?fields=id,account_id,name,currency,account_status,timezone_name'
  );
  v_numeric_account:=replace(p_ad_account_id,'act_','');
  if v_account->>'id' is distinct from p_ad_account_id
    or v_account->>'account_id' is distinct from v_numeric_account
    or coalesce((v_account->>'account_status')::integer,0)<>1
    or coalesce(v_account->>'currency','') !~ '^[A-Z]{3}$' then
    raise exception 'PANDORA_META_MEASUREMENT_ACCOUNT_MISMATCH' using errcode='42501';
  end if;

  v_pixels:=private.pandora_meta_measurement_graph_get_v1(
    v_token,p_ad_account_id||'/adspixels?fields=id,name&limit=100'
  );
  select value into v_pixel
  from jsonb_array_elements(coalesce(v_pixels->'data','[]'::jsonb))
  where value->>'id'=p_pixel_id
  limit 1;
  if v_pixel is null then
    raise exception 'PANDORA_META_MEASUREMENT_PIXEL_MISMATCH' using errcode='42501';
  end if;

  if p_meta_campaign_id is not null then
    v_provider_campaign:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_campaign_id||'?fields=id,account_id,name,status'
    );
    if v_provider_campaign->>'id' is distinct from p_meta_campaign_id
      or v_provider_campaign->>'account_id' is distinct from v_numeric_account then
      raise exception 'PANDORA_META_MEASUREMENT_CAMPAIGN_MISMATCH' using errcode='42501';
    end if;
  end if;
  if p_meta_adset_id is not null then
    v_provider_adset:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_adset_id||'?fields=id,account_id,campaign_id,name,status'
    );
    if v_provider_adset->>'id' is distinct from p_meta_adset_id
      or v_provider_adset->>'account_id' is distinct from v_numeric_account
      or v_provider_adset->>'campaign_id' is distinct from p_meta_campaign_id then
      raise exception 'PANDORA_META_MEASUREMENT_ADSET_MISMATCH' using errcode='42501';
    end if;
  end if;
  if p_meta_ad_id is not null then
    v_provider_ad:=private.pandora_meta_measurement_graph_get_v1(
      v_token,p_meta_ad_id||'?fields=id,account_id,campaign_id,adset_id,name,status'
    );
    if v_provider_ad->>'id' is distinct from p_meta_ad_id
      or v_provider_ad->>'account_id' is distinct from v_numeric_account
      or v_provider_ad->>'campaign_id' is distinct from p_meta_campaign_id
      or v_provider_ad->>'adset_id' is distinct from p_meta_adset_id then
      raise exception 'PANDORA_META_MEASUREMENT_AD_MISMATCH' using errcode='42501';
    end if;
  end if;
  v_token:=null;

  v_state:=case
    when p_meta_ad_id is not null then 'verified'
    when p_meta_campaign_id is not null then 'campaign_bound'
    else 'pixel_only'
  end;

  insert into private.pandora_meta_measurement_bindings(
    organization_id,project_id,tracking_tenant_id,tracking_campaign_id,
    installation_id,ad_account_id,pixel_id,meta_campaign_id,meta_adset_id,meta_ad_id,
    account_currency,account_timezone,binding_state,verified_at,provider_evidence,
    updated_at
  ) values (
    p_organization_id,p_project_id,v_tenant.id,p_tracking_campaign_id,
    p_installation_id,p_ad_account_id,p_pixel_id,p_meta_campaign_id,p_meta_adset_id,p_meta_ad_id,
    v_account->>'currency',nullif(v_account->>'timezone_name',''),v_state,v_now,
    jsonb_build_object(
      'account',jsonb_build_object('id',v_account->>'id','name',v_account->>'name',
        'currency',v_account->>'currency','status',v_account->>'account_status'),
      'pixel',jsonb_build_object('id',v_pixel->>'id','name',v_pixel->>'name'),
      'campaign',case when v_provider_campaign is null then null else
        jsonb_build_object('id',v_provider_campaign->>'id','name',v_provider_campaign->>'name',
          'status',v_provider_campaign->>'status') end,
      'adset',case when v_provider_adset is null then null else
        jsonb_build_object('id',v_provider_adset->>'id','name',v_provider_adset->>'name',
          'status',v_provider_adset->>'status') end,
      'ad',case when v_provider_ad is null then null else
        jsonb_build_object('id',v_provider_ad->>'id','name',v_provider_ad->>'name',
          'status',v_provider_ad->>'status') end
    ),
    v_now
  )
  on conflict(organization_id,tracking_campaign_id) do update
  set installation_id=excluded.installation_id,
      ad_account_id=excluded.ad_account_id,
      pixel_id=excluded.pixel_id,
      meta_campaign_id=excluded.meta_campaign_id,
      meta_adset_id=excluded.meta_adset_id,
      meta_ad_id=excluded.meta_ad_id,
      account_currency=excluded.account_currency,
      account_timezone=excluded.account_timezone,
      binding_state=excluded.binding_state,
      verified_at=excluded.verified_at,
      provider_evidence=excluded.provider_evidence,
      updated_at=excluded.updated_at
  returning id into v_binding_id;

  if p_meta_campaign_id is not null then
    update public.pandora_tracking_campaigns
    set provider_campaign_id=p_meta_campaign_id,
        provider_adset_id=p_meta_adset_id,
        provider_ad_id=p_meta_ad_id,
        updated_at=v_now
    where id=p_tracking_campaign_id and tenant_id=v_tenant.id;
  end if;

  return jsonb_build_object(
    'ok',true,'bindingId',v_binding_id,'bindingState',v_state,
    'trackingTenantId',v_tenant.id,'trackingCampaignId',p_tracking_campaign_id,
    'adAccountId',p_ad_account_id,'pixelId',p_pixel_id,
    'campaignId',p_meta_campaign_id,'adsetId',p_meta_adset_id,'adId',p_meta_ad_id,
    'currency',v_account->>'currency','timezone',v_account->>'timezone_name',
    'verifiedAt',v_now
  );
end;
$function$;
revoke all on function public.pandora_meta_verify_measurement_binding_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_meta_verify_measurement_binding_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text
) to service_role;

create or replace function public.pandora_ingest_growth_outcome_v1(
  p_event jsonb,
  p_claim_sha256 text,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_org uuid;
  v_tenant uuid;
  v_project uuid;
  v_existing public.pandora_growth_outcome_receipts%rowtype;
  v_receipt_id uuid;
  v_campaign_id uuid;
  v_click_id text;
  v_event_type text;
  v_tracking_event_id uuid;
  v_amount bigint;
  v_currency text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_GROWTH_OUTCOME_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if jsonb_typeof(p_event) is distinct from 'object'
    or p_claim_sha256 !~ '^[0-9a-f]{64}$'
    or p_policy_version !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception 'PANDORA_GROWTH_OUTCOME_INPUT_INVALID' using errcode='22023';
  end if;

  begin
    v_org:=(p_event->>'organization_id')::uuid;
    v_tenant:=(p_event->>'tracking_tenant_id')::uuid;
    v_project:=case when p_event->>'project_id' is null then null
      else (p_event->>'project_id')::uuid end;
  exception when others then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_INVALID' using errcode='22023';
  end;

  if v_project is null or not exists(
    select 1 from public.pandora_tracking_tenants t
    where t.id=v_tenant and t.organization_id=v_org and t.project_id=v_project
      and t.status='active'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_SCOPE_DENIED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    v_org,v_project,p_policy_version,'server_outcomes'
  ) then
    raise exception 'PANDORA_GROWTH_OUTCOME_PRIVACY_HOLD' using errcode='42501';
  end if;

  select * into v_existing
  from public.pandora_growth_outcome_receipts
  where organization_id=v_org and tracking_tenant_id=v_tenant
    and event_name=p_event->>'event_name' and outcome_id=p_event->>'outcome_id'
  for update;
  if found then
    if v_existing.claim_sha256 is distinct from p_claim_sha256
      or v_existing.event_id is distinct from p_event->>'event_id' then
      raise exception 'PANDORA_GROWTH_OUTCOME_IDEMPOTENCY_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'duplicate',true,'receiptId',v_existing.id,
      'trackingEventId',(
        select e.id from public.pandora_tracking_events e
        where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
          and e.external_event_id=p_event->>'event_id' limit 1
      )
    );
  end if;

  if p_event#>>'{attribution,kind}'='observed' then
    v_click_id:=p_event#>>'{attribution,click_id}';
    select c.campaign_id into v_campaign_id
    from public.pandora_tracking_clicks c
    where c.tenant_id=v_tenant and c.click_id=v_click_id;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_CLICK_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}' in ('platform_reported','inferred') then
    select c.id into v_campaign_id
    from public.pandora_tracking_campaigns c
    where c.tenant_id=v_tenant and c.status='active'
      and c.provider='meta'
      and c.provider_campaign_id=p_event#>>'{attribution,campaign_id}'
      and (not (p_event#>'{attribution}') ? 'adset_id'
        or c.provider_adset_id=p_event#>>'{attribution,adset_id}')
      and (not (p_event#>'{attribution}') ? 'ad_id'
        or c.provider_ad_id=p_event#>>'{attribution,ad_id}')
    limit 1;
    if not found then
      raise exception 'PANDORA_GROWTH_OUTCOME_PROVIDER_ATTRIBUTION_UNBOUND' using errcode='42501';
    end if;
  elsif p_event#>>'{attribution,kind}'<>'unattributed' then
    raise exception 'PANDORA_GROWTH_OUTCOME_ATTRIBUTION_INVALID' using errcode='22023';
  end if;

  v_amount:=case when p_event ? 'money' then
    (p_event#>>'{money,amount_minor}')::bigint else null end;
  v_currency:=case when p_event ? 'money' then
    p_event#>>'{money,currency}' else null end;

  insert into public.pandora_growth_outcome_receipts(
    organization_id,tracking_tenant_id,project_id,event_name,event_id,outcome_id,
    acquisition_path,journey_id,subject_id,occurred_at,delivery_source,evidence,
    attribution,amount_minor,currency,retention,claim_sha256
  ) values (
    v_org,v_tenant,v_project,p_event->>'event_name',p_event->>'event_id',
    p_event->>'outcome_id',p_event->>'acquisition_path',p_event->>'journey_id',
    p_event->>'subject_id',(p_event->>'occurred_at')::timestamptz,
    p_event->>'delivery_source',p_event->'evidence',p_event->'attribution',
    v_amount,v_currency,p_event->'retention',p_claim_sha256
  ) returning id into v_receipt_id;

  v_event_type:=case p_event->>'event_name'
    when 'lead_submitted' then 'lead'
    when 'lead_qualified' then 'qualified_lead'
    when 'demo_completed' then 'booking'
    when 'payment_settled' then 'sale'
    when 'refund_settled' then 'refund'
    else 'event'
  end;

  insert into public.pandora_tracking_events(
    tenant_id,campaign_id,click_id,event_type,event_name,source,
    external_event_id,value,currency,occurred_at,metadata,
    schema_version,consent,is_test
  ) values (
    v_tenant,v_campaign_id,v_click_id,v_event_type,p_event->>'event_name','server',
    p_event->>'event_id',null,null,(p_event->>'occurred_at')::timestamptz,
    '{}'::jsonb,1,'{"analytics":false,"marketing":false}'::jsonb,false
  )
  on conflict (tenant_id,event_name,external_event_id)
    where external_event_id is not null do nothing;

  select e.id into v_tracking_event_id
  from public.pandora_tracking_events e
  where e.tenant_id=v_tenant and e.event_name=p_event->>'event_name'
    and e.external_event_id=p_event->>'event_id'
  limit 1;

  return jsonb_build_object(
    'ok',true,'duplicate',false,'receiptId',v_receipt_id,
    'trackingEventId',v_tracking_event_id,
    'moneyProjection','minor_units_only'
  );
end;
$function$;
revoke all on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  from public,anon,authenticated;
grant execute on function public.pandora_ingest_growth_outcome_v1(jsonb,text,text)
  to service_role;

create or replace function public.pandora_meta_import_campaign_costs_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_binding_id uuid,
  p_since date,
  p_until date
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_runtime jsonb;
  v_token text;
  v_body jsonb;
  v_row jsonb;
  v_imported integer:=0;
  v_omitted integer:=0;
  v_day date;
  v_spend numeric;
  v_impressions bigint;
  v_clicks bigint;
  v_external text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_COST_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_since is null or p_until is null or p_since>p_until
    or p_until-p_since>31 then
    raise exception 'PANDORA_META_COST_WINDOW_INVALID' using errcode='22023';
  end if;
  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.id=p_binding_id and b.organization_id=p_organization_id
    and b.project_id=p_project_id and b.meta_campaign_id is not null
    and b.binding_state in ('campaign_bound','verified')
  for update;
  if not found then
    raise exception 'PANDORA_META_COST_BINDING_REQUIRED' using errcode='42501';
  end if;

  v_runtime:=public.pandora_meta_runtime_secret_v1(
    p_organization_id,v_binding.installation_id,'marketing'
  );
  v_token:=v_runtime->>'token';
  v_body:=private.pandora_meta_measurement_graph_get_v1(
    v_token,
    v_binding.meta_campaign_id||
      '?fields=id&limit=1'
  );
  if v_body->>'id' is distinct from v_binding.meta_campaign_id then
    raise exception 'PANDORA_META_COST_CAMPAIGN_MISMATCH' using errcode='42501';
  end if;
  v_body:=private.pandora_meta_measurement_graph_get_v1(
    v_token,
    v_binding.meta_campaign_id||
      '/insights?fields=spend,impressions,clicks,date_start,date_stop&time_increment=1&limit=100&time_range=%7B%22since%22%3A%22'||
      p_since::text||'%22%2C%22until%22%3A%22'||p_until::text||'%22%7D'
  );
  v_token:=null;

  for v_row in select value from jsonb_array_elements(coalesce(v_body->'data','[]'::jsonb))
  loop
    if coalesce(v_row->>'date_start','') !~ '^\d{4}-\d{2}-\d{2}$'
      or coalesce(v_row->>'spend','') !~ '^\d+(\.\d+)?$'
      or coalesce(v_row->>'impressions','') !~ '^\d+$'
      or coalesce(v_row->>'clicks','') !~ '^\d+$' then
      v_omitted:=v_omitted+1;
      continue;
    end if;
    v_day:=(v_row->>'date_start')::date;
    v_spend:=(v_row->>'spend')::numeric;
    v_impressions:=(v_row->>'impressions')::bigint;
    v_clicks:=(v_row->>'clicks')::bigint;
    v_external:='meta:'||v_binding.meta_campaign_id||':'||v_day::text||':'||
      v_binding.account_currency;

    insert into public.pandora_tracking_costs(
      tenant_id,campaign_id,provider,external_record_id,bucket_date,spend,
      impressions,provider_clicks,currency,metadata
    ) values (
      v_binding.tracking_tenant_id,v_binding.tracking_campaign_id,'meta',
      v_external,v_day,v_spend,v_impressions,v_clicks,
      v_binding.account_currency,'{}'::jsonb
    )
    on conflict(tenant_id,provider,external_record_id) do update
    set campaign_id=excluded.campaign_id,bucket_date=excluded.bucket_date,
        spend=excluded.spend,impressions=excluded.impressions,
        provider_clicks=excluded.provider_clicks,currency=excluded.currency,
        metadata='{}'::jsonb,updated_at=clock_timestamp();
    v_imported:=v_imported+1;
  end loop;

  update private.pandora_meta_measurement_bindings
  set last_cost_sync_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_binding.id;

  return jsonb_build_object(
    'ok',true,'importedDays',v_imported,'omittedUnknownRows',v_omitted,
    'currency',v_binding.account_currency,'since',p_since,'until',p_until,
    'missingIsZero',false
  );
end;
$function$;
revoke all on function public.pandora_meta_import_campaign_costs_v1(uuid,uuid,uuid,date,date)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_import_campaign_costs_v1(uuid,uuid,uuid,date,date)
  to service_role;

create or replace function public.pandora_meta_register_conversion_match_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_event_id uuid,
  p_policy_version text,
  p_em_sha256 text[] default '{}',
  p_ph_sha256 text[] default '{}',
  p_external_id_sha256 text[] default '{}'
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare v_value text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_MATCH_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,p_policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_MATCH_PRIVACY_HOLD' using errcode='42501';
  end if;
  if cardinality(coalesce(p_em_sha256,'{}'))+
     cardinality(coalesce(p_ph_sha256,'{}'))+
     cardinality(coalesce(p_external_id_sha256,'{}'))<1 then
    raise exception 'PANDORA_META_MATCH_KEY_REQUIRED' using errcode='22023';
  end if;
  foreach v_value in array coalesce(p_em_sha256,'{}')||coalesce(p_ph_sha256,'{}')||
    coalesce(p_external_id_sha256,'{}')
  loop
    if v_value !~ '^[0-9a-f]{64}$' then
      raise exception 'PANDORA_META_MATCH_KEY_INVALID' using errcode='22023';
    end if;
  end loop;
  if not exists(
    select 1 from public.pandora_tracking_events e
    join public.pandora_tracking_tenants t on t.id=e.tenant_id
    where e.id=p_tracking_event_id and t.organization_id=p_organization_id
      and t.project_id=p_project_id and e.source='server'
  ) then
    raise exception 'PANDORA_META_MATCH_EVENT_SCOPE_DENIED' using errcode='42501';
  end if;

  insert into private.pandora_meta_conversion_match_keys(
    tracking_event_id,organization_id,project_id,policy_version,
    em_sha256,ph_sha256,external_id_sha256
  ) values (
    p_tracking_event_id,p_organization_id,p_project_id,p_policy_version,
    coalesce(p_em_sha256,'{}'),coalesce(p_ph_sha256,'{}'),
    coalesce(p_external_id_sha256,'{}')
  )
  on conflict(tracking_event_id) do update
  set policy_version=excluded.policy_version,em_sha256=excluded.em_sha256,
      ph_sha256=excluded.ph_sha256,external_id_sha256=excluded.external_id_sha256;
  return jsonb_build_object('ok',true,'trackingEventId',p_tracking_event_id);
end;
$function$;
revoke all on function public.pandora_meta_register_conversion_match_v1(
  uuid,uuid,uuid,text,text[],text[],text[]
) from public,anon,authenticated;
grant execute on function public.pandora_meta_register_conversion_match_v1(
  uuid,uuid,uuid,text,text[],text[],text[]
) to service_role;

create or replace function public.pandora_meta_enqueue_conversion_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_event_id uuid,
  p_binding_id uuid,
  p_policy_version text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_event public.pandora_tracking_events%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_match private.pandora_meta_conversion_match_keys%rowtype;
  v_meta_name text;
  v_id uuid;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_CONVERSION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,p_policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_CONVERSION_PRIVACY_HOLD' using errcode='42501';
  end if;

  select e.* into v_event
  from public.pandora_tracking_events e
  join public.pandora_tracking_tenants t on t.id=e.tenant_id
  where e.id=p_tracking_event_id and t.organization_id=p_organization_id
    and t.project_id=p_project_id and e.source='server'
    and e.external_event_id is not null
    and e.is_test is false
    and coalesce((e.consent->>'marketing')::boolean,false) is true
    and e.event_type in ('lead','qualified_lead','booking','sale')
  for update of e;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_EVENT_INELIGIBLE' using errcode='42501';
  end if;

  select * into v_binding
  from private.pandora_meta_measurement_bindings b
  where b.id=p_binding_id and b.organization_id=p_organization_id
    and b.project_id=p_project_id and b.tracking_tenant_id=v_event.tenant_id
  for share;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_BINDING_DENIED' using errcode='42501';
  end if;

  select * into v_match
  from private.pandora_meta_conversion_match_keys m
  where m.tracking_event_id=v_event.id and m.organization_id=p_organization_id
    and m.project_id=p_project_id and m.policy_version=p_policy_version;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_MATCH_REQUIRED' using errcode='42501';
  end if;

  v_meta_name:=case v_event.event_type
    when 'lead' then 'Lead'
    when 'qualified_lead' then 'Lead'
    when 'booking' then 'Schedule'
    when 'sale' then 'Purchase'
  end;

  insert into private.pandora_meta_conversion_outbox(
    organization_id,project_id,tracking_event_id,binding_id,policy_version,
    event_id,meta_event_name
  ) values (
    p_organization_id,p_project_id,v_event.id,v_binding.id,p_policy_version,
    v_event.external_event_id,v_meta_name
  )
  on conflict(organization_id,event_id) do update
  set updated_at=private.pandora_meta_conversion_outbox.updated_at
  returning id into v_id;
  return jsonb_build_object('ok',true,'outboxId',v_id,'state','pending');
end;
$function$;
revoke all on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_enqueue_conversion_v1(uuid,uuid,uuid,uuid,text)
  to service_role;

create or replace function public.pandora_meta_dispatch_conversion_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_outbox_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','extensions'
as $function$
declare
  v_outbox private.pandora_meta_conversion_outbox%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_event public.pandora_tracking_events%rowtype;
  v_match private.pandora_meta_conversion_match_keys%rowtype;
  v_runtime jsonb;
  v_token text;
  v_user_data jsonb:='{}'::jsonb;
  v_event_payload jsonb;
  v_response extensions.http_response;
  v_body jsonb:='{}'::jsonb;
  v_success boolean:=false;
  v_attempt integer;
  v_next_state text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'PANDORA_META_CONVERSION_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  select * into v_outbox
  from private.pandora_meta_conversion_outbox o
  where o.id=p_outbox_id and o.organization_id=p_organization_id
    and o.project_id=p_project_id
  for update;
  if not found then
    raise exception 'PANDORA_META_CONVERSION_OUTBOX_NOT_FOUND' using errcode='P0002';
  end if;
  if v_outbox.state='delivered' then
    return jsonb_build_object('ok',true,'state','delivered','duplicate',true);
  end if;
  if v_outbox.state='dead_letter' or v_outbox.attempt_count>=5
    or v_outbox.next_attempt_at>clock_timestamp() then
    raise exception 'PANDORA_META_CONVERSION_NOT_DISPATCHABLE' using errcode='42501';
  end if;
  if not private.pandora_growth_privacy_active_v1(
    p_organization_id,p_project_id,v_outbox.policy_version,'provider_matching'
  ) then
    raise exception 'PANDORA_META_CONVERSION_PRIVACY_HOLD' using errcode='42501';
  end if;

  select * into v_binding
  from private.pandora_meta_measurement_bindings
  where id=v_outbox.binding_id and organization_id=p_organization_id
    and project_id=p_project_id;
  select * into v_event from public.pandora_tracking_events
  where id=v_outbox.tracking_event_id;
  select * into v_match from private.pandora_meta_conversion_match_keys
  where tracking_event_id=v_event.id and organization_id=p_organization_id
    and project_id=p_project_id and policy_version=v_outbox.policy_version;
  if v_binding.id is null or v_event.id is null or v_match.tracking_event_id is null then
    raise exception 'PANDORA_META_CONVERSION_LINEAGE_INVALID' using errcode='42501';
  end if;

  if cardinality(v_match.em_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('em',to_jsonb(v_match.em_sha256)); end if;
  if cardinality(v_match.ph_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('ph',to_jsonb(v_match.ph_sha256)); end if;
  if cardinality(v_match.external_id_sha256)>0 then v_user_data:=v_user_data||jsonb_build_object('external_id',to_jsonb(v_match.external_id_sha256)); end if;

  v_event_payload:=jsonb_build_object(
    'event_name',v_outbox.meta_event_name,
    'event_time',floor(extract(epoch from v_event.occurred_at))::bigint,
    'action_source','website',
    'event_id',v_outbox.event_id,
    'user_data',v_user_data
  );
  if v_event.event_type='sale' and v_event.value is not null and v_event.currency is not null then
    v_event_payload:=v_event_payload||jsonb_build_object(
      'custom_data',jsonb_build_object('value',v_event.value,'currency',v_event.currency)
    );
  end if;

  v_attempt:=v_outbox.attempt_count+1;
  update private.pandora_meta_conversion_outbox
  set state='submitted',attempt_count=v_attempt,updated_at=clock_timestamp()
  where id=v_outbox.id;

  begin
    v_runtime:=public.pandora_meta_runtime_secret_v1(
      p_organization_id,v_binding.installation_id,'marketing'
    );
    v_token:=v_runtime->>'token';
    select * into v_response
    from extensions.http((
      'POST'::extensions.http_method,
      ('https://graph.facebook.com/v26.0/'||v_binding.pixel_id||'/events')::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('content-type','application/json'),
        extensions.http_header('user-agent','Pandora-Facebook-Conversion/1.0')
      ]::extensions.http_header[],
      'application/json'::varchar,
      jsonb_build_object('data',jsonb_build_array(v_event_payload))::text::varchar
    )::extensions.http_request);
    v_token:=null;
    begin
      v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb);
    exception when others then
      v_body:='{}'::jsonb;
    end;
    v_success:=v_response.status=200
      and coalesce((v_body->>'events_received')::integer,0)>=1
      and not (v_body ? 'error');
  exception when others then
    v_token:=null;
    v_success:=false;
    v_body:='{}'::jsonb;
    v_response.status:=null;
  end;

  v_next_state:=case when v_success then 'delivered'
    when v_attempt>=5 then 'dead_letter' else 'pending' end;
  update private.pandora_meta_conversion_outbox
  set state=v_next_state,
      last_http_status=v_response.status,
      provider_receipt=case when v_success then jsonb_build_object(
        'eventsReceived',coalesce((v_body->>'events_received')::integer,0),
        'traceId',nullif(v_body->>'fbtrace_id','')
      ) else null end,
      last_error_code=case when v_success then null else 'provider_delivery_failed' end,
      next_attempt_at=case when v_success or v_attempt>=5 then next_attempt_at
        else clock_timestamp()+make_interval(secs=>least(3600,60*(2^(v_attempt-1)))) end,
      delivered_at=case when v_success then clock_timestamp() else null end,
      updated_at=clock_timestamp()
  where id=v_outbox.id;

  return jsonb_build_object(
    'ok',v_success,'state',v_next_state,'attempt',v_attempt,
    'httpStatus',v_response.status,'eventId',v_outbox.event_id
  );
end;
$function$;
revoke all on function public.pandora_meta_dispatch_conversion_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_meta_dispatch_conversion_v1(uuid,uuid,uuid)
  to service_role;

create or replace view public.pandora_facebook_measurement_status_v1 as
select
  t.organization_id,t.project_id,t.id as tracking_tenant_id,
  c.id as tracking_campaign_id,c.slug,c.name as tracking_campaign_name,
  c.provider_campaign_id,c.provider_adset_id,c.provider_ad_id,
  b.id as binding_id,b.ad_account_id,b.pixel_id,b.binding_state,
  b.account_currency,b.account_timezone,b.verified_at,b.last_cost_sync_at,
  exists(
    select 1 from public.pandora_growth_privacy_authorizations a
    where a.organization_id=t.organization_id and a.project_id=t.project_id
      and a.active is true and (a.expires_at is null or a.expires_at>clock_timestamp())
      and 'server_outcomes'=any(a.allowed_flows)
  ) as server_outcomes_authorized,
  exists(
    select 1 from public.pandora_growth_privacy_authorizations a
    where a.organization_id=t.organization_id and a.project_id=t.project_id
      and a.active is true and (a.expires_at is null or a.expires_at>clock_timestamp())
      and 'provider_matching'=any(a.allowed_flows)
  ) as provider_matching_authorized
from public.pandora_tracking_tenants t
join public.pandora_tracking_campaigns c on c.tenant_id=t.id
left join private.pandora_meta_measurement_bindings b
  on b.organization_id=t.organization_id and b.tracking_campaign_id=c.id
where c.provider='meta';

revoke all on public.pandora_facebook_measurement_status_v1 from public,anon,authenticated;
grant select on public.pandora_facebook_measurement_status_v1 to service_role;

comment on table public.pandora_growth_privacy_authorizations is
  'Explicit owner/privacy approval ledger. No row is seeded by the Facebook measurement release.';
comment on table public.pandora_growth_outcome_receipts is
  'Authoritative normalized FB003 outcome receipts; monetary values remain integer minor units.';
comment on table private.pandora_meta_conversion_outbox is
  'Consent/privacy-gated Meta CAPI delivery queue. Stable event_id provides provider deduplication; five attempts dead-letter.';
