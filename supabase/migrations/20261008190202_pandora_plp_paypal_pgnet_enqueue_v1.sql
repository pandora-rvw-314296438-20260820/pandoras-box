create or replace function private.pandora_paypal_pgnet_enqueue_v1() returns bigint language plpgsql security definer set search_path = pg_catalog, vault, net as $$
declare v_client text; v_secret text; v_id bigint;
begin
  select decrypted_secret into v_client from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  if nullif(btrim(v_client), '') is null or nullif(btrim(v_secret), '') is null then raise exception 'PAYPAL_SANDBOX_NOT_CONFIGURED' using errcode = '55000'; end if;
  select net.http_post(
    url := 'https://api-m.sandbox.paypal.com/v1/oauth2/token',
    body := '{}'::jsonb,
    params := jsonb_build_object('grant_type', 'client_credentials'),
    headers := jsonb_build_object('Authorization', 'Basic ' || encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64'), 'Accept', 'application/json', 'Content-Type', 'application/x-www-form-urlencoded'),
    timeout_milliseconds := 15000
  ) into v_id;
  return v_id;
end; $$;
revoke all on function private.pandora_paypal_pgnet_enqueue_v1() from public, anon, authenticated;
grant execute on function private.pandora_paypal_pgnet_enqueue_v1() to service_role;