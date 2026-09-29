-- G3 Pandora-native growth-learning courier.
-- Growth rows no longer use ProjectOS/HMAC transport. The Operations worker claims
-- them with a lease token and sends them to pandora-memory-bridge using Vercel OIDC.
begin;

alter table private.execution_learning_outbox
  add column if not exists native_claim_token uuid,
  add column if not exists native_claim_expires_at timestamptz;

create or replace function private.dispatch_execution_learning(p_outbox_id uuid)
returns bigint
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_outbox private.execution_learning_outbox%rowtype;
  v_secret text;
  v_timestamp text;
  v_basis text;
  v_signature text;
  v_request_id bigint;
  v_kind text;
  v_target_url text;
begin
  select * into v_outbox
  from private.execution_learning_outbox
  where id=p_outbox_id
  for update;

  if v_outbox.id is null then
    raise exception 'execution learning outbox item not found' using errcode='P0002';
  end if;
  if v_outbox.delivery_status='delivered' then return v_outbox.last_request_id; end if;
  if v_outbox.attempt_count>=5 then
    update private.execution_learning_outbox
    set delivery_status='failed',
        last_error=coalesce(last_error,'maximum delivery attempts reached'),
        updated_at=now()
    where id=v_outbox.id;
    return null;
  end if;

  v_kind:=coalesce(v_outbox.payload->>'learning_kind','');
  if v_kind='growth_learning_v1'
     or v_outbox.payload->>'tool'='facebook.growth_learning'
     or v_outbox.payload ? 'growth_learning' then
    raise exception 'GROWTH_LEARNING_NATIVE_TRANSPORT_REQUIRED' using errcode='55000';
  end if;
  v_target_url:=case
    when v_kind in ('visible_creation_decision_influence_v1','visible_creation_decision_outcome_v1')
      then 'https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-decision-lineage'
    else 'https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-projectos-learning'
  end;

  select secret_value into v_secret
  from private.integration_secrets
  where secret_name='projectos_memory_learning_hmac';
  if coalesce(v_secret,'')='' then
    raise exception 'projectos memory learning secret unavailable' using errcode='55000';
  end if;

  v_timestamp:=floor(extract(epoch from clock_timestamp())*1000)::bigint::text;
  v_basis:=private.execution_learning_signature_basis(v_outbox.payload);
  v_signature:=encode(extensions.hmac(v_timestamp||'.'||v_basis,v_secret,'sha256'),'hex');

  select net.http_post(
    url:=v_target_url,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-pandora-timestamp',v_timestamp,
      'x-pandora-signature',v_signature
    ),
    body:=v_outbox.payload,
    timeout_milliseconds:=10000
  ) into v_request_id;

  update private.execution_learning_outbox
  set delivery_status='submitted',
      attempt_count=attempt_count+1,
      last_request_id=v_request_id,
      last_http_status=null,
      last_response_excerpt=null,
      last_error=null,
      submitted_at=now(),
      next_attempt_at=now()+interval '2 minutes',
      updated_at=now()
  where id=v_outbox.id;
  return v_request_id;
exception when others then
  update private.execution_learning_outbox
  set delivery_status=case when attempt_count+1>=5 then 'failed' else 'pending' end,
      attempt_count=attempt_count+1,
      last_error=left(sqlerrm,1000),
      next_attempt_at=now()+interval '2 minutes',
      updated_at=now()
  where id=p_outbox_id;
  return null;
end;
$fn$;



create or replace function private.process_execution_learning_outbox(p_limit integer default 20)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_processed integer := 0;
begin
  perform private.reconcile_execution_learning_responses();

  for v_item in
    select id
    from private.execution_learning_outbox
    where delivery_status = 'pending'
      and coalesce(payload->>'learning_kind','') <> 'growth_learning_v1'
      and coalesce(payload->>'tool','') <> 'facebook.growth_learning'
      and not (payload ? 'growth_learning')
      and attempt_count < 5
      and next_attempt_at <= now()
    order by created_at
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked
  loop
    perform private.dispatch_execution_learning(v_item.id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;



create or replace function public.pandora_claim_growth_learning_delivery_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row private.execution_learning_outbox%rowtype;
  v_token uuid;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'GROWTH_LEARNING_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_organization_id is null or p_project_id is null
     or p_worker_key is distinct from 'pandora-native-builder-v1'
     or p_principal_key is distinct from 'vercel:mcpmaster:operations-native-builder-v1' then
    raise exception 'GROWTH_LEARNING_WORKER_DENIED' using errcode='42501';
  end if;
  perform 1 from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_worker_key and principal_key=p_principal_key
     and acknowledged and connected and health='ready'
     and heartbeat_at>=clock_timestamp()-interval '60 seconds'
     and 'memory.integrate'=any(capabilities);
  if not found then
    raise exception 'GROWTH_LEARNING_WORKER_NOT_READY' using errcode='42501';
  end if;

  update private.execution_learning_outbox
  set delivery_status=case when attempt_count>=5 then 'failed' else 'pending' end,
      native_claim_token=null,native_claim_expires_at=null,
      last_error=case when attempt_count>=5 then coalesce(last_error,'native delivery attempts exhausted')
                      else coalesce(last_error,'native claim expired') end,
      next_attempt_at=case when attempt_count>=5 then next_attempt_at else clock_timestamp() end,
      updated_at=clock_timestamp()
  where delivery_status='submitted'
    and payload->>'learning_kind'='growth_learning_v1'
    and native_claim_expires_at is not null
    and native_claim_expires_at<=clock_timestamp();

  select * into v_row
  from private.execution_learning_outbox
  where organization_id=p_organization_id
    and project_id='7c686cbd-d968-49d5-86cc-918f5e777bd2'::uuid
    and project_key='mcpmaster-pandoras-box'
    and payload->>'learning_kind'='growth_learning_v1'
    and payload->>'tool'='facebook.growth_learning'
    and delivery_status='pending'
    and attempt_count<5
    and next_attempt_at<=clock_timestamp()
    and private.pandora_growth_learning_payload_is_valid_v1(payload) is true
  order by created_at,id
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('state','idle');
  end if;

  v_token:=gen_random_uuid();
  update private.execution_learning_outbox
  set delivery_status='submitted',
      attempt_count=attempt_count+1,
      submitted_at=clock_timestamp(),
      native_claim_token=v_token,
      native_claim_expires_at=clock_timestamp()+interval '2 minutes',
      last_request_id=null,last_http_status=null,last_response_excerpt=null,last_error=null,
      updated_at=clock_timestamp()
  where id=v_row.id;

  return jsonb_build_object(
    'state','claimed','outboxId',v_row.id,'claimToken',v_token,
    'attempt',v_row.attempt_count+1,'payload',v_row.payload
  );
end;
$function$;

create or replace function public.pandora_ack_growth_learning_delivery_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_worker_key text,
  p_principal_key text,
  p_outbox_id uuid,
  p_claim_token uuid,
  p_http_status integer,
  p_content text,
  p_error text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row private.execution_learning_outbox%rowtype;
  v_valid boolean;
  v_state text;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'GROWTH_LEARNING_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_worker_key is distinct from 'pandora-native-builder-v1'
     or p_principal_key is distinct from 'vercel:mcpmaster:operations-native-builder-v1'
     or p_outbox_id is null or p_claim_token is null
     or p_http_status is null or p_http_status<100 or p_http_status>599
     or octet_length(coalesce(p_content,''))>65536
     or octet_length(coalesce(p_error,''))>2000 then
    raise exception 'GROWTH_LEARNING_ACK_INVALID' using errcode='22023';
  end if;
  perform 1 from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_worker_key and principal_key=p_principal_key
     and acknowledged and connected and health='ready'
     and heartbeat_at>=clock_timestamp()-interval '60 seconds'
     and 'memory.integrate'=any(capabilities);
  if not found then
    raise exception 'GROWTH_LEARNING_WORKER_NOT_READY' using errcode='42501';
  end if;

  select * into v_row
  from private.execution_learning_outbox
  where id=p_outbox_id and organization_id=p_organization_id
    and project_id='7c686cbd-d968-49d5-86cc-918f5e777bd2'::uuid
  for update;
  if not found or v_row.delivery_status<>'submitted'
     or v_row.native_claim_token is distinct from p_claim_token
     or v_row.native_claim_expires_at is null
     or v_row.native_claim_expires_at<clock_timestamp()
     or v_row.payload->>'learning_kind'<>'growth_learning_v1' then
    raise exception 'GROWTH_LEARNING_ACK_FENCED';
  end if;

  v_valid:=private.execution_learning_response_is_valid(
    v_row.payload,p_http_status,coalesce(p_content,''),p_error,false
  );
  v_state:=case when v_valid then 'delivered'
                when v_row.attempt_count>=5 then 'failed'
                else 'pending' end;

  update private.execution_learning_outbox
  set delivery_status=v_state,
      last_http_status=p_http_status,
      last_response_excerpt=left(coalesce(p_content,''),1000),
      last_error=case when v_valid then null
        when p_error is not null then left(p_error,1000)
        when p_http_status in (200,202) then 'invalid learning response contract'
        else 'HTTP '||p_http_status::text end,
      delivered_at=case when v_valid then clock_timestamp() else delivered_at end,
      next_attempt_at=case when v_valid or v_row.attempt_count>=5 then next_attempt_at
                           else clock_timestamp()+make_interval(secs=>least(3600,60*(2^(v_row.attempt_count-1)))) end,
      native_claim_token=null,native_claim_expires_at=null,updated_at=clock_timestamp()
  where id=v_row.id;

  return jsonb_build_object(
    'state',v_state,'delivered',v_valid,'attempt',v_row.attempt_count,
    'outboxId',v_row.id
  );
end;
$function$;

revoke all on function public.pandora_claim_growth_learning_delivery_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.pandora_ack_growth_learning_delivery_v1(
  uuid,uuid,text,text,uuid,uuid,integer,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_claim_growth_learning_delivery_v1(uuid,uuid,text,text) to service_role;
grant execute on function public.pandora_ack_growth_learning_delivery_v1(
  uuid,uuid,text,text,uuid,uuid,integer,text,text
) to service_role;

commit;
