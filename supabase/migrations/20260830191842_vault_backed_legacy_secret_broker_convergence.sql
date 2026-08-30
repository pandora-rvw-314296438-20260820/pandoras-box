do $$
declare
  r record;
begin
  for r in select secret_name, secret_value from private.integration_secrets loop
    perform vault.create_secret(r.secret_value, r.secret_name);
  end loop;
end $$;

alter table private.integration_secrets rename to integration_secrets_legacy_retired;
delete from private.integration_secrets_legacy_retired;

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
);

revoke all on private.integration_secrets from public, anon, authenticated, service_role;
revoke all on private.integration_secrets_legacy_retired from public, anon, authenticated, service_role;
