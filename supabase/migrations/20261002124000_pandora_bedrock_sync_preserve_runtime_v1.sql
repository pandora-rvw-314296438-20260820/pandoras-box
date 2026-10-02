begin;
create or replace function public.pandora_sync_bedrock_catalog_v1(p_snapshot jsonb) returns jsonb
language plpgsql security definer set search_path='pg_catalog','private','public','pg_temp'
as $$
declare
  m jsonb;
  o timestamptz;
  r text;
  st text;
  rs text;
  n int:=0;
  c int:=0;
  prev private.pandora_bedrock_reasoning_catalog%rowtype;
  same_target boolean;
  runtime_status text;
  tested_at timestamptz;
  is_routable boolean;
  probe_http integer;
  probe_in bigint;
  probe_out bigint;
  probe_total bigint;
  cost_micros bigint;
  cost_status text;
  cost_source text;
  conversational boolean;
  target text;
begin
  if session_user not in('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role'
  then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
  if jsonb_typeof(p_snapshot->'models')<>'array'
     or jsonb_array_length(p_snapshot->'models') not between 1 and 500
  then raise exception 'BEDROCK_SNAPSHOT_INVALID'; end if;
  o:=(p_snapshot->>'observedAt')::timestamptz;
  r:=coalesce(nullif(p_snapshot->>'region',''),'us-east-1');

  for m in select value from jsonb_array_elements(p_snapshot->'models') loop
    if coalesce(m->>'modelId','')!~'^[A-Za-z0-9][A-Za-z0-9._:-]{1,159}$' then continue; end if;
    conversational:=coalesce((m->>'conversational')::boolean,false);
    target:=nullif(m->>'invocationTarget','');
    st:=case
      when coalesce(m->>'lifecycleStatus','UNKNOWN')<>'ACTIVE' then 'retired'
      when coalesce(m->>'authorizationStatus','UNKNOWN')<>'AUTHORIZED' then 'discovered'
      when coalesce(m->>'agreementStatus','UNKNOWN')<>'AVAILABLE'
        or coalesce(m->>'entitlementStatus','UNKNOWN')<>'AVAILABLE' then 'authorized'
      when coalesce(m->>'regionAvailability','UNKNOWN')<>'AVAILABLE' then 'entitled'
      else 'region_available'
    end;
    rs:=case
      when st='retired' then 'lifecycle_'||lower(coalesce(m->>'lifecycleStatus','unknown'))
      when st='discovered' then 'authorization_'||lower(coalesce(m->>'authorizationStatus','unknown'))
      when coalesce(m->>'agreementStatus','UNKNOWN')<>'AVAILABLE' then 'agreement_'||lower(coalesce(m->>'agreementStatus','unknown'))
      when coalesce(m->>'entitlementStatus','UNKNOWN')<>'AVAILABLE' then 'entitlement_'||lower(coalesce(m->>'entitlementStatus','unknown'))
      when st='entitled' then 'region_'||lower(coalesce(m->>'regionAvailability','unknown'))
      when target is null then 'invocation_target_unresolved'
      else 'runtime_probe_required'
    end;

    prev:=null;
    select x.* into prev
    from private.pandora_bedrock_reasoning_catalog x
    where x.model_id=m->>'modelId';
    same_target:=found and prev.invocation_target is not distinct from target;

    runtime_status:=case when same_target then prev.runtime_verification_status else 'untested' end;
    tested_at:=case when same_target then prev.runtime_tested_at else null end;
    probe_http:=case when same_target then prev.probe_http_status else null end;
    probe_in:=case when same_target then prev.probe_input_tokens else null end;
    probe_out:=case when same_target then prev.probe_output_tokens else null end;
    probe_total:=case when same_target then prev.probe_total_tokens else null end;
    cost_micros:=case when same_target then prev.probe_cost_micros else null end;
    cost_status:=case when same_target then prev.probe_cost_status else 'pending_pricing_readback' end;
    cost_source:=case when same_target then prev.probe_pricing_source_ref else null end;
    is_routable:=false;

    if same_target and tested_at is not null and st='region_available' and conversational and target is not null then
      if runtime_status='passed' then
        st:='routable';
        rs:='bounded_runtime_probe_passed';
        is_routable:=true;
      else
        st:='runtime_tested';
        rs:=coalesce(nullif(prev.runtime_reason,''),'runtime_probe_failed');
      end if;
    end if;

    insert into private.pandora_bedrock_reasoning_catalog(
      model_id,model_name,provider_name,invocation_target,input_modalities,output_modalities,inference_types,
      risk_tier,capability_classes,observed_at,source_ref,runtime_state,runtime_reason,runtime_observed_at,
      region,response_streaming_supported,lifecycle_status,lifecycle,agreement_status,authorization_status,
      entitlement_status,region_availability,conversational,present_in_latest_sync,last_verified_at,
      runtime_verification_status,runtime_tested_at,routable,probe_http_status,probe_input_tokens,
      probe_output_tokens,probe_total_tokens,probe_cost_micros,probe_cost_status,probe_pricing_source_ref
    ) values(
      m->>'modelId',coalesce(nullif(m->>'modelName',''),m->>'modelId'),
      coalesce(nullif(m->>'providerName',''),'Unknown'),target,
      array(select jsonb_array_elements_text(coalesce(m->'inputModalities','[]'))),
      array(select jsonb_array_elements_text(coalesce(m->'outputModalities','[]'))),
      array(select jsonb_array_elements_text(coalesce(m->'inferenceTypes','[]'))),
      1,array(select jsonb_array_elements_text(coalesce(m->'capabilityClasses','[]'))),
      o,coalesce(nullif(m->>'sourceRef',''),'aws:bedrock:live-catalog-v2'),
      st,rs,o,r,coalesce((m->>'responseStreamingSupported')::boolean,false),
      coalesce(m->>'lifecycleStatus','UNKNOWN'),coalesce(m->'lifecycle','{}'),
      coalesce(m->>'agreementStatus','UNKNOWN'),coalesce(m->>'authorizationStatus','UNKNOWN'),
      coalesce(m->>'entitlementStatus','UNKNOWN'),coalesce(m->>'regionAvailability','UNKNOWN'),
      conversational,true,o,runtime_status,tested_at,is_routable,probe_http,probe_in,probe_out,probe_total,
      cost_micros,cost_status,cost_source
    )
    on conflict(model_id) do update set
      model_name=excluded.model_name,provider_name=excluded.provider_name,
      invocation_target=excluded.invocation_target,input_modalities=excluded.input_modalities,
      output_modalities=excluded.output_modalities,inference_types=excluded.inference_types,
      capability_classes=excluded.capability_classes,observed_at=excluded.observed_at,
      source_ref=excluded.source_ref,runtime_state=excluded.runtime_state,
      runtime_reason=excluded.runtime_reason,runtime_observed_at=excluded.runtime_observed_at,
      region=excluded.region,response_streaming_supported=excluded.response_streaming_supported,
      lifecycle_status=excluded.lifecycle_status,lifecycle=excluded.lifecycle,
      agreement_status=excluded.agreement_status,authorization_status=excluded.authorization_status,
      entitlement_status=excluded.entitlement_status,region_availability=excluded.region_availability,
      conversational=excluded.conversational,present_in_latest_sync=true,
      last_verified_at=excluded.last_verified_at,
      runtime_verification_status=excluded.runtime_verification_status,
      runtime_tested_at=excluded.runtime_tested_at,routable=excluded.routable,
      probe_http_status=excluded.probe_http_status,probe_input_tokens=excluded.probe_input_tokens,
      probe_output_tokens=excluded.probe_output_tokens,probe_total_tokens=excluded.probe_total_tokens,
      probe_cost_micros=excluded.probe_cost_micros,probe_cost_status=excluded.probe_cost_status,
      probe_pricing_source_ref=excluded.probe_pricing_source_ref;
    n:=n+1;
    if conversational then c:=c+1; end if;
  end loop;

  update private.pandora_bedrock_reasoning_catalog
  set lifecycle_status='REMOVED',runtime_state='retired',
      runtime_reason='not_present_in_latest_aws_catalog',routable=false,
      runtime_observed_at=o,last_verified_at=o,present_in_latest_sync=false
  where observed_at is distinct from o;

  execute 'alter table private.pandora_bedrock_reasoning_catalog validate constraint pandora_bedrock_reasoning_catalog_runtime_state_check';
  return jsonb_build_object('modelCount',n,'conversationalCount',c,'observedAt',o,'region',r);
end;$$;
revoke all on function public.pandora_sync_bedrock_catalog_v1(jsonb) from public,anon,authenticated;
grant execute on function public.pandora_sync_bedrock_catalog_v1(jsonb) to service_role;
commit;
