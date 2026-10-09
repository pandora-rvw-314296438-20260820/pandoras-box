create or replace function private.pandora_paypal_form_auth_probe_v1() returns jsonb language plpgsql security definer set search_path = pg_catalog, extensions, vault as $$
declare v_client text; v_secret text; v_response extensions.http_response; v_body jsonb; v_basic text;
begin
  select regexp_replace(decrypted_secret, '\s', '', 'g') into v_client from vault.decrypted_secrets where name = 'paypal_client_id_sandbox' limit 1;
  select regexp_replace(decrypted_secret, '\s', '', 'g') into v_secret from vault.decrypted_secrets where name = 'paypal_client_secret_sandbox' limit 1;
  v_basic := encode(convert_to(v_client || ':' || v_secret, 'UTF8'), 'base64');
  v_basic := replace(v_basic, E'\n', '');
  select * into v_response from extensions.http(('POST'::extensions.http_method, 'https://api-m.sandbox.paypal.com/v1/oauth2/token', array[extensions.http_header('authorization', 'Basic ' || v_basic), extensions.http_header('content-type', 'application/x-www-form-urlencoded'), extensions.http_header('accept', 'application/json')]::extensions.http_header[], 'application/x-www-form-urlencoded', 'grant_type=client_credentials')::extensions.http_request);
  begin v_body := nullif(v_response.content, '')::jsonb; exception when others then v_body := '{}'::jsonb; end;
  return jsonb_build_object('status', v_response.status, 'ok', v_response.status = 200 and v_body ? 'access_token', 'error', v_body->>'error', 'client_len', length(v_client), 'secret_len', length(v_secret));
end; $$;