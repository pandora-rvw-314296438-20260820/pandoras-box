-- Forward-only classification fix observed from the live OpenAI provider.
-- credit_balance_exhausted is quota exhaustion, not a retryable rate-limit condition.

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
    if v_code in (
      'insufficient_quota',
      'billing_hard_limit_reached',
      'exceeded_current_quota_error',
      'credit_balance_exhausted'
    ) then
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

revoke all on function private.pandora_openai_error_class_v1(integer,text)
  from public,anon,authenticated;
grant execute on function private.pandora_openai_error_class_v1(integer,text)
  to service_role;

comment on function private.pandora_openai_error_class_v1(integer,text) is
  'Sanitized OpenAI error classifier; credit exhaustion is non-retryable quota exhaustion so cross-provider failover can proceed immediately.';
