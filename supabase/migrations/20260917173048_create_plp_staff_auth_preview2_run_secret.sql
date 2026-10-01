do $do$
begin
 if not exists(select 1 from vault.secrets where name='plp_staff_auth_preview2_run_20260918') then
  perform vault.create_secret(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),'plp_staff_auth_preview2_run_20260918','One-time authorization for corrected PLP staff-auth preview');
 end if;
end $do$;
