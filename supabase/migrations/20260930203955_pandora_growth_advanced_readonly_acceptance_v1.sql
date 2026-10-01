
begin;

create or replace function public.pandora_growth_variant_lineage_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_variant_key text
) returns jsonb
language sql
security definer
set search_path='pg_catalog','public','private'
as $function$
  with v as (
    select *
    from public.pandora_growth_funnel_variants
    where organization_id=p_organization_id
      and project_id=p_project_id
      and variant_key=p_variant_key
    order by created_at desc
    limit 1
  ),
  obs as (
    select o.stage,count(*)::int as n,
           jsonb_agg(o.source_ref order by o.observed_at) refs
    from private.pandora_growth_variant_observations o
    join v on v.id=o.variant_id
    where o.organization_id=p_organization_id
      and o.project_id=p_project_id
    group by o.stage
  ),
  stages as (
    select unnest(array['ad','page','signup','preview','payment']::text[]) stage
  )
  select jsonb_build_object(
    'ok',exists(select 1 from v),
    'variant',coalesce((select jsonb_build_object(
      'id',id,'variantKey',variant_key,'version',version,
      'offerVersion',offer_version,'destinationVersion',destination_version,
      'onboardingVersion',onboarding_version,'deploymentVersion',deployment_version,
      'stageRefs',stage_refs,'trackingCampaignId',tracking_campaign_id,'status',status
    ) from v),'{}'::jsonb),
    'stageObservations',coalesce((select jsonb_object_agg(stage,jsonb_build_object('count',n,'refs',refs)) from obs),'{}'::jsonb),
    'missingStages',coalesce((select jsonb_agg(stage order by stage) from stages s where not exists(select 1 from obs where obs.stage=s.stage)),'[]'::jsonb),
    'mixedVariantEvidence',false,
    'unknownStagesRemainUnknown',true,
    'businessOutcomeClaimed',false
  );
$function$;
revoke all on function public.pandora_growth_variant_lineage_v1(uuid,uuid,text)
from public,anon,authenticated;
grant execute on function public.pandora_growth_variant_lineage_v1(uuid,uuid,text)
to service_role;

create or replace function public.pandora_growth_client_scope_validate_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_tracking_tenant_id uuid,
  p_template_key text,
  p_template_version text
) returns jsonb
language sql
security definer
set search_path='pg_catalog','public'
as $function$
  select jsonb_build_object(
    'ok',
      exists(
        select 1 from public.pandora_tracking_tenants t
        where t.id=p_tracking_tenant_id
          and t.organization_id=p_organization_id
          and t.project_id=p_project_id
          and t.status='active'
      )
      and exists(
        select 1 from public.pandora_growth_client_provisioning_templates p
        where p.template_key=p_template_key
          and p.version=p_template_version
          and p.status='approved'
          and p.cross_tenant_allowed=false
      ),
    'tenantScopeExact',
      exists(
        select 1 from public.pandora_tracking_tenants t
        where t.id=p_tracking_tenant_id
          and t.organization_id=p_organization_id
          and t.project_id=p_project_id
          and t.status='active'
      ),
    'templateApproved',
      exists(
        select 1 from public.pandora_growth_client_provisioning_templates p
        where p.template_key=p_template_key
          and p.version=p_template_version
          and p.status='approved'
      ),
    'crossTenantAllowed',false
  );
$function$;
revoke all on function public.pandora_growth_client_scope_validate_v1(uuid,uuid,uuid,text,text)
from public,anon,authenticated;
grant execute on function public.pandora_growth_client_scope_validate_v1(uuid,uuid,uuid,text,text)
to service_role;

create or replace function public.pandora_growth_lifecycle_status_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language sql
security definer
set search_path='pg_catalog','public','private'
as $function$
  with p as (
    select *
    from public.pandora_growth_data_lifecycle_policies
    where organization_id=p_organization_id
      and project_id=p_project_id
      and status='approved'
    order by approved_at desc
    limit 1
  ),
  fk as (
    select
      bool_or(c.conrelid='public.pandora_growth_client_contexts'::regclass and c.confdeltype='c') as tenant_context_cascade,
      bool_or(c.conrelid='private.pandora_growth_client_context_events'::regclass and c.confdeltype='c') as context_event_cascade
    from pg_constraint c
    where c.contype='f'
      and c.conrelid in (
        'public.pandora_growth_client_contexts'::regclass,
        'private.pandora_growth_client_context_events'::regclass
      )
  )
  select jsonb_build_object(
    'ok',exists(select 1 from p),
    'policyVersion',(select version from p),
    'retentionState',(select retention_state from p),
    'erasureMode',(select erasure_mode from p),
    'rawCustomerDataCrossTenant',coalesce((select raw_customer_data_cross_tenant from p),false),
    'crossClientLearning',coalesce((select cross_client_learning from p),false),
    'generalizedLearningRequiresSeparateApproval',coalesce((select generalized_learning_requires_separate_approval from p),true),
    'tenantContextCascade',coalesce((select tenant_context_cascade from fk),false),
    'contextEventCascade',coalesce((select context_event_cascade from fk),false),
    'rawCrossClientTransferAllowed',false
  );
$function$;
revoke all on function public.pandora_growth_lifecycle_status_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function public.pandora_growth_lifecycle_status_v1(uuid,uuid)
to service_role;

commit;
;
