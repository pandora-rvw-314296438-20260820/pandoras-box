create or replace function private.pandora_paypal_billing_api_v1(
  p_method text,
  p_path text,
  p_body jsonb default null,
  p_request_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions, private
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_method extensions.http_method;
  v_body jsonb;
  v_headers extensions.http_header[];
begin
  if upper(coalesce(p_method, '')) not in ('GET', 'POST') then
    raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' then
    raise exception 'PAYPAL_PATH_INVALID' using errcode = '22023';
  end if;
  if not (
    (upper(p_method) = 'POST' and p_path = '/v1/billing/subscriptions') or
    (upper(p_method) = 'GET' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+$') or
    (upper(p_method) = 'POST' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+/(revise|cancel)$')
  ) then
    raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode = '22023';
  end if;
  v_token := private.pandora_paypal_access_20260830();
  v_headers := array[
    extensions.http_header('authorization', 'Bearer ' || v_token),
    extensions.http_header('content-type', 'application/json'),
    extensions.http_header('accept', 'application/json'),
    extensions.http_header('prefer', 'return=representation'),
    extensions.http_header('user-agent', 'Pandora-PLP-Billing/1.0')
  ]::extensions.http_header[];
  if nullif(p_request_id, '') is not null then
    v_headers := array_append(v_headers, extensions.http_header('paypal-request-id', left(p_request_id, 78)));
  end if;
  v_method := upper(p_method)::extensions.http_method;
  select * into v_response from extensions.http((
    v_method,
    (private.pandora_paypal_base_20260830() || p_path)::varchar,
    v_headers,
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := jsonb_build_object('name', 'UNREADABLE_RESPONSE');
  end;
  return jsonb_build_object('status', v_response.status, 'body', coalesce(v_body, '{}'::jsonb));
end;
$$;
revoke all on function private.pandora_paypal_billing_api_v1(text, text, jsonb, text) from public, anon, authenticated;
grant execute on function private.pandora_paypal_billing_api_v1(text, text, jsonb, text) to service_role;
create or replace function private.pandora_plp_billing_money(p_micros bigint)
returns numeric
language sql
immutable
as $$
  select round(coalesce(p_micros, 0) / 1000000.0, 2);
$$;