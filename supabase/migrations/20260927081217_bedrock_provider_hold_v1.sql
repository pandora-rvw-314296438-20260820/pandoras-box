-- Bedrock provider hold after live invocation probes on 2026-09-27.
-- The discovery catalog remains registered, but no model is routable until a real
-- Bedrock Converse canary is accepted by AWS. This prevents control-plane
-- availability metadata from being mistaken for runtime availability.

alter table private.pandora_bedrock_reasoning_catalog
  add column if not exists runtime_state text not null default 'discovered',
  add column if not exists runtime_reason text,
  add column if not exists runtime_observed_at timestamptz;

alter table private.pandora_bedrock_reasoning_catalog
  drop constraint if exists pandora_bedrock_reasoning_catalog_runtime_state_check;

alter table private.pandora_bedrock_reasoning_catalog
  add constraint pandora_bedrock_reasoning_catalog_runtime_state_check
  check (runtime_state in (
    'discovered','provider_hold','account_denied','onboarding_required',
    'throttled','verified_available'
  ));

update private.pandora_bedrock_reasoning_catalog
set runtime_state = case
      when model_id in ('openai.gpt-6-astra','moonshotai.kimi-k3','xai.grok-4.6')
        then 'account_denied'
      when provider_name='Anthropic'
        then 'onboarding_required'
      else 'provider_hold'
    end,
    runtime_reason = case
      when model_id='openai.gpt-6-astra'
        then 'bedrock_converse_access_denied_not_available_for_account'
      when model_id in ('moonshotai.kimi-k3','xai.grok-4.6')
        then 'bedrock_converse_access_denied_not_available_for_account'
      when provider_name='Anthropic'
        then 'anthropic_use_case_details_required'
      else 'live_provider_canary_not_accepted'
    end,
    runtime_observed_at = clock_timestamp();

do $body$
declare
  v_policy jsonb;
  v_models jsonb;
begin
  select policy into v_policy
  from private.pandora_ops_inference_policies
  where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
    and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
    and active=true
  for update;

  if v_policy is not null then
    select jsonb_agg(
      jsonb_set(model,'{available}','false'::jsonb,false)
      order by model->>'model'
    )
    into v_models
    from jsonb_array_elements(v_policy->'models') model;

    if jsonb_array_length(v_models)<>72 then
      raise exception 'BEDROCK_PROVIDER_HOLD_MODEL_COUNT_MISMATCH';
    end if;

    update private.pandora_ops_inference_policies
    set policy=jsonb_set(
          jsonb_set(v_policy,'{version}',to_jsonb('bedrock-reasoning-fleet-v1-held'::text),false),
          '{models}',v_models,false
        ),
        approval_ref='provider-hold:2026-09-27:bedrock-live-canary-unavailable'
    where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      and project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid
      and active=true;
  end if;
end;
$body$;

insert into public.pandora_runtime_provider_configs(
  provider,config_key,config_value,active,updated_at
) values
  ('bedrock','routing_eligible','false',true,clock_timestamp()),
  ('bedrock','runtime_state','held',true,clock_timestamp()),
  ('bedrock','runtime_hold_reason','provider_canary_not_accepted',true,clock_timestamp()),
  ('bedrock','astra_runtime_state','account_denied',true,clock_timestamp()),
  ('bedrock','anthropic_runtime_state','use_case_form_required',true,clock_timestamp()),
  ('bedrock','other_runtime_state','daily_token_throttle_or_unverified',true,clock_timestamp()),
  ('bedrock','default_model','openai.gpt-oss-20b-1:0',true,clock_timestamp()),
  ('bedrock','fast_model','openai.gpt-oss-20b-1:0',true,clock_timestamp())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,
    active=true,
    updated_at=clock_timestamp();

comment on column private.pandora_bedrock_reasoning_catalog.runtime_state is
  'Runtime truth from actual provider probes; discovery/authorization alone is not enough to mark a model available.';
