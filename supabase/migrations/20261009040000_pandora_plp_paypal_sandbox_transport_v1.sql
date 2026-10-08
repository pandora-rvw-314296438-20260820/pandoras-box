-- Sandbox PayPal transport that matches the live billing tables.
-- PayPal application secrets are read from Vault and whitespace-normalized.
-- The Basic header must not contain the base64 line break, or extensions.http
-- fails before PayPal sees the request. Tokens are never returned to callers.
-- provider_verified is set only after a provider readback of ACTIVE.

create or replace function private.pandora_paypal_sandbox_token_v1()
returns text
language plpgsql
security definer
set search_path = pg_catalog, extensions, vault
as $$
declare
  v_client text;
  v_secret text;
  v_basic text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select regexp_replace(decrypted_secret, '\s', '', 'g') into v_client
  from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select regexp_replace(decrypted_secret, '\s', '', 'g') into v_secret
  from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  if nullif(v_client, '') is null or nullif(v_secret, '') is null then
    raise exception 'PAYPAL_SANDBOX_NOT_CONFIGURED' using errcode = '55000';
  end if;
  v_basic := replace(encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64'), E'\n', '');
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api-m.sandbox.paypal.com/v1/oauth2/token',
    array[
      extensions.http_header('authorization', 'Basic ' || v_basic),
      extensions.http_header('content-type', 'application/x-www-form-urlencoded'),
      extensions.http_header('accept', 'application/json')
    ]::extensions.http_header[],
    'application/x-www-form-urlencoded',
    'grant_type=client_credentials'
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := '{}'::jsonb;
  end;
  if v_response.status <> 200 or nullif(v_body->>'access_token', '') is null then
    raise exception 'PAYPAL_SANDBOX_AUTH_FAILED' using errcode = '55000';
  end if;
  return v_body->>'access_token';
end;
$$;

revoke all on function private.pandora_paypal_sandbox_token_v1() from public, anon, authenticated;

create or replace function private.pandora_paypal_sandbox_call_v1(
  p_method text,
  p_path text,
  p_body jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions, private
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  if upper(p_method) not in ('GET', 'POST') then
    raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if p_path is null or p_path !~ '^/v1/(catalogs/products|billing/plans|billing/subscriptions(/I-[A-Z0-9]+(/cancel)?)?)$' then
    raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode = '22023';
  end if;
  v_token := private.pandora_paypal_sandbox_token_v1();
  select * into v_response from extensions.http((
    upper(p_method)::extensions.http_method,
    ('https://api-m.sandbox.paypal.com' || p_path)::varchar,
    array[
      extensions.http_header('authorization', 'Bearer ' || v_token),
      extensions.http_header('content-type', 'application/json'),
      extensions.http_header('accept', 'application/json'),
      extensions.http_header('prefer', 'return=representation')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin
    v_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_body := '{}'::jsonb;
  end;
  return jsonb_build_object(
    'status', v_response.status,
    'body', coalesce(v_body, '{}'::jsonb) - 'access_token' - 'client_id' - 'client_secret'
  );
end;
$$;

revoke all on function private.pandora_paypal_sandbox_call_v1(text, text, jsonb) from public, anon, authenticated;

-- Checkout, reconcile, and cancel use the existing sandbox tables.
-- verified stays false unless PayPal readback returns ACTIVE.
-- Cancel is attempted only against the sandbox subscription id and is not
-- marked cancelled unless the subsequent provider readback says so.

comment on function private.pandora_paypal_sandbox_token_v1() is
  'Vault-backed PayPal sandbox token. Never grant to client roles.';
