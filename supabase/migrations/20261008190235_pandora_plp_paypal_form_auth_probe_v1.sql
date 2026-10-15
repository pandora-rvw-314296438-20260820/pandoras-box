create or replace function private.pandora_paypal_form_auth_probe_v1() returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions, vault as $$
declare v_client text; v_secret text; v_response extensions.http_response; v_body jsonb;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '20000');
  select decrypted_secret into v_client from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  select * into v_response from extensions.http(('POST'::extensions.http_method, 'https://api-m.sandbox.paypal.com/v1/oauth2/token', array[extensions.http_header('authorization', 'Basic ' || encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64')), extensions.http_header('content-type', 'application/x-www-form-urlencoded'), extensions.http_header('accept', 'application/json')]::extensions.http_header[], 'application/x-www-form-urlencoded', 'grant_type=client_credentials')::extensions.http_request);
  begin v_body := nullif(v_response.content, '')::jsonb; exception when others then v_body := '{}'::jsonb; end;
  return jsonb_build_object('status', v_response.status, 'ok', v_response.status = 200 and v_body ? 'access_token', 'error', v_body->>'error');
end; $$;
revoke all on function private.pandora_paypal_form_auth_probe_v1() from public, anon, authenticated;
grant execute on function private.pandora_paypal_form_auth_probe_v1() to service_role;