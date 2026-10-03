begin;

-- The conversation owns logical turns. Activity remains the execution/side-effect
-- owner. A delivery or retry cannot manufacture a second message or execution.
create table public.pandora_chat_turns (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  actor_user_id uuid not null references auth.users(id),
  thread_id uuid not null references public.pandora_intelligence_threads(id),
  project_id uuid,
  user_message_id uuid not null unique references public.pandora_intelligence_messages(id),
  request_fingerprint text not null check(request_fingerprint ~ '^[0-9a-f]{64}$'),
  turn_sequence bigint not null check(turn_sequence > 0),
  current_generation integer not null default 1 check(current_generation between 1 and 100),
  superseded_by uuid references public.pandora_chat_turns(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(thread_id,turn_sequence)
);
create table public.pandora_chat_turn_attempts (
  id uuid primary key,
  turn_id uuid not null references public.pandora_chat_turns(id),
  organization_id uuid not null references public.organizations(id),
  generation integer not null check(generation between 1 and 100),
  activity_job_id uuid not null unique references public.pandora_activity_jobs(id),
  model_run_id uuid references public.pandora_model_runs(id),
  assistant_message_id uuid unique references public.pandora_intelligence_messages(id),
  status text not null default 'accepted' check(status in
    ('accepted','processing','streaming','completed','cancelled','failed_recoverably',
     'failed_permanently','outcome_unknown','superseded')),
  last_event_sequence bigint not null default 1 check(last_event_sequence > 0),
  error_code text check(error_code is null or error_code ~ '^[A-Za-z0-9_:.-]{1,160}$'),
  retryable boolean not null default false,
  result jsonb check(result is null or octet_length(result::text) <= 131072),
  timings jsonb not null default '{}'::jsonb check(jsonb_typeof(timings)='object'),
  cancellation_requested_at timestamptz,
  uncertainty_acknowledged_at timestamptz,
  accepted_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique(turn_id,generation),
  check(uncertainty_acknowledged_at is null or cancellation_requested_at is not null)
);
create index pandora_chat_turns_actor_thread_idx on public.pandora_chat_turns(organization_id,actor_user_id,thread_id,turn_sequence);
create index pandora_chat_turn_attempts_turn_idx on public.pandora_chat_turn_attempts(turn_id,generation desc);
-- A negative admission receipt prevents a delayed first send from starting
-- after the actor explicitly cancels. It contains no message or execution.
create table private.pandora_chat_admission_tombstones_v2 (
  turn_id uuid not null,
  generation integer not null default 1 check(generation between 1 and 100),
  organization_id uuid not null references public.organizations(id),
  actor_user_id uuid not null references auth.users(id),
  attempt_id uuid not null unique,
  thread_id uuid references public.pandora_intelligence_threads(id),
  user_message_id uuid references public.pandora_intelligence_messages(id),
  cancelled_at timestamptz not null default clock_timestamp(),
  primary key(turn_id,generation),
  check((generation=1 and thread_id is null and user_message_id is null) or
        (generation>1 and thread_id is not null and user_message_id is not null))
);
revoke all on private.pandora_chat_admission_tombstones_v2 from public,anon,authenticated,service_role;
alter table public.pandora_intelligence_messages
  add column chat_turn_id uuid references public.pandora_chat_turns(id),
  add column chat_attempt_id uuid references public.pandora_chat_turn_attempts(id),
  add column chat_generation integer,
  add column client_origin text check(client_origin is null or client_origin in('local_device','character','device')),
  add column client_history_turn_id uuid,
  add column client_history_order bigint check(client_history_order is null or client_history_order>0);
create unique index pandora_chat_imported_history_uidx on public.pandora_intelligence_messages(thread_id,client_history_turn_id,author_role)
 where client_history_turn_id is not null;
create unique index pandora_chat_assistant_generation_uidx
  on public.pandora_intelligence_messages(chat_turn_id,chat_generation)
  where chat_turn_id is not null and author_role='assistant';

alter table public.pandora_chat_turns enable row level security;
alter table public.pandora_chat_turn_attempts enable row level security;
revoke all on public.pandora_chat_turns,public.pandora_chat_turn_attempts from public,anon,authenticated;
grant select on public.pandora_chat_turns,public.pandora_chat_turn_attempts to authenticated;
grant all on public.pandora_chat_turns,public.pandora_chat_turn_attempts to service_role;
create policy chat_turn_owner_read on public.pandora_chat_turns for select to authenticated using
  (actor_user_id=auth.uid() and exists(select 1 from public.memberships m
   where m.organization_id=pandora_chat_turns.organization_id and m.user_id=auth.uid() and m.status='active'));
create policy chat_attempt_owner_read on public.pandora_chat_turn_attempts for select to authenticated using
  (exists(select 1 from public.pandora_chat_turns t where t.id=turn_id and t.actor_user_id=auth.uid()));

create function private.pandora_chat_turn_authorize_v2(p_org uuid,p_turn uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.pandora_chat_turns t
    join public.pandora_intelligence_threads h on h.id=t.thread_id
    join public.memberships m on m.organization_id=t.organization_id and m.user_id=t.actor_user_id
    where t.id=p_turn and t.organization_id=p_org and t.actor_user_id=auth.uid()
      and h.organization_id=p_org and h.created_by=auth.uid() and h.status='active' and m.status='active')
  then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
end; $$;

create function private.pandora_chat_cancelled_admission_receipt_v2(p_turn uuid,p_generation integer default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('protocolVersion',2,'found',true,'admitted',false,'admissionCancelled',true,
   'organizationId',organization_id,'threadId',thread_id,'turnId',turn_id,'attemptId',attempt_id,
   'activityJobId',null,'userMessageId',user_message_id,'assistantMessageId',null,'generation',generation,'currentGeneration',generation,
   'turnSequence',(select t.turn_sequence from public.pandora_chat_turns t where t.id=p_turn),'supersededBy',null,
   'sequence',1,'status','cancelled','retryable',false,'cancellationRequested',true,'outcomeUnknownAcknowledged',false,
   'acceptedAt',null,'completedAt',cancelled_at,'result','{}'::jsonb,'timings','{}'::jsonb,'replayed',true)
 from private.pandora_chat_admission_tombstones_v2 x where turn_id=p_turn and
   (case when p_generation is not null then generation=p_generation else
     generation>=coalesce((select t.current_generation from public.pandora_chat_turns t where t.id=p_turn),1) end)
 order by generation desc limit 1;
$$;

create function private.pandora_chat_turn_receipt_v2(p_turn uuid,p_generation integer default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(private.pandora_chat_cancelled_admission_receipt_v2(p_turn,p_generation),(
 select coalesce(a.result,'{}'::jsonb)||jsonb_build_object('protocolVersion',2,'organizationId',t.organization_id,
   'threadId',t.thread_id,'turnId',t.id,'attemptId',a.id,'activityJobId',a.activity_job_id,
   'userMessageId',t.user_message_id,'assistantMessageId',a.assistant_message_id,
   'generation',a.generation,'currentGeneration',greatest(t.current_generation,coalesce((select max(x.generation) from private.pandora_chat_admission_tombstones_v2 x where x.turn_id=t.id),0)),
   'turnSequence',t.turn_sequence,'sequence',a.last_event_sequence,'status',a.status,
   'retryable',a.retryable,'errorCode',a.error_code,'supersededBy',t.superseded_by,
   'cancellationRequested',a.cancellation_requested_at is not null,
   'outcomeUnknownAcknowledged',a.uncertainty_acknowledged_at is not null,
   'acceptedAt',a.accepted_at,'completedAt',a.completed_at,'timings',a.timings,
   'result',a.result)
 from public.pandora_chat_turns t join public.pandora_chat_turn_attempts a
   on a.turn_id=t.id and a.generation=coalesce(p_generation,t.current_generation)
 where t.id=p_turn));
$$;

create function public.pandora_chat_turn_read_v2(p_organization_id uuid,p_turn_id uuid,p_generation integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tombstone private.pandora_chat_admission_tombstones_v2%rowtype;
begin
 if not exists(select 1 from public.pandora_chat_turns where id=p_turn_id) then
   if auth.uid() is null or not exists(select 1 from public.memberships where organization_id=p_organization_id and user_id=auth.uid() and status='active')
   then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
   select * into tombstone from private.pandora_chat_admission_tombstones_v2 where turn_id=p_turn_id and generation=1;
   if found then
     if tombstone.organization_id<>p_organization_id or tombstone.actor_user_id<>auth.uid() then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
     if p_generation is not null and p_generation<>1 then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
     return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id);
   end if;
   return jsonb_build_object('protocolVersion',2,'found',false,'turnId',p_turn_id);
 end if;
 perform private.pandora_chat_turn_authorize_v2(p_organization_id,p_turn_id);
 return private.pandora_chat_turn_receipt_v2(p_turn_id,p_generation)||jsonb_build_object('found',true,'replayed',true);
end; $$;

create function public.pandora_chat_history_v2(p_thread_id uuid,p_exclude_user_message_id uuid default null,p_limit integer default 32)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.pandora_intelligence_threads h join public.memberships m
   on m.organization_id=h.organization_id and m.user_id=auth.uid() and m.status='active'
   where h.id=p_thread_id and h.created_by=auth.uid() and h.status='active')
 then raise exception 'CHAT_THREAD_NOT_AVAILABLE' using errcode='42501'; end if;
 if p_limit not between 2 and 64 then raise exception 'CHAT_HISTORY_LIMIT_INVALID' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_data order by turn_at,turn_sequence,role_order,created_at,id),'[]') into rows from (
   select jsonb_build_object('id',m.id,'author_role',m.author_role,'content',m.content,'client_origin',m.client_origin) row_data,
     coalesce(t.created_at,m.created_at) turn_at,coalesce(t.turn_sequence,m.client_history_order) turn_sequence,
     case when m.author_role='user' then 0 else 1 end role_order,m.created_at,m.id
   from public.pandora_intelligence_messages m left join public.pandora_chat_turns t on t.id=m.chat_turn_id
   left join public.pandora_chat_turn_attempts a on a.turn_id=t.id and a.generation=t.current_generation
   where m.thread_id=p_thread_id and m.author_role in('user','assistant') and m.id is distinct from p_exclude_user_message_id
     and (t.id is null or (a.status='completed' and (m.author_role='user' or m.chat_generation=t.current_generation)))
   order by coalesce(t.created_at,m.created_at) desc,coalesce(t.turn_sequence,m.client_history_order) desc,
     case when m.author_role='user' then 0 else 1 end desc,m.created_at desc,m.id desc limit p_limit
 ) recent;
 return rows;
end; $$;

create function public.pandora_chat_thread_view_v2(p_thread_id uuid,p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare messages jsonb; turns jsonb; total bigint;
begin
 if auth.uid() is null or not exists(select 1 from public.pandora_intelligence_threads h join public.memberships m
   on m.organization_id=h.organization_id and m.user_id=auth.uid() and m.status='active'
   where h.id=p_thread_id and h.created_by=auth.uid() and h.status='active')
 then raise exception 'CHAT_THREAD_NOT_AVAILABLE' using errcode='42501'; end if;
 if p_limit not between 2 and 500 then raise exception 'CHAT_HISTORY_LIMIT_INVALID' using errcode='22023'; end if;
 select coalesce(jsonb_agg(row_data order by turn_at,turn_sequence,role_order,created_at,id),'[]') into messages from (
   select jsonb_build_object('id',m.id,'thread_id',m.thread_id,'author_role',m.author_role,'content',m.content,
     'created_at',m.created_at,'chat_turn_id',m.chat_turn_id,'chat_attempt_id',m.chat_attempt_id,'chat_generation',m.chat_generation,
     'structured_response',case when m.author_role='assistant'
       and m.structured_response->'handoff'->'required'='true'::jsonb
       and m.structured_response->'handoff'->>'kind'='core_navigation'
       and m.structured_response->'handoff'->>'action'='inspect'
       and m.structured_response->'handoff'->>'section' in('clients','business','platform','administration')
       and jsonb_typeof(m.structured_response->'handoff'->'request')='string'
       and length(trim(m.structured_response->'handoff'->>'request')) between 1 and 160
       and (m.structured_response->'handoff'->>'organizationId' is null or
         m.structured_response->'handoff'->>'organizationId' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
       then jsonb_build_object('handoff',jsonb_strip_nulls(jsonb_build_object(
         'required',true,'kind','core_navigation','source','core_navigation','action','inspect',
         'request',m.structured_response->'handoff'->>'request','section',m.structured_response->'handoff'->>'section',
         'organizationId',m.structured_response->'handoff'->>'organizationId')))
       else '{}'::jsonb end,
     'turn_sequence',t.turn_sequence,'client_origin',m.client_origin,'client_history_turn_id',m.client_history_turn_id,'client_history_order',m.client_history_order,
     'status',coalesce(private.pandora_chat_turn_receipt_v2(t.id)->>'status',a.status),'retryable',coalesce((private.pandora_chat_turn_receipt_v2(t.id)->>'retryable')::boolean,a.retryable,false)) row_data,
     coalesce(t.created_at,m.created_at) turn_at,coalesce(t.turn_sequence,m.client_history_order) turn_sequence,case when m.author_role='user' then 0 else 1 end role_order,m.created_at,m.id
   from public.pandora_intelligence_messages m left join public.pandora_chat_turns t on t.id=m.chat_turn_id
   left join public.pandora_chat_turn_attempts a on a.turn_id=t.id and a.generation=t.current_generation
   where m.thread_id=p_thread_id and m.author_role in('user','assistant')
     and (m.author_role='user' or t.id is null or (m.chat_generation=t.current_generation and a.status='completed'))
   order by coalesce(t.created_at,m.created_at) desc,coalesce(t.turn_sequence,m.client_history_order) desc,
     case when m.author_role='user' then 0 else 1 end desc,m.created_at desc,m.id desc limit p_limit
 ) recent;
 select coalesce(jsonb_agg(private.pandora_chat_turn_receipt_v2(t.id) order by t.turn_sequence),'[]') into turns
   from public.pandora_chat_turns t where t.thread_id=p_thread_id
   and exists(select 1 from jsonb_array_elements(messages) m where m->>'chat_turn_id'=t.id::text);
 select count(*) into total from public.pandora_intelligence_messages where thread_id=p_thread_id and author_role in('user','assistant');
 return jsonb_build_object('protocolVersion',2,'threadId',p_thread_id,'messages',messages,'turns',turns,'hasMore',total>p_limit);
end; $$;

create function public.pandora_chat_turn_admit_v2(
 p_organization_id uuid,p_turn_id uuid,p_attempt_id uuid,p_request_sha256 text,p_message text,
 p_thread_id uuid default null,p_project_id uuid default null,p_attachment_manifest jsonb default '[]',p_entry_id uuid default null,p_client_history jsonb default '[]')
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; h public.pandora_intelligence_threads%rowtype; tombstone private.pandora_chat_admission_tombstones_v2%rowtype;
 mid uuid; jid uuid; seq bigint; prior public.pandora_chat_turn_attempts%rowtype; local_message jsonb; local_order bigint;
begin
 perform public.pandora_enterprise_chat_authority_v1(p_organization_id,p_entry_id);
 if p_turn_id is null or p_attempt_id is null or p_request_sha256 !~ '^[0-9a-f]{64}$'
   or length(trim(coalesce(p_message,''))) not between 1 and 8000
   or jsonb_typeof(p_attachment_manifest)<>'array' or jsonb_array_length(p_attachment_manifest)>4
   or jsonb_typeof(p_client_history)<>'array' or jsonb_array_length(p_client_history)>32 or octet_length(p_client_history::text)>32768
 then raise exception 'CHAT_TURN_REQUEST_INVALID' using errcode='22023'; end if;
 -- Serialize both initial deliveries (before a thread exists) and same-thread sends.
 perform pg_advisory_xact_lock(hashtextextended(p_turn_id::text,98142));
 select * into tombstone from private.pandora_chat_admission_tombstones_v2 where turn_id=p_turn_id and generation=1;
 if found then
   if tombstone.organization_id<>p_organization_id or tombstone.actor_user_id<>auth.uid() then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
   if tombstone.attempt_id<>p_attempt_id then raise exception 'CHAT_TURN_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
   return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id);
 end if;
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 if found then
   perform private.pandora_chat_turn_authorize_v2(p_organization_id,p_turn_id);
   if t.request_fingerprint<>p_request_sha256 or (p_thread_id is not null and t.thread_id<>p_thread_id)
     or t.project_id is distinct from p_project_id
     or not exists(select 1 from public.pandora_intelligence_messages m where m.id=t.user_message_id and m.content=p_message and m.attachment_manifest=p_attachment_manifest)
     or not exists(select 1 from public.pandora_chat_turn_attempts a where a.turn_id=t.id and a.generation=1 and a.id=p_attempt_id)
   then raise exception 'CHAT_TURN_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
   return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('replayed',true);
 end if;
 if p_thread_id is null then
   insert into public.pandora_intelligence_threads(organization_id,project_id,created_by,title)
     values(p_organization_id,p_project_id,auth.uid(),left(regexp_replace(p_message,'\s+',' ','g'),80)) returning * into h;
 else
   select * into h from public.pandora_intelligence_threads where id=p_thread_id for update;
   if not found or h.organization_id<>p_organization_id or h.created_by<>auth.uid() or h.status<>'active'
      or (p_project_id is not null and h.project_id is distinct from p_project_id)
   then raise exception 'CHAT_THREAD_NOT_AVAILABLE' using errcode='42501'; end if;
 end if;
 select a.* into prior from public.pandora_chat_turns x join public.pandora_chat_turn_attempts a
   on a.turn_id=x.id and a.generation=x.current_generation where x.thread_id=h.id
   and (a.status in('accepted','processing','streaming') or
        (a.status='outcome_unknown' and a.uncertainty_acknowledged_at is null)) limit 1;
 if found then raise exception 'CHAT_THREAD_BUSY' using errcode='55000'; end if;
 select coalesce(max(turn_sequence),0)+1 into seq from public.pandora_chat_turns where thread_id=h.id;
 select coalesce(max(client_history_order),0) into local_order from public.pandora_intelligence_messages where thread_id=h.id;
 for local_message in select value from jsonb_array_elements(p_client_history) loop
   if coalesce(local_message->>'logicalTurnId','')!~'^[0-9a-fA-F-]{36}$'
     or coalesce(local_message->>'role','') not in('user','assistant')
     or coalesce(local_message->>'source','') not in('local_device','character','device')
     or length(trim(coalesce(local_message->>'content',''))) not between 1 and 8000 then
     raise exception 'CHAT_CLIENT_HISTORY_INVALID' using errcode='22023'; end if;
   if exists(select 1 from public.pandora_intelligence_messages m where m.thread_id=h.id
     and m.client_history_turn_id=(local_message->>'logicalTurnId')::uuid and m.author_role=local_message->>'role'
     and (m.content<>local_message->>'content' or m.client_origin<>local_message->>'source')) then
     raise exception 'CHAT_CLIENT_HISTORY_CONFLICT' using errcode='23505'; end if;
   local_order:=local_order+1;
   insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,client_origin,client_history_turn_id,client_history_order,
     structured_response)
   values(h.id,p_organization_id,p_project_id,local_message->>'role',local_message->>'content',local_message->>'source',
     (local_message->>'logicalTurnId')::uuid,local_order,jsonb_build_object('source','client_supplied_history','executionVerified',false))
   on conflict(thread_id,client_history_turn_id,author_role) where client_history_turn_id is not null do nothing;
 end loop;
 insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,attachment_manifest)
   values(h.id,p_organization_id,p_project_id,'user',p_message,p_attachment_manifest) returning id into mid;
 jid:=(public.pandora_core_activity_begin_v1(p_organization_id,'chat-v2:'||p_attempt_id,h.id,p_project_id,p_entry_id)->>'jobId')::uuid;
 insert into public.pandora_chat_turns(id,organization_id,actor_user_id,thread_id,project_id,user_message_id,request_fingerprint,turn_sequence)
   values(p_turn_id,p_organization_id,auth.uid(),h.id,p_project_id,mid,p_request_sha256,seq);
 insert into public.pandora_chat_turn_attempts(id,turn_id,organization_id,generation,activity_job_id)
   values(p_attempt_id,p_turn_id,p_organization_id,1,jid);
 update public.pandora_intelligence_messages set chat_turn_id=p_turn_id,chat_attempt_id=p_attempt_id,chat_generation=1 where id=mid;
 return private.pandora_chat_turn_receipt_v2(p_turn_id)||jsonb_build_object('replayed',false);
end; $$;

-- External mutation admission and cancellation serialize on the same turn lock.
-- A separate preflight followed by the old Activity checkpoint would leave a
-- cancellation window in which a supposedly cancelled turn could still mutate.
create function public.pandora_chat_turn_effect_v2(p_turn_id uuid,p_attempt_id uuid,p_generation integer,p_claim_id uuid,p_phase text,p_result jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into a from public.pandora_chat_turn_attempts where id=p_attempt_id and turn_id=t.id and generation=p_generation for update;
 if not found or t.current_generation<>p_generation or p_phase not in('begin','verified') then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if p_claim_id is null or j.execution_claim_id is distinct from p_claim_id or j.execution_state<>'running'
 then raise exception 'CHAT_EXECUTION_CLAIM_STALE' using errcode='55000'; end if;
 if p_phase='begin' then
   if a.status not in('accepted','processing') or a.cancellation_requested_at is not null then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
   perform public.pandora_activity_execution_checkpoint_v1(j.id,p_claim_id,'capability_dispatching','chat-turn:'||t.id,'ambiguous',null);
 else
   if a.status not in('accepted','processing','outcome_unknown') or j.execution_effect_state<>'ambiguous'
      or length(trim(coalesce(p_result->>'reply',''))) not between 1 and 32000 or octet_length(p_result::text)>131072
   then raise exception 'CHAT_EFFECT_RECEIPT_INVALID' using errcode='55000'; end if;
   perform public.pandora_activity_execution_checkpoint_v1(j.id,p_claim_id,'result_persisted','chat-turn:'||t.id,'verified',p_result);
 end if;
 return private.pandora_chat_turn_receipt_v2(t.id);
end; $$;

create function public.pandora_chat_turn_retry_v2(
 p_organization_id uuid,p_turn_id uuid,p_attempt_id uuid,p_expected_generation integer,p_request_sha256 text,p_entry_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype; jid uuid; tombstone private.pandora_chat_admission_tombstones_v2%rowtype;
begin
 perform private.pandora_chat_turn_authorize_v2(p_organization_id,p_turn_id);
 perform pg_advisory_xact_lock(hashtextextended(p_turn_id::text,98142));
 perform public.pandora_enterprise_chat_authority_v1(p_organization_id,p_entry_id);
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into tombstone from private.pandora_chat_admission_tombstones_v2 where turn_id=p_turn_id order by generation desc limit 1;
 if found then
   if tombstone.generation=p_expected_generation+1 and tombstone.attempt_id=p_attempt_id then
     return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id,tombstone.generation);
   end if;
   raise exception 'CHAT_RECONCILIATION_REQUIRED' using errcode='55000';
 end if;
 if t.request_fingerprint is distinct from p_request_sha256 or p_attempt_id is null
 then raise exception 'CHAT_TURN_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
 select * into a from public.pandora_chat_turn_attempts where turn_id=t.id and generation=t.current_generation for update;
 if a.id=p_attempt_id and a.generation=p_expected_generation+1 then
   return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('replayed',true);
 end if;
 if t.current_generation is distinct from p_expected_generation or p_expected_generation>=100
 then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if not a.retryable or a.status not in('failed_recoverably','superseded')
    or j.execution_effect_state<>'none' or j.execution_state<>'failed'
 then raise exception 'CHAT_RECONCILIATION_REQUIRED' using errcode='55000'; end if;
 perform 1 from public.pandora_intelligence_threads where id=t.thread_id for update;
 if exists(select 1 from public.pandora_chat_turns x join public.pandora_chat_turn_attempts y
   on y.turn_id=x.id and y.generation=x.current_generation where x.thread_id=t.thread_id and x.id<>t.id
   and (y.status in('accepted','processing','streaming') or
        (y.status='outcome_unknown' and y.uncertainty_acknowledged_at is null)))
 then raise exception 'CHAT_THREAD_BUSY' using errcode='55000'; end if;
 jid:=(public.pandora_core_activity_begin_v1(p_organization_id,'chat-v2:'||p_attempt_id,t.thread_id,t.project_id,p_entry_id)->>'jobId')::uuid;
 update public.pandora_chat_turn_attempts set status='superseded',updated_at=clock_timestamp() where id=a.id;
 update public.pandora_chat_turns set current_generation=current_generation+1,superseded_by=null,updated_at=clock_timestamp() where id=t.id;
 insert into public.pandora_chat_turn_attempts(id,turn_id,organization_id,generation,activity_job_id)
   values(p_attempt_id,t.id,p_organization_id,p_expected_generation+1,jid);
 return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('replayed',false);
end; $$;

create function public.pandora_chat_turn_cancel_v2(p_organization_id uuid,p_turn_id uuid,p_expected_generation integer,p_attempt_id uuid default null,p_acknowledge_unknown boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype;
 tombstone private.pandora_chat_admission_tombstones_v2%rowtype;
begin
 if auth.uid() is null or not exists(select 1 from public.memberships where organization_id=p_organization_id and user_id=auth.uid() and status='active')
 then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
 if p_turn_id is null or p_expected_generation is null or p_expected_generation not between 1 and 100 or p_acknowledge_unknown is null
 then raise exception 'CHAT_TURN_REQUEST_INVALID' using errcode='22023'; end if;
 if p_acknowledge_unknown and p_attempt_id is null then raise exception 'CHAT_CANCEL_ATTEMPT_REQUIRED' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn_id::text,98142));
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 if not found then
   if p_acknowledge_unknown then raise exception 'CHAT_OUTCOME_NOT_UNKNOWN' using errcode='55000'; end if;
   if p_expected_generation is distinct from 1 or p_attempt_id is null then raise exception 'CHAT_CANCEL_ATTEMPT_REQUIRED' using errcode='22023'; end if;
   select * into tombstone from private.pandora_chat_admission_tombstones_v2 where turn_id=p_turn_id for update;
   if found then
     if tombstone.organization_id<>p_organization_id or tombstone.actor_user_id<>auth.uid() then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
     if tombstone.attempt_id<>p_attempt_id then raise exception 'CHAT_TURN_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
   else
     insert into private.pandora_chat_admission_tombstones_v2(turn_id,organization_id,actor_user_id,attempt_id)
       values(p_turn_id,p_organization_id,auth.uid(),p_attempt_id);
   end if;
   return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id);
 end if;
 perform private.pandora_chat_turn_authorize_v2(p_organization_id,p_turn_id);
 if t.current_generation is distinct from p_expected_generation then
   if p_acknowledge_unknown then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
   -- A lost retry ACK can be cancelled without restoring private attachment
   -- bytes: either retry won this lock and exists below, or this exact future
   -- attempt is negatively admitted while its predecessor remains audit data.
   if p_expected_generation<>t.current_generation+1 or p_expected_generation>100 or p_attempt_id is null
   then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
   select * into tombstone from private.pandora_chat_admission_tombstones_v2 where turn_id=p_turn_id order by generation desc limit 1 for update;
   if found then
     if tombstone.generation<>p_expected_generation or tombstone.attempt_id<>p_attempt_id then raise exception 'CHAT_TURN_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
     return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id,p_expected_generation);
   end if;
   select * into a from public.pandora_chat_turn_attempts where turn_id=t.id and generation=t.current_generation for update;
   select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
   if a.status not in('failed_recoverably','superseded') or not a.retryable or j.execution_state<>'failed' or j.execution_effect_state<>'none'
   then raise exception 'CHAT_RECONCILIATION_REQUIRED' using errcode='55000'; end if;
   insert into private.pandora_chat_admission_tombstones_v2(turn_id,generation,organization_id,actor_user_id,attempt_id,thread_id,user_message_id)
     values(t.id,p_expected_generation,t.organization_id,t.actor_user_id,p_attempt_id,t.thread_id,t.user_message_id);
   return private.pandora_chat_cancelled_admission_receipt_v2(p_turn_id,p_expected_generation);
 end if;
 select * into a from public.pandora_chat_turn_attempts where turn_id=t.id and generation=t.current_generation for update;
 if p_attempt_id is not null and a.id<>p_attempt_id then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 if a.status not in('accepted','processing','streaming','outcome_unknown') then return private.pandora_chat_turn_receipt_v2(t.id); end if;
 if p_acknowledge_unknown and a.status<>'outcome_unknown' then raise exception 'CHAT_OUTCOME_NOT_UNKNOWN' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if j.execution_effect_state='verified' and j.execution_result is not null then
   -- A verified execution result takes precedence; readback must reconcile it.
   update public.pandora_chat_turn_attempts set cancellation_requested_at=coalesce(cancellation_requested_at,clock_timestamp()),
     status='outcome_unknown',last_event_sequence=last_event_sequence+1 where id=a.id;
 else
   -- A repeated ordinary Stop cannot acknowledge uncertainty. A separate
   -- explicit action releases only conversation admission, never the original
   -- ambiguous effect, execution claim, retry fence, or diagnostic evidence.
   if a.uncertainty_acknowledged_at is not null or
      (not p_acknowledge_unknown and a.cancellation_requested_at is not null)
   then return private.pandora_chat_turn_receipt_v2(t.id); end if;
   if a.cancellation_requested_at is null and j.terminal_state is null and j.controls_sealed_at is null then
     perform public.pandora_activity_control_request_v1(p_organization_id,j.id,'chat-v2-cancel:'||a.id,'cancel',null);
   end if;
   update public.pandora_chat_turn_attempts set cancellation_requested_at=coalesce(cancellation_requested_at,clock_timestamp()),
     uncertainty_acknowledged_at=case when p_acknowledge_unknown then clock_timestamp() else uncertainty_acknowledged_at end,
     status=case when p_acknowledge_unknown or j.execution_effect_state='ambiguous' then 'outcome_unknown' else 'cancelled' end,
     retryable=false,last_event_sequence=last_event_sequence+1,updated_at=clock_timestamp(),
     completed_at=case when not p_acknowledge_unknown and j.execution_effect_state='none' then clock_timestamp() else completed_at end where id=a.id;
   if j.execution_effect_state='none' then
     -- This authenticated wrapper has already locked and authorized the exact
     -- owned turn/job. Do not forge a service-role JWT to call its private API.
     update public.pandora_activity_jobs set execution_state='cancelled',execution_checkpoint='terminal',
       execution_error_code='REQUEST_CANCELLED',execution_updated_at=clock_timestamp(),updated_at=clock_timestamp() where id=j.id;
   end if;
 end if;
 return private.pandora_chat_turn_receipt_v2(t.id);
end; $$;

create function public.pandora_chat_turn_transition_v2(
 p_turn_id uuid,p_attempt_id uuid,p_generation integer,p_claim_id uuid,p_status text,
 p_sequence bigint default null,p_error_code text default null,p_retryable boolean default false,p_timings jsonb default '{}',p_model_run_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype; s text;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into a from public.pandora_chat_turn_attempts where id=p_attempt_id and turn_id=t.id and generation=p_generation for update;
 if not found or t.current_generation<>p_generation then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if p_claim_id is null or j.execution_claim_id is distinct from p_claim_id then raise exception 'CHAT_EXECUTION_CLAIM_STALE' using errcode='55000'; end if;
 if a.status in('completed','cancelled','superseded','failed_recoverably','failed_permanently') then
   return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('applied',false);
 end if;
 if p_status not in('processing','streaming','cancelled','failed_recoverably','failed_permanently','outcome_unknown')
    or (p_status='processing' and a.status not in('accepted','processing'))
    or (p_status='streaming' and a.status not in('processing','streaming'))
    or jsonb_typeof(p_timings)<>'object' or octet_length(p_timings::text)>4096
 then raise exception 'CHAT_TRANSITION_INVALID' using errcode='22023'; end if;
 -- Once the user explicitly stops waiting, stale failures cannot re-open a
 -- retry path or overwrite the uncertainty audit. Only verified completion
 -- through the original claim can resolve this attempt afterwards.
 if a.uncertainty_acknowledged_at is not null then
   return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('applied',false);
 end if;
 s:=p_status;
 if p_status in('failed_recoverably','failed_permanently','cancelled') and j.execution_effect_state in('ambiguous','verified') then s:='outcome_unknown'; end if;
 update public.pandora_chat_turn_attempts set status=s,error_code=p_error_code,
   retryable=(p_retryable and s='failed_recoverably' and j.execution_effect_state='none'),
   last_event_sequence=greatest(last_event_sequence+1,coalesce(p_sequence,0)),timings=timings||p_timings,
   model_run_id=coalesce(p_model_run_id,model_run_id),updated_at=clock_timestamp(),
   completed_at=case when s in('failed_recoverably','failed_permanently','cancelled') then clock_timestamp() else completed_at end where id=a.id;
 -- Turn failure and original Activity finalization share one lock/transaction.
 -- A lost completion acknowledgement therefore cannot reverse a committed
 -- successful execution through the old Activity finish endpoint.
 if s in('failed_recoverably','failed_permanently','cancelled') and j.execution_effect_state='none' then
   perform public.pandora_activity_execution_finish_v1(j.id,p_claim_id,case when s='cancelled' then 'cancelled' else 'failed' end,null,p_error_code);
 end if;
 return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('applied',true);
end; $$;

-- Context is private and exists only inside the adapter's transaction. A client
-- cannot impersonate this context with set_config or by matching message text.
create table private.pandora_chat_dispatch_context_v2 (
 transaction_id bigint primary key,turn_id uuid not null,attempt_id uuid not null,generation integer not null,claim_id uuid not null
);
revoke all on private.pandora_chat_dispatch_context_v2 from public,anon,authenticated,service_role;
create function private.pandora_chat_bind_dispatch_message_v2()
returns trigger language plpgsql security definer set search_path='' as $$
declare x private.pandora_chat_dispatch_context_v2%rowtype; t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype;
begin
 select * into x from private.pandora_chat_dispatch_context_v2 where transaction_id=txid_current();
 if not found then return new; end if;
 select * into t from public.pandora_chat_turns where id=x.turn_id;
 select * into a from public.pandora_chat_turn_attempts where id=x.attempt_id;
 if new.thread_id<>t.thread_id or new.organization_id<>t.organization_id or t.current_generation<>x.generation
   or a.status not in('accepted','processing','streaming') or a.cancellation_requested_at is not null
 then raise exception 'CHAT_DISPATCH_SCOPE_STALE' using errcode='55000'; end if;
 if new.author_role='user' then return null; end if;
 if new.author_role<>'assistant' then raise exception 'CHAT_DISPATCH_MESSAGE_INVALID' using errcode='22023'; end if;
 new.chat_turn_id:=t.id;new.chat_attempt_id:=a.id;new.chat_generation:=a.generation;
 return new;
end; $$;
create trigger pandora_chat_bind_dispatch_message_v2 before insert on public.pandora_intelligence_messages
 for each row execute function private.pandora_chat_bind_dispatch_message_v2();

create function public.pandora_chat_dispatch_turn_v2(p_organization_id uuid,p_turn_id uuid,p_attempt_id uuid,p_generation integer,p_claim_id uuid,p_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype; r jsonb;
begin
 perform private.pandora_chat_turn_authorize_v2(p_organization_id,p_turn_id);
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into a from public.pandora_chat_turn_attempts where id=p_attempt_id and turn_id=t.id and generation=p_generation for update;
 if not found or t.current_generation<>p_generation or a.status not in('accepted','processing') or a.cancellation_requested_at is not null
 then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if j.execution_claim_id is distinct from p_claim_id or j.execution_state<>'running' then raise exception 'CHAT_EXECUTION_CLAIM_STALE' using errcode='55000'; end if;
 insert into private.pandora_chat_dispatch_context_v2 values(txid_current(),t.id,a.id,p_generation,p_claim_id);
 r:=public.pandora_chat_universal_dispatch_v9(p_organization_id,p_message,t.thread_id,t.project_id);
 delete from private.pandora_chat_dispatch_context_v2 where transaction_id=txid_current();
 if coalesce((r->>'handled')::boolean,false) then
   select id into a.assistant_message_id from public.pandora_intelligence_messages
     where chat_turn_id=t.id and chat_generation=p_generation and author_role='assistant';
   if a.assistant_message_id is null then raise exception 'CHAT_DISPATCH_RESULT_NOT_PERSISTED' using errcode='55000'; end if;
   update public.pandora_chat_turn_attempts set assistant_message_id=a.assistant_message_id where id=a.id;
   -- Preserve the original dispatch receipt in the same transaction as its
   -- message. A lost Edge callback can then reconcile, never repeat the action.
   update public.pandora_activity_jobs set execution_checkpoint='result_persisted',
     execution_checkpoint_ref='chat-turn:'||t.id,execution_effect_state='verified',execution_result=r,
     execution_updated_at=clock_timestamp(),updated_at=clock_timestamp() where id=j.id;
 elsif exists(select 1 from public.pandora_intelligence_messages where chat_turn_id=t.id and chat_attempt_id=a.id and author_role='assistant') then
   raise exception 'CHAT_DISPATCH_RESULT_CONFLICT' using errcode='55000';
 end if;
 return r;
end; $$;

create function public.pandora_chat_turn_complete_v2(
 p_turn_id uuid,p_attempt_id uuid,p_generation integer,p_claim_id uuid,p_result jsonb,
 p_message jsonb default '{}',p_sequence bigint default null,p_timings jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype; mid uuid; r jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into a from public.pandora_chat_turn_attempts where id=p_attempt_id and turn_id=t.id and generation=p_generation for update;
 if not found or t.current_generation<>p_generation then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if p_claim_id is null or j.execution_claim_id is distinct from p_claim_id then raise exception 'CHAT_EXECUTION_CLAIM_STALE' using errcode='55000'; end if;
 if a.status='completed' then return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('replayed',true); end if;
 if a.status not in('accepted','processing','streaming','outcome_unknown') or
    (a.cancellation_requested_at is not null and not(j.execution_effect_state='verified' and j.execution_result is not null))
 then raise exception 'CHAT_GENERATION_STALE' using errcode='55000'; end if;
 if jsonb_typeof(p_result)<>'object' or length(trim(coalesce(p_result->>'reply',''))) not between 1 and 32000
   or octet_length(p_result::text)>131072 or jsonb_typeof(p_timings)<>'object' or octet_length(p_timings::text)>4096
 then raise exception 'CHAT_COMPLETION_INVALID' using errcode='22023'; end if;
 mid:=a.assistant_message_id;
 if mid is null then
   insert into public.pandora_intelligence_messages(thread_id,organization_id,project_id,author_role,content,
     structured_response,provider,model,request_sha256,response_sha256,input_tokens,output_tokens,total_tokens,
     trusted_context_sha256,trusted_skill_refs,trusted_knowledge_refs,chat_turn_id,chat_attempt_id,chat_generation)
   values(t.thread_id,t.organization_id,t.project_id,'assistant',p_result->>'reply',coalesce(p_message->'structured_response',p_result),
     p_message->>'provider',p_message->>'model',p_message->>'request_sha256',p_message->>'response_sha256',
     coalesce((p_message->>'input_tokens')::bigint,0),coalesce((p_message->>'output_tokens')::bigint,0),coalesce((p_message->>'total_tokens')::bigint,0),
     p_message->>'trusted_context_sha256',coalesce(p_message->'trusted_skill_refs','[]'),coalesce(p_message->'trusted_knowledge_refs','[]'),t.id,a.id,a.generation)
   returning id into mid;
 else
   if not exists(select 1 from public.pandora_intelligence_messages m where m.id=mid and m.chat_turn_id=t.id and m.chat_attempt_id=a.id and m.author_role='assistant')
   then raise exception 'CHAT_COMPLETION_MESSAGE_MISMATCH' using errcode='55000'; end if;
 end if;
 r:=p_result||jsonb_build_object('threadId',t.thread_id,'assistantMessageId',mid);
 update public.pandora_chat_turn_attempts set status='completed',result=r,assistant_message_id=mid,error_code=null,retryable=false,
   last_event_sequence=greatest(last_event_sequence+1,coalesce(p_sequence,0)),timings=timings||p_timings,
   updated_at=clock_timestamp(),completed_at=clock_timestamp() where id=a.id;
 -- Obsolete error evidence remains in attempts; its presentation is resolved.
 update public.pandora_chat_turns x set superseded_by=t.id,updated_at=clock_timestamp()
   where x.thread_id=t.thread_id and x.turn_sequence<t.turn_sequence and exists(select 1 from public.pandora_chat_turn_attempts y
   where y.turn_id=x.id and y.generation=x.current_generation and y.status in('failed_recoverably','failed_permanently'));
 update public.pandora_chat_turn_attempts y set status='superseded',updated_at=clock_timestamp()
   from public.pandora_chat_turns x where x.id=y.turn_id and x.superseded_by=t.id and x.current_generation=y.generation
   and y.status in('failed_recoverably','failed_permanently');
 update public.pandora_intelligence_threads set last_message_at=clock_timestamp(),updated_at=clock_timestamp() where id=t.thread_id;
 -- Commit the result and its original Activity claim in the same transaction.
 perform public.pandora_activity_execution_finish_v1(j.id,p_claim_id,'complete',r,null);
 return private.pandora_chat_turn_receipt_v2(t.id)||jsonb_build_object('replayed',false);
end; $$;

-- Readback may finish a verified original execution, but never dispatches a
-- provider or action. Unknown outcome stays unknown until evidence resolves it.
create function public.pandora_chat_turn_reconcile_v2(p_turn_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.pandora_chat_turns%rowtype; a public.pandora_chat_turn_attempts%rowtype; j public.pandora_activity_jobs%rowtype;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501'; end if;
 select * into t from public.pandora_chat_turns where id=p_turn_id for update;
 select * into a from public.pandora_chat_turn_attempts where turn_id=t.id and generation=t.current_generation for update;
 if not found then raise exception 'CHAT_TURN_NOT_AVAILABLE' using errcode='42501'; end if;
 if a.status in('completed','cancelled','superseded','failed_recoverably','failed_permanently') then return private.pandora_chat_turn_receipt_v2(t.id); end if;
 select * into j from public.pandora_activity_jobs where id=a.activity_job_id for update;
 if j.execution_effect_state='verified' and length(coalesce(j.execution_result->>'reply',''))>0 then
   return public.pandora_chat_turn_complete_v2(t.id,a.id,a.generation,j.execution_claim_id,j.execution_result);
 end if;
 if a.uncertainty_acknowledged_at is not null then return private.pandora_chat_turn_receipt_v2(t.id); end if;
 if j.execution_claim_id is not null and j.execution_state in('failed','cancelled') then
   return public.pandora_chat_turn_transition_v2(t.id,a.id,a.generation,j.execution_claim_id,
     case when j.execution_state='cancelled' then 'cancelled' else 'failed_recoverably' end,
     null,coalesce(j.execution_error_code,'CHAT_EXECUTION_INTERRUPTED'),j.execution_state='failed');
 end if;
 if j.execution_state='ready' and a.accepted_at<clock_timestamp()-interval '3 minutes' then
   -- The unclaimed admission proves no execution began. An explicit retry is safe.
   update public.pandora_activity_jobs set execution_state='failed',execution_error_code='CHAT_ADMISSION_INTERRUPTED',execution_updated_at=clock_timestamp() where id=j.id;
   update public.pandora_chat_turn_attempts set status='failed_recoverably',retryable=true,error_code='CHAT_ADMISSION_INTERRUPTED',last_event_sequence=last_event_sequence+1,completed_at=clock_timestamp(),updated_at=clock_timestamp() where id=a.id;
 elsif j.execution_state='running' and greatest(coalesce(j.execution_updated_at,j.created_at),a.updated_at)<clock_timestamp()-interval '5 minutes' then
   update public.pandora_chat_turn_attempts set status='outcome_unknown',retryable=false,error_code='CHAT_RECONCILIATION_REQUIRED',last_event_sequence=last_event_sequence+1,updated_at=clock_timestamp() where id=a.id;
 end if;
 return private.pandora_chat_turn_receipt_v2(t.id);
end; $$;

revoke all on function private.pandora_chat_turn_authorize_v2(uuid,uuid),private.pandora_chat_turn_receipt_v2(uuid,integer),private.pandora_chat_cancelled_admission_receipt_v2(uuid,integer),
 private.pandora_chat_bind_dispatch_message_v2() from public,anon,authenticated,service_role;
revoke all on function public.pandora_chat_turn_admit_v2(uuid,uuid,uuid,text,text,uuid,uuid,jsonb,uuid,jsonb),
 public.pandora_chat_turn_retry_v2(uuid,uuid,uuid,integer,text,uuid),public.pandora_chat_turn_read_v2(uuid,uuid,integer),
 public.pandora_chat_turn_cancel_v2(uuid,uuid,integer,uuid,boolean),public.pandora_chat_dispatch_turn_v2(uuid,uuid,uuid,integer,uuid,text),public.pandora_chat_history_v2(uuid,uuid,integer),public.pandora_chat_thread_view_v2(uuid,integer)
 from public,anon;
grant execute on function public.pandora_chat_turn_admit_v2(uuid,uuid,uuid,text,text,uuid,uuid,jsonb,uuid,jsonb),
 public.pandora_chat_turn_retry_v2(uuid,uuid,uuid,integer,text,uuid),public.pandora_chat_turn_read_v2(uuid,uuid,integer),
 public.pandora_chat_turn_cancel_v2(uuid,uuid,integer,uuid,boolean),public.pandora_chat_dispatch_turn_v2(uuid,uuid,uuid,integer,uuid,text),public.pandora_chat_history_v2(uuid,uuid,integer),public.pandora_chat_thread_view_v2(uuid,integer) to authenticated;
revoke all on function public.pandora_chat_turn_transition_v2(uuid,uuid,integer,uuid,text,bigint,text,boolean,jsonb,uuid),
 public.pandora_chat_turn_complete_v2(uuid,uuid,integer,uuid,jsonb,jsonb,bigint,jsonb),public.pandora_chat_turn_reconcile_v2(uuid),public.pandora_chat_turn_effect_v2(uuid,uuid,integer,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_chat_turn_transition_v2(uuid,uuid,integer,uuid,text,bigint,text,boolean,jsonb,uuid),
 public.pandora_chat_turn_complete_v2(uuid,uuid,integer,uuid,jsonb,jsonb,bigint,jsonb),public.pandora_chat_turn_reconcile_v2(uuid),public.pandora_chat_turn_effect_v2(uuid,uuid,integer,uuid,text,jsonb) to service_role;

commit;
