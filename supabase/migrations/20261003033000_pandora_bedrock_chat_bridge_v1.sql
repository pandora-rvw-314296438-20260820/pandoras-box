begin;

create table if not exists private.pandora_bedrock_chat_tickets(
  id uuid primary key default gen_random_uuid(),
  token_sha256 text not null unique check(token_sha256~'^[0-9a-f]{64}$'),
  model_id text not null,
  invocation_target text not null,
  provider_name text,
  request_body jsonb not null check(jsonb_typeof(request_body)='object'),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check(expires_at>created_at)
);
alter table private.pandora_bedrock_chat_tickets enable row level security;
revoke all on private.pandora_bedrock_chat_tickets from public,anon,authenticated,service_role;

create or replace function public.pandora_bedrock_chat_routing_config_v1()
returns jsonb language plpgsql security definer
set search_path='pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_models jsonb;v_image_models jsonb;v_default text;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
  select
    coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id),'[]'::jsonb),
    coalesce(jsonb_agg(c.model_id order by c.provider_name,c.model_name,c.model_id) filter(where 'IMAGE'=any(c.input_modalities)),'[]'::jsonb),
    (array_agg(c.model_id order by c.provider_name,c.model_name,c.model_id))[1]
  into v_models,v_image_models,v_default
  from private.pandora_bedrock_reasoning_catalog c
  where c.routable=true and c.conversational=true and c.present_in_latest_sync=true
    and c.runtime_verification_status='passed' and c.lifecycle_status='ACTIVE'
    and nullif(c.invocation_target,'') is not null;
  return jsonb_build_object('enabled',v_default is not null,'routingEligible',v_default is not null,'fallbackEnabled',true,'model',v_default,'allowedModels',v_models,'imageModels',v_image_models,'policyVersion','bedrock-live-catalog-chat-v1','streamMode','buffered_v1');
end;$$;
revoke all on function public.pandora_bedrock_chat_routing_config_v1() from public,anon,authenticated;
grant execute on function public.pandora_bedrock_chat_routing_config_v1() to service_role;

create or replace function public.pandora_claim_bedrock_chat_ticket_v1(p_token_sha256 text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','private','public','pg_temp'
as $$
declare v_role text;v_row private.pandora_bedrock_chat_tickets%rowtype;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
  if coalesce(p_token_sha256,'')!~'^[0-9a-f]{64}$' then raise exception 'BEDROCK_CHAT_TICKET_DENIED' using errcode='42501';end if;
  delete from private.pandora_bedrock_chat_tickets where token_sha256=p_token_sha256 and expires_at>clock_timestamp() returning * into v_row;
  if v_row.id is null then raise exception 'BEDROCK_CHAT_TICKET_DENIED' using errcode='42501';end if;
  return jsonb_build_object('modelId',v_row.model_id,'invocationTarget',v_row.invocation_target,'providerName',v_row.provider_name,'requestBody',v_row.request_body);
end;$$;
revoke all on function public.pandora_claim_bedrock_chat_ticket_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_claim_bedrock_chat_ticket_v1(text) to service_role;

create or replace function private.pandora_bedrock_chat_api_v1(p_model text,p_body jsonb)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','private','public','extensions','pg_temp'
as $$
declare v_role text;v_target text;v_provider text;v_token text;v_token_sha text;v_ticket_id uuid;v_response extensions.http_response;v_text text;v_json jsonb;v_max_tokens integer;
begin
  v_role:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','');
  if session_user not in('postgres','service_role','supabase_admin') and v_role<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';end if;
  if coalesce(p_model,'')!~'^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$' or p_body is null or jsonb_typeof(p_body)<>'object' or jsonb_typeof(p_body->'parts')<>'array' or jsonb_array_length(p_body->'parts') not between 1 and 64 then raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';end if;
  if exists(select 1 from jsonb_object_keys(p_body) k where k not in('system','parts','maxTokens')) then raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';end if;
  begin v_max_tokens:=coalesce(nullif(p_body->>'maxTokens','')::integer,4096);exception when others then raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';end;
  if v_max_tokens not between 1 and 8192 or octet_length(p_body::text)>1048576 then raise exception 'BEDROCK_CHAT_REQUEST_INVALID' using errcode='22023';end if;
  select c.invocation_target,c.provider_name into v_target,v_provider from private.pandora_bedrock_reasoning_catalog c
  where c.model_id=p_model and c.routable=true and c.conversational=true and c.present_in_latest_sync=true and c.runtime_verification_status='passed' and c.lifecycle_status='ACTIVE' and nullif(c.invocation_target,'') is not null limit 1;
  if v_target is null then raise exception 'BEDROCK_CHAT_MODEL_UNAVAILABLE' using errcode='55000';end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');v_token_sha:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.pandora_bedrock_chat_tickets(token_sha256,model_id,invocation_target,provider_name,request_body,expires_at)
  values(v_token_sha,p_model,v_target,v_provider,p_body||jsonb_build_object('maxTokens',v_max_tokens),clock_timestamp()+interval '2 minutes') returning id into v_ticket_id;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','90000');perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  begin
    select * into v_response from extensions.http(('POST'::extensions.http_method,'https://mcpmaster.vercel.app/api/operations-inference?operation=bedrock-chat'::varchar,array[extensions.http_header('content-type','application/json'),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Bedrock-Chat/1.0')]::extensions.http_header[],'application/json'::varchar,jsonb_build_object('ticket',v_token)::text::varchar)::extensions.http_request);
  exception when others then
    delete from private.pandora_bedrock_chat_tickets where id=v_ticket_id;v_token:=null;
    return jsonb_build_object('status',0,'ok',false,'error',jsonb_build_object('kind','transport_unavailable','retryable',true));
  end;
  v_text:=coalesce(v_response.content,'');delete from private.pandora_bedrock_chat_tickets where id=v_ticket_id;v_token:=null;
  if octet_length(v_text)>2097152 then return jsonb_build_object('status',502,'ok',false,'error',jsonb_build_object('kind','response_too_large','retryable',false));end if;
  begin v_json:=nullif(v_text,'')::jsonb;exception when others then v_json:=null;end;
  if v_response.status between 200 and 299 and v_json is not null then return v_json;end if;
  return jsonb_build_object('status',coalesce(v_response.status,503),'ok',false,'error',jsonb_build_object('kind','provider_unavailable','retryable',true));
end;$$;
revoke all on function private.pandora_bedrock_chat_api_v1(text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_bedrock_chat_api_v1(text,jsonb) to service_role;

create or replace function public.pandora_bedrock_chat_request_v1(p_model text,p_body jsonb)
returns jsonb language sql security definer set search_path='pg_catalog','private','public'
as $$select private.pandora_bedrock_chat_api_v1(p_model,p_body);$$;
revoke all on function public.pandora_bedrock_chat_request_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_bedrock_chat_request_v1(text,jsonb) to service_role;
alter function private.pandora_bedrock_chat_api_v1(text,jsonb) set statement_timeout='95s';
alter function public.pandora_bedrock_chat_request_v1(text,jsonb) set statement_timeout='95s';

commit;
