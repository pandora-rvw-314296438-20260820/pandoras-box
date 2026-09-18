insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active)
values
 ('gemini','enabled','true',true),
 ('gemini','routing_eligible','true',true),
 ('gemini','fallback_enabled','true',true),
 ('gemini','default_model','gemini-3.7-flash',true),
 ('gemini','allowed_models','["gemini-3.5-flash-lite","gemini-3.7-flash","gemini-3.1-pro-preview"]',true),
 ('gemini','task_eligibility','["chat","clarify"]',true),
 ('gemini','preferred_tasks','[]',true),
 ('gemini','policy_version','provider-auto-failover-v4',true),
 ('gemini','stream_mode','buffered_v1',true)
on conflict (provider,config_key) do update
set config_value=excluded.config_value, active=true, updated_at=now();

create or replace function public.pandora_intelligence_model_catalog_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_models jsonb;
begin
  if v_user_id is null then raise exception 'SIGN_IN_REQUIRED'; end if;
  if not exists (
    select 1 from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_user_id
      and m.status='active'
  ) then raise exception 'ORGANIZATION_ACCESS_REQUIRED'; end if;

  with configs as (
    select provider,
      max(config_value) filter (where config_key='enabled') enabled,
      max(config_value) filter (where config_key='routing_eligible') routing_eligible,
      max(config_value) filter (where config_key='default_model') default_model,
      max(config_value) filter (where config_key='allowed_models') allowed_models
    from public.pandora_runtime_provider_configs
    where active=true and provider in ('gemini','openai','kimi','local')
    group by provider
  ),
  expanded as (
    select c.provider,model.value model,c.default_model,
      case c.provider when 'gemini' then 10 when 'openai' then 20 when 'kimi' then 30 when 'local' then 40 else 90 end provider_order
    from configs c
    cross join lateral jsonb_array_elements_text(
      case when c.allowed_models is null or c.allowed_models='' then jsonb_build_array(c.default_model) else c.allowed_models::jsonb end
    ) model(value)
    where c.enabled='true' and c.routing_eligible='true' and model.value is not null
  ),
  decorated as (
    select e.provider,e.model,e.provider_order,e.model=e.default_model is_default,
      case e.model
        when 'gemini-3.5-flash-lite' then 'Gemini 3.5 Flash Lite'
        when 'gemini-3.7-flash' then 'Gemini 3.7 Flash'
        when 'gemini-3.1-pro-preview' then 'Gemini 3.1 Pro Preview'
        when 'gpt-5.6-terra' then 'GPT-5.6 Terra'
        when 'gpt-5.6-luna' then 'GPT-5.6 Luna'
        when 'gpt-5.6-sol' then 'GPT-5.6 Sol'
        when 'kimi-k3' then 'Kimi K3'
        when 'Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M' then 'Qwen2.5 7B Local'
        else e.model end label,
      case when e.provider<>'local' then true else exists (
        select 1 from public.pandora_local_ai_workers w
        where w.model=e.model
          and w.last_seen_at>now()-interval '45 seconds'
          and w.status in ('ready','busy')
      ) end available,
      case when e.provider<>'local' then 'ready' else coalesce((
        select w.status from public.pandora_local_ai_workers w
        where w.model=e.model order by w.last_seen_at desc limit 1
      ),'offline') end state
    from expanded e
  ),
  all_models as (
    select 0 provider_order,0 model_order,jsonb_build_object(
      'provider','auto','model','auto','label','Auto','available',true,
      'state','ready','local',false,'default',true
    ) item
    union all
    select d.provider_order,row_number() over(partition by d.provider order by d.model)::integer,
      jsonb_build_object(
        'provider',d.provider,'model',d.model,'label',d.label,'available',d.available,
        'state',d.state,'local',d.provider='local','default',d.is_default
      )
    from decorated d
  )
  select coalesce(jsonb_agg(item order by provider_order,model_order),'[]'::jsonb)
  into v_models from all_models;

  return jsonb_build_object('models',v_models,'observedAt',now());
end;
$$;

revoke all on function public.pandora_intelligence_model_catalog_v1(uuid) from public, anon;
grant execute on function public.pandora_intelligence_model_catalog_v1(uuid) to authenticated;

comment on function public.pandora_intelligence_model_catalog_v1(uuid) is
  'Returns the safe Pandora Chat model catalog for an authorized organization member.';
