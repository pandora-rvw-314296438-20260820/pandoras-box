
begin;

create or replace function private.pandora_meta_paid_pilot_target_is_allowed_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_installation_id uuid,
  p_target_type text,
  p_target_id text
) returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public','private'
as $function$
  select exists(
    select 1
    from private.pandora_meta_measurement_bindings b
    join public.pandora_tracking_campaigns c
      on c.id=b.tracking_campaign_id
    join private.pandora_meta_paid_pilot_authorizations a
      on a.organization_id=b.organization_id
     and a.project_id=b.project_id
     and a.installation_id=b.installation_id
     and a.tracking_campaign_id=b.tracking_campaign_id
     and a.meta_campaign_id=b.meta_campaign_id
     and a.meta_adset_id=b.meta_adset_id
     and a.meta_ad_id=b.meta_ad_id
    where b.organization_id=p_organization_id
      and b.project_id=p_project_id
      and b.installation_id=p_installation_id
      and b.binding_state='verified'
      and c.status='active'
      and c.metadata->>'purpose'='promote-pandora'
      and c.metadata->'business_kpi' is not distinct from 'true'::jsonb
      and c.metadata->'delivery_authorized' is not distinct from 'false'::jsonb
      and a.currency='PHP'
      and a.max_spend_minor=500000
      and a.daily_budget_minor=40000
      and a.duration_seconds=604800
      and case p_target_type
        when 'campaign' then b.meta_campaign_id=p_target_id
        when 'adset' then b.meta_adset_id=p_target_id
        when 'ad' then b.meta_ad_id=p_target_id
        else false
      end
  );
$function$;

revoke all on function private.pandora_meta_paid_pilot_target_is_allowed_v1(
  uuid,uuid,uuid,text,text
) from public,anon,authenticated,service_role;

update public.pandora_tracking_campaigns
set
  provider_campaign_id='120251929350590047',
  provider_adset_id='120251929352200047',
  provider_ad_id='120251929352870047',
  status='active',
  metadata=metadata||jsonb_build_object(
    'business_kpi',true,
    'purpose','promote-pandora',
    'delivery_authorized',false,
    'paid_pilot_state','stopped',
    'paid_pilot_currency','PHP',
    'paid_pilot_max_spend_minor',500000,
    'paid_pilot_authorization_id','0150939a-5c04-4899-a82c-bb27a539dacf',
    'tracking_mode','business',
    'tracked_redirect','https://mcpmaster.vercel.app/t/pandora-meta-main',
    'provider_creative_ready',false,
    'provider_creative_blocker','meta_app_development_mode'
  ),
  updated_at=clock_timestamp()
where id='683f0b2d-a133-42ff-988c-4dbe0be7ae7e'::uuid;

update public.pandora_tracking_campaigns
set
  provider_campaign_id=null,
  provider_adset_id=null,
  provider_ad_id=null,
  status='paused',
  metadata=metadata||jsonb_build_object(
    'business_kpi',false,
    'purpose','controlled-test',
    'delivery_authorized',false,
    'historical_acceptance',true,
    'historical_provider_campaign_id','120251929350590047',
    'historical_provider_adset_id','120251929352200047',
    'historical_provider_ad_id','120251929352870047',
    'superseded_for_live_delivery_by','683f0b2d-a133-42ff-988c-4dbe0be7ae7e'
  ),
  updated_at=clock_timestamp()
where id='0168f514-db7c-4ce2-a78f-ea7ae2d9f1ec'::uuid;

update private.pandora_meta_measurement_bindings
set
  tracking_campaign_id='683f0b2d-a133-42ff-988c-4dbe0be7ae7e'::uuid,
  provider_evidence=provider_evidence||jsonb_build_object(
    'liveTrackingCampaignId','683f0b2d-a133-42ff-988c-4dbe0be7ae7e',
    'liveTrackingSlug','pandora-meta-main',
    'trackingMode','business',
    'trackedRedirect','https://mcpmaster.vercel.app/t/pandora-meta-main',
    'remappedAt',clock_timestamp()
  ),
  verified_at=clock_timestamp(),
  updated_at=clock_timestamp()
where id='8e916a42-9696-4a64-8926-147830c401f2'::uuid
  and organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid;

update private.pandora_meta_paid_pilot_authorizations
set
  tracking_campaign_id='683f0b2d-a133-42ff-988c-4dbe0be7ae7e'::uuid,
  state='approved',
  prepared_at=null,
  activated_at=null,
  end_at=null,
  stopped_at=null,
  evidence_ref=evidence_ref||'; attribution remapped to pandora-meta-main after end-to-end audit',
  updated_at=clock_timestamp()
where id='0150939a-5c04-4899-a82c-bb27a539dacf'::uuid
  and state='stopped';

do $patch$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.pandora_meta_prepare_paid_pilot_v1(uuid,text)'::regprocedure)
  into v_def;

  if position('private.pandora_meta_zero_delivery_target_is_allowed_v1' in v_def)=0 then
    raise exception 'PANDORA_META_PAID_PILOT_PREPARE_PATCH_BASE_MISMATCH';
  end if;

  v_new:=replace(
    v_def,
    'private.pandora_meta_zero_delivery_target_is_allowed_v1',
    'private.pandora_meta_paid_pilot_target_is_allowed_v1'
  );
  execute v_new;
end
$patch$;

do $assert$
declare
  v_business public.pandora_tracking_campaigns%rowtype;
  v_test public.pandora_tracking_campaigns%rowtype;
  v_binding private.pandora_meta_measurement_bindings%rowtype;
  v_auth private.pandora_meta_paid_pilot_authorizations%rowtype;
  v_def text;
begin
  select * into strict v_business
  from public.pandora_tracking_campaigns
  where id='683f0b2d-a133-42ff-988c-4dbe0be7ae7e'::uuid;
  select * into strict v_test
  from public.pandora_tracking_campaigns
  where id='0168f514-db7c-4ce2-a78f-ea7ae2d9f1ec'::uuid;
  select * into strict v_binding
  from private.pandora_meta_measurement_bindings
  where id='8e916a42-9696-4a64-8926-147830c401f2'::uuid;
  select * into strict v_auth
  from private.pandora_meta_paid_pilot_authorizations
  where id='0150939a-5c04-4899-a82c-bb27a539dacf'::uuid;
  select pg_get_functiondef('public.pandora_meta_prepare_paid_pilot_v1(uuid,text)'::regprocedure)
  into v_def;

  if v_business.provider_campaign_id<>'120251929350590047'
     or v_business.provider_adset_id<>'120251929352200047'
     or v_business.provider_ad_id<>'120251929352870047'
     or v_business.metadata->'business_kpi' is distinct from 'true'::jsonb
     or v_business.metadata->>'tracked_redirect'<>'https://mcpmaster.vercel.app/t/pandora-meta-main'
     or v_test.status<>'paused'
     or v_test.provider_campaign_id is not null
     or v_binding.tracking_campaign_id<>v_business.id
     or v_auth.tracking_campaign_id<>v_business.id
     or v_auth.state<>'approved'
     or position('private.pandora_meta_paid_pilot_target_is_allowed_v1' in v_def)=0
     or position('private.pandora_meta_zero_delivery_target_is_allowed_v1' in v_def)>0 then
    raise exception 'PANDORA_META_BUSINESS_ATTRIBUTION_ASSERTION_FAILED';
  end if;
end
$assert$;

commit;
;
