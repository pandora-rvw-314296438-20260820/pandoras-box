
do $migration$
declare
  v_definition text;
  v_old text := $old$
    v_status := case
      when v_auth_verified and coalesce((v_registry.config#>>'{auth,customSmtpConfigured}')::boolean,false) then 'healthy'
      when v_auth_verified then 'degraded'
      else 'unknown'
    end;
$old$;
  v_new text := $new$
    v_status := case
      when v_auth_verified and coalesce((v_registry.config#>>'{auth,customSmtpConfigured}')::boolean,false) then 'healthy'
      when v_auth_verified
       and coalesce((v_registry.config#>>'{auth,publicSignupDisabled}')::boolean,false)
       and not coalesce((v_registry.config#>>'{auth,customSmtpConfigured}')::boolean,false)
      then 'not_configured'
      when v_auth_verified then 'degraded'
      else 'unknown'
    end;
$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private'
    and p.proname='projectos_refresh_integration_health'
  limit 1;

  if v_definition is null or position(v_old in v_definition)=0 then
    raise exception 'expected projectos_refresh_integration_health auth status block not found';
  end if;

  execute replace(v_definition,v_old,v_new);
end
$migration$;
