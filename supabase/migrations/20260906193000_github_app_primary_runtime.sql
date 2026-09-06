-- Pandora GitHub App-primary runtime material. The credential value remains in Supabase Vault.

CREATE OR REPLACE FUNCTION public.pandora_get_github_app_runtime_material()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_private_key text;
begin
  select decrypted_secret into strict v_private_key
  from vault.decrypted_secrets
  where name='Github_app_private_key'
  limit 1;

  if v_private_key not like '-----BEGIN RSA PRIVATE KEY%END RSA PRIVATE KEY-----%'
     and v_private_key not like '-----BEGIN PRIVATE KEY%END PRIVATE KEY-----%' then
    raise exception 'GitHub App private key is not a PEM private key' using errcode='22023';
  end if;

  return jsonb_build_object(
    'appId', 4785021,
    'installationId', 158056492,
    'privateKeyPem', v_private_key
  );
end;
$function$


revoke all on function public.pandora_get_github_app_runtime_material() from public, anon, authenticated;
grant execute on function public.pandora_get_github_app_runtime_material() to service_role;
