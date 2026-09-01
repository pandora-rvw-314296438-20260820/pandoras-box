-- Chat C: provider-neutral intelligence thread routing state.
-- Keeps provider/model continuity private and service-owned; no raw conversation content or credentials are stored.

create table if not exists private.pandora_intelligence_thread_routing_state (
  thread_id uuid primary key references public.pandora_intelligence_threads(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null,
  model text not null,
  model_version text,
  routing_policy_version text,
  reasoning_policy text,
  stickiness_mode text not null default 'sticky',
  recovery_epoch integer not null default 0,
  last_compatible_message_id uuid references public.pandora_intelligence_messages(id) on delete set null,
  selected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_intelligence_thread_route_provider_check check (provider ~ '^[a-z][a-z0-9_-]{1,31}$'),
  constraint pandora_intelligence_thread_route_model_check check (length(trim(model)) between 1 and 160),
  constraint pandora_intelligence_thread_route_model_version_check check (model_version is null or length(trim(model_version)) between 1 and 160),
  constraint pandora_intelligence_thread_route_policy_version_check check (routing_policy_version is null or length(trim(routing_policy_version)) between 1 and 160),
  constraint pandora_intelligence_thread_route_reasoning_check check (reasoning_policy is null or length(trim(reasoning_policy)) between 1 and 80),
  constraint pandora_intelligence_thread_route_stickiness_check check (stickiness_mode in ('sticky','recovering')),
  constraint pandora_intelligence_thread_route_epoch_check check (recovery_epoch >= 0)
);

create index if not exists pandora_intelligence_thread_route_org_idx
  on private.pandora_intelligence_thread_routing_state(organization_id, updated_at desc);

alter table private.pandora_intelligence_thread_routing_state enable row level security;
revoke all on private.pandora_intelligence_thread_routing_state from public, anon, authenticated;
grant select, insert, update, delete on private.pandora_intelligence_thread_routing_state to service_role;

create or replace function private.pandora_read_intelligence_thread_route_v1(
  p_thread_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;

  select r.* into v_row
  from private.pandora_intelligence_thread_routing_state r
  where r.thread_id = p_thread_id
    and r.organization_id = p_organization_id;

  if not found then return null; end if;
  return jsonb_build_object(
    'provider', v_row.provider,
    'model', v_row.model,
    'modelVersion', v_row.model_version,
    'routingPolicyVersion', v_row.routing_policy_version,
    'reasoningPolicy', v_row.reasoning_policy,
    'stickinessMode', v_row.stickiness_mode,
    'recoveryEpoch', v_row.recovery_epoch,
    'lastCompatibleMessageId', v_row.last_compatible_message_id,
    'selectedAt', v_row.selected_at,
    'updatedAt', v_row.updated_at
  );
end;
$$;

create or replace function private.pandora_claim_intelligence_thread_route_v1(
  p_thread_id uuid,
  p_organization_id uuid,
  p_provider text,
  p_model text,
  p_model_version text default null,
  p_routing_policy_version text default null,
  p_reasoning_policy text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if nullif(trim(p_provider),'') is null or p_provider !~ '^[a-z][a-z0-9_-]{1,31}$' then
    raise exception 'INVALID_PROVIDER' using errcode = '22023';
  end if;
  if nullif(trim(p_model),'') is null or length(trim(p_model)) > 160 then
    raise exception 'INVALID_MODEL' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.pandora_intelligence_threads t
    where t.id = p_thread_id and t.organization_id = p_organization_id and t.status = 'active'
  ) then
    raise exception 'THREAD_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into private.pandora_intelligence_thread_routing_state(
    thread_id, organization_id, provider, model, model_version,
    routing_policy_version, reasoning_policy, stickiness_mode, recovery_epoch
  ) values (
    p_thread_id, p_organization_id, trim(p_provider), trim(p_model), nullif(trim(p_model_version),''),
    nullif(trim(p_routing_policy_version),''), nullif(trim(p_reasoning_policy),''), 'sticky', 0
  )
  on conflict (thread_id) do nothing;

  select r.* into strict v_row
  from private.pandora_intelligence_thread_routing_state r
  where r.thread_id = p_thread_id and r.organization_id = p_organization_id;

  return jsonb_build_object(
    'claimed', v_row.provider = trim(p_provider) and v_row.model = trim(p_model),
    'compatible', v_row.provider = trim(p_provider) and v_row.model = trim(p_model),
    'provider', v_row.provider,
    'model', v_row.model,
    'modelVersion', v_row.model_version,
    'routingPolicyVersion', v_row.routing_policy_version,
    'reasoningPolicy', v_row.reasoning_policy,
    'stickinessMode', v_row.stickiness_mode,
    'recoveryEpoch', v_row.recovery_epoch,
    'lastCompatibleMessageId', v_row.last_compatible_message_id
  );
end;
$$;

create or replace function private.pandora_recover_intelligence_thread_route_v1(
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_expected_recovery_epoch is null or p_expected_recovery_epoch < 0 then
    raise exception 'INVALID_RECOVERY_EPOCH' using errcode = '22023';
  end if;
  if nullif(trim(p_provider),'') is null or p_provider !~ '^[a-z][a-z0-9_-]{1,31}$' then
    raise exception 'INVALID_PROVIDER' using errcode = '22023';
  end if;
  if nullif(trim(p_model),'') is null or length(trim(p_model)) > 160 then
    raise exception 'INVALID_MODEL' using errcode = '22023';
  end if;
  if p_last_compatible_message_id is not null and not exists (
    select 1 from public.pandora_intelligence_messages m
    where m.id = p_last_compatible_message_id
      and m.thread_id = p_thread_id
      and m.organization_id = p_organization_id
  ) then
    raise exception 'LAST_COMPATIBLE_MESSAGE_MISMATCH' using errcode = '22023';
  end if;

  update private.pandora_intelligence_thread_routing_state r
  set provider = trim(p_provider),
      model = trim(p_model),
      model_version = nullif(trim(p_model_version),''),
      routing_policy_version = nullif(trim(p_routing_policy_version),''),
      reasoning_policy = nullif(trim(p_reasoning_policy),''),
      stickiness_mode = 'recovering',
      recovery_epoch = r.recovery_epoch + 1,
      last_compatible_message_id = p_last_compatible_message_id,
      selected_at = now(),
      updated_at = now()
  where r.thread_id = p_thread_id
    and r.organization_id = p_organization_id
    and r.recovery_epoch = p_expected_recovery_epoch
  returning r.* into v_row;

  if not found then
    raise exception 'RECOVERY_EPOCH_CONFLICT' using errcode = '40001';
  end if;

  return jsonb_build_object(
    'provider', v_row.provider,
    'model', v_row.model,
    'modelVersion', v_row.model_version,
    'routingPolicyVersion', v_row.routing_policy_version,
    'reasoningPolicy', v_row.reasoning_policy,
    'stickinessMode', v_row.stickiness_mode,
    'recoveryEpoch', v_row.recovery_epoch,
    'lastCompatibleMessageId', v_row.last_compatible_message_id,
    'selectedAt', v_row.selected_at
  );
end;
$$;

revoke all on function private.pandora_read_intelligence_thread_route_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function private.pandora_claim_intelligence_thread_route_v1(uuid,uuid,text,text,text,text,text) from public, anon, authenticated;
revoke all on function private.pandora_recover_intelligence_thread_route_v1(uuid,uuid,integer,text,text,text,text,text,uuid) from public, anon, authenticated;
grant execute on function private.pandora_read_intelligence_thread_route_v1(uuid,uuid) to service_role;
grant execute on function private.pandora_claim_intelligence_thread_route_v1(uuid,uuid,text,text,text,text,text) to service_role;
grant execute on function private.pandora_recover_intelligence_thread_route_v1(uuid,uuid,integer,text,text,text,text,text,uuid) to service_role;

comment on table private.pandora_intelligence_thread_routing_state is
  'Provider-neutral private continuity state for Pandora intelligence threads. No prompts, responses, credentials, or provider-internal hidden state are stored.';
