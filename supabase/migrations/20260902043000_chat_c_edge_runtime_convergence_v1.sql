-- Chat C active Edge/runtime convergence for governed multi-provider chat.
-- Service-role wrappers expose only provider-neutral routing state; Kimi remains disabled by runtime config.

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('kimi','preferred_tasks','[]',true,now()),
  ('kimi','fallback_enabled','true',true,now()),
  ('kimi','stream_mode','buffered_v1',true,now())
on conflict (provider,config_key) do update
set config_value=excluded.config_value, active=excluded.active, updated_at=excluded.updated_at;

create or replace function public.pandora_read_intelligence_thread_route_v1(
  p_thread_id uuid,
  p_organization_id uuid
)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $function$
  select private.pandora_read_intelligence_thread_route_v1(p_thread_id,p_organization_id);
$function$;

create or replace function public.pandora_claim_intelligence_thread_route_v1(
  p_thread_id uuid,
  p_organization_id uuid,
  p_provider text,
  p_model text,
  p_model_version text default null,
  p_routing_policy_version text default null,
  p_reasoning_policy text default null
)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $function$
  select private.pandora_claim_intelligence_thread_route_v1(
    p_thread_id,p_organization_id,p_provider,p_model,p_model_version,p_routing_policy_version,p_reasoning_policy
  );
$function$;

create or replace function public.pandora_recover_intelligence_thread_route_v1(
  p_thread_id uuid,
  p_organization_id uuid,
  p_expected_recovery_epoch integer,
  p_provider text,
  p_model text,
  p_model_version text default null,
  p_routing_policy_version text default null,
  p_reasoning_policy text default null,
  p_last_compatible_message_id uuid default null
)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $function$
  select private.pandora_recover_intelligence_thread_route_v1(
    p_thread_id,p_organization_id,p_expected_recovery_epoch,p_provider,p_model,p_model_version,
    p_routing_policy_version,p_reasoning_policy,p_last_compatible_message_id
  );
$function$;

revoke all on function public.pandora_read_intelligence_thread_route_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function public.pandora_claim_intelligence_thread_route_v1(uuid,uuid,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.pandora_recover_intelligence_thread_route_v1(uuid,uuid,integer,text,text,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.pandora_read_intelligence_thread_route_v1(uuid,uuid) to service_role;
grant execute on function public.pandora_claim_intelligence_thread_route_v1(uuid,uuid,text,text,text,text,text) to service_role;
grant execute on function public.pandora_recover_intelligence_thread_route_v1(uuid,uuid,integer,text,text,text,text,text,uuid) to service_role;

revoke insert, update, delete on public.pandora_runtime_provider_configs from anon, authenticated;

comment on function public.pandora_read_intelligence_thread_route_v1(uuid,uuid) is
  'Service-role Edge wrapper for private provider-neutral chat route state.';
comment on function public.pandora_claim_intelligence_thread_route_v1(uuid,uuid,text,text,text,text,text) is
  'Service-role Edge wrapper for first provider/model claim on a chat thread.';
comment on function public.pandora_recover_intelligence_thread_route_v1(uuid,uuid,integer,text,text,text,text,text,uuid) is
  'Service-role Edge wrapper for explicit cross-provider recovery with epoch CAS.';
