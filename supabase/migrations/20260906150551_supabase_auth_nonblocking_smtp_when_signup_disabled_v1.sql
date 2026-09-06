-- Remote migration 20260906150551.
-- The live control-plane function can be ahead of older PGlite recovery
-- snapshots. Apply the exact transformation when its source block exists;
-- treat already-applied or older replay states as safe idempotent no-ops.
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

  if v_definition is null then
    raise notice 'projectos_refresh_integration_health is absent in this replay state; skipping history-only transformation';
    return;
  end if;

  if position(v_new in v_definition) > 0 then
    return;
  end if;

  if position(v_old in v_definition) = 0 then
    raise notice 'projectos_refresh_integration_health differs from the live post-recovery body; skipping history-only transformation';
    return;
  end if;

  execute replace(v_definition,v_old,v_new);
end
$migration$;
