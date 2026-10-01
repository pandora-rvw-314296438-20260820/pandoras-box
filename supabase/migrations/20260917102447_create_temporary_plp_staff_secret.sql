do $do$
begin
  if not exists (select 1 from vault.secrets where name='plp_temp_staff_code_20260917') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),
      'plp_temp_staff_code_20260917',
      'Temporary PLP staff authorization code while PLP runtime is hosted in pandoras-box Supabase'
    );
  end if;
end
$do$;
