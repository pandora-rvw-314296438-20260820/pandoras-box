-- OpenAI secure fallback transport and provider routing activation.
-- Credential value remains in Supabase Vault as openai_key and never leaves this trusted boundary.

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.pandora_openai_error_class_v1(
  p_status integer,
  p_provider_code text default null
)
returns jsonb
language plpgsql
immutable
set search_path='pg_catalog','private'
as $function$
declare
  v_code text := lower(coalesce(p_provider_code,''));
  v_kind text;
  v_retryable boolean;
begin
  if p_status in (301,302,303,307,308) then
    v_kind := 'provider_redirect_rejected'; v_retryable := false;
  elsif p_status in (401,403) then
    v_kind := 'authorization'; v_retryable := false;
  elsif p_status = 400 then
    v_kind := 'invalid_request'; v_retryable := false;
  elsif p_status = 404 then
    v_kind := 'not_found'; v_retryable := false;
  elsif p_status in (408,504) then
    v_kind := 'timeout'; v_retryable := true;
  elsif p_status = 429 then
    if v_code in ('insufficient_quota','billing_hard_limit_reached','exceeded_current_quota_error') then
      v_kind := 'quota_exhausted'; v_retryable := false;
    else
      v_kind := 'rate_limit'; v_retryable := true;
    end if;
  elsif p_status >= 500 then
    v_kind := 'provider_unavailable'; v_retryable := true;
  else
    v_kind := 'provider_rejected'; v_retryable := false;
  end if;
  return jsonb_build_object('kind',v_kind,'retryable',v_retryable);
end;
$function$;

create or replace function private.pandora_openai_chat_api_v1(
  p_model text,
  p_body jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $function$
declare
  v_key text;
  v_response extensions.http_response;
  v_body jsonb;
  v_payload jsonb;
  v_payload_text text;
  v_response_text text;
  v_model text;
  v_provider_code text;
  v_retry_header text;
  v_retry_after_ms integer;
  v_error_class jsonb;
  v_error_kind text;
  v_retryable boolean;
  v_attempt integer := 0;
  v_sleep_ms integer;
  v_max_completion_tokens integer;
  v_content_bytes integer;
  v_max_attempts constant integer := 2;
  v_max_request_bytes constant integer := 1048576;
  v_max_response_bytes constant integer := 2097152;
  v_max_output_tokens constant integer := 16384;
begin
  v_model := trim(coalesce(p_model,''));
  if v_model !~ '^gpt-(5[.]6-(sol|terra|luna)|6-astra)$' then
    raise exception 'invalid OpenAI model identifier' using errcode='22023';
  end if;
  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'OpenAI request body must be an object' using errcode='22023';
  end if;
  if p_body ? 'model' then
    raise exception 'OpenAI model must be supplied through p_model only' using errcode='22023';
  end if;
  if p_body ? 'stream' and jsonb_typeof(p_body->'stream') <> 'boolean' then
    raise exception 'stream must be a boolean' using errcode='22023';
  end if;
  if coalesce((p_body->>'stream')::boolean,false) then
    raise exception 'streaming is not supported by this bounded transport' using errcode='22023';
  end if;
  if jsonb_typeof(p_body->'messages') <> 'array'
     or jsonb_array_length(p_body->'messages') < 1
     or jsonb_array_length(p_body->'messages') > 256 then
    raise exception 'OpenAI messages must contain between 1 and 256 entries' using errcode='22023';
  end if;
  if p_body ? 'tools' and (
       jsonb_typeof(p_body->'tools') <> 'array'
       or jsonb_array_length(p_body->'tools') > 128
     ) then
    raise exception 'OpenAI tools exceed the supported bound' using errcode='22023';
  end if;
  if p_body ? 'reasoning_effort'
     and coalesce(p_body->>'reasoning_effort','') not in ('none','low','medium','high','xhigh','max') then
    raise exception 'invalid reasoning_effort' using errcode='22023';
  end if;
  if p_body ? 'temperature' or p_body ? 'top_p' or p_body ? 'logprobs' then
    raise exception 'unsupported sampling parameters are not accepted' using errcode='22023';
  end if;
  begin
    v_max_completion_tokens := coalesce(nullif(p_body->>'max_completion_tokens','')::integer,4096);
  exception when others then
    raise exception 'max_completion_tokens must be an integer' using errcode='22023';
  end;
  if v_max_completion_tokens < 1 or v_max_completion_tokens > v_max_output_tokens then
    raise exception 'max_completion_tokens exceeds Pandora transport limit' using errcode='22023';
  end if;

  v_payload := (p_body - 'stream' - 'max_completion_tokens')
    || jsonb_build_object('model',v_model,'stream',false,'max_completion_tokens',v_max_completion_tokens);
  v_payload_text := v_payload::text;

  if octet_length(v_payload_text) > v_max_request_bytes then
    raise exception 'OpenAI request body exceeds 1 MiB' using errcode='22023';
  end if;
  if v_payload_text ~* '"(openai_key|openai_api_key|moonshot_api_key|kimi_api_key|gemini_api_key|github_supabase|github_pat|service_role_key|supabase_service_role|vercel_token|authorization|proxy_authorization|cookie|private_key|database_password)"[[:space:]]*:'
     or v_payload_text ~* 'OPENAI[_-]?API[_-]?KEY[[:space:]]*[:=]'
     or v_payload_text ~* 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}'
     or v_payload_text ~ 'sk-[A-Za-z0-9_-]{20,}'
     or v_payload_text ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_payload_text ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_payload_text ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_payload_text ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
     or v_payload_text ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
    raise exception 'credential material rejected from OpenAI request' using errcode='22023';
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='openai_key'
  limit 1;
  if nullif(trim(v_key),'') is null then
    raise exception 'provider credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','85000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  <<request_loop>>
  loop
    v_attempt := v_attempt + 1;
    v_retry_header := null;
    v_retry_after_ms := null;
    v_provider_code := null;
    begin
      select * into v_response
      from extensions.http((
        'POST'::extensions.http_method,
        'https://api.openai.com/v1/chat/completions'::varchar,
        array[
          extensions.http_header('authorization','Bearer '||v_key),
          extensions.http_header('content-type','application/json'),
          extensions.http_header('accept','application/json'),
          extensions.http_header('user-agent','Pandora-OpenAI-Transport/1.0')
        ]::extensions.http_header[],
        'application/json'::varchar,
        v_payload_text::varchar
      )::extensions.http_request);
    exception when others then
      v_error_kind := case when lower(sqlerrm) ~ 'timeout|timed out|operation too slow' then 'timeout' else 'transport_unavailable' end;
      if v_attempt < v_max_attempts then perform pg_sleep(0.25); continue request_loop; end if;
      return jsonb_build_object('status',0,'ok',false,'attempts',v_attempt,'error',
        jsonb_build_object('kind',v_error_kind,'retryable',true,'retryAfterMs',null));
    end;

    v_response_text := coalesce(v_response.content,'');
    v_content_bytes := octet_length(v_response_text);
    if v_content_bytes > v_max_response_bytes then
      return jsonb_build_object('status',502,'ok',false,'attempts',v_attempt,'error',
        jsonb_build_object('kind','response_too_large','retryable',false,'retryAfterMs',null));
    end if;
    if position(v_key in v_response_text) > 0 then
      raise exception 'provider response failed secret-leak guard' using errcode='55000';
    end if;

    if v_response.headers is not null then
      select nullif(trim((h).value),'') into v_retry_header
      from unnest(v_response.headers) as h
      where lower((h).field)='retry-after'
      limit 1;
    end if;
    if v_retry_header is not null and v_retry_header ~ '^[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*$' then
      v_retry_after_ms := least(600000,greatest(0,ceil(v_retry_header::numeric*1000)::integer));
    end if;

    begin v_body := nullif(v_response_text,'')::jsonb; exception when others then v_body := null; end;
    if v_body is not null and jsonb_typeof(v_body)='object' then
      v_provider_code := lower(left(regexp_replace(
        coalesce(nullif(v_body #>> '{error,code}',''),v_body #>> '{error,type}',''),
        '[^A-Za-z0-9_.-]','','g'
      ),80));
      v_provider_code := nullif(v_provider_code,'');
    end if;

    if v_response.status between 200 and 299 then
      if v_body is null or jsonb_typeof(v_body) <> 'object' then
        return jsonb_build_object('status',502,'ok',false,'attempts',v_attempt,'error',
          jsonb_build_object('kind','malformed_response','retryable',false,'retryAfterMs',null));
      end if;
      return jsonb_build_object('status',v_response.status,'ok',true,'attempts',v_attempt,
        'contentType',v_response.content_type,'body',v_body);
    end if;

    v_error_class := private.pandora_openai_error_class_v1(v_response.status,v_provider_code);
    v_error_kind := v_error_class->>'kind';
    v_retryable := coalesce((v_error_class->>'retryable')::boolean,false);
    if v_retryable and v_attempt < v_max_attempts then
      v_sleep_ms := case
        when v_retry_after_ms is not null and v_retry_after_ms <= 2000 then greatest(100,v_retry_after_ms)
        when v_retry_after_ms is null and v_response.status=429 then 500
        when v_retry_after_ms is null then 250
        else null
      end;
      if v_sleep_ms is not null then perform pg_sleep(v_sleep_ms::numeric/1000); continue request_loop; end if;
    end if;
    return jsonb_build_object('status',v_response.status,'ok',false,'attempts',v_attempt,'error',
      jsonb_strip_nulls(jsonb_build_object('kind',v_error_kind,'providerCode',v_provider_code,
        'retryable',v_retryable,'retryAfterMs',v_retry_after_ms)));
  end loop;
end;
$function$;

create or replace function public.pandora_openai_chat_request_v1(p_model text,p_body jsonb)
returns jsonb
language sql
security definer
set search_path='pg_catalog','private','public'
as $function$
  select private.pandora_openai_chat_api_v1(p_model,p_body);
$function$;

revoke all on function private.pandora_openai_error_class_v1(integer,text) from public,anon,authenticated;
revoke all on function private.pandora_openai_chat_api_v1(text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_openai_chat_request_v1(text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_openai_error_class_v1(integer,text) to service_role;
grant execute on function private.pandora_openai_chat_api_v1(text,jsonb) to service_role;
grant execute on function public.pandora_openai_chat_request_v1(text,jsonb) to service_role;
alter function private.pandora_openai_chat_api_v1(text,jsonb) set statement_timeout='90s';
alter function public.pandora_openai_chat_request_v1(text,jsonb) set statement_timeout='90s';

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
 ('openai','enabled','true',true,now()),
 ('openai','routing_eligible','true',true,now()),
 ('openai','fallback_enabled','true',true,now()),
 ('openai','default_model','gpt-5.6-terra',true,now()),
 ('openai','allowed_models','["gpt-5.6-terra","gpt-5.6-luna","gpt-5.6-sol"]',true,now()),
 ('openai','task_eligibility','[]',true,now()),
 ('openai','preferred_tasks','[]',true,now()),
 ('openai','policy_version','provider-auto-failover-v3',true,now()),
 ('openai','stream_mode','buffered_v1',true,now()),
 ('kimi','policy_version','provider-auto-failover-v3',true,now())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=excluded.active,updated_at=excluded.updated_at;

revoke insert,update,delete on public.pandora_runtime_provider_configs from anon,authenticated;

comment on function public.pandora_openai_chat_request_v1(text,jsonb) is
  'Service-role-only Vault-backed OpenAI Chat Completions transport for Pandora provider failover.';
