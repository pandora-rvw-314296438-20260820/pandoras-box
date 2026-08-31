-- Forward-only recovery authority constraint alignment.
-- Historical migrations remain immutable; active evidence constraints move to the
-- recovery GitHub repositories and transferred Vercel team.

alter table private.canonical_physical_android_receipts
  drop constraint if exists canonical_physical_android_receipts_check2,
  add constraint canonical_physical_android_receipts_check2 check (
    ci_artifact_url = 'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/' || ci_artifact_external_id
  ) not valid,
  drop constraint if exists canonical_physical_android_receipts_repository_check,
  add constraint canonical_physical_android_receipts_repository_check check (
    repository = 'pandora-rvw-314296438-20260820/pandoras-box'
  ) not valid;

alter table private.canonical_release_owner_authorizations
  drop constraint if exists canonical_release_owner_authorizations_repository_check,
  add constraint canonical_release_owner_authorizations_repository_check check (
    repository = 'pandora-rvw-314296438-20260820/pandoras-box'
  ) not valid;

alter table private.canonical_release_review_receipts
  drop constraint if exists canonical_release_review_receipts_repository_check,
  add constraint canonical_release_review_receipts_repository_check check (
    repository = 'pandora-rvw-314296438-20260820/pandoras-box'
  ) not valid;

alter table private.canonical_supabase_release_receipts
  drop constraint if exists canonical_supabase_release_receipts_check,
  add constraint canonical_supabase_release_receipts_check check (
    source_artifact_url = 'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/' || source_artifact_external_id
  ) not valid,
  drop constraint if exists canonical_supabase_release_receipts_repository_check,
  add constraint canonical_supabase_release_receipts_repository_check check (
    repository = 'pandora-rvw-314296438-20260820/pandoras-box'
  ) not valid;

alter table private.canonical_vercel_rehearsal_receipts
  drop constraint if exists canonical_vercel_rehearsal_receipts_alias_api_source_url_check,
  add constraint canonical_vercel_rehearsal_receipts_alias_api_source_url_check check (
    alias_api_source_url = 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3'
  ) not valid,
  drop constraint if exists canonical_vercel_rehearsal_receipts_check3,
  add constraint canonical_vercel_rehearsal_receipts_check3 check (
    vercel_api_source_url = 'https://api.vercel.com/v13/deployments/' || external_id || '?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3'
  ) not valid,
  drop constraint if exists canonical_vercel_rehearsal_receipts_repository_check,
  add constraint canonical_vercel_rehearsal_receipts_repository_check check (
    repository = 'pandora-rvw-314296438-20260820/pandoras-box'
  ) not valid,
  drop constraint if exists canonical_vercel_rehearsal_receipts_team_id_check,
  add constraint canonical_vercel_rehearsal_receipts_team_id_check check (
    team_id = 'team_3yw1CN59ce4pj5SwyQGCAqN3'
  ) not valid;

alter table private.physical_android_observer_identities
  drop constraint if exists physical_android_observer_identities_allowed_repositories_check,
  add constraint physical_android_observer_identities_allowed_repositories_check check (
    allowed_repositories = array['pandora-rvw-314296438-20260820/pandoras-box']::text[]
  ) not valid;

do $constraint_guard$
declare
  legacy_constraint_count integer;
begin
  select count(*)
    into legacy_constraint_count
  from pg_constraint constraint_row
  join pg_class relation_row on relation_row.oid = constraint_row.conrelid
  join pg_namespace namespace_row on namespace_row.oid = relation_row.relnamespace
  where namespace_row.nspname in ('public', 'private')
    and (
      pg_get_constraintdef(constraint_row.oid, true) like '%banataosystems/Pandoras-box%'
      or pg_get_constraintdef(constraint_row.oid, true) like '%banataosystems/pandoras-box-memory%'
      or pg_get_constraintdef(constraint_row.oid, true) like '%team_IcdJUnzLi5wUN1GD8ALHyjF7%'
      or pg_get_constraintdef(constraint_row.oid, true) like '%mbanatao-dc676069%'
    );

  if legacy_constraint_count <> 0 then
    raise exception 'legacy recovery authority remains in active constraints: %', legacy_constraint_count
      using errcode = '55000';
  end if;
end;
$constraint_guard$;
