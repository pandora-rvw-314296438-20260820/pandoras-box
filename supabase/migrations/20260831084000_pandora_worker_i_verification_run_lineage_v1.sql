-- Pandora Worker I / D: bind each TRUSTED materialized primitive to the exact Worker E PASS run.
begin;

alter table public.pandora_project_version_primitives
  add column if not exists primitive_verification_run_id uuid;

update public.pandora_project_version_primitives p
set primitive_verification_run_id = r.id
from public.pandora_primitive_catalog_entries c
join public.pandora_primitive_verification_runs r
  on r.id = case
    when c.worker_e_evidence_ref ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then c.worker_e_evidence_ref::uuid
    else null
  end
where p.trust_state = 'TRUSTED'
  and p.primitive_verification_run_id is null
  and c.primitive_name = p.primitive_name
  and c.primitive_version = p.primitive_version
  and r.status = 'PASS'
  and r.verifier_identity = 'worker-e-primitive-static-v1'
  and r.primitive_name = p.primitive_name
  and r.primitive_version = p.primitive_version
  and r.source_commit = c.source_commit
  and r.source_manifest_path = c.source_manifest_path
  and r.source_digest = p.source_digest
  and r.source_digest = c.source_digest
  and r.evidence_sha256 is not null;

do $guard$
begin
  if exists (
    select 1
    from public.pandora_project_version_primitives
    where trust_state = 'TRUSTED'
      and primitive_verification_run_id is null
  ) then
    raise exception 'existing TRUSTED project-version primitive lacks exact Worker E verification-run lineage' using errcode='23514';
  end if;
end;
$guard$;

do $constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'pandora_project_version_primitives_verification_run_fkey'
      and conrelid = 'public.pandora_project_version_primitives'::regclass
  ) then
    alter table public.pandora_project_version_primitives
      add constraint pandora_project_version_primitives_verification_run_fkey
      foreign key (primitive_verification_run_id)
      references public.pandora_primitive_verification_runs(id)
      on delete restrict;
  end if;
end;
$constraint$;

do $constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'pandora_project_version_primitives_trusted_run_check'
      and conrelid = 'public.pandora_project_version_primitives'::regclass
  ) then
    alter table public.pandora_project_version_primitives
      add constraint pandora_project_version_primitives_trusted_run_check
      check (trust_state <> 'TRUSTED' or primitive_verification_run_id is not null);
  end if;
end;
$constraint$;

create index if not exists pandora_project_version_primitives_verification_run_idx
  on public.pandora_project_version_primitives (primitive_verification_run_id)
  where primitive_verification_run_id is not null;

create or replace function private.pandora_validate_primitive_verification_run_lineage_20260831()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_run public.pandora_primitive_verification_runs%rowtype;
begin
  if new.trust_state = 'TRUSTED' and new.primitive_verification_run_id is null then
    raise exception 'TRUSTED project-version primitive requires exact Worker E verification-run lineage' using errcode='23514';
  end if;

  if new.primitive_verification_run_id is not null then
    select * into v_run
    from public.pandora_primitive_verification_runs
    where id = new.primitive_verification_run_id;

    if not found
       or v_run.status <> 'PASS'
       or v_run.verifier_identity <> 'worker-e-primitive-static-v1'
       or v_run.primitive_name <> new.primitive_name
       or v_run.primitive_version <> new.primitive_version
       or v_run.source_digest <> new.source_digest
       or v_run.evidence_sha256 is null then
      raise exception 'project-version primitive Worker E verification-run lineage mismatch' using errcode='23514';
    end if;
  end if;
  return new;
end;
$fn$;

revoke all on function private.pandora_validate_primitive_verification_run_lineage_20260831() from public, anon, authenticated;

drop trigger if exists pandora_project_version_primitives_verification_run_guard
  on public.pandora_project_version_primitives;
create trigger pandora_project_version_primitives_verification_run_guard
before insert or update on public.pandora_project_version_primitives
for each row execute function private.pandora_validate_primitive_verification_run_lineage_20260831();

commit;
