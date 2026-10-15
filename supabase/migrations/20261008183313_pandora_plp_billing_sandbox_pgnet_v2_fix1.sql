create or replace function private.pandora_paypal_sandbox_http_v2(
  p_method text,
  p_path text,
  p_body jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, extensions, public, private, vault, net
as $$
declare
  v_client text;
  v_secret text;
  v_token text;
  v_request_id bigint;
  v_status integer;
  v_body text;
  v_error text;
  v_response jsonb;
  v_headers jsonb;
  v_bytes bytea;
  v_attempt integer;
begin
  if upper(coalesce(p_method, '')) not in ('GET','POST') then
    raise exception 'PAYPAL_METHOD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' then
    raise exception 'PAYPAL_PATH_INVALID' using errcode = '22023';
  end if;
  if not (
    (upper(p_method)='POST' and p_path in ('/v1/oauth2/token','/v1/catalogs/products','/v1/billing/plans','/v1/billing/subscriptions')) or
    (upper(p_method)='GET' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+$') or
    (upper(p_method)='POST' and p_path ~ '^/v1/billing/subscriptions/I-[A-Z0-9]+/(revise|activate|cancel)$')
  ) then
    raise exception 'PAYPAL_PATH_NOT_ALLOWED' using errcode = '22023';
  end if;

  select
    max(decrypted_secret) filter (where name='paypal_client_id_sandbox'),
    max(decrypted_secret) filter (where name='paypal_client_secret_sandbox')
  into v_client, v_secret
  from vault.decrypted_secrets
  where name in ('paypal_client_id_sandbox','paypal_client_secret_sandbox');

  if nullif(btrim(v_client),'') is null or nullif(btrim(v_secret),'') is null then
    raise exception 'PAYPAL_SANDBOX_NOT_CONFIGURED' using errcode = '55000';
  end if;

  if p_path = '/v1/oauth2/token' then
    v_headers := jsonb_build_object(
      'Authorization','Basic ' || encode(convert_to(btrim(v_client)||':'||btrim(v_secret),'UTF8'),'base64'),
      'Content-Type','application/x-www-form-urlencoded',
      'Accept','application/json'
    );
    v_bytes := convert_to('grant_type=client_credentials','UTF8');
  else
    select private.pandora_paypal_sandbox_http_v2('POST','/v1/oauth2/token',null)->>'access_token'
      into v_token;
    v_headers := jsonb_build_object(
      'Authorization','Bearer ' || v_token,
      'Content-Type','application/json',
      'Accept','application/json',
      'Prefer','return=representation'
    );
    v_bytes := case when p_body is null then null else convert_to(p_body::text,'UTF8') end;
  end if;

  insert into net.http_request_queue(method,url,headers,body,timeout_milliseconds)
  values (
    upper(p_method),
    'https://api-m.sandbox.paypal.com' || p_path,
    v_headers,
    v_bytes,
    15000
  )
  returning id into v_request_id;

  perform net.wake();

  for v_attempt in 1..60 loop
    select status_code, content, error_msg
      into v_status, v_body, v_error
    from net._http_response
    where id=v_request_id;

    if found then
      begin
        v_response := case when nullif(v_body,'') is null then '{}'::jsonb else v_body::jsonb end;
      exception when others then
        v_response := jsonb_build_object('raw', left(coalesce(v_body,''),500));
      end;
      if coalesce(v_status,0)=200 and p_path='/v1/oauth2/token' then
        return v_response;
      end if;
      return jsonb_build_object(
        'status',coalesce(v_status,0),
        'body',v_response,
        'error',nullif(left(coalesce(v_error,''),240),'')
      );
    end if;
    perform pg_sleep(0.25);
  end loop;

  raise exception 'PAYPAL_SANDBOX_TIMEOUT' using errcode='57014';
end;
$$;