-- Vault-backed OpenRouter fallback for Pandora intelligence.
-- The credential remains only in Supabase Vault under the stable name openrouter.

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.pandora_openrouter_error_class_v1(
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
  elsif p_status = 402 then
    v_kind := 'quota_exhausted'; v_retryable := false;
  elsif p_status = 400 then
    v_kind := 'invalid_request'; v_retryable := false;
  elsif p_status = 404 then
    v_kind := 'not_found'; v_retryable := false;
  elsif p_status in (408,504) then
    v_kind := 'timeout'; v_retryable := true;
  elsif p_status = 429 then
    if v_code in ('insufficient_quota','insufficient_credits','billing_hard_limit_reached') then
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

create or replace function private.pandora_openrouter_chat_api_v1(
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
  v_error_class jsonb;
  v_error_kind text;
  v_retryable boolean;
  v_attempt integer := 0;
  v_max_tokens integer;
  v_content_bytes integer;
  v_max_attempts constant integer := 2;
  v_max_request_bytes constant integer := 1048576;
  v_max_response_bytes constant integer := 2097152;
  v_max_output_tokens constant integer := 8192;
begin
  v_model := trim(coalesce(p_model,''));
  if v_model not in (
    'qwen/qwen3-30b-a3b-instruct-2507',
    'qwen/qwen3-235b-a22b-2507',
    'openai/gpt-oss-20b'
  ) then
    raise exception 'invalid OpenRouter model identifier' using errcode='22023';
  end if;
  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'OpenRouter request body must be an object' using errcode='22023';
  end if;
  if p_body ? 'model' then
    raise exception 'OpenRouter model must be supplied through p_model only' using errcode='22023';
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
    raise exception 'OpenRouter messages must contain between 1 and 256 entries' using errcode='22023';
  end if;
  begin
    v_max_tokens := coalesce(
      nullif(p_body->>'max_completion_tokens','')::integer,
      nullif(p_body->>'max_tokens','')::integer,
      4096
    );
  exception when others then
    raise exception 'max tokens must be an integer' using errcode='22023';
  end;
  if v_max_tokens < 1 or v_max_tokens > v_max_output_tokens then
    raise exception 'max tokens exceeds Pandora transport limit' using errcode='22023';
  end if;

  v_payload := (p_body - 'model' - 'stream' - 'max_completion_tokens' - 'max_tokens' - 'reasoning_effort')
    || jsonb_build_object('model',v_model,'stream',false,'max_tokens',v_max_tokens);
  v_payload_text := v_payload::text;

  if octet_length(v_payload_text) > v_max_request_bytes then
    raise exception 'OpenRouter request body exceeds 1 MiB' using errcode='22023';
  end if;
  if v_payload_text ~* '"(openrouter_api_key|openrouter_key|openai_api_key|openai_key|moonshot_api_key|kimi_api_key|gemini_api_key|github_supabase|github_pat|service_role_key|supabase_service_role|vercel_token|authorization|proxy_authorization|cookie|private_key|database_password)"[[:space:]]*:'
     or v_payload_text ~* 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}'
     or v_payload_text ~ 'sk-[A-Za-z0-9_-]{20,}'
     or v_payload_text ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_payload_text ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_payload_text ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_payload_text ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
     or v_payload_text ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
    raise exception 'credential material rejected from OpenRouter request' using errcode='22023';
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='openrouter'
  limit 1;
  if nullif(trim(v_key),'') is null then
    raise exception 'provider credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','85000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  <<request_loop>>
  loop
    v_attempt := v_attempt + 1;
    v_provider_code := null;
    begin
      select * into v_response
      from extensions.http((
        'POST'::extensions.http_method,
        'https://openrouter.ai/api/v1/chat/completions'::varchar,
        array[
          extensions.http_header('authorization','Bearer '||v_key),
          extensions.http_header('content-type','application/json'),
          extensions.http_header('accept','application/json'),
          extensions.http_header('user-agent','Pandora-OpenRouter-Transport/1.0')
        ]::extensions.http_header[],
        'application/json'::varchar,
        v_payload_text::varchar
      )::extensions.http_request);
    exception when others then
      if v_attempt < v_max_attempts then
        perform pg_sleep(0.25);
        continue request_loop;
      end if;
      return jsonb_build_object(
        'status',0,'ok',false,'attempts',v_attempt,
        'error',jsonb_build_object('kind','transport_unavailable','retryable',true)
      );
    end;

    v_response_text := coalesce(v_response.content,'');
    v_content_bytes := octet_length(v_response_text);
    if v_content_bytes > v_max_response_bytes then
      return jsonb_build_object(
        'status',502,'ok',false,'attempts',v_attempt,
        'error',jsonb_build_object('kind','response_too_large','retryable',false)
      );
    end if;
    if position(v_key in v_response_text) > 0 then
      raise exception 'provider response failed secret-leak guard' using errcode='55000';
    end if;

    begin
      v_body := nullif(v_response_text,'')::jsonb;
    exception when others then
      v_body := null;
    end;
    if v_body is not null and jsonb_typeof(v_body)='object' then
      v_provider_code := lower(left(regexp_replace(
        coalesce(nullif(v_body #>> '{error,code}',''),v_body #>> '{error,type}',''),
        '[^A-Za-z0-9_.-]','','g'
      ),80));
      v_provider_code := nullif(v_provider_code,'');
    end if;

    if v_response.status between 200 and 299 then
      if v_body is null or jsonb_typeof(v_body) <> 'object' then
        return jsonb_build_object(
          'status',502,'ok',false,'attempts',v_attempt,
          'error',jsonb_build_object('kind','malformed_response','retryable',false)
        );
      end if;
      return jsonb_build_object(
        'status',v_response.status,'ok',true,'attempts',v_attempt,
        'contentType',v_response.content_type,'body',v_body
      );
    end if;

    v_error_class := private.pandora_openrouter_error_class_v1(v_response.status,v_provider_code);
    v_error_kind := v_error_class->>'kind';
    v_retryable := coalesce((v_error_class->>'retryable')::boolean,false);
    if v_retryable and v_attempt < v_max_attempts then
      perform pg_sleep(case when v_response.status=429 then 0.5 else 0.25 end);
      continue request_loop;
    end if;
    return jsonb_build_object(
      'status',v_response.status,'ok',false,'attempts',v_attempt,
      'error',jsonb_strip_nulls(jsonb_build_object(
        'kind',v_error_kind,'providerCode',v_provider_code,'retryable',v_retryable
      ))
    );
  end loop;
end;
$function$;

create or replace function public.pandora_openrouter_chat_request_v1(p_model text,p_body jsonb)
returns jsonb
language sql
security definer
set search_path='pg_catalog','private','public'
as $function$
  select private.pandora_openrouter_chat_api_v1(p_model,p_body);
$function$;

revoke all on function private.pandora_openrouter_error_class_v1(integer,text) from public,anon,authenticated;
revoke all on function private.pandora_openrouter_chat_api_v1(text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_openrouter_chat_request_v1(text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_openrouter_error_class_v1(integer,text) to service_role;
grant execute on function private.pandora_openrouter_chat_api_v1(text,jsonb) to service_role;
grant execute on function public.pandora_openrouter_chat_request_v1(text,jsonb) to service_role;
alter function private.pandora_openrouter_chat_api_v1(text,jsonb) set statement_timeout='90s';
alter function public.pandora_openrouter_chat_request_v1(text,jsonb) set statement_timeout='90s';

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('openrouter','enabled','true',true,now()),
  ('openrouter','routing_eligible','true',true,now()),
  ('openrouter','fallback_enabled','true',true,now()),
  ('openrouter','default_model','qwen/qwen3-30b-a3b-instruct-2507',true,now()),
  ('openrouter','allowed_models','["qwen/qwen3-30b-a3b-instruct-2507","qwen/qwen3-235b-a22b-2507","openai/gpt-oss-20b"]',true,now()),
  ('openrouter','task_eligibility','[]',true,now()),
  ('openrouter','preferred_tasks','[]',true,now()),
  ('openrouter','policy_version','provider-auto-failover-v4',true,now()),
  ('openrouter','stream_mode','buffered_v1',true,now()),
  ('kimi','policy_version','provider-auto-failover-v4',true,now()),
  ('openai','policy_version','provider-auto-failover-v4',true,now())
on conflict(provider,config_key) do update
set config_value=excluded.config_value,active=excluded.active,updated_at=excluded.updated_at;

revoke insert,update,delete on public.pandora_runtime_provider_configs from anon,authenticated;

comment on function public.pandora_openrouter_chat_request_v1(text,jsonb) is
  'Service-role-only Vault-backed OpenRouter Chat Completions transport for Pandora provider failover.';
