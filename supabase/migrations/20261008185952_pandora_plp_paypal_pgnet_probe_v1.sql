create or replace function private.pandora_paypal_pgnet_probe_v1() returns jsonb language plpgsql security definer set search_path = pg_catalog, vault, net as $$
declare v_client text; v_secret text; v_id bigint; v_result record; v_body jsonb; v_keys text;
begin
  select decrypted_secret into v_client from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  if nullif(btrim(v_client), '') is null or nullif(btrim(v_secret), '') is null then return jsonb_build_object('ok', false, 'reason', 'PAYPAL_SANDBOX_NOT_CONFIGURED'); end if;
  select net.http_post(
    url := 'https://api-m.sandbox.paypal.com/v1/oauth2/token',
    body := jsonb_build_object('grant_type', 'client_credentials'),
    params := '{}'::jsonb,
    headers := jsonb_build_object('Authorization', 'Basic ' || encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64'), 'Accept', 'application/json', 'Content-Type', 'application/json'),
    timeout_milliseconds := 15000
  ) into v_id;
  select * into v_result from net.http_collect_response(v_id, false);
  begin v_body := v_result.response_body::jsonb; exception when others then v_body := '{}'::jsonb; end;
  select string_agg(key, ',') into v_keys from jsonb_object_keys(coalesce(v_body, '{}'::jsonb)) key;
  return jsonb_build_object('ok', coalesce(v_result.status_code, 0) = 200 and v_body ? 'access_token', 'status', v_result.status_code, 'keys', v_keys);
end; $$;
revoke all on function private.pandora_paypal_pgnet_probe_v1() from public, anon, authenticated;
grant execute on function private.pandora_paypal_pgnet_probe_v1() to service_role;