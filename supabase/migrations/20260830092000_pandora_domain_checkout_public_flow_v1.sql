-- RedApple domain checkout public flow. Customers must settle with Xendit or PayPal before registrar purchase.

CREATE OR REPLACE FUNCTION public.pandora_quote_domain_checkout(p_organization_id uuid, p_domain text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_result jsonb; v_quote_id uuid; v_wholesale numeric; v_retail numeric; v_markup integer;
begin
  v_result:=public.pandora_quote_domain(p_organization_id,p_domain);
  v_quote_id:=nullif(v_result->>'quoteId','')::uuid;
  if coalesce((v_result->>'available')::boolean,false) is not true then
    return v_result||jsonb_build_object('retailPrice',null,'wholesalePurchasePrice',null,'markupBps',0);
  end if;
  v_wholesale:=nullif(v_result->>'purchasePrice','')::numeric;
  if v_wholesale is null or v_wholesale<=0 then raise exception 'DOMAIN_PRICE_INVALID' using errcode='55000'; end if;
  v_markup:=private.pandora_domain_markup_bps_20260830();
  v_retail:=round(v_wholesale*(1+(v_markup::numeric/10000)),2);
  if v_retail<v_wholesale then v_retail:=v_wholesale; end if;
  update public.pandora_domain_quotes
  set retail_price=v_retail,markup_bps=v_markup,updated_at=now()
  where id=v_quote_id and organization_id=p_organization_id;
  return v_result||jsonb_build_object(
    'purchasePrice',v_retail,
    'retailPrice',v_retail,
    'wholesalePurchasePrice',v_wholesale,
    'markupBps',v_markup
  );
end; $function$;

revoke all on function public.pandora_quote_domain_checkout(uuid,text) from public,anon;
grant execute on function public.pandora_quote_domain_checkout(uuid,text) to authenticated;

CREATE OR REPLACE FUNCTION public.pandora_create_domain_checkout(p_organization_id uuid, p_project_identifier text, p_quote_id uuid, p_gateway text, p_contact_information jsonb, p_auto_renew_requested boolean, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth', 'extensions'
AS $function$
declare
  v_user uuid:=auth.uid(); v_quote public.pandora_domain_quotes%rowtype; v_project public.projectos_projects%rowtype;
  v_gateway text:=lower(btrim(coalesce(p_gateway,''))); v_required text; v_phone text; v_country text;
  v_markup integer; v_retail numeric; v_operation_key text; v_checkout public.pandora_domain_checkouts%rowtype;
  v_existing public.pandora_domain_checkouts%rowtype; v_contact_key text; v_base text; v_return text; v_cancel text;
  v_provider jsonb; v_provider_status integer; v_session_id text; v_checkout_url text; v_provider_expires timestamptz;
  v_reference text; v_order_id text; v_link jsonb; v_amount_text text; v_now timestamptz:=now();
begin
  if v_user is null then raise exception 'SIGN_IN_REQUIRED' using errcode='28000'; end if;
  if not exists(select 1 from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_user and m.status::text='active' and m.role::text in ('owner','admin')) then raise exception 'OWNER_ROLE_REQUIRED' using errcode='42501'; end if;
  if v_gateway not in ('xendit','paypal') then raise exception 'DOMAIN_PAYMENT_GATEWAY_INVALID' using errcode='22023'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 200 or p_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode='22023'; end if;

  select * into v_quote from public.pandora_domain_quotes
  where id=p_quote_id and organization_id=p_organization_id and requested_by=v_user for update;
  if not found then raise exception 'DOMAIN_QUOTE_NOT_FOUND' using errcode='P0002'; end if;
  if v_quote.status<>'quoted' or not v_quote.available or v_quote.expires_at<=v_now or v_quote.purchase_price is null then raise exception 'DOMAIN_QUOTE_EXPIRED' using errcode='22023'; end if;

  if p_project_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select * into v_project from public.projectos_projects where organization_id=p_organization_id and id=p_project_identifier::uuid and status<>'archived';
  else
    select * into v_project from public.projectos_projects where organization_id=p_organization_id and project_key=p_project_identifier and status<>'archived';
  end if;
  if not found then raise exception 'PROJECT_NOT_FOUND' using errcode='P0002'; end if;

  if jsonb_typeof(p_contact_information)<>'object' then raise exception 'DOMAIN_CONTACT_INVALID' using errcode='22023'; end if;
  foreach v_required in array array['firstName','lastName','email','phone','address1','city','state','zip','country'] loop
    if nullif(btrim(p_contact_information->>v_required),'') is null then raise exception 'DOMAIN_CONTACT_REQUIRED_%',v_required using errcode='22023'; end if;
  end loop;
  if (p_contact_information->>'email') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'DOMAIN_CONTACT_EMAIL_INVALID' using errcode='22023'; end if;
  v_phone:=p_contact_information->>'phone'; if v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'DOMAIN_CONTACT_PHONE_INVALID' using errcode='22023'; end if;
  v_country:=upper(p_contact_information->>'country'); if v_country !~ '^[A-Z]{2}$' then raise exception 'DOMAIN_CONTACT_COUNTRY_INVALID' using errcode='22023'; end if;
  p_contact_information:=jsonb_set(p_contact_information,'{country}',to_jsonb(v_country),true);

  v_markup:=coalesce(v_quote.markup_bps,private.pandora_domain_markup_bps_20260830());
  v_retail:=coalesce(v_quote.retail_price,round(v_quote.purchase_price*(1+(v_markup::numeric/10000)),2));
  if v_retail<v_quote.purchase_price then v_retail:=v_quote.purchase_price; end if;
  v_operation_key:=encode(extensions.digest(convert_to('domain_checkout|'||p_organization_id::text||'|'||v_user::text||'|'||p_quote_id::text||'|'||v_project.id::text||'|'||v_gateway||'|'||p_idempotency_key,'UTF8'),'sha256'),'hex');
  v_contact_key:=private.pandora_domain_contact_key_20260830();

  begin
    insert into public.pandora_domain_checkouts(
      organization_id,project_id,quote_id,requested_by,domain,gateway,idempotency_key,status,
      wholesale_price,retail_price,currency,years,auto_renew_requested,contact_ciphertext,expires_at
    ) values(
      p_organization_id,v_project.id,v_quote.id,v_user,v_quote.domain,v_gateway,v_operation_key,'created',
      v_quote.purchase_price,v_retail,v_quote.currency,v_quote.years,coalesce(p_auto_renew_requested,false),
      extensions.pgp_sym_encrypt(p_contact_information::text,v_contact_key,'cipher-algo=aes256,compress-algo=0'),
      now()+interval '2 hours'
    ) returning * into v_checkout;
  exception when unique_violation then
    select * into v_existing from public.pandora_domain_checkouts where gateway=v_gateway and idempotency_key=v_operation_key;
    if not found then raise exception 'DOMAIN_CHECKOUT_CLAIM_FAILED' using errcode='55000'; end if;
    return jsonb_build_object(
      'checkoutId',v_existing.id,'domain',v_existing.domain,'gateway',v_existing.gateway,'status',v_existing.status,
      'checkoutUrl',v_existing.checkout_url,'amount',v_existing.retail_price,'currency',v_existing.currency,
      'expiresAt',v_existing.expires_at,'projectId',v_existing.project_id,'replayed',true,
      'plainMessage',case when v_existing.status='fulfilled' then 'Domain registration completed.' else 'Continue the existing payment checkout.' end
    );
  end;

  update public.pandora_domain_quotes set retail_price=v_retail,markup_bps=v_markup,expires_at=greatest(expires_at,now()+interval '2 hours'),updated_at=now() where id=v_quote.id;
  v_base:=private.pandora_domain_return_base_20260830();
  v_return:=v_base||case when position('?' in v_base)>0 then '&' else '?' end||'domain_checkout='||v_checkout.id::text||'&payment=success';
  v_cancel:=v_base||case when position('?' in v_base)>0 then '&' else '?' end||'domain_checkout='||v_checkout.id::text||'&payment=cancel';
  v_reference:='d'||replace(v_checkout.id::text,'-','');

  if v_gateway='xendit' then
    v_provider:=private.pandora_xendit_api_20260830('POST','/sessions',jsonb_build_object(
      'reference_id',v_reference,
      'session_type','PAY',
      'mode','PAYMENT_LINK',
      'amount',v_retail,
      'currency',v_quote.currency,
      'country','PH',
      'capture_method','AUTOMATIC',
      'allow_save_payment_method','DISABLED',
      'locale','en',
      'description','RedApple domain registration: '||v_quote.domain,
      'success_return_url',v_return,
      'cancel_return_url',v_cancel,
      'metadata',jsonb_build_object('checkout_id',v_checkout.id::text,'domain',v_quote.domain)
    ));
    v_provider_status:=coalesce((v_provider->>'status')::integer,0);
    v_session_id:=nullif(v_provider#>>'{body,payment_session_id}','');
    v_checkout_url:=nullif(v_provider#>>'{body,payment_link_url}','');
    begin v_provider_expires:=nullif(v_provider#>>'{body,expires_at}','')::timestamptz; exception when others then v_provider_expires:=null; end;
    if v_provider_status<>201 or v_session_id is null or v_checkout_url is null then
      update public.pandora_domain_checkouts set status='failed',contact_ciphertext=null,normalized_error=jsonb_build_object('code','xendit_checkout_failed','httpStatus',v_provider_status),updated_at=now() where id=v_checkout.id;
      if v_provider_status=0 then raise exception 'XENDIT_CHECKOUT_UNAVAILABLE' using errcode='55000'; end if;
      return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_quote.domain,'gateway',v_gateway,'status','failed','amount',v_retail,'currency',v_quote.currency,'code','PAYMENT_CHECKOUT_FAILED','plainMessage','Xendit could not start this payment.');
    end if;
  else
    v_amount_text:=to_char(v_retail,'FM999999990.00');
    v_provider:=private.pandora_paypal_api_20260830('POST','/v2/checkout/orders',jsonb_build_object(
      'intent','CAPTURE',
      'purchase_units',jsonb_build_array(jsonb_build_object(
        'reference_id',v_reference,
        'description','RedApple domain registration: '||v_quote.domain,
        'amount',jsonb_build_object('currency_code',v_quote.currency,'value',v_amount_text)
      )),
      'application_context',jsonb_build_object(
        'brand_name','RedApple',
        'landing_page','LOGIN',
        'user_action','PAY_NOW',
        'return_url',v_return,
        'cancel_url',v_cancel
      )
    ),'create-'||replace(v_checkout.id::text,'-',''));
    v_provider_status:=coalesce((v_provider->>'status')::integer,0);
    v_order_id:=nullif(v_provider#>>'{body,id}','');
    select x.value into v_link from jsonb_array_elements(coalesce(v_provider#>'{body,links}','[]'::jsonb)) x(value)
      where x.value->>'rel' in ('payer-action','approve') order by case when x.value->>'rel'='payer-action' then 0 else 1 end limit 1;
    v_checkout_url:=nullif(v_link->>'href','');
    v_session_id:=v_order_id;
    v_provider_expires:=null;
    if v_provider_status not in (200,201) or v_order_id is null or v_checkout_url is null then
      update public.pandora_domain_checkouts set status='failed',contact_ciphertext=null,normalized_error=jsonb_build_object('code','paypal_checkout_failed','httpStatus',v_provider_status),updated_at=now() where id=v_checkout.id;
      return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_quote.domain,'gateway',v_gateway,'status','failed','amount',v_retail,'currency',v_quote.currency,'code','PAYMENT_CHECKOUT_FAILED','plainMessage','PayPal could not start this payment.');
    end if;
  end if;

  update public.pandora_domain_checkouts
  set status='pending',provider_session_id=v_session_id,checkout_url=v_checkout_url,
      expires_at=coalesce(v_provider_expires,expires_at),updated_at=now()
  where id=v_checkout.id;

  return jsonb_build_object(
    'checkoutId',v_checkout.id,'domain',v_quote.domain,'gateway',v_gateway,'status','pending',
    'checkoutUrl',v_checkout_url,'amount',v_retail,'currency',v_quote.currency,
    'expiresAt',coalesce(v_provider_expires,v_checkout.expires_at),'projectId',v_project.id,
    'plainMessage','Complete payment, then return to Pandora to finish registration.'
  );
end; $function$;

revoke all on function public.pandora_create_domain_checkout(uuid,text,uuid,text,jsonb,boolean,text) from public,anon;
grant execute on function public.pandora_create_domain_checkout(uuid,text,uuid,text,jsonb,boolean,text) to authenticated;

CREATE OR REPLACE FUNCTION public.pandora_reconcile_domain_checkout(p_organization_id uuid, p_checkout_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth', 'extensions'
AS $function$
declare
  v_user uuid:=auth.uid(); v_checkout public.pandora_domain_checkouts%rowtype; v_project public.projectos_projects%rowtype;
  v_provider jsonb; v_provider_status integer; v_status text; v_reference text; v_payment_id text; v_payment_request_id text;
  v_capture jsonb; v_capture_id text; v_paid_amount numeric; v_paid_currency text; v_contact jsonb; v_purchase jsonb; v_code text;
  v_refund jsonb; v_refund_status text; v_refund_id text; v_refund_http integer; v_amount_text text; v_now timestamptz:=now();
begin
  if v_user is null then raise exception 'SIGN_IN_REQUIRED' using errcode='28000'; end if;
  if not exists(select 1 from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_user and m.status::text='active' and m.role::text in ('owner','admin')) then raise exception 'OWNER_ROLE_REQUIRED' using errcode='42501'; end if;
  select * into v_checkout from public.pandora_domain_checkouts
    where id=p_checkout_id and organization_id=p_organization_id and requested_by=v_user for update;
  if not found then raise exception 'DOMAIN_CHECKOUT_NOT_FOUND' using errcode='P0002'; end if;
  select * into v_project from public.projectos_projects where id=v_checkout.project_id and organization_id=p_organization_id;
  if not found then raise exception 'PROJECT_NOT_FOUND' using errcode='P0002'; end if;

  if v_checkout.status='fulfilled' then
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','fulfilled','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'purchase',v_checkout.safe_result->'purchase','plainMessage','Domain registration completed.');
  elsif v_checkout.status in ('refunded','refund_pending') then
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status',v_checkout.status,'amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage',case when v_checkout.status='refunded' then 'The payment was refunded.' else 'The refund is being processed.' end);
  elsif v_checkout.status='failed' then
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','failed','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','This checkout failed. Start a new checkout.');
  end if;

  v_reference:='d'||replace(v_checkout.id::text,'-','');

  if v_checkout.status not in ('paid','fulfilling','needs_attention') then
    if v_checkout.gateway='xendit' then
      if nullif(v_checkout.provider_session_id,'') is null then raise exception 'DOMAIN_PAYMENT_SESSION_MISSING' using errcode='55000'; end if;
      v_provider:=private.pandora_xendit_api_20260830('GET','/sessions/'||v_checkout.provider_session_id,null);
      v_provider_status:=coalesce((v_provider->>'status')::integer,0);
      if v_provider_status<>200 then
        update public.pandora_domain_checkouts set normalized_error=jsonb_build_object('code','xendit_status_unavailable','httpStatus',v_provider_status),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','pending','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment confirmation is not available yet. Check again shortly.');
      end if;
      v_status:=upper(coalesce(v_provider#>>'{body,status}',''));
      if v_status='ACTIVE' then
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','pending','checkoutUrl',v_checkout.checkout_url,'amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'providerStatus',v_status,'plainMessage','Payment is still waiting for completion.');
      elsif v_status in ('EXPIRED','CANCELED') then
        update public.pandora_domain_checkouts set status='expired',contact_ciphertext=null,normalized_error=jsonb_build_object('code','payment_'||lower(v_status)),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','expired','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'providerStatus',v_status,'plainMessage','This payment checkout expired or was canceled. Start a new checkout.');
      elsif v_status<>'COMPLETED' then
        update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','unexpected_xendit_session_status','providerStatus',v_status),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'providerStatus',v_status,'plainMessage','Pandora needs to verify this payment before registration.');
      end if;
      v_payment_id:=nullif(v_provider#>>'{body,payment_id}','');
      v_payment_request_id:=nullif(v_provider#>>'{body,payment_request_id}','');
      if v_payment_id is null or v_payment_request_id is null then
        update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','xendit_payment_reference_missing'),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Pandora needs to verify the completed payment before registration.');
      end if;
      v_capture:=private.pandora_xendit_api_20260830('GET','/v3/payments/'||v_payment_id,null);
      if coalesce((v_capture->>'status')::integer,0)<>200 then
        update public.pandora_domain_checkouts set status='needs_attention',provider_payment_id=v_payment_id,provider_payment_request_id=v_payment_request_id,normalized_error=jsonb_build_object('code','xendit_payment_read_failed'),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Pandora needs to verify the completed payment before registration.');
      end if;
      v_status:=upper(coalesce(v_capture#>>'{body,status}',''));
      begin v_paid_amount:=nullif(v_capture#>>'{body,request_amount}','')::numeric; exception when others then v_paid_amount:=null; end;
      v_paid_currency:=upper(coalesce(v_capture#>>'{body,currency}',''));
      if v_status<>'SUCCEEDED' or coalesce(v_capture#>>'{body,reference_id}','')<>v_reference or v_paid_amount is null or round(v_paid_amount,2)<>round(v_checkout.retail_price,2) or v_paid_currency<>upper(v_checkout.currency) then
        update public.pandora_domain_checkouts set status='needs_attention',provider_payment_id=v_payment_id,provider_payment_request_id=v_payment_request_id,normalized_error=jsonb_build_object('code','xendit_payment_identity_mismatch','providerStatus',v_status),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment details did not match this checkout. Pandora will not register the domain automatically.');
      end if;
      update public.pandora_domain_checkouts set status='paid',provider_payment_id=v_payment_id,provider_payment_request_id=v_payment_request_id,paid_at=coalesce(paid_at,now()),updated_at=now() where id=v_checkout.id;
      v_checkout.status:='paid'; v_checkout.provider_payment_id:=v_payment_id; v_checkout.provider_payment_request_id:=v_payment_request_id;
    else
      if nullif(v_checkout.provider_session_id,'') is null then raise exception 'DOMAIN_PAYMENT_SESSION_MISSING' using errcode='55000'; end if;
      v_provider:=private.pandora_paypal_api_20260830('GET','/v2/checkout/orders/'||v_checkout.provider_session_id,null,null);
      v_provider_status:=coalesce((v_provider->>'status')::integer,0);
      if v_provider_status<>200 then
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','pending','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment confirmation is not available yet. Check again shortly.');
      end if;
      v_status:=upper(coalesce(v_provider#>>'{body,status}',''));
      if v_status in ('CREATED','PAYER_ACTION_REQUIRED','SAVED') then
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','pending','checkoutUrl',v_checkout.checkout_url,'amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'providerStatus',v_status,'plainMessage','Payment is still waiting for approval.');
      elsif v_status='APPROVED' then
        v_provider:=private.pandora_paypal_api_20260830('POST','/v2/checkout/orders/'||v_checkout.provider_session_id||'/capture','{}'::jsonb,'capture-'||replace(v_checkout.id::text,'-',''));
        if coalesce((v_provider->>'status')::integer,0) not in (200,201) then
          update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','paypal_capture_failed','httpStatus',v_provider->>'status'),updated_at=now() where id=v_checkout.id;
          return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','PayPal approved the payment, but Pandora could not confirm capture yet.');
        end if;
        v_status:=upper(coalesce(v_provider#>>'{body,status}',''));
      end if;
      if v_status<>'COMPLETED' then
        update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','unexpected_paypal_order_status','providerStatus',v_status),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'providerStatus',v_status,'plainMessage','Pandora needs to verify this PayPal payment before registration.');
      end if;
      v_capture:=coalesce(v_provider#>'{body,purchase_units,0,payments,captures,0}','{}'::jsonb);
      v_capture_id:=nullif(v_capture->>'id','');
      begin v_paid_amount:=nullif(v_capture#>>'{amount,value}','')::numeric; exception when others then v_paid_amount:=null; end;
      v_paid_currency:=upper(coalesce(v_capture#>>'{amount,currency_code}',''));
      if v_capture_id is null or upper(coalesce(v_capture->>'status',''))<>'COMPLETED' or v_paid_amount is null or round(v_paid_amount,2)<>round(v_checkout.retail_price,2) or v_paid_currency<>upper(v_checkout.currency) then
        update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','paypal_payment_identity_mismatch'),updated_at=now() where id=v_checkout.id;
        return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment details did not match this checkout. Pandora will not register the domain automatically.');
      end if;
      update public.pandora_domain_checkouts set status='paid',provider_payment_id=v_checkout.provider_session_id,provider_capture_id=v_capture_id,paid_at=coalesce(paid_at,now()),updated_at=now() where id=v_checkout.id;
      v_checkout.status:='paid'; v_checkout.provider_capture_id:=v_capture_id;
    end if;
  end if;

  if v_checkout.status='needs_attention' then
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Pandora has stopped automatic fulfillment until this payment is reconciled.');
  end if;

  select contact_ciphertext into v_checkout.contact_ciphertext from public.pandora_domain_checkouts where id=v_checkout.id;
  if v_checkout.contact_ciphertext is null then
    update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','registrant_contact_missing'),updated_at=now() where id=v_checkout.id;
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Pandora cannot safely complete registration without the registrant details.');
  end if;
  begin
    v_contact:=extensions.pgp_sym_decrypt(v_checkout.contact_ciphertext,private.pandora_domain_contact_key_20260830())::jsonb;
  exception when others then
    update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','registrant_contact_decrypt_failed'),updated_at=now() where id=v_checkout.id;
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Pandora cannot safely read the temporary registrant details.');
  end;

  update public.pandora_domain_checkouts set status='fulfilling',updated_at=now() where id=v_checkout.id and status in ('paid','fulfilling');
  begin
    v_purchase:=public.pandora_purchase_domain(
      p_organization_id,
      v_project.id::text,
      v_checkout.quote_id,
      v_checkout.wholesale_price,
      false,
      v_contact,
      'checkout:'||v_checkout.id::text,
      true
    );
  exception when others then
    v_code:=upper(sqlerrm);
    if v_code like '%DOMAIN_QUOTE_EXPIRED%' or v_code like '%DOMAIN_PRICE_CONFIRMATION%' or v_code like '%DOMAIN_CONTACT_%' then
      v_purchase:=jsonb_build_object('ok',false,'code','DOMAIN_FULFILLMENT_DEFINITE_FAILURE','detail',left(v_code,120));
    else
      update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code','fulfillment_exception','detail',left(v_code,120)),updated_at=now() where id=v_checkout.id;
      return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment succeeded, but Pandora needs to reconcile registration before taking another action.');
    end if;
  end;

  if coalesce((v_purchase->>'ok')::boolean,false) is true then
    update public.pandora_domain_checkouts
      set status='fulfilled',contact_ciphertext=null,fulfilled_at=now(),
          safe_result=jsonb_build_object('purchase',v_purchase,'autoRenewRequested',v_checkout.auto_renew_requested,'registrarAutoRenew',false),
          normalized_error='{}'::jsonb,updated_at=now()
      where id=v_checkout.id;
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','fulfilled','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'purchase',v_purchase,'autoRenewRequested',v_checkout.auto_renew_requested,'registrarAutoRenew',false,'plainMessage','Payment received. The domain is registered and Pandora is connecting it to the project.');
  end if;

  v_code:=upper(coalesce(v_purchase->>'code','DOMAIN_FULFILLMENT_FAILED'));
  if v_code in ('DOMAIN_PURCHASE_RECONCILIATION_REQUIRED','DOMAIN_PURCHASE_IN_PROGRESS') then
    update public.pandora_domain_checkouts set status='needs_attention',normalized_error=jsonb_build_object('code',lower(v_code)),updated_at=now() where id=v_checkout.id;
    return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Payment succeeded. Pandora is confirming whether registration completed; do not pay or register again.');
  end if;

  -- Definite fulfillment failure after successful customer payment: refund to the original source.
  if v_checkout.gateway='xendit' then
    if nullif(v_checkout.provider_payment_request_id,'') is null then
      select provider_payment_request_id into v_payment_request_id from public.pandora_domain_checkouts where id=v_checkout.id;
    else v_payment_request_id:=v_checkout.provider_payment_request_id; end if;
    if nullif(v_payment_request_id,'') is null then
      update public.pandora_domain_checkouts set status='needs_attention',contact_ciphertext=null,normalized_error=jsonb_build_object('code','refund_reference_missing','fulfillmentCode',v_code),updated_at=now() where id=v_checkout.id;
      return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Registration did not complete and Pandora needs to reconcile the refund.');
    end if;
    v_refund:=private.pandora_xendit_api_20260830('POST','/refunds',jsonb_build_object(
      'reference_id','r'||replace(v_checkout.id::text,'-',''),
      'payment_request_id',v_payment_request_id,
      'currency',v_checkout.currency,
      'amount',v_checkout.retail_price,
      'reason','CANCELLATION',
      'metadata',jsonb_build_object('checkout_id',v_checkout.id::text,'fulfillment_code',v_code)
    ));
    v_refund_http:=coalesce((v_refund->>'status')::integer,0);
    v_refund_id:=nullif(v_refund#>>'{body,id}','');
    v_refund_status:=upper(coalesce(v_refund#>>'{body,status}',''));
    if v_refund_http=200 and v_refund_status='SUCCEEDED' then v_status:='refunded';
    elsif v_refund_http=200 and v_refund_status='PENDING' then v_status:='refund_pending';
    else v_status:='needs_attention'; end if;
  else
    if nullif(v_checkout.provider_capture_id,'') is null then select provider_capture_id into v_capture_id from public.pandora_domain_checkouts where id=v_checkout.id; else v_capture_id:=v_checkout.provider_capture_id; end if;
    if nullif(v_capture_id,'') is null then
      update public.pandora_domain_checkouts set status='needs_attention',contact_ciphertext=null,normalized_error=jsonb_build_object('code','refund_reference_missing','fulfillmentCode',v_code),updated_at=now() where id=v_checkout.id;
      return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status','needs_attention','amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'plainMessage','Registration did not complete and Pandora needs to reconcile the refund.');
    end if;
    v_amount_text:=to_char(v_checkout.retail_price,'FM999999990.00');
    v_refund:=private.pandora_paypal_api_20260830('POST','/v2/payments/captures/'||v_capture_id||'/refund',jsonb_build_object(
      'amount',jsonb_build_object('value',v_amount_text,'currency_code',v_checkout.currency),
      'note_to_payer','Domain registration could not be completed.'
    ),'refund-'||replace(v_checkout.id::text,'-',''));
    v_refund_http:=coalesce((v_refund->>'status')::integer,0);
    v_refund_id:=nullif(v_refund#>>'{body,id}','');
    v_refund_status:=upper(coalesce(v_refund#>>'{body,status}',''));
    if v_refund_http in (200,201) and v_refund_status='COMPLETED' then v_status:='refunded';
    elsif v_refund_http in (200,201) and v_refund_status='PENDING' then v_status:='refund_pending';
    else v_status:='needs_attention'; end if;
  end if;

  update public.pandora_domain_checkouts
  set status=v_status,provider_refund_id=v_refund_id,contact_ciphertext=null,
      refunded_at=case when v_status='refunded' then now() else refunded_at end,
      normalized_error=jsonb_build_object('code',case when v_status='needs_attention' then 'refund_failed' else 'fulfillment_refunded' end,'fulfillmentCode',v_code,'refundStatus',v_refund_status,'refundHttpStatus',v_refund_http),
      updated_at=now()
  where id=v_checkout.id;

  return jsonb_build_object('checkoutId',v_checkout.id,'domain',v_checkout.domain,'gateway',v_checkout.gateway,'status',v_status,'amount',v_checkout.retail_price,'currency',v_checkout.currency,'projectId',v_checkout.project_id,'refundId',v_refund_id,'plainMessage',case when v_status='refunded' then 'Registration could not be completed, so the payment was refunded.' when v_status='refund_pending' then 'Registration could not be completed. The refund is being processed.' else 'Registration could not be completed and Pandora needs to reconcile the refund.' end);
end; $function$;

revoke all on function public.pandora_reconcile_domain_checkout(uuid,uuid) from public,anon;
grant execute on function public.pandora_reconcile_domain_checkout(uuid,uuid) to authenticated;

-- Customers cannot bypass settlement and make the platform fund a registrar charge.
revoke execute on function public.pandora_purchase_domain(uuid,text,uuid,numeric,boolean,jsonb,text,boolean) from authenticated;
