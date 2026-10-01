do $$
declare v_id uuid; v_secret text := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
begin
  select id into v_id from vault.secrets where name='plp_preview_run_secret_20260917' limit 1;
  if v_id is null then
    perform vault.create_secret(v_secret,'plp_preview_run_secret_20260917','One-time auth for PLP exact-source preview deployer; remove after deployment');
  else
    perform vault.update_secret(v_id,v_secret,'plp_preview_run_secret_20260917','One-time auth for PLP exact-source preview deployer; remove after deployment');
  end if;
end $$;

create or replace function public.pandora_plp_preview_authorize_20260917(p_secret text)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','vault'
as $$
declare v_expected text;
begin
  select decrypted_secret into v_expected from vault.decrypted_secrets where name='plp_preview_run_secret_20260917' limit 1;
  return v_expected is not null and p_secret is not null and p_secret = v_expected;
end $$;

revoke all on function public.pandora_plp_preview_authorize_20260917(text) from public;
grant execute on function public.pandora_plp_preview_authorize_20260917(text) to service_role;
