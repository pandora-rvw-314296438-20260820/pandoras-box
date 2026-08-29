-- Generated-source identity convergence for Worker D / E / F.
-- Generated ProjectVersions use their immutable ProjectVersion UUID as source_ref and SHA-256 as content identity.

alter table public.pandora_project_versions
  add column if not exists source_kind text null,
  add column if not exists source_ref text null;

update public.pandora_project_versions
set source_kind = case when source_commit is null then 'artifact_snapshot' else 'git_commit' end,
    source_ref = case when source_commit is null then id::text else lower(source_commit) end
where source_kind is null or source_ref is null;

create or replace function private.pandora_default_project_version_source_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source_kind is null then
    new.source_kind := case when new.source_commit is null then 'artifact_snapshot' else 'git_commit' end;
  end if;
  if nullif(trim(new.source_ref), '') is null then
    new.source_ref := case when new.source_kind = 'git_commit' then lower(new.source_commit) else new.id::text end;
  end if;
  if new.source_commit is not null then new.source_commit := lower(new.source_commit); end if;
  return new;
end;
$$;

drop trigger if exists pandora_project_versions_source_identity_defaults on public.pandora_project_versions;
create trigger pandora_project_versions_source_identity_defaults
before insert or update of source_kind, source_ref, source_commit
on public.pandora_project_versions
for each row execute function private.pandora_default_project_version_source_identity();

alter table public.pandora_project_versions alter column source_kind set not null;
alter table public.pandora_project_versions alter column source_ref set not null;
alter table public.pandora_project_versions drop constraint if exists pandora_project_versions_source_identity_v1_check;
alter table public.pandora_project_versions add constraint pandora_project_versions_source_identity_v1_check check (
  (source_kind = 'git_commit' and source_commit ~ '^[0-9a-f]{40}$' and source_ref = source_commit)
  or
  (source_kind = 'artifact_snapshot' and source_commit is null and source_ref = id::text)
);

alter table public.pandora_verification_runs
  add column if not exists source_kind text null,
  add column if not exists source_ref text null;

update public.pandora_verification_runs
set source_kind = case when source_commit is null then 'artifact_snapshot' else 'git_commit' end,
    source_ref = case when source_commit is null then project_version_id::text else lower(source_commit) end
where source_kind is null or source_ref is null;

create or replace function private.pandora_default_verification_source_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.source_kind is null then
    new.source_kind := case when new.source_commit is null then 'artifact_snapshot' else 'git_commit' end;
  end if;
  if nullif(trim(new.source_ref), '') is null then
    new.source_ref := case when new.source_kind = 'git_commit' then lower(new.source_commit) else new.project_version_id::text end;
  end if;
  if new.source_commit is not null then new.source_commit := lower(new.source_commit); end if;
  return new;
end;
$$;

drop trigger if exists pandora_verification_runs_source_identity_defaults on public.pandora_verification_runs;
create trigger pandora_verification_runs_source_identity_defaults
before insert or update of source_kind, source_ref, source_commit, project_version_id
on public.pandora_verification_runs
for each row execute function private.pandora_default_verification_source_identity();

alter table public.pandora_verification_runs alter column source_commit drop not null;
alter table public.pandora_verification_runs alter column source_kind set not null;
alter table public.pandora_verification_runs alter column source_ref set not null;
alter table public.pandora_verification_runs drop constraint if exists pandora_verification_runs_source_commit_check;
alter table public.pandora_verification_runs drop constraint if exists pandora_verification_runs_source_identity_v1_check;
alter table public.pandora_verification_runs add constraint pandora_verification_runs_source_identity_v1_check check (
  (source_kind = 'git_commit' and source_commit ~ '^[0-9a-f]{40}$' and source_ref = source_commit)
  or
  (source_kind = 'artifact_snapshot' and source_commit is null and source_ref = project_version_id::text)
);

create or replace function private.pandora_validate_verification_source_lineage_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_project uuid;
  v_spec uuid;
  v_source_kind text;
  v_source_ref text;
  v_source_commit text;
  v_source_digest text;
  v_artifact_digest text;
begin
  select organization_id, project_id, project_spec_id, source_kind, source_ref, source_commit, source_sha256, artifact_digest_sha256
    into v_org, v_project, v_spec, v_source_kind, v_source_ref, v_source_commit, v_source_digest, v_artifact_digest
  from public.pandora_project_versions
  where id = new.project_version_id;
  if v_project is null or v_org <> new.organization_id or v_project <> new.project_id then
    raise exception 'verification ProjectVersion lineage mismatch' using errcode='23514';
  end if;
  if v_spec is not null and v_spec <> new.project_spec_id then
    raise exception 'verification ProjectSpec lineage mismatch' using errcode='23514';
  end if;
  if v_source_kind <> new.source_kind or v_source_ref <> new.source_ref or v_source_commit is distinct from new.source_commit then
    raise exception 'verification source identity mismatch' using errcode='23514';
  end if;
  if v_source_digest <> new.source_digest then
    raise exception 'verification source digest mismatch' using errcode='23514';
  end if;
  if v_artifact_digest is not null and v_artifact_digest <> new.artifact_digest then
    raise exception 'verification artifact digest mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_verification_runs_source_lineage_v1 on public.pandora_verification_runs;
create trigger pandora_verification_runs_source_lineage_v1
before insert or update of project_version_id, project_spec_id, source_kind, source_ref, source_commit, source_digest, artifact_digest
on public.pandora_verification_runs
for each row execute function private.pandora_validate_verification_source_lineage_v1();

create or replace function private.pandora_validate_project_version_verification_source_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_ref text;
  v_commit text;
begin
  if new.verification_run_id is not null then
    select source_kind, source_ref, source_commit into v_kind, v_ref, v_commit
    from public.pandora_verification_runs where id = new.verification_run_id;
    if v_kind is null or v_kind <> new.source_kind or v_ref <> new.source_ref or v_commit is distinct from new.source_commit then
      raise exception 'project version verification source identity mismatch' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pandora_project_versions_verification_source_v1 on public.pandora_project_versions;
create trigger pandora_project_versions_verification_source_v1
before insert or update of verification_run_id, source_kind, source_ref, source_commit
on public.pandora_project_versions
for each row execute function private.pandora_validate_project_version_verification_source_v1();
