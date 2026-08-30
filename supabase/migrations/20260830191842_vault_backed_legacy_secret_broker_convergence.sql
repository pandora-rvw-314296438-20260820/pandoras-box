do $$
declare
  r record;
  v_vault_live boolean := false;
begin
  -- Supabase Vault is provider-managed and is not available in the PGlite
  -- migration replay harness. Only perform the provider migration when the
  -- real Vault contract is present; otherwise keep the legacy fixture table
  -- intact so clean replay can continue without pretending Vault exists.
  select
    to_regprocedure('vault.create_secret(text,text)') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'vault'
        and table_name = 'decrypted_secrets'
        and column_name = 'name'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'vault'
        and table_name = 'decrypted_secrets'
        and column_name = 'updated_at'
    )
  into v_vault_live;

  if not v_vault_live then
    return;
  end if;

  for r in select secret_name, secret_value from private.integration_secrets loop
    execute 'select vault.create_secret($1,$2)' using r.secret_value, r.secret_name;
  end loop;

  execute 'alter table private.integration_secrets rename to integration_secrets_legacy_retired';
  execute 'delete from private.integration_secrets_legacy_retired';

  execute $view$
    create view private.integration_secrets as
    select
      name as secret_name,
      decrypted_secret as secret_value,
      created_at,
      updated_at
    from vault.decrypted_secrets
    where name in (
      'posthog_intelligence_hash_salt',
      'posthog_intelligence_webhook_secret',
      'projectos_fxpass_intake_hmac',
      'projectos_memory_learning_hmac'
    )
  $view$;

  execute 'revoke all on private.integration_secrets from public, anon, authenticated, service_role';
  execute 'revoke all on private.integration_secrets_legacy_retired from public, anon, authenticated, service_role';
end $$;
