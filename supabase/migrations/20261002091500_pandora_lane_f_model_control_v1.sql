begin;
alter table private.pandora_intelligence_thread_routing_state
  alter column provider drop not null,
  alter column model drop not null,
  add column if not exists selection_mode text not null default 'auto',
  add column if not exists requested_provider text null,
  add column if not exists requested_model text null,
  add column if not exists fallback_mode text not null default 'allow_fallback',
  add column if not exists reasoning_mode text not null default 'auto';
alter table private.pandora_intelligence_thread_routing_state
  drop constraint if exists pandora_intelligence_thread_route_provider_check,
  drop constraint if exists pandora_intelligence_thread_route_model_check,
  drop constraint if exists pandora_intelligence_thread_route_stickiness_check,
  add constraint pandora_intelligence_thread_route_provider_check check (provider is null or provider ~ '^[a-z][a-z0-9_-]{1,31}$'),
  add constraint pandora_intelligence_thread_route_model_check check (model is null or length(trim(model)) between 1 and 160),
  add constraint pandora_intelligence_thread_route_pair_check check ((provider is null)=(model is null)),
  add constraint pandora_intelligence_thread_route_stickiness_check check (stickiness_mode in ('unassigned','sticky','recovering')),
  add constraint pandora_intelligence_thread_route_selection_check check (
    selection_mode in ('auto','manual') and fallback_mode in ('strict','allow_fallback') and reasoning_mode in ('auto','fast','deep')
    and ((selection_mode='auto' and requested_provider is null and requested_model is null)
      or (selection_mode='manual' and requested_provider ~ '^[a-z][a-z0-9_-]{1,31}$' and length(trim(requested_model)) between 1 and 160))
  );

create or replace function private.pandora_set_intelligence_thread_model_selection_v1(p_thread_id uuid,p_organization_id uuid,p_selection_mode text,p_requested_provider text default null,p_requested_model text default null,p_fallback_mode text default 'allow_fallback',p_reasoning_mode text default 'auto') returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_row private.pandora_intelligence_thread_routing_state%rowtype;v_selection text:=lower(coalesce(trim(p_selection_mode),''));v_fallback text:=lower(coalesce(trim(p_fallback_mode),''));v_reasoning text:=lower(coalesce(trim(p_reasoning_mode),''));v_provider text:=nullif(lower(trim(coalesce(p_requested_provider,''))),'');v_model text:=nullif(trim(coalesce(p_requested_model,'')),'');
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in ('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
  if v_selection not in ('auto','manual') or v_fallback not in ('strict','allow_fallback') or v_reasoning not in ('auto','fast','deep') then raise exception 'INVALID_MODEL_SELECTION' using errcode='22023';end if;
  if v_selection='auto' then v_provider:=null;v_model:=null;v_fallback:='allow_fallback';
  elsif v_provider is null or v_provider!~'^[a-z][a-z0-9_-]{1,31}$' or v_model is null or length(v_model)>160 then raise exception 'INVALID_MODEL_SELECTION' using errcode='22023';end if;
  if not exists(select 1 from public.pandora_intelligence_threads t where t.id=p_thread_id and t.organization_id=p_organization_id and t.status='active') then raise exception 'THREAD_NOT_FOUND' using errcode='P0002';end if;
  insert into private.pandora_intelligence_thread_routing_state(thread_id,organization_id,provider,model,stickiness_mode,recovery_epoch,selection_mode,requested_provider,requested_model,fallback_mode,reasoning_mode)
  values(p_thread_id,p_organization_id,null,null,'unassigned',0,v_selection,v_provider,v_model,v_fallback,v_reasoning)
  on conflict(thread_id) do update set selection_mode=excluded.selection_mode,requested_provider=excluded.requested_provider,requested_model=excluded.requested_model,fallback_mode=excluded.fallback_mode,reasoning_mode=excluded.reasoning_mode,updated_at=now()
  where pandora_intelligence_thread_routing_state.organization_id=excluded.organization_id;
  select r.* into strict v_row from private.pandora_intelligence_thread_routing_state r where r.thread_id=p_thread_id and r.organization_id=p_organization_id;
  return jsonb_build_object('provider',v_row.provider,'model',v_row.model,'modelVersion',v_row.model_version,'routingPolicyVersion',v_row.routing_policy_version,'reasoningPolicy',v_row.reasoning_policy,'stickinessMode',v_row.stickiness_mode,'recoveryEpoch',v_row.recovery_epoch,'lastCompatibleMessageId',v_row.last_compatible_message_id,'selectionMode',v_row.selection_mode,'requestedProvider',v_row.requested_provider,'requestedModel',v_row.requested_model,'fallbackMode',v_row.fallback_mode,'reasoningMode',v_row.reasoning_mode,'selectedAt',v_row.selected_at,'updatedAt',v_row.updated_at);
end;$$;
revoke all on function private.pandora_set_intelligence_thread_model_selection_v1(uuid,uuid,text,text,text,text,text) from public;
grant execute on function private.pandora_set_intelligence_thread_model_selection_v1(uuid,uuid,text,text,text,text,text) to service_role;
create or replace function public.pandora_set_intelligence_thread_model_selection_v1(p_thread_id uuid,p_organization_id uuid,p_selection_mode text,p_requested_provider text default null,p_requested_model text default null,p_fallback_mode text default 'allow_fallback',p_reasoning_mode text default 'auto') returns jsonb
language sql security definer set search_path to 'pg_catalog','private','public'
as $$select private.pandora_set_intelligence_thread_model_selection_v1(p_thread_id,p_organization_id,p_selection_mode,p_requested_provider,p_requested_model,p_fallback_mode,p_reasoning_mode);$$;
revoke all on function public.pandora_set_intelligence_thread_model_selection_v1(uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.pandora_set_intelligence_thread_model_selection_v1(uuid,uuid,text,text,text,text,text) to service_role;

create or replace function private.pandora_read_intelligence_thread_route_v1(p_thread_id uuid,p_organization_id uuid) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');if session_user not in ('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
select r.* into v_row from private.pandora_intelligence_thread_routing_state r where r.thread_id=p_thread_id and r.organization_id=p_organization_id;if not found then return null;end if;
return jsonb_build_object('provider',v_row.provider,'model',v_row.model,'modelVersion',v_row.model_version,'routingPolicyVersion',v_row.routing_policy_version,'reasoningPolicy',v_row.reasoning_policy,'stickinessMode',v_row.stickiness_mode,'recoveryEpoch',v_row.recovery_epoch,'lastCompatibleMessageId',v_row.last_compatible_message_id,'selectionMode',v_row.selection_mode,'requestedProvider',v_row.requested_provider,'requestedModel',v_row.requested_model,'fallbackMode',v_row.fallback_mode,'reasoningMode',v_row.reasoning_mode,'selectedAt',v_row.selected_at,'updatedAt',v_row.updated_at);end;$$;

create or replace function private.pandora_claim_intelligence_thread_route_v1(p_thread_id uuid,p_organization_id uuid,p_provider text,p_model text,p_model_version text default null,p_routing_policy_version text default null,p_reasoning_policy text default null) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');if session_user not in ('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
if nullif(trim(p_provider),'') is null or p_provider!~'^[a-z][a-z0-9_-]{1,31}$' then raise exception 'INVALID_PROVIDER' using errcode='22023';end if;if nullif(trim(p_model),'') is null or length(trim(p_model))>160 then raise exception 'INVALID_MODEL' using errcode='22023';end if;
if not exists(select 1 from public.pandora_intelligence_threads t where t.id=p_thread_id and t.organization_id=p_organization_id and t.status='active') then raise exception 'THREAD_NOT_FOUND' using errcode='P0002';end if;
insert into private.pandora_intelligence_thread_routing_state(thread_id,organization_id,provider,model,model_version,routing_policy_version,reasoning_policy,stickiness_mode,recovery_epoch)
values(p_thread_id,p_organization_id,trim(p_provider),trim(p_model),nullif(trim(p_model_version),''),nullif(trim(p_routing_policy_version),''),nullif(trim(p_reasoning_policy),''),'sticky',0)
on conflict(thread_id) do update set provider=excluded.provider,model=excluded.model,model_version=excluded.model_version,routing_policy_version=excluded.routing_policy_version,reasoning_policy=excluded.reasoning_policy,stickiness_mode='sticky',selected_at=now(),updated_at=now()
where pandora_intelligence_thread_routing_state.organization_id=excluded.organization_id and pandora_intelligence_thread_routing_state.provider is null and pandora_intelligence_thread_routing_state.model is null;
select r.* into strict v_row from private.pandora_intelligence_thread_routing_state r where r.thread_id=p_thread_id and r.organization_id=p_organization_id;
return jsonb_build_object('claimed',v_row.provider=trim(p_provider) and v_row.model=trim(p_model),'compatible',v_row.provider=trim(p_provider) and v_row.model=trim(p_model),'provider',v_row.provider,'model',v_row.model,'modelVersion',v_row.model_version,'routingPolicyVersion',v_row.routing_policy_version,'reasoningPolicy',v_row.reasoning_policy,'stickinessMode',v_row.stickiness_mode,'recoveryEpoch',v_row.recovery_epoch,'lastCompatibleMessageId',v_row.last_compatible_message_id,'selectionMode',v_row.selection_mode,'requestedProvider',v_row.requested_provider,'requestedModel',v_row.requested_model,'fallbackMode',v_row.fallback_mode,'reasoningMode',v_row.reasoning_mode);end;$$;

create or replace function private.pandora_recover_intelligence_thread_route_v1(p_thread_id uuid,p_organization_id uuid,p_expected_recovery_epoch integer,p_provider text,p_model text,p_model_version text default null,p_routing_policy_version text default null,p_reasoning_policy text default null,p_last_compatible_message_id uuid default null) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_row private.pandora_intelligence_thread_routing_state%rowtype;
begin v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');if session_user not in ('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
if p_expected_recovery_epoch is null or p_expected_recovery_epoch<0 then raise exception 'INVALID_RECOVERY_EPOCH' using errcode='22023';end if;if nullif(trim(p_provider),'') is null or p_provider!~'^[a-z][a-z0-9_-]{1,31}$' then raise exception 'INVALID_PROVIDER' using errcode='22023';end if;if nullif(trim(p_model),'') is null or length(trim(p_model))>160 then raise exception 'INVALID_MODEL' using errcode='22023';end if;
if p_last_compatible_message_id is not null and not exists(select 1 from public.pandora_intelligence_messages m where m.id=p_last_compatible_message_id and m.thread_id=p_thread_id and m.organization_id=p_organization_id) then raise exception 'LAST_COMPATIBLE_MESSAGE_MISMATCH' using errcode='22023';end if;
update private.pandora_intelligence_thread_routing_state r set provider=trim(p_provider),model=trim(p_model),model_version=nullif(trim(p_model_version),''),routing_policy_version=nullif(trim(p_routing_policy_version),''),reasoning_policy=nullif(trim(p_reasoning_policy),''),stickiness_mode='recovering',recovery_epoch=r.recovery_epoch+1,last_compatible_message_id=p_last_compatible_message_id,selected_at=now(),updated_at=now()
where r.thread_id=p_thread_id and r.organization_id=p_organization_id and r.recovery_epoch=p_expected_recovery_epoch returning r.* into v_row;if not found then raise exception 'RECOVERY_EPOCH_CONFLICT' using errcode='40001';end if;
return jsonb_build_object('provider',v_row.provider,'model',v_row.model,'modelVersion',v_row.model_version,'routingPolicyVersion',v_row.routing_policy_version,'reasoningPolicy',v_row.reasoning_policy,'stickinessMode',v_row.stickiness_mode,'recoveryEpoch',v_row.recovery_epoch,'lastCompatibleMessageId',v_row.last_compatible_message_id,'selectionMode',v_row.selection_mode,'requestedProvider',v_row.requested_provider,'requestedModel',v_row.requested_model,'fallbackMode',v_row.fallback_mode,'reasoningMode',v_row.reasoning_mode,'selectedAt',v_row.selected_at);end;$$;

alter table public.pandora_model_runs alter column project_id drop not null,alter column project_spec_id drop not null,
  add column if not exists thread_id uuid null references public.pandora_intelligence_threads(id) on delete set null,
  add column if not exists intelligence_project_id uuid null,
  add column if not exists requested_selection_mode text not null default 'auto',
  add column if not exists requested_provider text null,
  add column if not exists requested_model text null,
  add column if not exists requested_fallback_mode text not null default 'allow_fallback',
  add column if not exists requested_reasoning_mode text not null default 'auto',
  add column if not exists fallback_reason text null;
alter table public.pandora_model_runs drop constraint if exists pandora_model_runs_task_check,
  add constraint pandora_model_runs_task_check check(task in ('chat','understand_intent','compile_project_spec','classify_task','plan_build','design_experience','plan_architecture','generate_code','generate_project_source','repair_code','inspect_error','inspect_visual','write_copy','summarize_context','extract_structure','derive_acceptance_tests')),
  add constraint pandora_model_runs_chat_scope_check check(task='chat' or(project_id is not null and project_spec_id is not null)),
  add constraint pandora_model_runs_selection_check check(requested_selection_mode in('auto','manual') and requested_fallback_mode in('strict','allow_fallback') and requested_reasoning_mode in('auto','fast','deep') and((requested_selection_mode='auto' and requested_provider is null and requested_model is null)or(requested_selection_mode='manual' and requested_provider~'^[a-z][a-z0-9_-]{1,31}$' and length(trim(requested_model)) between 1 and 160)));
create index if not exists pandora_model_runs_thread_idx on public.pandora_model_runs(thread_id,created_at desc);
alter table public.pandora_model_attempts alter column project_id drop not null,
  add column if not exists thread_id uuid null references public.pandora_intelligence_threads(id) on delete set null,
  add column if not exists intelligence_project_id uuid null;
create index if not exists pandora_model_attempts_thread_idx on public.pandora_model_attempts(thread_id,created_at desc);
comment on column public.pandora_model_runs.intelligence_project_id is 'Owner-facing Pandora project identity; intentionally no foreign key because public.pandora_projects is a compatibility view.';
comment on column public.pandora_model_attempts.intelligence_project_id is 'Owner-facing Pandora project identity; intentionally no foreign key because public.pandora_projects is a compatibility view.';
commit;
