-- Chat B Task 33 closure: make all same-provider attempts share one 90s deadline.
-- The Vault credential remains internal to private.pandora_kimi_chat_api_v1.

create or replace function private.pandora_kimi_chat_api_v1(p_model text, p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'vault', 'extensions', 'public'
set statement_timeout = '90s'
as $function$
declare
  v_key text; v_response extensions.http_response; v_body jsonb; v_payload jsonb; v_payload_text text; v_response_text text; v_model text;
  v_provider_type text; v_provider_message text; v_retry_header text; v_retry_after_ms integer; v_retry_match text[]; v_retryable boolean;
  v_error_kind text; v_error_class jsonb; v_attempt integer := 0; v_max_completion_tokens integer; v_sleep_ms integer; v_content_bytes integer;
  v_started_at timestamptz := clock_timestamp(); v_deadline_at timestamptz; v_remaining_ms integer; v_attempt_timeout_ms integer;
  v_max_attempts constant integer := 2; v_max_request_bytes constant integer := 1048576; v_max_response_bytes constant integer := 2097152;
  v_max_output_tokens constant integer := 16384; v_global_deadline_ms constant integer := 90000; v_provider_timeout_ms constant integer := 85000;
  v_deadline_reserve_ms constant integer := 1000;
begin
  v_deadline_at := v_started_at + make_interval(secs => v_global_deadline_ms::numeric / 1000);
  v_model := trim(coalesce(p_model, ''));
  if v_model !~ '^(kimi-[A-Za-z0-9][A-Za-z0-9._-]{0,79}|moonshot-v1([-.][A-Za-z0-9][A-Za-z0-9._-]{0,79})?)$' then raise exception 'invalid Moonshot model identifier' using errcode='22023'; end if;
  if p_body is null or jsonb_typeof(p_body) <> 'object' then raise exception 'Moonshot request body must be an object' using errcode='22023'; end if;
  if p_body ? 'model' then raise exception 'Moonshot model must be supplied through p_model only' using errcode='22023'; end if;
  if p_body ? 'max_tokens' then raise exception 'deprecated max_tokens is not accepted; use max_completion_tokens' using errcode='22023'; end if;
  if p_body ? 'stream' and jsonb_typeof(p_body->'stream') <> 'boolean' then raise exception 'stream must be a boolean' using errcode='22023'; end if;
  if coalesce((p_body->>'stream')::boolean, false) then raise exception 'streaming is not supported by this bounded transport' using errcode='22023'; end if;
  if jsonb_typeof(p_body->'messages') <> 'array' or jsonb_array_length(p_body->'messages') < 1 or jsonb_array_length(p_body->'messages') > 256 then raise exception 'Moonshot messages must contain between 1 and 256 entries' using errcode='22023'; end if;
  if p_body ? 'tools' and (jsonb_typeof(p_body->'tools') <> 'array' or jsonb_array_length(p_body->'tools') > 128) then raise exception 'Moonshot tools exceed the supported bound' using errcode='22023'; end if;
  if p_body ? 'reasoning_effort' and coalesce(p_body->>'reasoning_effort','') not in ('low','high','max') then raise exception 'invalid reasoning_effort' using errcode='22023'; end if;
  begin v_max_completion_tokens := coalesce(nullif(p_body->>'max_completion_tokens','')::integer, 8192); exception when others then raise exception 'max_completion_tokens must be an integer' using errcode='22023'; end;
  if v_max_completion_tokens < 1 or v_max_completion_tokens > v_max_output_tokens then raise exception 'max_completion_tokens exceeds Pandora transport limit' using errcode='22023'; end if;
  v_payload := (p_body - 'stream' - 'max_completion_tokens') || jsonb_build_object('model',v_model,'stream',false,'max_completion_tokens',v_max_completion_tokens);
  v_payload_text := v_payload::text;
  if octet_length(v_payload_text) > v_max_request_bytes then raise exception 'Moonshot request body exceeds 1 MiB' using errcode='22023'; end if;
  if v_payload_text ~* '\"(moonshot_api_key|kimi_api_key|gemini_api_key|github_supabase|github_pat|service_role_key|supabase_service_role|vercel_token|authorization|proxy_authorization|cookie|private_key|database_password)\"[[:space:]]*:' or v_payload_text ~* '(MOONSHOT|KIMI)[_-]?API[_-]?KEY[[:space:]]*[:=]' or v_payload_text ~* 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}' or v_payload_text ~ 'sk-[A-Za-z0-9_-]{20,}' or v_payload_text ~ 'AIza[0-9A-Za-z_-]{20,}' or v_payload_text ~ 'gh[pousr]_[A-Za-z0-9_]{20,}' or v_payload_text ~ 'github_pat_[A-Za-z0-9_]{20,}' or v_payload_text ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' or v_payload_text ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then raise exception 'credential material rejected from Moonshot request' using errcode='22023'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='moonshot_api_key' limit 1;
  if nullif(trim(v_key),'') is null then raise exception 'provider credential unavailable' using errcode='55000'; end if;
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  <<request_loop>> loop
    v_attempt := v_attempt + 1; v_retry_header := null; v_retry_after_ms := null; v_provider_type := null; v_provider_message := null; v_retryable := false; v_error_kind := null;
    v_remaining_ms := floor(extract(epoch from (v_deadline_at - clock_timestamp())) * 1000)::integer;
    if v_remaining_ms <= v_deadline_reserve_ms then return jsonb_build_object('status',0,'ok',false,'attempts',v_attempt-1,'error',jsonb_build_object('kind','timeout','retryable',true,'retryAfterMs',null)); end if;
    v_attempt_timeout_ms := least(v_provider_timeout_ms, greatest(1, v_remaining_ms - v_deadline_reserve_ms));
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS',v_attempt_timeout_ms::text);
    begin
      select * into v_response from extensions.http(('POST'::extensions.http_method,'https://api.moonshot.ai/v1/chat/completions'::varchar,array[extensions.http_header('authorization','Bearer '||v_key),extensions.http_header('content-type','application/json'),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Kimi-Transport/1.1')]::extensions.http_header[],'application/json'::varchar,v_payload_text::varchar)::extensions.http_request);
    exception when others then
      v_error_kind := case when lower(sqlerrm) ~ 'timeout|timed out|operation too slow' then 'timeout' else 'transport_unavailable' end;
      if v_attempt < v_max_attempts then v_remaining_ms := floor(extract(epoch from (v_deadline_at-clock_timestamp()))*1000)::integer; if v_remaining_ms > v_deadline_reserve_ms + 250 then perform pg_sleep(0.25); continue request_loop; end if; end if;
      return jsonb_build_object('status',0,'ok',false,'attempts',v_attempt,'error',jsonb_build_object('kind',v_error_kind,'retryable',true,'retryAfterMs',null));
    end;
    v_response_text := coalesce(v_response.content,''); v_content_bytes := octet_length(v_response_text);
    if v_content_bytes > v_max_response_bytes then return jsonb_build_object('status',502,'ok',false,'attempts',v_attempt,'error',jsonb_build_object('kind','response_too_large','retryable',false,'retryAfterMs',null)); end if;
    if position(v_key in v_response_text)>0 then raise exception 'provider response failed secret-leak guard' using errcode='55000'; end if;
    if v_response.headers is not null then select nullif(trim((h).value),'') into v_retry_header from unnest(v_response.headers) as h where lower((h).field)='retry-after' limit 1; end if;
    if v_retry_header is not null then if v_retry_header ~ '^[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*$' then v_retry_after_ms:=least(600000,greatest(0,ceil(v_retry_header::numeric*1000)::integer)); else begin v_retry_after_ms:=least(600000,greatest(0,ceil(extract(epoch from (v_retry_header::timestamptz-clock_timestamp()))*1000)::integer)); exception when others then v_retry_after_ms:=null; end; end if; end if;
    begin v_body:=nullif(v_response_text,'')::jsonb; exception when others then v_body:=null; end;
    if v_body is not null and jsonb_typeof(v_body)='object' then v_provider_type:=lower(left(regexp_replace(coalesce(v_body#>>'{error,type}',''),'[^A-Za-z0-9_.-]','','g'),80)); v_provider_type:=nullif(v_provider_type,''); v_provider_message:=left(coalesce(v_body#>>'{error,message}',''),1000); end if;
    if v_retry_after_ms is null and nullif(v_provider_message,'') is not null then v_retry_match:=regexp_match(lower(v_provider_message),'(retry|try again|after)[^0-9]{0,32}([0-9]+([.][0-9]+)?)[[:space:]]*(s|sec|secs|second|seconds)'); if v_retry_match is not null then begin v_retry_after_ms:=least(600000,greatest(0,ceil(v_retry_match[2]::numeric*1000)::integer)); exception when others then v_retry_after_ms:=null; end; end if; end if;
    if v_response.status between 200 and 299 then if v_body is null or jsonb_typeof(v_body)<>'object' then return jsonb_build_object('status',502,'ok',false,'attempts',v_attempt,'error',jsonb_build_object('kind','malformed_response','retryable',false,'retryAfterMs',null)); end if; return jsonb_build_object('status',v_response.status,'ok',true,'attempts',v_attempt,'contentType',v_response.content_type,'body',v_body); end if;
    v_error_class:=private.pandora_kimi_error_class_v1(v_response.status,v_provider_type); v_error_kind:=v_error_class->>'kind'; v_retryable:=coalesce((v_error_class->>'retryable')::boolean,false);
    if v_retryable and v_attempt<v_max_attempts then if v_retry_after_ms is null then v_sleep_ms:=case when v_response.status=429 then 500 else 250 end; elsif v_retry_after_ms<=2000 then v_sleep_ms:=greatest(100,v_retry_after_ms); else v_sleep_ms:=null; end if; if v_sleep_ms is not null then v_remaining_ms:=floor(extract(epoch from (v_deadline_at-clock_timestamp()))*1000)::integer; if v_remaining_ms > v_deadline_reserve_ms + v_sleep_ms then perform pg_sleep(v_sleep_ms::numeric/1000); continue request_loop; end if; end if; end if;
    return jsonb_build_object('status',v_response.status,'ok',false,'attempts',v_attempt,'error',jsonb_strip_nulls(jsonb_build_object('kind',v_error_kind,'providerCode',v_provider_type,'retryable',v_retryable,'retryAfterMs',v_retry_after_ms)));
  end loop;
end;
$function$;

revoke all on function private.pandora_kimi_chat_api_v1(text,jsonb) from public, anon, authenticated;
grant execute on function private.pandora_kimi_chat_api_v1(text,jsonb) to service_role;
comment on function private.pandora_kimi_chat_api_v1(text,jsonb) is 'Vault-backed Moonshot transport with fixed host, bounded payloads, shared 90s deadline, remaining-budget per-attempt timeout, max two attempts, bounded Retry-After and sanitized errors.';
