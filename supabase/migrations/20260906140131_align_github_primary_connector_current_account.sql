-- Align the owner-facing GitHub connector with the current canonical GitHub App account.
-- Credentials remain Vault-backed; this migration changes metadata only.

do $$
declare
  v_rows integer;
begin
  update public.connector_installations
  set display_name = 'GitHub Account — pandora-rvw-314296438-20260820',
      configuration = coalesce(configuration, '{}'::jsonb) || jsonb_build_object(
        'login', 'pandora-rvw-314296438-20260820',
        'installation_account', 'pandora-rvw-314296438-20260820',
        'canonical_repository', 'pandora-rvw-314296438-20260820/pandoras-box'
      ),
      updated_at = timezone('utc'::text, now())
  where provider = 'github'
    and configuration ->> 'account_id' = 'github-primary';

  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'expected exactly one github-primary connector, updated %', v_rows;
  end if;
end
$$;
