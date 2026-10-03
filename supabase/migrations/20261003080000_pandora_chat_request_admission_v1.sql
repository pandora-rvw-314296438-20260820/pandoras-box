-- Explicit monthly paid cloud-chat request admission. Existing model runs are
-- the reservation ledger; no parallel execution, quota, or tenant store.
begin;

alter table public.pandora_service_plans add column request_admission_policy text not null default 'record_only'
 check(request_admission_policy in ('record_only','block'));
alter table public.pandora_customer_subscriptions
 add column request_admission_enabled boolean not null default false,
 add column request_admission_started_at timestamptz,
 add constraint pandora_subscription_admission_anchor_check check(not request_admission_enabled or request_admission_started_at is not null);

alter table public.pandora_model_runs
 add column actor_user_id uuid references auth.users(id),
 add column request_admitted_at timestamptz,
 add column request_admission_enforced boolean not null default false,
 add column request_admission_plan_id uuid references public.pandora_service_plans(id),
 add column request_admission_window_start timestamptz,
 add column admission_activity_job_id uuid references public.pandora_activity_jobs(id),
 add column admission_activity_fingerprint text check(admission_activity_fingerprint is null or admission_activity_fingerprint~'^[0-9a-f]{64}$'),
 add constraint pandora_model_runs_request_admission_check check(
  (not request_admission_enforced or (actor_user_id is not null and request_admitted_at is not null
    and request_admission_plan_id is not null and request_admission_window_start is not null
    and admission_activity_job_id is not null and admission_activity_fingerprint is not null))
  and ((admission_activity_job_id is null)=(admission_activity_fingerprint is null)));
create index pandora_model_runs_admission_actor_idx on public.pandora_model_runs(actor_user_id) where actor_user_id is not null;
create index pandora_model_runs_admission_plan_idx on public.pandora_model_runs(request_admission_plan_id) where request_admission_plan_id is not null;
create index pandora_model_runs_admission_activity_idx on public.pandora_model_runs(admission_activity_job_id) where admission_activity_job_id is not null;
create index pandora_model_runs_admission_window_idx on public.pandora_model_runs(organization_id,request_admission_window_start)
 where request_admission_enforced;

create function private.pandora_request_admission_immutable_v1()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.request_admission_enforced and old.request_admission_window_start>=(date_trunc('month',clock_timestamp() at time zone 'UTC') at time zone 'UTC')
  then raise exception 'CURRENT_REQUEST_RESERVATION_RETAINED' using errcode='23514';end if;
  return old;
 end if;
 if tg_table_name='pandora_customer_subscriptions' then
  if old.request_admission_started_at is not null and new.request_admission_started_at is distinct from old.request_admission_started_at
  then raise exception 'ADMISSION_ANCHOR_IMMUTABLE' using errcode='23514';end if;
 elsif old.actor_user_id is not null and
  row(new.actor_user_id,new.request_admitted_at,new.request_admission_enforced,new.request_admission_plan_id,
      new.request_admission_window_start,new.admission_activity_job_id,new.admission_activity_fingerprint,new.organization_id,new.request_id,new.request_sha256,new.thread_id,new.intelligence_project_id)
  is distinct from
  row(old.actor_user_id,old.request_admitted_at,old.request_admission_enforced,old.request_admission_plan_id,
      old.request_admission_window_start,old.admission_activity_job_id,old.admission_activity_fingerprint,old.organization_id,old.request_id,old.request_sha256,old.thread_id,old.intelligence_project_id)
 then raise exception 'REQUEST_ADMISSION_IMMUTABLE' using errcode='23514';end if;
 return new;
end;
$$;
revoke all on function private.pandora_request_admission_immutable_v1() from public,anon,authenticated,service_role;
create trigger pandora_subscription_admission_anchor_immutable before update on public.pandora_customer_subscriptions
 for each row execute function private.pandora_request_admission_immutable_v1();
create trigger pandora_model_run_admission_immutable before update or delete on public.pandora_model_runs
 for each row execute function private.pandora_request_admission_immutable_v1();

create function private.pandora_chat_request_policy_v1(p_organization_id uuid,p_at timestamptz)
returns jsonb language plpgsql volatile set search_path='' as $$
declare v_sub public.pandora_customer_subscriptions%rowtype;v_plan public.pandora_service_plans%rowtype;
 v_window timestamptz:=date_trunc('month',p_at at time zone 'UTC') at time zone 'UTC';
 v_reset timestamptz:=(date_trunc('month',p_at at time zone 'UTC')+interval '1 month') at time zone 'UTC';
 v_limit bigint;v_used bigint;v_effective timestamptz;v_state text:='not_enrolled';v_valid boolean:=false;
begin
 select * into v_sub from public.pandora_customer_subscriptions where organization_id=p_organization_id;
 if found then
  select * into v_plan from public.pandora_service_plans where id=v_sub.plan_id;
  if jsonb_typeof(v_plan.limits->'monthly_requests')='number' and (v_plan.limits->>'monthly_requests')~'^[0-9]{1,10}$'
    and (v_plan.limits->>'monthly_requests')::numeric<=1000000000
  then v_limit:=(v_plan.limits->>'monthly_requests')::bigint;end if;
  if v_sub.request_admission_enabled then
   v_effective:=greatest(v_window,v_sub.request_admission_started_at);
   select count(*) into v_used from public.pandora_model_runs r
    where r.organization_id=p_organization_id and r.request_admission_enforced
     and r.request_admission_window_start=v_window and r.request_admitted_at>=v_effective;
   v_valid:=v_sub.state in ('active','trial') and v_plan.state='active' and v_plan.request_admission_policy='block'
    and v_sub.request_admission_started_at is not null and v_sub.request_admission_started_at<=p_at
    and (v_sub.starts_on is null or v_sub.starts_on<=(p_at at time zone 'UTC')::date)
    and (v_sub.ends_on is null or v_sub.ends_on>=(p_at at time zone 'UTC')::date)
    and v_limit is not null;
   v_state:=case when v_valid is not true then 'policy_unavailable' when v_used>=v_limit then 'limit_reached' else 'enforcing' end;
  end if;
 end if;
 return jsonb_build_object('request_admission_enabled',coalesce(v_sub.request_admission_enabled,false),
  'request_admission_policy',coalesce(v_plan.request_admission_policy,'record_only'),
  'request_admission_started_at',v_sub.request_admission_started_at,'request_admission_state',v_state,
  'request_window_start',v_window,'request_reset_at',v_reset,'request_effective_from',v_effective,
  'request_limit',v_limit,'requests_admitted',v_used,
  'requests_remaining',case when v_valid then greatest(v_limit-v_used,0) else null end,
  'coverage',case when v_sub.request_admission_enabled then 'cloud_chat_requests_since_enrollment_only' else 'commercial_records_only' end,
  'evidence_note','One protected cloud-chat turn counts once, including failures and fallback attempts. Requests made while protection is off are not counted. Other allowances are commercial records, not runtime hard limits.');
end;
$$;
revoke all on function private.pandora_chat_request_policy_v1(uuid,timestamptz) from public,anon,authenticated,service_role;

create function private.pandora_core_save_admission_commercial_v1(p_operation text,p_organization_id uuid,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare v_actor uuid:=auth.uid();v_id uuid;v_plan public.pandora_service_plans%rowtype;
 v_sub public.pandora_customer_subscriptions%rowtype;v_enabled boolean;v_start timestamptz;v_state text;
begin
 perform private.pandora_core_assert_v1(p_organization_id,array['owner','finance'],true);
 if p_operation='plan.save' then
  if p_organization_id is not null then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  -- Lock before checking subscriptions so concurrent enrollment cannot race plan edits.
  perform 1 from public.pandora_service_plans where id=v_id for update;
  if exists(select 1 from public.pandora_customer_subscriptions where plan_id=v_id and
    (state in ('active','trial','past_due') or request_admission_enabled))
  then raise exception 'PLAN_IN_USE_CREATE_NEW_VERSION' using errcode='23505';end if;
  if jsonb_typeof(coalesce(p_payload->'limits','{}'))<>'object' or exists(
    select 1 from jsonb_each(coalesce(p_payload->'limits','{}')) kv
    where kv.key not in ('users','devices','monthly_requests','monthly_tokens','budget_micros','storage_bytes')
      or jsonb_typeof(kv.value)<>'number' or (kv.value::text)::numeric<0
      or (kv.value::text)::numeric<>trunc((kv.value::text)::numeric)
      or (kv.value::text)::numeric>9223372036854775807)
  then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  if coalesce(p_payload->>'request_admission_policy','record_only') not in ('record_only','block')
    or (coalesce(p_payload->>'request_admission_policy','record_only')='block'
      and (jsonb_typeof(p_payload#>'{limits,monthly_requests}')='number'
       and p_payload#>>'{limits,monthly_requests}'~'^[0-9]{1,10}$'
       and (p_payload#>>'{limits,monthly_requests}')::numeric<=1000000000) is not true)
  then raise exception 'REQUEST_ADMISSION_POLICY_INVALID' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'entitlements','[]')) e where jsonb_typeof(e)<>'string' or trim(both '"' from e::text)!~'^[a-z][a-z0-9_.-]{1,100}$')
  then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into public.pandora_service_plans(id,code,name,state,currency,monthly_fee_micros,included_allowance_micros,entitlements,limits,overage_policy,support_tier,created_by,request_admission_policy)
  values(v_id,p_payload->>'code',p_payload->>'name',coalesce(p_payload->>'state','draft'),p_payload->>'currency',
   nullif(p_payload->>'monthly_fee_micros','')::bigint,nullif(p_payload->>'included_allowance_micros','')::bigint,
   coalesce(p_payload->'entitlements','[]'),coalesce(p_payload->'limits','{}'),coalesce(p_payload->>'overage_policy','approval_required'),
   coalesce(p_payload->>'support_tier','standard'),v_actor,coalesce(p_payload->>'request_admission_policy','record_only'))
  on conflict(id) do update set code=excluded.code,name=excluded.name,state=excluded.state,currency=excluded.currency,
   monthly_fee_micros=excluded.monthly_fee_micros,included_allowance_micros=excluded.included_allowance_micros,
   entitlements=excluded.entitlements,limits=excluded.limits,overage_policy=excluded.overage_policy,
   support_tier=excluded.support_tier,request_admission_policy=excluded.request_admission_policy,updated_at=now();
  return jsonb_build_object('status','saved','id',v_id,'source_kind','manual');
 elsif p_operation='subscription.save' then
  select * into v_sub from public.pandora_customer_subscriptions where organization_id=p_organization_id for update;
  select * into strict v_plan from public.pandora_service_plans where id=(p_payload->>'plan_id')::uuid and state='active' for share;
  if p_payload?'currency' and p_payload->>'currency'<>v_plan.currency then raise exception 'CURRENCY_MISMATCH' using errcode='22023';end if;
  if p_payload?'request_admission_enabled' and jsonb_typeof(p_payload->'request_admission_enabled') is distinct from 'boolean'
  then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  v_enabled:=coalesce((p_payload->>'request_admission_enabled')::boolean,v_sub.request_admission_enabled,false);
  v_start:=v_sub.request_admission_started_at;v_state:=coalesce(p_payload->>'state','draft');
  if v_enabled then
   if (v_plan.request_admission_policy='block' and v_state in ('active','trial')
    and jsonb_typeof(v_plan.limits->'monthly_requests')='number'
    and v_plan.limits->>'monthly_requests'~'^[0-9]{1,10}$'
    and (v_plan.limits->>'monthly_requests')::numeric<=1000000000
    and (nullif(p_payload->>'starts_on','')::date is null or (p_payload->>'starts_on')::date<=(clock_timestamp() at time zone 'UTC')::date)
    and (nullif(p_payload->>'ends_on','')::date is null or (p_payload->>'ends_on')::date>=(clock_timestamp() at time zone 'UTC')::date)) is not true
   then raise exception 'REQUEST_ADMISSION_POLICY_INVALID' using errcode='22023';end if;
   v_start:=coalesce(v_start,clock_timestamp());
  end if;
  insert into public.pandora_customer_subscriptions(organization_id,plan_id,state,currency,monthly_fee_micros,setup_fee_micros,
   discount_micros,starts_on,ends_on,renews_on,notes,updated_by,request_admission_enabled,request_admission_started_at)
  values(p_organization_id,v_plan.id,v_state,v_plan.currency,coalesce(nullif(p_payload->>'monthly_fee_micros','')::bigint,v_plan.monthly_fee_micros),
   nullif(p_payload->>'setup_fee_micros','')::bigint,coalesce(nullif(p_payload->>'discount_micros','')::bigint,0),
   nullif(p_payload->>'starts_on','')::date,nullif(p_payload->>'ends_on','')::date,nullif(p_payload->>'renews_on','')::date,
   coalesce(p_payload->>'notes',''),v_actor,v_enabled,v_start)
  on conflict(organization_id) do update set plan_id=excluded.plan_id,state=excluded.state,currency=excluded.currency,
   monthly_fee_micros=excluded.monthly_fee_micros,setup_fee_micros=excluded.setup_fee_micros,discount_micros=excluded.discount_micros,
   starts_on=excluded.starts_on,ends_on=excluded.ends_on,renews_on=excluded.renews_on,notes=excluded.notes,
   request_admission_enabled=excluded.request_admission_enabled,request_admission_started_at=excluded.request_admission_started_at,
   source_kind='manual',provider_reference=null,verified_at=null,updated_by=v_actor,updated_at=now();
  return jsonb_build_object('status','saved','organization_id',p_organization_id,'source_kind','manual',
    'request_admission_enabled',v_enabled,'request_admission_started_at',v_start);
 end if;
 raise exception 'INVALID_REQUEST' using errcode='22023';
end;
$$;
revoke all on function private.pandora_core_save_admission_commercial_v1(text,uuid,jsonb) from public,anon,authenticated,service_role;

create function public.pandora_chat_request_admit_v1(p_organization_id uuid,p_thread_id uuid,p_user_message_id uuid,
 p_request_sha256 text,p_metadata jsonb,p_entry_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();v_authority jsonb;v_policy jsonb;v_rate jsonb;v_run public.pandora_model_runs%rowtype;
 v_job public.pandora_activity_jobs%rowtype;v_job_id uuid;v_claim uuid;v_fingerprint text;
 v_request_id text;v_thread_project uuid;v_now timestamptz;v_id uuid:=gen_random_uuid();v_code text;v_enforced boolean;
begin
 if p_organization_id is null or p_thread_id is null or p_user_message_id is null
  or p_request_sha256 is null or p_request_sha256!~'^[0-9a-f]{64}$'
  or jsonb_typeof(p_metadata) is distinct from 'object' or octet_length(p_metadata::text)>100000
  or p_metadata-array['intelligence_project_id','max_attempts','reasoning_tier','routing_policy_version','routing_candidates',
    'routing_exclusions','routing_scores','session_stickiness_state','requested_selection_mode','requested_provider',
    'requested_model','requested_fallback_mode','requested_reasoning_mode','activity_job_id','activity_claim_id','activity_request_fingerprint']<>'{}'::jsonb
 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 if (jsonb_typeof(p_metadata->'max_attempts')='number' and p_metadata->>'max_attempts'~'^[1-9][0-9]{0,2}$'
  and (p_metadata->>'max_attempts')::integer<=100
  and jsonb_typeof(p_metadata->'routing_candidates')='array' and jsonb_typeof(p_metadata->'routing_exclusions')='array'
  and jsonb_typeof(p_metadata->'routing_scores')='object'
  and octet_length((p_metadata->'routing_candidates')::text)<=32768
  and octet_length((p_metadata->'routing_exclusions')::text)<=32768
  and octet_length((p_metadata->'routing_scores')::text)<=32768
  and p_metadata->>'requested_selection_mode' in ('auto','manual')
  and p_metadata->>'requested_fallback_mode' in ('strict','allow_fallback')
  and p_metadata->>'requested_reasoning_mode' in ('auto','fast','deep')
  and length(coalesce(p_metadata->>'reasoning_tier',''))<=80
  and length(coalesce(p_metadata->>'routing_policy_version',''))<=160
  and length(coalesce(p_metadata->>'session_stickiness_state',''))<=80
  and length(coalesce(p_metadata->>'requested_model',''))<=160
 ) is not true then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 v_authority:=public.pandora_enterprise_chat_authority_v1(p_organization_id,p_entry_id);
 if ((v_authority->>'scope_kind'='platform' and (v_authority->>'can_execute_core')::boolean)
   or (v_authority->>'scope_kind'='administrator' and v_authority->>'adapter_key'='plp_v1')) is not true
  or v_authority->>'actor_role' not in ('owner','admin')
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('pandora-core-org:'||p_organization_id::text,0));
 v_authority:=public.pandora_enterprise_chat_authority_v1(p_organization_id,p_entry_id);
 if ((v_authority->>'scope_kind'='platform' and (v_authority->>'can_execute_core')::boolean)
   or (v_authority->>'scope_kind'='administrator' and v_authority->>'adapter_key'='plp_v1')) is not true
  or v_authority->>'actor_role' not in ('owner','admin')
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if not exists(select 1 from public.pandora_intelligence_threads t
   join public.pandora_intelligence_messages m on m.thread_id=t.id and m.organization_id=t.organization_id
   where t.id=p_thread_id and t.organization_id=p_organization_id and t.created_by=v_actor and t.status='active'
    and m.id=p_user_message_id and m.author_role='user')
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select project_id into v_thread_project from public.pandora_intelligence_threads where id=p_thread_id;
 if v_thread_project is not null and not private.pandora_control_plane_project_org_matches(p_organization_id,v_thread_project)
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if nullif(p_metadata->>'intelligence_project_id','')::uuid is not null and nullif(p_metadata->>'intelligence_project_id','')::uuid is distinct from v_thread_project
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 -- These row locks serialize policy editing across plan/subscription changes.
 perform 1 from public.pandora_customer_subscriptions where organization_id=p_organization_id for share;
 perform 1 from public.pandora_service_plans where id=(select plan_id from public.pandora_customer_subscriptions where organization_id=p_organization_id) for share;
 v_now:=clock_timestamp();v_policy:=private.pandora_chat_request_policy_v1(p_organization_id,v_now);
 v_enforced:=(v_policy->>'request_admission_enabled')::boolean;
 begin
  v_job_id:=nullif(p_metadata->>'activity_job_id','')::uuid;
  v_claim:=nullif(p_metadata->>'activity_claim_id','')::uuid;
 exception when invalid_text_representation then raise exception 'INVALID_REQUEST' using errcode='22023';end;
 v_fingerprint:=nullif(p_metadata->>'activity_request_fingerprint','');
 if (v_job_id is null)<>(v_claim is null) or (v_job_id is null)<>(v_fingerprint is null)
 then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
 if v_job_id is not null then
  select * into v_job from public.pandora_activity_jobs where id=v_job_id for share;
  if not found or v_job.organization_id<>p_organization_id or v_job.requested_by<>v_actor
    or v_job.thread_id is distinct from p_thread_id or v_job.execution_claim_id is distinct from v_claim
    or v_job.request_fingerprint is distinct from v_fingerprint or v_fingerprint!~'^[0-9a-f]{64}$'
  then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  v_request_id:='chat-activity-'||v_job_id::text;
 else v_request_id:='chat-'||p_user_message_id::text;end if;
 select * into v_run from public.pandora_model_runs where organization_id=p_organization_id and request_id=v_request_id;
 if found then
  if v_run.actor_user_id is distinct from v_actor or v_run.thread_id is distinct from p_thread_id
   or v_run.request_sha256 is distinct from p_request_sha256
   or v_run.admission_activity_job_id is distinct from v_job_id
   or v_run.admission_activity_fingerprint is distinct from v_fingerprint
  then raise exception 'REQUEST_ADMISSION_CONFLICT' using errcode='23505';end if;
  return jsonb_build_object('admitted',true,'id',v_run.id,'fallback_chain_id',v_run.id,'replay',true,
   'organization_id',p_organization_id,'thread_id',p_thread_id,'admission_enforced',v_run.request_admission_enforced,
   'admission_window_start',v_run.request_admission_window_start,'request_limit',v_policy->'request_limit',
   'requests_used',v_policy->'requests_admitted','reset_at',v_policy->'request_reset_at');
 end if;
 if v_job_id is not null and (v_job.execution_state<>'running' or v_job.expires_at<=v_now or v_job.terminal_state is not null)
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if v_job_id is null then
  v_rate:=public.consume_runtime_rate_limit(p_organization_id,
   encode(extensions.digest(v_actor::text||':pandora-chat-admission-legacy','sha256'),'hex'),30,60);
 end if;
 v_code:=case when v_job_id is null and (v_rate->>'allowed')::boolean is not true then 'CHAT_REQUEST_RATE_LIMITED'
  when v_enforced and v_job_id is null then 'CHAT_REQUEST_IDEMPOTENCY_REQUIRED'
  when v_enforced and v_policy->>'request_admission_state'='policy_unavailable' then 'CHAT_REQUEST_POLICY_UNAVAILABLE'
  when v_enforced and v_policy->>'request_admission_state'='limit_reached' then 'CHAT_REQUEST_LIMIT_REACHED' else null end;
 if v_code is not null then
  perform private.append_audit_event(p_organization_id,null,null,'human',v_actor,'core.chat_request_admission.denied',
   jsonb_build_object('code',v_code,'request_id',v_request_id,'request_limit',v_policy->'request_limit',
    'requests_used',v_policy->'requests_admitted','reset_at',case when v_code='CHAT_REQUEST_RATE_LIMITED' then v_rate->'resetAt' else v_policy->'request_reset_at' end));
  return jsonb_build_object('admitted',false,'code',v_code,'request_limit',v_policy->'request_limit',
   'requests_used',v_policy->'requests_admitted','reset_at',case when v_code='CHAT_REQUEST_RATE_LIMITED' then v_rate->'resetAt' else v_policy->'request_reset_at' end);
 end if;
 insert into public.pandora_model_runs(id,organization_id,project_id,project_spec_id,thread_id,intelligence_project_id,
  request_id,task,output_mode,status,request_sha256,attempt,max_attempts,started_at,reasoning_tier,routing_decision_id,
  routing_policy_version,routing_candidates,routing_exclusions,routing_scores,session_stickiness_state,
  requested_selection_mode,requested_provider,requested_model,requested_fallback_mode,requested_reasoning_mode,
  actor_user_id,request_admitted_at,request_admission_enforced,request_admission_plan_id,request_admission_window_start,
  admission_activity_job_id,admission_activity_fingerprint)
 values(v_id,p_organization_id,null,null,p_thread_id,v_thread_project,
  v_request_id,'chat','structured','running',p_request_sha256,1,(p_metadata->>'max_attempts')::integer,v_now,
  p_metadata->>'reasoning_tier',gen_random_uuid(),p_metadata->>'routing_policy_version',
  p_metadata->'routing_candidates',p_metadata->'routing_exclusions',p_metadata->'routing_scores',p_metadata->>'session_stickiness_state',
  p_metadata->>'requested_selection_mode',nullif(p_metadata->>'requested_provider',''),nullif(p_metadata->>'requested_model',''),
  p_metadata->>'requested_fallback_mode',p_metadata->>'requested_reasoning_mode',v_actor,v_now,v_enforced,
  case when v_enforced then (select plan_id from public.pandora_customer_subscriptions where organization_id=p_organization_id) else null end,
  case when v_enforced then (v_policy->>'request_window_start')::timestamptz else null end,v_job_id,v_fingerprint);
 return jsonb_build_object('admitted',true,'id',v_id,'fallback_chain_id',v_id,'replay',false,
  'organization_id',p_organization_id,'thread_id',p_thread_id,'admission_enforced',v_enforced,
  'admission_window_start',case when v_enforced then v_policy->'request_window_start' else null end,
  'request_limit',v_policy->'request_limit',
  'requests_used',case when v_enforced then (v_policy->>'requests_admitted')::bigint+1 else null end,
  'reset_at',v_policy->'request_reset_at');
end;
$$;
revoke all on function public.pandora_chat_request_admit_v1(uuid,uuid,uuid,text,jsonb,uuid) from public,anon,service_role;
grant execute on function public.pandora_chat_request_admit_v1(uuid,uuid,uuid,text,jsonb,uuid) to authenticated;

-- Source-fenced commercial operation and owner projection changes follow.
-- An older Edge deployment cannot bypass an explicitly enabled subscription
-- by returning to direct service-role model-run INSERTs.
create function private.pandora_chat_request_insert_guard_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_entry uuid;v_authority jsonb;v_policy jsonb;v_job public.pandora_activity_jobs%rowtype;
 v_now timestamptz:=clock_timestamp();
begin
 if new.task<>'chat' or new.request_id not like 'chat-%' then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('pandora-core-org:'||new.organization_id::text,0));
 if not exists(select 1 from public.pandora_customer_subscriptions where organization_id=new.organization_id and request_admission_enabled)
 then return new;end if;
 v_now:=clock_timestamp();
 if v_actor is null or new.actor_user_id is distinct from v_actor or not new.request_admission_enforced
  or new.admission_activity_job_id is null or new.admission_activity_fingerprint is null
  or new.request_id is distinct from 'chat-activity-'||new.admission_activity_job_id::text
  or new.request_admitted_at is null or new.request_admitted_at>v_now
  or new.request_admitted_at<v_now-interval '1 minute'
  or new.request_admission_window_start is distinct from (date_trunc('month',v_now at time zone 'UTC') at time zone 'UTC')
 then raise exception 'CHAT_REQUEST_ADMISSION_REQUIRED' using errcode='42501';end if;
 select id into v_entry from private.pandora_client_entry_sessions
 where actor_user_id=v_actor and organization_id=new.organization_id
  and auth_session_id::text=auth.jwt()->>'session_id' and ended_at is null and expires_at>v_now
 order by expires_at desc limit 1;
 v_authority:=public.pandora_enterprise_chat_authority_v1(new.organization_id,v_entry);
 if ((v_authority->>'scope_kind'='platform' and (v_authority->>'can_execute_core')::boolean)
   or (v_authority->>'scope_kind'='administrator' and v_authority->>'adapter_key'='plp_v1')) is not true
  or v_authority->>'actor_role' not in ('owner','admin')
 then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select * into v_job from public.pandora_activity_jobs where id=new.admission_activity_job_id;
 if not found or v_job.organization_id<>new.organization_id or v_job.requested_by<>v_actor
  or v_job.thread_id is distinct from new.thread_id or v_job.request_fingerprint is distinct from new.admission_activity_fingerprint
  or v_job.execution_state<>'running' or v_job.execution_claim_id is null
  or v_job.expires_at<=v_now or v_job.terminal_state is not null
 then raise exception 'CHAT_REQUEST_ADMISSION_REQUIRED' using errcode='42501';end if;
 v_policy:=private.pandora_chat_request_policy_v1(new.organization_id,v_now);
 if v_policy->>'request_admission_state'<>'enforcing'
  or new.request_admission_plan_id is distinct from (select plan_id from public.pandora_customer_subscriptions where organization_id=new.organization_id)
  or new.request_admitted_at<(v_policy->>'request_effective_from')::timestamptz
 then raise exception 'CHAT_REQUEST_POLICY_UNAVAILABLE' using errcode='42501';end if;
 return new;
end;
$$;
revoke all on function private.pandora_chat_request_insert_guard_v1() from public,anon,authenticated,service_role;
create trigger pandora_chat_request_insert_guard before insert on public.pandora_model_runs
 for each row execute function private.pandora_chat_request_insert_guard_v1();

do $patch$
declare v_definition text;v_body text;v_old text;v_new text;
begin
 select pg_get_functiondef(p.oid),p.prosrc into v_definition,v_body from pg_proc p where p.oid='public.pandora_core_operate_v1(text,uuid,jsonb,uuid)'::regprocedure;
 if encode(extensions.digest(v_body,'sha256'),'hex')<>'a553f17ead527b0cf00291d1f30d6aaccbcd12eb216e815e83e48b0a1352d048' then raise exception 'ADMISSION_CORE_SOURCE_DRIFT';end if;
 v_old:=$old$when 'plan.save' then array['id','code','name','state','currency','monthly_fee_micros','included_allowance_micros','entitlements','limits','overage_policy','support_tier']$old$;
 v_new:=$new$when 'plan.save' then array['id','code','name','state','currency','monthly_fee_micros','included_allowance_micros','entitlements','limits','overage_policy','support_tier','request_admission_policy']$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_CORE_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$when 'subscription.save' then array['plan_id','state','currency','monthly_fee_micros','setup_fee_micros','discount_micros','starts_on','ends_on','renews_on','notes']$old$;
 v_new:=$new$when 'subscription.save' then array['plan_id','state','currency','monthly_fee_micros','setup_fee_micros','discount_micros','starts_on','ends_on','renews_on','notes','request_admission_enabled']$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_CORE_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$ when 'plan.save' then
  v_id:=coalesce(nullif(p_payload->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from public.pandora_customer_subscriptions where plan_id=v_id and state in ('active','trial','past_due')) then raise exception 'PLAN_IN_USE_CREATE_NEW_VERSION' using errcode='23505';end if;
  if jsonb_typeof(coalesce(p_payload->'limits','{}'))<>'object' or exists(select 1 from jsonb_each(coalesce(p_payload->'limits','{}')) kv where kv.key not in ('users','devices','monthly_requests','monthly_tokens','budget_micros','storage_bytes') or jsonb_typeof(kv.value)<>'number' or (kv.value::text)::numeric<0 or (kv.value::text)::numeric<>trunc((kv.value::text)::numeric)) then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'entitlements','[]')) e where jsonb_typeof(e)<>'string' or trim(both '"' from e::text)!~'^[a-z][a-z0-9_.-]{1,100}$') then raise exception 'INVALID_REQUEST' using errcode='22023';end if;
  insert into public.pandora_service_plans(id,code,name,state,currency,monthly_fee_micros,included_allowance_micros,entitlements,limits,overage_policy,support_tier,created_by)
  values(v_id,p_payload->>'code',p_payload->>'name',coalesce(p_payload->>'state','draft'),p_payload->>'currency',nullif(p_payload->>'monthly_fee_micros','')::bigint,nullif(p_payload->>'included_allowance_micros','')::bigint,coalesce(p_payload->'entitlements','[]'),coalesce(p_payload->'limits','{}'),coalesce(p_payload->>'overage_policy','approval_required'),coalesce(p_payload->>'support_tier','standard'),v_actor)
  on conflict(id) do update set code=excluded.code,name=excluded.name,state=excluded.state,currency=excluded.currency,monthly_fee_micros=excluded.monthly_fee_micros,included_allowance_micros=excluded.included_allowance_micros,entitlements=excluded.entitlements,limits=excluded.limits,overage_policy=excluded.overage_policy,support_tier=excluded.support_tier,updated_at=now();
  v_result:=jsonb_build_object('status','saved','id',v_id,'source_kind','manual');
 when 'subscription.save' then
  select * into strict v_plan from public.pandora_service_plans where id=(p_payload->>'plan_id')::uuid and state='active';
  if p_payload?'currency' and p_payload->>'currency'<>v_plan.currency then raise exception 'CURRENCY_MISMATCH' using errcode='22023';end if;
  select to_jsonb(s) into v_before from public.pandora_customer_subscriptions s where organization_id=v_org;
  insert into public.pandora_customer_subscriptions(organization_id,plan_id,state,currency,monthly_fee_micros,setup_fee_micros,discount_micros,starts_on,ends_on,renews_on,notes,updated_by)
  values(v_org,v_plan.id,coalesce(p_payload->>'state','draft'),v_plan.currency,coalesce(nullif(p_payload->>'monthly_fee_micros','')::bigint,v_plan.monthly_fee_micros),nullif(p_payload->>'setup_fee_micros','')::bigint,coalesce(nullif(p_payload->>'discount_micros','')::bigint,0),nullif(p_payload->>'starts_on','')::date,nullif(p_payload->>'ends_on','')::date,nullif(p_payload->>'renews_on','')::date,coalesce(p_payload->>'notes',''),v_actor)
  on conflict(organization_id) do update set plan_id=excluded.plan_id,state=excluded.state,currency=excluded.currency,monthly_fee_micros=excluded.monthly_fee_micros,setup_fee_micros=excluded.setup_fee_micros,discount_micros=excluded.discount_micros,starts_on=excluded.starts_on,ends_on=excluded.ends_on,renews_on=excluded.renews_on,notes=excluded.notes,source_kind='manual',provider_reference=null,verified_at=null,updated_by=v_actor,updated_at=now();
  v_result:=jsonb_build_object('status','saved','organization_id',v_org,'source_kind','manual');
$old$;
 v_new:=$new$ when 'plan.save','subscription.save' then
  if p_operation='subscription.save' then select to_jsonb(s) into v_before from public.pandora_customer_subscriptions s where organization_id=v_org;end if;
  v_result:=private.pandora_core_save_admission_commercial_v1(p_operation,v_org,p_payload);
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_CORE_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end;
$patch$;

do $patch$
declare v_definition text;v_body text;v_old text;v_new text;
begin
 select pg_get_functiondef(p.oid),p.prosrc into v_definition,v_body from pg_proc p where p.oid='public.pandora_core_snapshot_v1(text,uuid)'::regprocedure;
 if encode(extensions.digest(v_body,'sha256'),'hex')<>'a578004587619e94a3b08f6e767bc468ed1ff3f82c640a451d71552b5ee0e9f5' then raise exception 'ADMISSION_CORE_SOURCE_DRIFT';end if;
 v_old:=$old$'usage_allowances',coalesce((select jsonb_agg(to_jsonb(q)) from (
   select s.organization_id,o.name client_name,s.currency,s.state subscription_state,
    (p.limits->>'monthly_requests')::bigint request_limit,(p.limits->>'monthly_tokens')::bigint token_limit,
    (p.limits->>'budget_micros')::bigint budget_micros,p.included_allowance_micros,
    (select count(*) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) requests_recorded,
    (select sum(r.total_tokens) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) tokens_recorded,
    'recorded_model_runs_only' coverage,
    'Configured allowances require matching execution admission; missing usage is not zero' evidence_note
   from public.pandora_customer_subscriptions s join public.pandora_service_plans p on p.id=s.plan_id join public.organizations o on o.id=s.organization_id
   where s.state in ('trial','active','past_due') and (p_organization_id is null or s.organization_id=p_organization_id) and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')
  ) q),'[]'::jsonb));
$old$;
 v_new:=$new$'usage_allowances',coalesce((select jsonb_agg(to_jsonb(q)||private.pandora_chat_request_policy_v1(q.organization_id,clock_timestamp())) from (
   select s.organization_id,o.name client_name,s.currency,s.state subscription_state,
    (p.limits->>'monthly_tokens')::bigint token_limit,(p.limits->>'budget_micros')::bigint budget_micros,p.included_allowance_micros,
    (select count(*) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) requests_recorded,
    (select sum(r.total_tokens) from public.pandora_model_runs r where r.organization_id=s.organization_id and r.created_at>=date_trunc('month',now())) tokens_recorded
   from public.pandora_customer_subscriptions s join public.pandora_service_plans p on p.id=s.plan_id join public.organizations o on o.id=s.organization_id
   where (s.state in ('trial','active','past_due') or s.request_admission_enabled) and (p_organization_id is null or s.organization_id=p_organization_id)
    and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')
  ) q),'[]'::jsonb));
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_CORE_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$  union all select jsonb_build_object('id','gate:'||g.task_key||':'||g.gate_kind$old$;
 v_new:=$new$  union all select jsonb_build_object('id','request-limit:'||s.organization_id::text,'kind','request_allowance',
   'organization_id',s.organization_id,'client_name',o.name,
   'title',case policy->>'request_admission_state' when 'limit_reached' then 'Cloud-chat request allowance reached' else 'Cloud-chat protection needs attention' end,
   'why',case policy->>'request_admission_state' when 'limit_reached' then 'Review the client allowance before another paid cloud-chat turn' else 'Review the enrolled subscription and its active request policy' end,
   'risk','commercial','action','open_client_commercial',
   'evidence',jsonb_build_object('request_limit',policy->'request_limit','requests_admitted',policy->'requests_admitted',
    'request_window_start',policy->'request_window_start','request_reset_at',policy->'request_reset_at'))
  from public.pandora_customer_subscriptions s join public.organizations o on o.id=s.organization_id
  cross join lateral (select private.pandora_chat_request_policy_v1(s.organization_id,clock_timestamp()) policy) p
  where s.request_admission_enabled and policy->>'request_admission_state' in ('limit_reached','policy_unavailable')
   and (p_organization_id is null or s.organization_id=p_organization_id)
   and private.pandora_core_role_v1(s.organization_id) in ('owner','operator','finance')
  union all select jsonb_build_object('id','gate:'||g.task_key||':'||g.gate_kind$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_CORE_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end;
$patch$;


do $patch$
declare v_definition text;v_body text;v_old text;v_new text;
begin
 select pg_get_functiondef(p.oid),p.prosrc into v_definition,v_body from pg_proc p where p.oid='private.pandora_core_onboarding_verify_v1(uuid)'::regprocedure;
 if encode(extensions.digest(v_body,'sha256'),'hex')<>'6ba54ded85bbf32428ff7a432653d923ce561fc1f36ed152f0c88055c24b0b96' then raise exception 'ADMISSION_ONBOARDING_SOURCE_DRIFT';end if;
 v_old:=$old$   when 'limits' then
    select exists(select 1 from public.pandora_customer_subscriptions cs join public.pandora_service_plans p on p.id=cs.plan_id where cs.organization_id=p_organization_id and p.limits<>'{}'::jsonb and cs.state not in ('cancelled','suspended')) into v_ok;
    v_reason:=case when v_ok then 'Server-side plan limits are recorded; execution enforcement is separate' else 'Record plan limits and confirm enforcement before go-live' end;
$old$;
 v_new:=$new$   when 'limits' then
    select exists(select 1 from public.pandora_customer_subscriptions cs join public.pandora_service_plans p on p.id=cs.plan_id
     where cs.organization_id=p_organization_id and p.state='active' and cs.state in ('active','trial') and p.limits<>'{}'::jsonb
      and ((p.request_admission_policy='record_only' and not cs.request_admission_enabled)
       or (cs.request_admission_enabled and private.pandora_chat_request_policy_v1(cs.organization_id,clock_timestamp())->>'request_admission_state' in ('enforcing','limit_reached')))) into v_ok;
    v_reason:=case
     when v_ok and exists(select 1 from public.pandora_customer_subscriptions where organization_id=p_organization_id and request_admission_enabled)
      then 'Cloud-chat request protection is enabled; other allowances remain commercial records'
     when v_ok then 'Commercial allowances recorded; cloud-chat request protection is not enabled'
     when exists(select 1 from public.pandora_customer_subscriptions cs join public.pandora_service_plans p on p.id=cs.plan_id where cs.organization_id=p_organization_id and p.request_admission_policy='block' and not cs.request_admission_enabled)
      then 'Enable this plan''s cloud-chat request protection before go-live'
     else 'Review the active plan and request-admission configuration before go-live' end;
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'ADMISSION_ONBOARDING_PATCH_NOT_FOUND';end if;
 execute replace(v_definition,v_old,v_new);
end;
$patch$;

commit;
