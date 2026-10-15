-- Canonical source for production migration 20261010015142_plp_paypal_webhook_ingest_v1.
-- This migration was previously applied directly to production and is now being reconciled into Git.
-- No credential values are stored in source. DDL is idempotent for exact-state reconciliation.

create table if not exists public.pandora_paypal_billing_webhook_events (
  provider_event_id text primary key,
  event_type text not null,
  resource_id text,
  paypal_subscription_id text,
  organization_id uuid references public.organizations(id) on delete set null,
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  payload jsonb not null default '{}'::jsonb,
  processing_status text not null default 'received'
    check (processing_status in ('received','processed','ignored','failed')),
  processing_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists pandora_paypal_billing_webhook_events_subscription_idx
  on public.pandora_paypal_billing_webhook_events (paypal_subscription_id, received_at desc);
create index if not exists pandora_paypal_billing_webhook_events_org_idx
  on public.pandora_paypal_billing_webhook_events (organization_id, received_at desc);

alter table public.pandora_paypal_billing_webhook_events enable row level security;
alter table public.pandora_paypal_billing_webhook_events force row level security;
revoke all on table public.pandora_paypal_billing_webhook_events from public, anon, authenticated;
grant select, insert, update, delete, truncate, references, trigger
  on table public.pandora_paypal_billing_webhook_events to service_role;

create or replace function private.pandora_paypal_verify_webhook_v1(
  p_headers jsonb,
  p_raw_body text
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','extensions','private','vault'
as $function$
declare
  v_auth_algo text;
  v_cert_url text;
  v_transmission_id text;
  v_transmission_sig text;
  v_transmission_time text;
  v_webhook_id text;
  v_token text;
  v_base text;
  v_req_body text;
  v_headers extensions.http_header[];
  v_response extensions.http_response;
  v_resp_body jsonb;
begin
  v_auth_algo := coalesce(p_headers->>'paypal-auth-algo', p_headers->>'PAYPAL-AUTH-ALGO');
  v_cert_url := coalesce(p_headers->>'paypal-cert-url', p_headers->>'PAYPAL-CERT-URL');
  v_transmission_id := coalesce(p_headers->>'paypal-transmission-id', p_headers->>'PAYPAL-TRANSMISSION-ID');
  v_transmission_sig := coalesce(p_headers->>'paypal-transmission-sig', p_headers->>'PAYPAL-TRANSMISSION-SIG');
  v_transmission_time := coalesce(p_headers->>'paypal-transmission-time', p_headers->>'PAYPAL-TRANSMISSION-TIME');

  if v_auth_algo is null or v_auth_algo = ''
     or v_cert_url is null or v_cert_url = ''
     or v_transmission_id is null or v_transmission_id = ''
     or v_transmission_sig is null or v_transmission_sig = ''
     or v_transmission_time is null or v_transmission_time = '' then
    return false;
  end if;

  if v_cert_url !~* '^https://(api|api-m)(\.sandbox)?\.paypal\.com(/.*)?$' then
    return false;
  end if;

  select decrypted_secret into v_webhook_id
  from vault.decrypted_secrets
  where name = 'paypal_webhook_id'
    and nullif(btrim(decrypted_secret), '') is not null
  limit 1;

  if v_webhook_id is null or v_webhook_id = '' then
    raise exception 'PAYPAL_WEBHOOK_NOT_CONFIGURED' using errcode = 'P0002';
  end if;

  v_token := private.pandora_paypal_access_20260830();
  v_base := private.pandora_paypal_base_20260830();

  v_req_body := rtrim(jsonb_build_object(
    'auth_algo', v_auth_algo,
    'cert_url', v_cert_url,
    'transmission_id', v_transmission_id,
    'transmission_sig', v_transmission_sig,
    'transmission_time', v_transmission_time,
    'webhook_id', v_webhook_id
  )::text, '}') || ', "webhook_event": ' || p_raw_body || '}';

  v_headers := array[
    extensions.http_header('authorization', 'Bearer ' || v_token),
    extensions.http_header('content-type', 'application/json'),
    extensions.http_header('accept', 'application/json'),
    extensions.http_header('user-agent', 'Pandora-PLP-Webhook/1.0')
  ]::extensions.http_header[];

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    (v_base || '/v1/notifications/verify-webhook-signature')::varchar,
    v_headers,
    'application/json'::varchar,
    v_req_body::varchar
  )::extensions.http_request);

  begin
    v_resp_body := nullif(v_response.content, '')::jsonb;
  exception when others then
    v_resp_body := '{}'::jsonb;
  end;

  return coalesce(v_response.status, 0) = 200
    and coalesce(v_resp_body->>'verification_status', '') = 'SUCCESS';
end;
$function$;

revoke all on function private.pandora_paypal_verify_webhook_v1(jsonb,text) from public, anon, authenticated;
grant execute on function private.pandora_paypal_verify_webhook_v1(jsonb,text) to service_role;

create or replace function public.pandora_plp_paypal_webhook_ingest_v1(
  p_headers jsonb,
  p_raw_body text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','extensions','public','private'
as $function$
declare
  v_event jsonb;
  v_event_id text;
  v_event_type text;
  v_verified boolean;
  v_sha text;
  v_res jsonb;
  v_safe_payload jsonb;
  v_existing_status text;
  v_sub_id text;
  v_org_id uuid;
  v_rec_result jsonb;
begin
  if p_raw_body is null or octet_length(p_raw_body) > 131072 then
    return jsonb_build_object('accepted', false, 'code', 'BODY_TOO_LARGE');
  end if;

  begin
    v_event := p_raw_body::jsonb;
  exception when others then
    return jsonb_build_object('accepted', false, 'code', 'BODY_INVALID');
  end;

  v_event_id := nullif(btrim(v_event->>'id'), '');
  v_event_type := nullif(btrim(v_event->>'event_type'), '');
  if v_event_id is null or v_event_type is null then
    return jsonb_build_object('accepted', false, 'code', 'BODY_INVALID');
  end if;

  -- PayPal transmission signature is checked before any event is written.
  begin
    v_verified := private.pandora_paypal_verify_webhook_v1(p_headers, p_raw_body);
  exception when others then
    return jsonb_build_object('accepted', false, 'code', 'VERIFY_UNAVAILABLE');
  end;

  if not coalesce(v_verified, false) then
    return jsonb_build_object('accepted', false, 'code', 'SIGNATURE_INVALID');
  end if;

  v_sha := encode(extensions.digest(p_raw_body, 'sha256'), 'hex');
  v_res := coalesce(v_event->'resource', '{}'::jsonb);
  v_safe_payload := jsonb_build_object(
    'id', v_event_id,
    'event_type', v_event_type,
    'resource', jsonb_build_object(
      'id', v_res->>'id',
      'status', v_res->>'status',
      'plan_id', v_res->>'plan_id',
      'billing_agreement_id', v_res->>'billing_agreement_id',
      'custom_id', v_res->>'custom_id'
    )
  );

  select processing_status into v_existing_status
  from public.pandora_paypal_billing_webhook_events
  where provider_event_id = v_event_id;

  if found then
    if v_existing_status in ('processed', 'ignored') then
      return jsonb_build_object('accepted', true, 'duplicate', true);
    end if;
  else
    insert into public.pandora_paypal_billing_webhook_events (
      provider_event_id, event_type, resource_id, paypal_subscription_id,
      organization_id, payload_sha256, payload, processing_status, received_at
    ) values (
      v_event_id, v_event_type, v_res->>'id', null, null,
      v_sha, v_safe_payload, 'received', now()
    )
    on conflict (provider_event_id) do nothing;
  end if;

  if v_event_type like 'PAYMENT.SALE.%' then
    v_sub_id := coalesce(nullif(v_res->>'billing_agreement_id', ''), nullif(v_res->>'id', ''));
  else
    v_sub_id := nullif(v_res->>'id', '');
  end if;

  v_org_id := null;
  if v_sub_id is not null then
    select organization_id into v_org_id
    from public.pandora_paypal_billing_sessions
    where paypal_subscription_id = v_sub_id
    order by created_at desc
    limit 1;

    if v_org_id is null then
      select organization_id into v_org_id
      from public.pandora_customer_subscriptions
      where provider_reference = v_sub_id
      limit 1;
    end if;
  end if;

  if v_org_id is null
     and (v_res->>'custom_id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    select organization_id into v_org_id
    from public.pandora_paypal_billing_sessions
    where id = (v_res->>'custom_id')::uuid;
  end if;

  update public.pandora_paypal_billing_webhook_events
  set organization_id = v_org_id,
      paypal_subscription_id = v_sub_id,
      resource_id = v_res->>'id'
  where provider_event_id = v_event_id;

  begin
    if v_org_id is null then
      update public.pandora_paypal_billing_webhook_events
      set processing_status = 'ignored', processed_at = now()
      where provider_event_id = v_event_id;
      return jsonb_build_object('accepted', true, 'ignored', true);
    end if;

    if v_event_type like 'BILLING.SUBSCRIPTION.%' or v_event_type like 'PAYMENT.SALE.%' then
      v_rec_result := public.pandora_plp_billing_reconcile_v1(v_org_id, null);
      if coalesce((v_rec_result->>'verified')::boolean, false) = false
         and (v_rec_result->>'reason') in ('PAYPAL_READ_FAILED', 'PAYPAL_AUTH_FAILED', 'PAYPAL_UNREACHABLE') then
        update public.pandora_paypal_billing_webhook_events
        set processing_status = 'failed',
            processing_error = left(coalesce(v_rec_result->>'reason', 'PayPal read failed'), 500),
            processed_at = now()
        where provider_event_id = v_event_id;
        return jsonb_build_object('accepted', false, 'code', 'PROCESSING_FAILED');
      else
        update public.pandora_paypal_billing_webhook_events
        set processing_status = 'processed',
            processed_at = now(),
            processing_error = null
        where provider_event_id = v_event_id;
        return jsonb_build_object('accepted', true, 'processed', true);
      end if;
    else
      update public.pandora_paypal_billing_webhook_events
      set processing_status = 'ignored', processed_at = now()
      where provider_event_id = v_event_id;
      return jsonb_build_object('accepted', true, 'ignored', true);
    end if;
  exception when others then
    update public.pandora_paypal_billing_webhook_events
    set processing_status = 'failed',
        processing_error = left(sqlerrm, 500),
        processed_at = now()
    where provider_event_id = v_event_id;
    return jsonb_build_object('accepted', false, 'code', 'PROCESSING_FAILED');
  end;
end;
$function$;

revoke all on function public.pandora_plp_paypal_webhook_ingest_v1(jsonb,text) from public, anon, authenticated;
grant execute on function public.pandora_plp_paypal_webhook_ingest_v1(jsonb,text) to service_role;
