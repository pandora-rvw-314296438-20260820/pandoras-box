
-- RedApple domain commerce payment gate.
-- Customers pay RedApple through Xendit or PayPal before Pandora spends registrar funds.
-- Registrant contact data is encrypted at rest and purged after fulfillment/refund.

alter table public.pandora_domain_quotes
  add column if not exists retail_price numeric(12,2),
  add column if not exists markup_bps integer not null default 0;

alter table public.pandora_domain_quotes
  drop constraint if exists pandora_domain_quotes_retail_price_check,
  add constraint pandora_domain_quotes_retail_price_check check (retail_price is null or retail_price > 0),
  drop constraint if exists pandora_domain_quotes_markup_bps_check,
  add constraint pandora_domain_quotes_markup_bps_check check (markup_bps between 0 and 100000);

insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active,updated_at)
values
  ('domain_commerce','markup_bps','0',true,now()),
  ('domain_commerce','return_base_url','https://mcpmaster.vercel.app/',true,now()),
  ('paypal','mode','sandbox',true,now())
on conflict (provider,config_key) do nothing;

do $domain_contact_key$
declare
  v_secret_exists boolean := false;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema='vault'
      and table_name='decrypted_secrets'
      and column_name='name'
  ) then
    execute 'select exists(select 1 from vault.decrypted_secrets where name=$1)'
      into v_secret_exists
      using 'domain_contact_encryption_key';
    if not v_secret_exists then
      perform vault.create_secret(
        encode(extensions.gen_random_bytes(32),'hex'),
        'domain_contact_encryption_key',
        'Pandora domain checkout transient registrant-contact encryption key',
        null
      );
    end if;
  end if;
end
$domain_contact_key$;

create table if not exists public.pandora_domain_checkouts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  quote_id uuid not null references public.pandora_domain_quotes(id) on delete restrict,
  requested_by uuid not null,
  domain text not null,
  gateway text not null,
  idempotency_key text not null,
  status text not null default 'created',
  wholesale_price numeric(12,2) not null,
  retail_price numeric(12,2) not null,
  currency text not null,
  years integer not null,
  auto_renew_requested boolean not null default false,
  provider_session_id text,
  provider_payment_id text,
  provider_payment_request_id text,
  provider_capture_id text,
  provider_refund_id text,
  checkout_url text,
  contact_ciphertext bytea,
  safe_result jsonb not null default '{}'::jsonb,
  normalized_error jsonb not null default '{}'::jsonb,
  paid_at timestamptz,
  fulfilled_at timestamptz,
  refunded_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_domain_checkouts_domain_check check (length(domain) between 1 and 253),
  constraint pandora_domain_checkouts_gateway_check check (gateway in ('xendit','paypal')),
  constraint pandora_domain_checkouts_key_check check (idempotency_key ~ '^[0-9a-f]{64}$'),
  constraint pandora_domain_checkouts_status_check check (status in ('created','pending','paid','fulfilling','fulfilled','failed','expired','refund_pending','refunded','needs_attention')),
  constraint pandora_domain_checkouts_prices_check check (wholesale_price > 0 and retail_price > 0),
  constraint pandora_domain_checkouts_years_check check (years between 1 and 10),
  unique(gateway,idempotency_key)
);
create index if not exists pandora_domain_checkouts_org_user_idx on public.pandora_domain_checkouts(organization_id,requested_by,created_at desc);
create index if not exists pandora_domain_checkouts_project_idx on public.pandora_domain_checkouts(organization_id,project_id,created_at desc);
alter table public.pandora_domain_checkouts enable row level security;
revoke all on public.pandora_domain_checkouts from public,anon,authenticated;
grant select,insert,update on public.pandora_domain_checkouts to service_role;

create or replace function private.pandora_domain_markup_bps_20260830()
returns integer
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v text; v_value integer; begin
  select config_value into v from public.pandora_runtime_provider_configs
  where provider='domain_commerce' and config_key='markup_bps' and active=true;
  begin v_value:=coalesce(nullif(v,''),'0')::integer; exception when others then v_value:=0; end;
  return greatest(0,least(v_value,100000));
end; $$;
revoke all on function private.pandora_domain_markup_bps_20260830() from public,anon,authenticated;
grant execute on function private.pandora_domain_markup_bps_20260830() to service_role;

create or replace function private.pandora_domain_contact_key_20260830()
returns text
language plpgsql
security definer
set search_path='pg_catalog','vault'
as $$
declare v text; begin
  select decrypted_secret into strict v from vault.decrypted_secrets where name='domain_contact_encryption_key' limit 1;
  if nullif(btrim(v),'') is null then raise exception 'DOMAIN_CONTACT_KEY_UNAVAILABLE' using errcode='55000'; end if;
  return v;
end; $$;
revoke all on function private.pandora_domain_contact_key_20260830() from public,anon,authenticated;
grant execute on function private.pandora_domain_contact_key_20260830() to service_role;

create or replace function private.pandora_domain_return_base_20260830()
returns text
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v text; begin
  select config_value into v from public.pandora_runtime_provider_configs
  where provider='domain_commerce' and config_key='return_base_url' and active=true;
  if v is null or v !~ '^https://[A-Za-z0-9.-]+(/.*)?$' then return 'https://mcpmaster.vercel.app/'; end if;
  return v;
end; $$;
revoke all on function private.pandora_domain_return_base_20260830() from public,anon,authenticated;
grant execute on function private.pandora_domain_return_base_20260830() to service_role;

create or replace function private.pandora_xendit_api_20260830(p_method text,p_path text,p_body jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $$
declare
  v_secret text; v_response extensions.http_response; v_method extensions.http_method; v_body jsonb; v_auth text;
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST') then raise exception 'XENDIT_METHOD_NOT_ALLOWED' using errcode='22023'; end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' then raise exception 'XENDIT_PATH_INVALID' using errcode='22023'; end if;
  if not (
    (upper(p_method)='POST' and p_path='/sessions') or
    (upper(p_method)='GET' and p_path ~ '^/sessions/ps-[A-Za-z0-9-]+$') or
    (upper(p_method)='GET' and p_path ~ '^/v3/payments/py-[A-Za-z0-9-]+$') or
    (upper(p_method)='POST' and p_path='/refunds')
  ) then raise exception 'XENDIT_PATH_NOT_ALLOWED' using errcode='22023'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name='xendit_secret_key' limit 1;
  if nullif(btrim(v_secret),'') is null then raise exception 'XENDIT_NOT_CONFIGURED' using errcode='55000'; end if;
  v_auth:='Basic '||replace(encode(convert_to(v_secret||':','UTF8'),'base64'),E'\n','');
  v_method:=upper(p_method)::extensions.http_method;
  select * into v_response from extensions.http((
    v_method,
    ('https://api.xendit.co'||p_path)::varchar,
    array[
      extensions.http_header('authorization',v_auth),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('accept','application/json'),
      extensions.http_header('api-version','2024-11-11'),
      extensions.http_header('user-agent','RedApple-Pandora-Domain-Checkout/1.0')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then v_body:=jsonb_build_object('error_code','UNREADABLE_RESPONSE'); end;
  return jsonb_build_object('status',v_response.status,'body',coalesce(v_body,'{}'::jsonb));
end; $$;
revoke all on function private.pandora_xendit_api_20260830(text,text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_xendit_api_20260830(text,text,jsonb) to service_role;

create or replace function private.pandora_paypal_base_20260830()
returns text
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v text; begin
  select lower(config_value) into v from public.pandora_runtime_provider_configs
  where provider='paypal' and config_key='mode' and active=true;
  if v='live' then return 'https://api-m.paypal.com'; end if;
  return 'https://api-m.sandbox.paypal.com';
end; $$;
revoke all on function private.pandora_paypal_base_20260830() from public,anon,authenticated;
grant execute on function private.pandora_paypal_base_20260830() to service_role;

create or replace function private.pandora_paypal_access_20260830()
returns text
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions','private'
as $$
declare
  v_client text; v_secret text; v_response extensions.http_response; v_body jsonb; v_auth text;
begin
  select decrypted_secret into v_client from vault.decrypted_secrets where name='paypal_client_id' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name='paypal_client_secret' limit 1;
  if nullif(btrim(v_client),'') is null or nullif(btrim(v_secret),'') is null then raise exception 'PAYPAL_NOT_CONFIGURED' using errcode='55000'; end if;
  v_auth:='Basic '||replace(encode(convert_to(v_client||':'||v_secret,'UTF8'),'base64'),E'\n','');
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    (private.pandora_paypal_base_20260830()||'/v1/oauth2/token')::varchar,
    array[
      extensions.http_header('authorization',v_auth),
      extensions.http_header('content-type','application/x-www-form-urlencoded'),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','RedApple-Pandora-Domain-Checkout/1.0')
    ]::extensions.http_header[],
    'application/x-www-form-urlencoded'::varchar,
    'grant_type=client_credentials'::varchar
  )::extensions.http_request);
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then v_body:='{}'::jsonb; end;
  if v_response.status<>200 or nullif(v_body->>'access_token','') is null then raise exception 'PAYPAL_AUTH_FAILED' using errcode='55000'; end if;
  return v_body->>'access_token';
end; $$;
revoke all on function private.pandora_paypal_access_20260830() from public,anon,authenticated;
grant execute on function private.pandora_paypal_access_20260830() to service_role;

create or replace function private.pandora_paypal_api_20260830(p_method text,p_path text,p_body jsonb default null,p_request_id text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','extensions','private'
as $$
declare
  v_token text; v_response extensions.http_response; v_method extensions.http_method; v_body jsonb; v_headers extensions.http_header[];
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST') then raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode='22023'; end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' then raise exception 'PAYPAL_PATH_INVALID' using errcode='22023'; end if;
  if not (
    (upper(p_method)='POST' and p_path='/v2/checkout/orders') or
    (upper(p_method)='GET' and p_path ~ '^/v2/checkout/orders/[A-Za-z0-9]+$') or
    (upper(p_method)='POST' and p_path ~ '^/v2/checkout/orders/[A-Za-z0-9]+/capture$') or
    (upper(p_method)='POST' and p_path ~ '^/v2/payments/captures/[A-Za-z0-9]+/refund$')
  ) then raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode='22023'; end if;
  v_token:=private.pandora_paypal_access_20260830();
  v_headers:=array[
    extensions.http_header('authorization','Bearer '||v_token),
    extensions.http_header('content-type','application/json'),
    extensions.http_header('accept','application/json'),
    extensions.http_header('prefer','return=representation'),
    extensions.http_header('user-agent','RedApple-Pandora-Domain-Checkout/1.0')
  ]::extensions.http_header[];
  if nullif(p_request_id,'') is not null then v_headers:=array_append(v_headers,extensions.http_header('paypal-request-id',left(p_request_id,78))); end if;
  v_method:=upper(p_method)::extensions.http_method;
  select * into v_response from extensions.http((
    v_method,
    (private.pandora_paypal_base_20260830()||p_path)::varchar,
    v_headers,
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then v_body:=jsonb_build_object('name','UNREADABLE_RESPONSE'); end;
  return jsonb_build_object('status',v_response.status,'body',coalesce(v_body,'{}'::jsonb));
end; $$;
revoke all on function private.pandora_paypal_api_20260830(text,text,jsonb,text) from public,anon,authenticated;
grant execute on function private.pandora_paypal_api_20260830(text,text,jsonb,text) to service_role;
