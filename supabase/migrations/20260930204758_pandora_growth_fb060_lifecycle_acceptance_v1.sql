
begin;

create table if not exists private.pandora_growth_lifecycle_acceptance_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  test_key text not null unique,
  synthetic_only boolean not null check (synthetic_only is true),
  customer_data_used boolean not null check (customer_data_used is false),
  valid_scope_inserted boolean not null,
  wrong_tenant_denied boolean not null,
  child_events_before_erasure integer not null,
  child_events_after_erasure integer not null,
  cross_client_learning boolean not null check (cross_client_learning is false),
  raw_customer_data_cross_tenant boolean not null check (raw_customer_data_cross_tenant is false),
  generalized_learning_requires_separate_approval boolean not null check (generalized_learning_requires_separate_approval is true),
  result text not null check (result in ('pass','fail')),
  details jsonb not null check(jsonb_typeof(details)='object'),
  created_at timestamptz not null default clock_timestamp()
);
alter table private.pandora_growth_lifecycle_acceptance_receipts enable row level security;
revoke all on private.pandora_growth_lifecycle_acceptance_receipts from public,anon,authenticated,service_role;

delete from private.pandora_growth_lifecycle_acceptance_receipts
where test_key='fb060-lifecycle-erasure-20261001';

do $block$
declare
  v_template uuid;
  v_context uuid:=gen_random_uuid();
  v_valid boolean:=false;
  v_wrong boolean:=false;
  v_before integer:=0;
  v_after integer:=0;
  v_cross boolean;
  v_raw boolean;
  v_generalized boolean;
  v_detail text:=null;
begin
  select id into strict v_template
  from public.pandora_growth_client_provisioning_templates
  where template_key='pandora-enterprise-growth'
    and version='v1'
    and status='approved'
    and cross_tenant_allowed=false;

  select cross_client_learning,raw_customer_data_cross_tenant,generalized_learning_requires_separate_approval
    into strict v_cross,v_raw,v_generalized
  from public.pandora_growth_data_lifecycle_policies
  where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
    and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
    and status='approved'
  order by approved_at desc
  limit 1;

  delete from public.pandora_growth_client_contexts
  where client_key in ('fb060-synthetic-valid','fb060-synthetic-wrong');

  insert into public.pandora_growth_client_contexts(
    id,organization_id,project_id,tracking_tenant_id,template_id,client_key,status,metadata
  ) values (
    v_context,
    '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
    'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
    '326b51af-0445-4e96-bf31-d346bab05220'::uuid,
    v_template,
    'fb060-synthetic-valid',
    'provisioned',
    '{"syntheticAcceptance":true,"containsCustomerData":false}'::jsonb
  );
  v_valid:=true;

  insert into private.pandora_growth_client_context_events(context_id,event_type,safe_summary)
  values (
    v_context,
    'synthetic_acceptance_event',
    '{"syntheticAcceptance":true,"containsCustomerData":false}'::jsonb
  );

  select count(*)::integer into v_before
  from private.pandora_growth_client_context_events
  where context_id=v_context;

  begin
    insert into public.pandora_growth_client_contexts(
      organization_id,project_id,tracking_tenant_id,template_id,client_key,status,metadata
    ) values (
      '11111111-1111-4111-8111-111111111111'::uuid,
      'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
      '326b51af-0445-4e96-bf31-d346bab05220'::uuid,
      v_template,
      'fb060-synthetic-wrong',
      'provisioned',
      '{"syntheticAcceptance":true,"containsCustomerData":false}'::jsonb
    );
  exception when sqlstate '42501' then
    v_wrong:=true;
  end;

  delete from public.pandora_growth_client_contexts where id=v_context;

  select count(*)::integer into v_after
  from private.pandora_growth_client_context_events
  where context_id=v_context;

  delete from public.pandora_growth_client_contexts
  where client_key='fb060-synthetic-wrong';

  if not v_valid then v_detail:='valid scope insert failed'; end if;
  if not v_wrong then v_detail:=coalesce(v_detail||'; ','')||'wrong tenant was not denied'; end if;
  if v_before<>1 then v_detail:=coalesce(v_detail||'; ','')||'child before erasure count was not 1'; end if;
  if v_after<>0 then v_detail:=coalesce(v_detail||'; ','')||'child after erasure count was not 0'; end if;
  if v_cross is not false or v_raw is not false or v_generalized is not true then
    v_detail:=coalesce(v_detail||'; ','')||'lifecycle policy invariants failed';
  end if;

  insert into private.pandora_growth_lifecycle_acceptance_receipts(
    organization_id,project_id,test_key,synthetic_only,customer_data_used,
    valid_scope_inserted,wrong_tenant_denied,child_events_before_erasure,
    child_events_after_erasure,cross_client_learning,raw_customer_data_cross_tenant,
    generalized_learning_requires_separate_approval,result,details
  ) values (
    '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
    'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
    'fb060-lifecycle-erasure-20261001',
    true,false,v_valid,v_wrong,v_before,v_after,v_cross,v_raw,v_generalized,
    case when v_valid and v_wrong and v_before=1 and v_after=0 and v_cross=false and v_raw=false and v_generalized=true then 'pass' else 'fail' end,
    jsonb_build_object(
      'containsCustomerData',false,
      'validContextDeleted',true,
      'wrongTenantContextPersisted',false,
      'erasureMode','context_cascade',
      'failureDetail',v_detail
    )
  );
end
$block$;

commit;
;
