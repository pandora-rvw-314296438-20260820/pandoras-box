-- PLP Enterprise PayPal billing webhook ingest & background reconcile.
-- Purpose: Ingest and cryptographically verify PayPal webhooks, process subscription lifecycle events,
-- and schedule background reconciliation for pending checkouts and stale subscriptions.
--
-- Dependencies & Scope:
-- - Depends on 20261010090000_plp_billing_checkout_hotfix_v1.sql (Migration A).
-- - Applying it alone changes nothing user-visible until the edge function is deployed and PayPal is re-pointed.
--
-- Defects fixed:
-- - S3: Missing PayPal webhook ingest receiver and reconcile cron.
--       Fix: Implement private.pandora_paypal_verify_webhook_v1, public.pandora_plp_paypal_webhook_ingest_v1,
--            private.pandora_plp_billing_reconcile_open_v1, and pg_cron schedule.
--
-- Scope & Safety:
-- - Non-destructive (adds new functions and pg_cron schedule only; no table/column/data drops). Replay-safe.
-- - No begin/commit (Supabase migrations run inside transactions automatically).
-- - Rollback: supabase/rollback/20261010091000_plp_paypal_webhook_ingest_v1.down.sql
--
-- STATUS: NOT APPLIED — requires owner approval.

create or replace function private.pandora_paypal_verify_webhook_v1(
  p_headers jsonb,
  p_raw_body text
) returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'extensions', 'private', 'vault'
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

  if v_cert_url !~* '^https:\/\/(api|api-m)(\.sandbox)?\.paypal\.com(\/.*)?$' then
    return false;
  end if;

  select decrypted_secret into v_webhook_id
  from vault.decrypted_secrets
  where name = 'paypal_webhook_id' and nullif(btrim(decrypted_secret), '') is not null
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

  return coalesce(v_response.status, 0) = 200 and coalesce(v_resp_body->>'verification_status', '') = 'SUCCESS';
end;
$function$;

create or replace function public.pandora_plp_paypal_webhook_ingest_v1(
  p_headers jsonb,
  p_raw_body text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'extensions', 'public', 'private'
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

  -- Signature verification FIRST
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
      provider_event_id, event_type, resource_id, paypal_subscription_id, organization_id,
      payload_sha256, payload, processing_status, received_at
    ) values (
      v_event_id, v_event_type, v_res->>'id', null, null,
      v_sha, v_safe_payload, 'received', now()
    )
    on conflict (provider_event_id) do nothing;
  end if;

  -- Subscription id and organization resolution
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

  if v_org_id is null and (v_res->>'custom_id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
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
            processing_error = left(coalesce(v_rec_result->>'reason', 'Reconcile provider failure'), 500),
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

create or replace function private.pandora_plp_billing_reconcile_open_v1(
  p_limit int default 20
) returns int
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_rec record;
  v_count int := 0;
begin
  for v_rec in (
    select distinct org_id from (
      select organization_id as org_id
      from public.pandora_paypal_billing_sessions
      where status = 'approval_pending'
        and created_at >= now() - interval '3 days'
      union
      select organization_id as org_id
      from public.pandora_customer_subscriptions
      where state = 'active'
        and source_kind = 'provider_verified'
        and verified_at < now() - interval '20 hours'
    ) targets
    limit p_limit
  ) loop
    begin
      perform public.pandora_plp_billing_reconcile_v1(v_rec.org_id, null);
      v_count := v_count + 1;
    exception when others then
      -- Bounded failure: one failing org does not abort others
      null;
    end;
  end loop;
  return v_count;
end;
$function$;

do $schedule$
declare
  v_job record;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and to_regnamespace('cron') is not null
     and to_regprocedure('cron.schedule(text,text,text)') is not null then
    for v_job in execute
      'select jobid from cron.job where jobname = $1'
      using 'pandora-plp-billing-reconcile-v1'
    loop
      execute 'select cron.unschedule($1)' using v_job.jobid;
    end loop;
    perform cron.schedule(
      'pandora-plp-billing-reconcile-v1',
      '*/10 * * * *',
      'select private.pandora_plp_billing_reconcile_open_v1(20);'
    );
  end if;
end;
$schedule$;

revoke all on function private.pandora_paypal_verify_webhook_v1(jsonb, text) from public, anon, authenticated;
grant execute on function private.pandora_paypal_verify_webhook_v1(jsonb, text) to postgres, service_role;

revoke all on function public.pandora_plp_paypal_webhook_ingest_v1(jsonb, text) from public, anon, authenticated;
grant execute on function public.pandora_plp_paypal_webhook_ingest_v1(jsonb, text) to postgres, service_role;

revoke all on function private.pandora_plp_billing_reconcile_open_v1(int) from public, anon, authenticated;
grant execute on function private.pandora_plp_billing_reconcile_open_v1(int) to postgres, service_role;
