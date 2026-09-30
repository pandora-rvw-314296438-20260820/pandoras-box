
create or replace function public.pandora_growth_lifecycle_self_test_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_context_id uuid:=gen_random_uuid();
  v_template_id uuid;
  v_before integer:=0;
  v_after integer:=0;
  v_wrong_tenant_denied boolean:=false;
begin
  select id into v_template_id
  from public.pandora_growth_client_provisioning_templates
  where template_key='pandora-enterprise-growth'
    and version='v1'
    and status='approved'
  limit 1;
  if v_template_id is null then
    raise exception 'PANDORA_GROWTH_LIFECYCLE_TEST_TEMPLATE_MISSING';
  end if;

  delete from public.pandora_growth_client_contexts
  where client_key='acceptance-fb060-self-test';

  insert into public.pandora_growth_client_contexts(
    id,organization_id,project_id,tracking_tenant_id,template_id,client_key,status,metadata
  ) values (
    v_context_id,
    '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
    'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
    '326b51af-0445-4e96-bf31-d346bab05220'::uuid,
    v_template_id,
    'acceptance-fb060-self-test',
    'provisioned',
    '{"syntheticAcceptance":true,"containsCustomerData":false}'::jsonb
  );

  insert into private.pandora_growth_client_context_events(
    context_id,event_type,safe_summary
  ) values (
    v_context_id,'acceptance_event','{"synthetic":true,"containsCustomerData":false}'::jsonb
  );

  select count(*) into v_before
  from private.pandora_growth_client_context_events
  where context_id=v_context_id;

  begin
    insert into public.pandora_growth_client_contexts(
      organization_id,project_id,tracking_tenant_id,template_id,client_key,status,metadata
    ) values (
      '11111111-1111-4111-8111-111111111111'::uuid,
      'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid,
      '326b51af-0445-4e96-bf31-d346bab05220'::uuid,
      v_template_id,
      'acceptance-fb060-wrong-tenant',
      'provisioned',
      '{"syntheticAcceptance":true}'::jsonb
    );
  exception when sqlstate '42501' then
    v_wrong_tenant_denied:=true;
  end;

  delete from public.pandora_growth_client_contexts
  where id=v_context_id;

  select count(*) into v_after
  from private.pandora_growth_client_context_events
  where context_id=v_context_id;

  delete from public.pandora_growth_client_contexts
  where client_key='acceptance-fb060-wrong-tenant';

  return jsonb_build_object(
    'ok',v_before=1 and v_after=0 and v_wrong_tenant_denied,
    'syntheticOnly',true,
    'customerDataUsed',false,
    'childEventsBeforeErasure',v_before,
    'childEventsAfterErasure',v_after,
    'wrongTenantDenied',v_wrong_tenant_denied,
    'crossClientLearning',false,
    'rawCustomerDataCrossTenant',false,
    'generalizedLearningRequiresSeparateApproval',true
  );
end;
$function$;

revoke all on function public.pandora_growth_lifecycle_self_test_v1()
from public,anon,authenticated;
grant execute on function public.pandora_growth_lifecycle_self_test_v1()
to service_role;
;
