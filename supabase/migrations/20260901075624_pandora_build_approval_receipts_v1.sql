-- Pandora Visible Creation — Proposal + Conversation
-- Chat B: exact customer Build-it authorization + derived conversation evidence spine.
-- Conversation remains a read projection; canonical lifecycle tables remain authoritative.

begin;

create table if not exists public.pandora_build_authorization_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  source_intent_id uuid not null references public.pandora_project_intents(id) on delete restrict,
  project_spec_id uuid not null references public.pandora_project_specs(id) on delete restrict,
  approved_spec_sha256 text not null,
  authorized_by uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null,
  build_job_id uuid references public.pandora_build_jobs(id) on delete restrict,
  authorized_at timestamptz not null default now(),
  admitted_at timestamptz,
  constraint pandora_build_authorization_receipts_sha_check
    check (approved_spec_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_build_authorization_receipts_idempotency_check
    check (length(trim(idempotency_key)) between 8 and 200),
  constraint pandora_build_authorization_receipts_admission_shape_check
    check ((build_job_id is null and admitted_at is null) or (build_job_id is not null and admitted_at is not null)),
  constraint pandora_build_authorization_receipts_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  unique (organization_id, project_id, idempotency_key),
  unique (build_job_id)
);

comment on table public.pandora_build_authorization_receipts is
  'Immutable customer Build-it approval receipt bound to exact source intent and ProjectSpec hash. It is not publish authorization.';

create index if not exists pandora_build_authorization_receipts_project_time_idx
  on public.pandora_build_authorization_receipts
  (organization_id, project_id, authorized_at desc, id desc);

create or replace function private.pandora_validate_build_authorization_receipt_v1()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $fn$
declare
  v_spec public.pandora_project_specs%rowtype;
  v_intent public.pandora_project_intents%rowtype;
  v_job public.pandora_build_jobs%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.project_id is distinct from old.project_id
       or new.source_intent_id is distinct from old.source_intent_id
       or new.project_spec_id is distinct from old.project_spec_id
       or new.approved_spec_sha256 is distinct from old.approved_spec_sha256
       or new.authorized_by is distinct from old.authorized_by
       or new.idempotency_key is distinct from old.idempotency_key
       or new.authorized_at is distinct from old.authorized_at then
      raise exception 'BUILD_AUTHORIZATION_IMMUTABLE' using errcode = '23514';
    end if;
    if old.build_job_id is not null
       and new.build_job_id is distinct from old.build_job_id then
      raise exception 'BUILD_AUTHORIZATION_ADMISSION_IMMUTABLE' using errcode = '23514';
    end if;
    if old.admitted_at is not null
       and new.admitted_at is distinct from old.admitted_at then
      raise exception 'BUILD_AUTHORIZATION_ADMISSION_IMMUTABLE' using errcode = '23514';
    end if;
  end if;

  select * into v_spec
  from public.pandora_project_specs s
  where s.id = new.project_spec_id
    and s.organization_id = new.organization_id
    and s.project_id = new.project_id
    and s.source_intent_id = new.source_intent_id;

  if not found or v_spec.content_sha256 <> new.approved_spec_sha256 then
    raise exception 'BUILD_AUTHORIZATION_SPEC_LINEAGE_INVALID' using errcode = '23514';
  end if;

  select * into v_intent
  from public.pandora_project_intents i
  where i.id = new.source_intent_id
    and i.organization_id = new.organization_id
    and i.project_id = new.project_id;

  if not found then
    raise exception 'BUILD_AUTHORIZATION_INTENT_LINEAGE_INVALID' using errcode = '23514';
  end if;

  if new.build_job_id is not null then
    select * into v_job
    from public.pandora_build_jobs j
    where j.id = new.build_job_id
      and j.organization_id = new.organization_id
      and j.project_id = new.project_id
      and j.project_spec_id = new.project_spec_id
      and j.job_kind = 'build';

    if not found
       or v_job.source_intent_id is distinct from new.source_intent_id
       or v_job.requested_by is distinct from new.authorized_by then
      raise exception 'BUILD_AUTHORIZATION_JOB_LINEAGE_INVALID' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$fn$;

drop trigger if exists pandora_validate_build_authorization_receipt
  on public.pandora_build_authorization_receipts;
create trigger pandora_validate_build_authorization_receipt
before insert or update on public.pandora_build_authorization_receipts
for each row
execute function private.pandora_validate_build_authorization_receipt_v1();

alter table public.pandora_build_authorization_receipts enable row level security;
revoke all on table public.pandora_build_authorization_receipts from public, anon, authenticated;
grant select, insert, update on table public.pandora_build_authorization_receipts to service_role;

create or replace function public.pandora_authorize_project_build_v1(
  p_project_id uuid,
  p_project_spec_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $fn$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_spec public.pandora_project_specs%rowtype;
  v_receipt public.pandora_build_authorization_receipts%rowtype;
  v_key text := trim(coalesce(p_idempotency_key, ''));
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode = '42501';
  end if;
  if p_project_id is null or p_project_spec_id is null
     or length(v_key) not between 8 and 200 then
    raise exception 'INVALID_BUILD_AUTHORIZATION_REQUEST' using errcode = '22023';
  end if;

  select p.organization_id into v_organization_id
  from public.projectos_projects p
  where p.id = p_project_id;

  if v_organization_id is null then
    raise exception 'PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = v_organization_id
      and m.user_id = v_user_id
      and m.status::text = 'active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  select * into v_spec
  from public.pandora_project_specs s
  where s.id = p_project_spec_id
    and s.organization_id = v_organization_id
    and s.project_id = p_project_id
    and s.status = 'active';

  if not found then
    raise exception 'ACTIVE_PROJECT_SPEC_REQUIRED' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.pandora_project_intents i
    where i.id = v_spec.source_intent_id
      and i.organization_id = v_organization_id
      and i.project_id = p_project_id
  ) then
    raise exception 'PROJECT_SPEC_INTENT_LINEAGE_INVALID' using errcode = '23514';
  end if;

  insert into public.pandora_build_authorization_receipts (
    organization_id,
    project_id,
    source_intent_id,
    project_spec_id,
    approved_spec_sha256,
    authorized_by,
    idempotency_key
  ) values (
    v_organization_id,
    p_project_id,
    v_spec.source_intent_id,
    v_spec.id,
    v_spec.content_sha256,
    v_user_id,
    v_key
  )
  on conflict (organization_id, project_id, idempotency_key) do nothing
  returning * into v_receipt;

  if v_receipt.id is null then
    select * into v_receipt
    from public.pandora_build_authorization_receipts r
    where r.organization_id = v_organization_id
      and r.project_id = p_project_id
      and r.idempotency_key = v_key;

    if not found
       or v_receipt.project_spec_id <> v_spec.id
       or v_receipt.source_intent_id <> v_spec.source_intent_id
       or v_receipt.approved_spec_sha256 <> v_spec.content_sha256
       or v_receipt.authorized_by <> v_user_id then
      raise exception 'BUILD_AUTHORIZATION_COLLISION' using errcode = '23505';
    end if;
  end if;

  return jsonb_build_object(
    'authorizationId', v_receipt.id,
    'projectId', v_receipt.project_id,
    'sourceIntentId', v_receipt.source_intent_id,
    'projectSpecId', v_receipt.project_spec_id,
    'approvedSpecSha256', v_receipt.approved_spec_sha256,
    'authorizedBy', v_receipt.authorized_by,
    'authorizedAt', v_receipt.authorized_at,
    'buildJobId', v_receipt.build_job_id,
    'admittedAt', v_receipt.admitted_at,
    'publishAuthorized', false
  );
end;
$fn$;

revoke all on function public.pandora_authorize_project_build_v1(uuid, uuid, text)
  from public, anon;
grant execute on function public.pandora_authorize_project_build_v1(uuid, uuid, text)
  to authenticated;

create or replace function private.pandora_bind_build_authorization_v1(
  p_authorization_id uuid,
  p_build_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public'
as $fn$
declare
  v_receipt public.pandora_build_authorization_receipts%rowtype;
  v_job public.pandora_build_jobs%rowtype;
begin
  if p_authorization_id is null or p_build_job_id is null then
    raise exception 'INVALID_BUILD_ADMISSION_BINDING' using errcode = '22023';
  end if;

  select * into v_receipt
  from public.pandora_build_authorization_receipts
  where id = p_authorization_id
  for update;

  if not found then
    raise exception 'BUILD_AUTHORIZATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_job
  from public.pandora_build_jobs
  where id = p_build_job_id
  for share;

  if not found
     or v_job.organization_id <> v_receipt.organization_id
     or v_job.project_id <> v_receipt.project_id
     or v_job.project_spec_id <> v_receipt.project_spec_id
     or v_job.source_intent_id is distinct from v_receipt.source_intent_id
     or v_job.requested_by is distinct from v_receipt.authorized_by
     or v_job.job_kind <> 'build' then
    raise exception 'BUILD_AUTHORIZATION_JOB_LINEAGE_INVALID' using errcode = '23514';
  end if;

  if v_receipt.build_job_id is not null then
    if v_receipt.build_job_id <> p_build_job_id then
      raise exception 'BUILD_AUTHORIZATION_ALREADY_BOUND' using errcode = '23505';
    end if;
  else
    update public.pandora_build_authorization_receipts
    set build_job_id = p_build_job_id,
        admitted_at = now()
    where id = p_authorization_id
    returning * into v_receipt;
  end if;

  return jsonb_build_object(
    'authorizationId', v_receipt.id,
    'buildJobId', v_receipt.build_job_id,
    'projectId', v_receipt.project_id,
    'projectSpecId', v_receipt.project_spec_id,
    'sourceIntentId', v_receipt.source_intent_id,
    'approvedSpecSha256', v_receipt.approved_spec_sha256,
    'authorizedBy', v_receipt.authorized_by,
    'authorizedAt', v_receipt.authorized_at,
    'admittedAt', v_receipt.admitted_at
  );
end;
$fn$;

revoke all on function private.pandora_bind_build_authorization_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.pandora_bind_build_authorization_v1(uuid, uuid)
  to service_role;

create or replace function public.pandora_bind_build_authorization_service_v1(
  p_authorization_id uuid,
  p_build_job_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $fn$
  select private.pandora_bind_build_authorization_v1(p_authorization_id, p_build_job_id)
$fn$;

revoke all on function public.pandora_bind_build_authorization_service_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pandora_bind_build_authorization_service_v1(uuid, uuid)
  to service_role;

commit;
