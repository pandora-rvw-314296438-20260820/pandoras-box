-- Pandora Tax Operating Core V1
-- Phases 2-6 backend: canonical ledger, reconciliation, rule governance,
-- deterministic calculation, filing package, professional review, command center.
--
-- Safety:
-- * AI/provider output never self-verifies tax evidence or ledger treatment.
-- * calculations require an approved immutable rule pack.
-- * the Philippines pack seeded here is IN_REVIEW, not approved.
-- * filing submission, signature/OTP and tax payment remain disabled.
-- * material customer data stays tenant-scoped and outside canonical Memory.

alter table public.tax_ledger_entries
  add column if not exists entry_key text,
  add column if not exists entry_kind text,
  add column if not exists entry_fingerprint_sha256 text,
  add column if not exists evidence_state text not null default 'unverified',
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='tax_ledger_entries_entry_kind_check'
  ) then
    alter table public.tax_ledger_entries
      add constraint tax_ledger_entries_entry_kind_check
      check (
        entry_kind is null or entry_kind in (
          'sale','purchase','payment','receipt','refund','adjustment',
          'payroll','withholding','credit','debit','other'
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='tax_ledger_entries_fingerprint_check'
  ) then
    alter table public.tax_ledger_entries
      add constraint tax_ledger_entries_fingerprint_check
      check (
        entry_fingerprint_sha256 is null
        or entry_fingerprint_sha256 ~ '^[0-9a-f]{64}$'
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='tax_ledger_entries_evidence_state_check'
  ) then
    alter table public.tax_ledger_entries
      add constraint tax_ledger_entries_evidence_state_check
      check (evidence_state in ('unverified','verified','waived'));
  end if;
end $$;

create unique index if not exists tax_ledger_entries_org_entry_key_uidx
  on public.tax_ledger_entries(organization_id,entry_key)
  where entry_key is not null;
create index if not exists tax_ledger_entries_fingerprint_idx
  on public.tax_ledger_entries(organization_id,tax_period_id,entry_fingerprint_sha256)
  where entry_fingerprint_sha256 is not null;

create table if not exists public.tax_counterparties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  counterparty_key text not null,
  display_name text,
  country_code text,
  tax_identifier_hash text,
  classification text,
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,counterparty_key),
  unique (id,organization_id),
  check (tax_identifier_hash is null or tax_identifier_hash ~ '^[0-9a-f]{64}$'),
  check (jsonb_typeof(metadata_redacted)='object')
);

create table if not exists public.tax_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  account_key text not null,
  display_name text not null,
  account_type text not null
    check (account_type in ('asset','liability','equity','revenue','expense','tax','cash','other')),
  currency_code text,
  active boolean not null default true,
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,account_key),
  unique (id,organization_id),
  check (jsonb_typeof(metadata_redacted)='object')
);

alter table public.tax_ledger_entries
  add column if not exists counterparty_id uuid,
  add column if not exists account_id uuid;

alter table public.tax_reviews
  add column if not exists professional_credential_ref text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='tax_ledger_counterparty_org_fkey'
  ) then
    alter table public.tax_ledger_entries
      add constraint tax_ledger_counterparty_org_fkey
      foreign key (counterparty_id,organization_id)
      references public.tax_counterparties(id,organization_id)
      on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='tax_ledger_account_org_fkey'
  ) then
    alter table public.tax_ledger_entries
      add constraint tax_ledger_account_org_fkey
      foreign key (account_id,organization_id)
      references public.tax_accounts(id,organization_id)
      on delete restrict;
  end if;
end $$;

create table if not exists public.tax_entry_classifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  ledger_entry_id uuid not null,
  classification_version integer not null check (classification_version >= 1),
  accounting_category text,
  tax_category text,
  business_purpose text,
  treatment_state text not null
    check (treatment_state in ('suggested','review_required','verified','excluded')),
  confidence numeric(5,4) check (confidence is null or confidence between 0 and 1),
  source_kind text not null
    check (source_kind in ('provider','deterministic','user','accountant','import')),
  source_ref text,
  reviewer_user_id uuid,
  review_notes text,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,ledger_entry_id,classification_version),
  unique (id,organization_id),
  constraint tax_entry_classifications_ledger_org_fkey
    foreign key (ledger_entry_id,organization_id)
    references public.tax_ledger_entries(id,organization_id)
    on delete cascade
);

create table if not exists public.tax_entry_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  ledger_entry_id uuid not null,
  adjustment_type text not null
    check (adjustment_type in ('amount','category','period','evidence','counterparty','account','exclusion','other')),
  before_state_redacted jsonb not null default '{}'::jsonb,
  after_state_redacted jsonb not null default '{}'::jsonb,
  reason text not null,
  actor_user_id uuid,
  actor_type text not null
    check (actor_type in ('user','accountant','system')),
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  constraint tax_entry_adjustments_ledger_org_fkey
    foreign key (ledger_entry_id,organization_id)
    references public.tax_ledger_entries(id,organization_id)
    on delete restrict,
  check (jsonb_typeof(before_state_redacted)='object'),
  check (jsonb_typeof(after_state_redacted)='object'),
  check (jsonb_typeof(evidence_refs)='array')
);

create table if not exists public.tax_reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reconciliation_run_id uuid not null,
  left_entity_type text not null,
  left_entity_id uuid not null,
  right_entity_type text not null,
  right_entity_id uuid not null,
  match_type text not null
    check (match_type in ('evidence_link','exact_amount','reference','source_identity','manual')),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  status text not null default 'matched'
    check (status in ('matched','review_required','rejected','superseded')),
  rationale_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,reconciliation_run_id,left_entity_type,left_entity_id,right_entity_type,right_entity_id,match_type),
  unique (id,organization_id),
  constraint tax_reconciliation_matches_run_org_fkey
    foreign key (reconciliation_run_id,organization_id)
    references public.tax_reconciliation_runs(id,organization_id)
    on delete cascade,
  check (jsonb_typeof(rationale_redacted)='object')
);

create table if not exists public.tax_exception_resolutions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  exception_id uuid not null,
  decision text not null check (decision in ('resolved','waived')),
  reason text not null,
  actor_user_id uuid not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,exception_id),
  unique (id,organization_id),
  constraint tax_exception_resolutions_exception_org_fkey
    foreign key (exception_id,organization_id)
    references public.tax_exceptions(id,organization_id)
    on delete cascade,
  check (jsonb_typeof(evidence_refs)='array')
);

create unique index if not exists tax_exceptions_open_identity_uidx
  on public.tax_exceptions(
    organization_id,
    coalesce(tax_period_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(ledger_entry_id,'00000000-0000-0000-0000-000000000000'::uuid),
    exception_type
  )
  where status in ('open','in_review');

create table if not exists public.tax_rule_sources (
  id uuid primary key default gen_random_uuid(),
  rule_pack_id uuid not null references public.tax_rule_packs(id) on delete cascade,
  source_key text not null,
  authority text not null,
  title text not null,
  source_url text not null,
  published_on date,
  retrieved_on date not null,
  content_sha256 text,
  source_scope text not null default 'official'
    check (source_scope in ('official','professional_interpretation')),
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  unique (rule_pack_id,source_key),
  check (content_sha256 is null or content_sha256 ~ '^[0-9a-f]{64}$')
);

create table if not exists public.tax_rule_tests (
  id uuid primary key default gen_random_uuid(),
  rule_pack_id uuid not null references public.tax_rule_packs(id) on delete cascade,
  test_key text not null,
  rule_key text,
  input_fixture jsonb not null,
  expected_output jsonb not null,
  status text not null default 'pending'
    check (status in ('pending','passed','failed','superseded')),
  last_result jsonb,
  last_run_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (rule_pack_id,test_key),
  check (jsonb_typeof(input_fixture)='object'),
  check (jsonb_typeof(expected_output)='object'),
  check (last_result is null or jsonb_typeof(last_result)='object')
);

create table if not exists public.tax_rule_reviews (
  id uuid primary key default gen_random_uuid(),
  rule_pack_id uuid not null references public.tax_rule_packs(id) on delete cascade,
  reviewer_user_id uuid,
  reviewer_role text not null
    check (reviewer_role in ('cpa','tax_professional','legal_tax_counsel')),
  reviewer_credential_ref text not null,
  decision text not null check (decision in ('approve','reject','changes_required')),
  review_notes text not null,
  source_reviewed boolean not null default false,
  tests_reviewed boolean not null default false,
  reviewed_at timestamptz not null default clock_timestamp(),
  evidence_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (id,rule_pack_id),
  check (jsonb_typeof(evidence_redacted)='object')
);

create table if not exists public.tax_return_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  calculation_run_id uuid not null,
  version integer not null check (version >= 1),
  form_key text not null,
  status text not null default 'draft'
    check (status in ('draft','review_required','reviewed','approved','superseded')),
  return_payload_redacted jsonb not null default '{}'::jsonb,
  package_sha256 text not null check (package_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,tax_period_id,form_key,version),
  unique (id,organization_id),
  constraint tax_return_versions_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade,
  constraint tax_return_versions_calc_org_fkey
    foreign key (calculation_run_id,organization_id)
    references public.tax_calculation_runs(id,organization_id)
    on delete restrict,
  check (jsonb_typeof(return_payload_redacted)='object')
);

create table if not exists public.tax_return_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  return_version_id uuid not null,
  schedule_key text not null,
  payload_redacted jsonb not null default '{}'::jsonb,
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,return_version_id,schedule_key),
  unique (id,organization_id),
  constraint tax_return_schedules_return_org_fkey
    foreign key (return_version_id,organization_id)
    references public.tax_return_versions(id,organization_id)
    on delete cascade,
  check (jsonb_typeof(payload_redacted)='object')
);

create table if not exists public.tax_filing_packages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  calculation_run_id uuid not null,
  package_version integer not null check (package_version >= 1),
  status text not null default 'review_required'
    check (status in (
      'review_required','accountant_approved','owner_approved',
      'submission_disabled','submitted','acknowledged','superseded'
    )),
  package_sha256 text not null check (package_sha256 ~ '^[0-9a-f]{64}$'),
  summary_redacted jsonb not null default '{}'::jsonb,
  evidence_index_redacted jsonb not null default '[]'::jsonb,
  filing_adapter_state text not null default 'disabled'
    check (filing_adapter_state in ('disabled','prepare_only','verified_submit')),
  accountant_review_id uuid,
  owner_approval_id uuid,
  created_by uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,tax_period_id,package_version),
  unique (id,organization_id),
  constraint tax_filing_packages_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade,
  constraint tax_filing_packages_calc_org_fkey
    foreign key (calculation_run_id,organization_id)
    references public.tax_calculation_runs(id,organization_id)
    on delete restrict,
  check (jsonb_typeof(summary_redacted)='object'),
  check (jsonb_typeof(evidence_index_redacted)='array')
);

create index if not exists tax_counterparties_org_idx
  on public.tax_counterparties(organization_id,display_name);
create index if not exists tax_entry_classifications_entry_idx
  on public.tax_entry_classifications(organization_id,ledger_entry_id,classification_version desc);
create index if not exists tax_reconciliation_matches_run_idx
  on public.tax_reconciliation_matches(organization_id,reconciliation_run_id,status);
create index if not exists tax_rule_sources_pack_idx
  on public.tax_rule_sources(rule_pack_id,source_key);
create index if not exists tax_rule_reviews_pack_idx
  on public.tax_rule_reviews(rule_pack_id,reviewed_at desc);
create index if not exists tax_filing_packages_period_idx
  on public.tax_filing_packages(organization_id,tax_period_id,package_version desc);

alter table public.tax_counterparties enable row level security;
alter table public.tax_accounts enable row level security;
alter table public.tax_entry_classifications enable row level security;
alter table public.tax_entry_adjustments enable row level security;
alter table public.tax_reconciliation_matches enable row level security;
alter table public.tax_exception_resolutions enable row level security;
alter table public.tax_rule_sources enable row level security;
alter table public.tax_rule_tests enable row level security;
alter table public.tax_rule_reviews enable row level security;
alter table public.tax_return_versions enable row level security;
alter table public.tax_return_schedules enable row level security;
alter table public.tax_filing_packages enable row level security;

drop policy if exists tax_counterparties_org_read on public.tax_counterparties;
create policy tax_counterparties_org_read on public.tax_counterparties
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_accounts_org_read on public.tax_accounts;
create policy tax_accounts_org_read on public.tax_accounts
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_entry_classifications_org_read on public.tax_entry_classifications;
create policy tax_entry_classifications_org_read on public.tax_entry_classifications
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_entry_adjustments_org_read on public.tax_entry_adjustments;
create policy tax_entry_adjustments_org_read on public.tax_entry_adjustments
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_reconciliation_matches_org_read on public.tax_reconciliation_matches;
create policy tax_reconciliation_matches_org_read on public.tax_reconciliation_matches
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_exception_resolutions_org_read on public.tax_exception_resolutions;
create policy tax_exception_resolutions_org_read on public.tax_exception_resolutions
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_rule_sources_authenticated_read on public.tax_rule_sources;
create policy tax_rule_sources_authenticated_read on public.tax_rule_sources
for select to authenticated
using (
  exists(
    select 1 from public.tax_rule_packs rp
    where rp.id=tax_rule_sources.rule_pack_id and rp.status='approved'
  )
);

drop policy if exists tax_rule_tests_authenticated_read on public.tax_rule_tests;
create policy tax_rule_tests_authenticated_read on public.tax_rule_tests
for select to authenticated
using (
  exists(
    select 1 from public.tax_rule_packs rp
    where rp.id=tax_rule_tests.rule_pack_id and rp.status='approved'
  )
);

drop policy if exists tax_rule_reviews_authenticated_read on public.tax_rule_reviews;
create policy tax_rule_reviews_authenticated_read on public.tax_rule_reviews
for select to authenticated
using (
  exists(
    select 1 from public.tax_rule_packs rp
    where rp.id=tax_rule_reviews.rule_pack_id and rp.status='approved'
  )
);

drop policy if exists tax_return_versions_org_read on public.tax_return_versions;
create policy tax_return_versions_org_read on public.tax_return_versions
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_return_schedules_org_read on public.tax_return_schedules;
create policy tax_return_schedules_org_read on public.tax_return_schedules
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_filing_packages_org_read on public.tax_filing_packages;
create policy tax_filing_packages_org_read on public.tax_filing_packages
for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

revoke all on table public.tax_counterparties from public,anon,authenticated;
revoke all on table public.tax_accounts from public,anon,authenticated;
revoke all on table public.tax_entry_classifications from public,anon,authenticated;
revoke all on table public.tax_entry_adjustments from public,anon,authenticated;
revoke all on table public.tax_reconciliation_matches from public,anon,authenticated;
revoke all on table public.tax_exception_resolutions from public,anon,authenticated;
revoke all on table public.tax_rule_sources from public,anon,authenticated;
revoke all on table public.tax_rule_tests from public,anon,authenticated;
revoke all on table public.tax_rule_reviews from public,anon,authenticated;
revoke all on table public.tax_return_versions from public,anon,authenticated;
revoke all on table public.tax_return_schedules from public,anon,authenticated;
revoke all on table public.tax_filing_packages from public,anon,authenticated;

grant select on table public.tax_counterparties to authenticated;
grant select on table public.tax_accounts to authenticated;
grant select on table public.tax_entry_classifications to authenticated;
grant select on table public.tax_entry_adjustments to authenticated;
grant select on table public.tax_reconciliation_matches to authenticated;
grant select on table public.tax_exception_resolutions to authenticated;
grant select on table public.tax_rule_sources to authenticated;
grant select on table public.tax_rule_tests to authenticated;
grant select on table public.tax_rule_reviews to authenticated;
grant select on table public.tax_return_versions to authenticated;
grant select on table public.tax_return_schedules to authenticated;
grant select on table public.tax_filing_packages to authenticated;

grant select,insert,update,delete on table public.tax_counterparties to service_role;
grant select,insert,update,delete on table public.tax_accounts to service_role;
grant select,insert,update,delete on table public.tax_entry_classifications to service_role;
grant select,insert on table public.tax_entry_adjustments to service_role;
grant select,insert,update,delete on table public.tax_reconciliation_matches to service_role;
grant select,insert on table public.tax_exception_resolutions to service_role;
grant select,insert,update,delete on table public.tax_rule_sources to service_role;
grant select,insert,update,delete on table public.tax_rule_tests to service_role;
grant select,insert on table public.tax_rule_reviews to service_role;
grant select,insert,update,delete on table public.tax_return_versions to service_role;
grant select,insert,update,delete on table public.tax_return_schedules to service_role;
grant select,insert,update,delete on table public.tax_filing_packages to service_role;

create or replace function public.pandora_tax_post_ledger_entry_v1(
  p_organization_id uuid,
  p_entry_key text,
  p_tax_period_id uuid,
  p_source_object_id uuid,
  p_document_id uuid,
  p_transaction_date date,
  p_entry_kind text,
  p_currency_code text,
  p_gross_amount numeric,
  p_net_amount numeric default null,
  p_tax_amount numeric default null,
  p_accounting_category text default null,
  p_tax_category text default null,
  p_business_purpose text default null,
  p_confidence numeric default null,
  p_counterparty_key text default null,
  p_counterparty_name text default null,
  p_account_key text default null,
  p_account_name text default null,
  p_account_type text default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  period_row public.tax_periods%rowtype;
  document_row public.tax_documents%rowtype;
  existing public.tax_ledger_entries%rowtype;
  ledger_row public.tax_ledger_entries%rowtype;
  counterparty_row public.tax_counterparties%rowtype;
  account_row public.tax_accounts%rowtype;
  fingerprint text;
  evidence_state_value text := 'unverified';
begin
  if p_organization_id is null
     or p_entry_key is null
     or length(btrim(p_entry_key)) not between 1 and 240
     or p_transaction_date is null
     or p_entry_kind not in (
       'sale','purchase','payment','receipt','refund','adjustment',
       'payroll','withholding','credit','debit','other'
     )
     or p_currency_code is null
     or p_currency_code !~ '^[A-Z]{3}$'
     or p_gross_amount is null
     or abs(p_gross_amount) > 1000000000000000
     or (p_net_amount is not null and abs(p_net_amount) > 1000000000000000)
     or (p_tax_amount is not null and abs(p_tax_amount) > 1000000000000000)
     or (p_confidence is not null and (p_confidence < 0 or p_confidence > 1))
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_ledger_entry_invalid' using errcode='22023';
  end if;

  select * into period_row
  from public.tax_periods
  where id=p_tax_period_id and organization_id=p_organization_id;
  if period_row.id is null then
    raise exception 'pandora_tax_period_not_found' using errcode='P0002';
  end if;

  if p_document_id is not null then
    select * into document_row
    from public.tax_documents
    where id=p_document_id and organization_id=p_organization_id;
    if document_row.id is null then
      raise exception 'pandora_tax_document_not_found' using errcode='P0002';
    end if;
    evidence_state_value := case
      when document_row.extraction_state='verified' then 'verified'
      else 'unverified'
    end;
  end if;

  if p_source_object_id is not null and not exists(
    select 1 from public.tax_source_objects
    where id=p_source_object_id and organization_id=p_organization_id
  ) then
    raise exception 'pandora_tax_source_object_not_found' using errcode='P0002';
  end if;

  if p_counterparty_key is not null then
    insert into public.tax_counterparties(
      organization_id,counterparty_key,display_name
    ) values (
      p_organization_id,btrim(p_counterparty_key),
      nullif(btrim(coalesce(p_counterparty_name,'')),'')
    )
    on conflict (organization_id,counterparty_key)
    do update set
      display_name=coalesce(excluded.display_name,public.tax_counterparties.display_name),
      updated_at=clock_timestamp()
    returning * into counterparty_row;
  end if;

  if p_account_key is not null then
    if p_account_name is null or p_account_type not in (
      'asset','liability','equity','revenue','expense','tax','cash','other'
    ) then
      raise exception 'pandora_tax_account_invalid' using errcode='22023';
    end if;
    insert into public.tax_accounts(
      organization_id,account_key,display_name,account_type,currency_code
    ) values (
      p_organization_id,btrim(p_account_key),btrim(p_account_name),
      p_account_type,p_currency_code
    )
    on conflict (organization_id,account_key)
    do update set
      display_name=excluded.display_name,
      account_type=excluded.account_type,
      currency_code=excluded.currency_code,
      updated_at=clock_timestamp()
    returning * into account_row;
  end if;

  fingerprint := encode(
    extensions.digest(
      convert_to(concat_ws('|',
        p_transaction_date::text,
        p_entry_kind,
        p_currency_code,
        round(p_gross_amount,4)::text,
        coalesce(round(p_net_amount,4)::text,''),
        coalesce(round(p_tax_amount,4)::text,''),
        coalesce(p_document_id::text,''),
        coalesce(p_source_object_id::text,'')
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into existing
  from public.tax_ledger_entries
  where organization_id=p_organization_id
    and entry_key=btrim(p_entry_key);

  if existing.id is not null then
    if existing.entry_fingerprint_sha256 is distinct from fingerprint then
      raise exception 'pandora_tax_ledger_idempotency_conflict' using errcode='23505';
    end if;
    return jsonb_build_object(
      'schemaVersion','pandora.tax.ledger-entry.v1',
      'ledgerEntryId',existing.id,
      'entryKey',existing.entry_key,
      'fingerprint',existing.entry_fingerprint_sha256,
      'treatmentState',existing.treatment_state,
      'evidenceState',existing.evidence_state,
      'replayed',true
    );
  end if;

  insert into public.tax_ledger_entries(
    organization_id,tax_period_id,source_object_id,document_id,
    transaction_date,counterparty_ref,counterparty_id,account_id,
    currency_code,gross_amount,net_amount,tax_amount,
    accounting_category,tax_category,business_purpose,
    treatment_state,classification_confidence,rule_pack_id,provenance,
    entry_key,entry_kind,entry_fingerprint_sha256,evidence_state
  ) values (
    p_organization_id,p_tax_period_id,p_source_object_id,p_document_id,
    p_transaction_date,nullif(btrim(coalesce(p_counterparty_key,'')),''),
    counterparty_row.id,account_row.id,
    p_currency_code,round(p_gross_amount,4),
    case when p_net_amount is null then null else round(p_net_amount,4) end,
    case when p_tax_amount is null then null else round(p_tax_amount,4) end,
    nullif(btrim(coalesce(p_accounting_category,'')),''),
    nullif(btrim(coalesce(p_tax_category,'')),''),
    nullif(btrim(coalesce(p_business_purpose,'')),''),
    case
      when p_tax_category is null or p_accounting_category is null then 'review_required'
      else 'suggested'
    end,
    p_confidence,period_row.rule_pack_id,coalesce(p_provenance,'{}'::jsonb),
    btrim(p_entry_key),p_entry_kind,fingerprint,evidence_state_value
  )
  returning * into ledger_row;

  insert into public.tax_entry_classifications(
    organization_id,ledger_entry_id,classification_version,
    accounting_category,tax_category,business_purpose,treatment_state,
    confidence,source_kind,source_ref
  ) values (
    p_organization_id,ledger_row.id,1,
    ledger_row.accounting_category,ledger_row.tax_category,ledger_row.business_purpose,
    ledger_row.treatment_state,p_confidence,'import',
    coalesce(p_document_id::text,p_source_object_id::text,p_entry_key)
  );

  if p_document_id is not null then
    insert into public.tax_document_links(
      organization_id,document_id,linked_entity_type,linked_entity_id,
      link_type,confidence,provenance_redacted
    ) values (
      p_organization_id,p_document_id,'ledger_entry',ledger_row.id,
      'derived_from',coalesce(p_confidence,1.0),
      jsonb_build_object('entryKey',ledger_row.entry_key,'fingerprint',fingerprint)
    )
    on conflict (organization_id,document_id,linked_entity_type,linked_entity_id,link_type)
    do nothing;
  end if;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,p_tax_period_id,'tax_ledger_entry_posted',null,'system',
    'pandora_tax_post_ledger_entry_v1',ledger_row.id::text,
    jsonb_build_object(
      'ledgerEntryId',ledger_row.id,
      'entryKey',ledger_row.entry_key,
      'entryKind',ledger_row.entry_kind,
      'fingerprint',fingerprint,
      'evidenceState',ledger_row.evidence_state,
      'treatmentState',ledger_row.treatment_state
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.ledger-entry.v1',
    'ledgerEntryId',ledger_row.id,
    'entryKey',ledger_row.entry_key,
    'fingerprint',fingerprint,
    'treatmentState',ledger_row.treatment_state,
    'evidenceState',ledger_row.evidence_state,
    'replayed',false
  );
end;
$$;

revoke all on function public.pandora_tax_post_ledger_entry_v1(
  uuid,text,uuid,uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,numeric,text,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_post_ledger_entry_v1(
  uuid,text,uuid,uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,numeric,text,text,text,text,text,jsonb
) to service_role;

create or replace function public.pandora_tax_review_ledger_entry_v1(
  p_organization_id uuid,
  p_ledger_entry_id uuid,
  p_decision text,
  p_accounting_category text,
  p_tax_category text,
  p_business_purpose text default null,
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  row_before public.tax_ledger_entries%rowtype;
  row_after public.tax_ledger_entries%rowtype;
  next_version integer;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized_decision not in ('verified','excluded')
     or p_accounting_category is null
     or length(btrim(p_accounting_category)) not between 1 and 120
     or (
       normalized_decision='verified'
       and (p_tax_category is null or length(btrim(p_tax_category)) not between 1 and 120)
     )
     or (p_review_notes is not null and length(p_review_notes)>2000)
  then
    raise exception 'pandora_tax_ledger_review_invalid' using errcode='22023';
  end if;

  select * into row_before
  from public.tax_ledger_entries
  where id=p_ledger_entry_id and organization_id=p_organization_id
  for update;
  if row_before.id is null then
    raise exception 'pandora_tax_ledger_entry_not_found' using errcode='P0002';
  end if;

  if normalized_decision='verified'
     and row_before.document_id is not null
     and row_before.evidence_state<>'verified'
  then
    raise exception 'pandora_tax_verified_evidence_required' using errcode='55000';
  end if;

  select coalesce(max(classification_version),0)+1 into next_version
  from public.tax_entry_classifications
  where organization_id=p_organization_id and ledger_entry_id=p_ledger_entry_id;

  update public.tax_ledger_entries
  set accounting_category=btrim(p_accounting_category),
      tax_category=case
        when normalized_decision='excluded' then null
        else btrim(p_tax_category)
      end,
      business_purpose=nullif(btrim(coalesce(p_business_purpose,'')),''),
      treatment_state=normalized_decision,
      reviewed_by=uid,
      reviewed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=p_ledger_entry_id and organization_id=p_organization_id
  returning * into row_after;

  insert into public.tax_entry_classifications(
    organization_id,ledger_entry_id,classification_version,
    accounting_category,tax_category,business_purpose,treatment_state,
    confidence,source_kind,source_ref,reviewer_user_id,review_notes
  ) values (
    p_organization_id,p_ledger_entry_id,next_version,
    row_after.accounting_category,row_after.tax_category,row_after.business_purpose,
    row_after.treatment_state,1.0,'user',
    'pandora_tax_review_ledger_entry_v1',uid,p_review_notes
  );

  insert into public.tax_entry_adjustments(
    organization_id,ledger_entry_id,adjustment_type,
    before_state_redacted,after_state_redacted,reason,
    actor_user_id,actor_type,evidence_refs
  ) values (
    p_organization_id,p_ledger_entry_id,'category',
    jsonb_build_object(
      'accountingCategory',row_before.accounting_category,
      'taxCategory',row_before.tax_category,
      'treatmentState',row_before.treatment_state
    ),
    jsonb_build_object(
      'accountingCategory',row_after.accounting_category,
      'taxCategory',row_after.tax_category,
      'treatmentState',row_after.treatment_state
    ),
    coalesce(nullif(btrim(coalesce(p_review_notes,'')),''),'Owner/admin ledger review'),
    uid,'user','[]'::jsonb
  );

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,row_after.tax_period_id,'tax_ledger_entry_reviewed',uid,'user',
    'pandora_tax_review_ledger_entry_v1',row_after.id::text,
    jsonb_build_object(
      'ledgerEntryId',row_after.id,
      'classificationVersion',next_version,
      'decision',normalized_decision
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.ledger-review.v1',
    'ledgerEntryId',row_after.id,
    'classificationVersion',next_version,
    'decision',normalized_decision,
    'reviewedBy',uid
  );
end;
$$;

revoke all on function public.pandora_tax_review_ledger_entry_v1(
  uuid,uuid,text,text,text,text,text
) from public,anon;
grant execute on function public.pandora_tax_review_ledger_entry_v1(
  uuid,uuid,text,text,text,text,text
) to authenticated;

create or replace function public.pandora_tax_period_ledger_checksum_v1(
  p_organization_id uuid,
  p_tax_period_id uuid
)
returns text
language sql
stable
security definer
set search_path='pg_catalog','public'
as $$
  select encode(
    extensions.digest(
      convert_to(coalesce(
        string_agg(
          concat_ws('|',
            le.id::text,
            le.transaction_date::text,
            coalesce(le.entry_kind,''),
            le.currency_code,
            round(le.gross_amount,4)::text,
            coalesce(round(le.net_amount,4)::text,''),
            coalesce(round(le.tax_amount,4)::text,''),
            coalesce(le.accounting_category,''),
            coalesce(le.tax_category,''),
            le.treatment_state,
            le.evidence_state,
            coalesce(le.entry_fingerprint_sha256,'')
          ),
          E'\n'
          order by le.transaction_date,le.id
        ),
        ''
      ),'UTF8'),
      'sha256'
    ),
    'hex'
  )
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
$$;

revoke all on function public.pandora_tax_period_ledger_checksum_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_tax_period_ledger_checksum_v1(uuid,uuid)
  to service_role;

create or replace function public.pandora_tax_run_reconciliation_v1(
  p_organization_id uuid,
  p_tax_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  period_row public.tax_periods%rowtype;
  run_row public.tax_reconciliation_runs%rowtype;
  matched_count_value integer := 0;
  exception_count_value integer := 0;
  period_currency text;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;

  select * into period_row
  from public.tax_periods
  where id=p_tax_period_id and organization_id=p_organization_id
  for update;
  if period_row.id is null then
    raise exception 'pandora_tax_period_not_found' using errcode='P0002';
  end if;

  select currency_code into period_currency
  from public.tax_jurisdictions
  where code=period_row.jurisdiction_code;

  insert into public.tax_reconciliation_runs(
    organization_id,tax_period_id,status,summary
  ) values (
    p_organization_id,p_tax_period_id,'running',
    jsonb_build_object('engine','pandora-tax-reconciliation-v1')
  )
  returning * into run_row;

  insert into public.tax_reconciliation_matches(
    organization_id,reconciliation_run_id,
    left_entity_type,left_entity_id,right_entity_type,right_entity_id,
    match_type,confidence,status,rationale_redacted
  )
  select
    p_organization_id,run_row.id,
    'ledger_entry',le.id,'document',le.document_id,
    'evidence_link',1.0,'matched',
    jsonb_build_object('documentExtractionState',d.extraction_state)
  from public.tax_ledger_entries le
  join public.tax_documents d
    on d.id=le.document_id and d.organization_id=le.organization_id
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and d.extraction_state='verified'
  on conflict do nothing;

  get diagnostics matched_count_value = row_count;

  insert into public.tax_exceptions(
    organization_id,tax_period_id,ledger_entry_id,
    exception_type,severity,amount_at_risk,status,recommended_next_action,evidence_refs
  )
  select
    p_organization_id,p_tax_period_id,le.id,
    'missing_receipt',
    case when abs(le.gross_amount)>=100000 then 'high' else 'medium' end,
    abs(le.gross_amount),'open',
    'Attach or verify supporting evidence before calculation.',
    '[]'::jsonb
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and le.treatment_state<>'excluded'
    and (
      le.document_id is null
      or le.evidence_state<>'verified'
    )
  on conflict do nothing;

  insert into public.tax_exceptions(
    organization_id,tax_period_id,ledger_entry_id,
    exception_type,severity,amount_at_risk,status,recommended_next_action,evidence_refs
  )
  select
    p_organization_id,p_tax_period_id,le.id,
    'unknown_tax_category','high',abs(le.gross_amount),'open',
    'Review and verify the tax treatment for this ledger entry.',
    '[]'::jsonb
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and le.treatment_state not in ('verified','excluded')
  on conflict do nothing;

  insert into public.tax_exceptions(
    organization_id,tax_period_id,ledger_entry_id,
    exception_type,severity,amount_at_risk,status,recommended_next_action,evidence_refs
  )
  select
    p_organization_id,p_tax_period_id,le.id,
    'period_mismatch','high',abs(le.gross_amount),'open',
    'Move the entry to the correct tax period or document the approved period treatment.',
    '[]'::jsonb
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and (le.transaction_date<period_row.period_start or le.transaction_date>period_row.period_end)
  on conflict do nothing;

  insert into public.tax_exceptions(
    organization_id,tax_period_id,ledger_entry_id,
    exception_type,severity,amount_at_risk,status,recommended_next_action,evidence_refs
  )
  select
    p_organization_id,p_tax_period_id,le.id,
    'currency_mismatch','medium',abs(le.gross_amount),'open',
    'Provide a verified currency conversion or foreign-currency treatment.',
    '[]'::jsonb
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and period_currency is not null
    and le.currency_code<>period_currency
  on conflict do nothing;

  insert into public.tax_exceptions(
    organization_id,tax_period_id,ledger_entry_id,
    exception_type,severity,amount_at_risk,status,recommended_next_action,evidence_refs
  )
  select
    p_organization_id,p_tax_period_id,le.id,
    'duplicate_invoice','high',abs(le.gross_amount),'open',
    'Review duplicate fingerprint candidates and retain only the correct tax treatment.',
    jsonb_build_array(jsonb_build_object('fingerprint',le.entry_fingerprint_sha256))
  from public.tax_ledger_entries le
  where le.organization_id=p_organization_id
    and le.tax_period_id=p_tax_period_id
    and le.entry_fingerprint_sha256 is not null
    and exists(
      select 1
      from public.tax_ledger_entries other
      where other.organization_id=le.organization_id
        and other.tax_period_id=le.tax_period_id
        and other.entry_fingerprint_sha256=le.entry_fingerprint_sha256
        and other.id<>le.id
    )
  on conflict do nothing;

  select count(*)::integer into exception_count_value
  from public.tax_exceptions
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status in ('open','in_review');

  update public.tax_reconciliation_runs
  set status='complete',
      matched_count=matched_count_value,
      exception_count=exception_count_value,
      completed_at=clock_timestamp(),
      summary=jsonb_build_object(
        'engine','pandora-tax-reconciliation-v1',
        'matched',matched_count_value,
        'openExceptions',exception_count_value,
        'periodCurrency',period_currency
      )
  where id=run_row.id and organization_id=p_organization_id
  returning * into run_row;

  update public.tax_periods
  set status='review_required',
      updated_at=clock_timestamp()
  where id=p_tax_period_id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,p_tax_period_id,'tax_reconciliation_completed',uid,'user',
    'pandora_tax_run_reconciliation_v1',run_row.id::text,
    jsonb_build_object(
      'reconciliationRunId',run_row.id,
      'matchedCount',run_row.matched_count,
      'exceptionCount',run_row.exception_count
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.reconciliation.v1',
    'reconciliationRunId',run_row.id,
    'status',run_row.status,
    'matchedCount',run_row.matched_count,
    'exceptionCount',run_row.exception_count,
    'readyForCalculation',run_row.exception_count=0
  );
end;
$$;

revoke all on function public.pandora_tax_run_reconciliation_v1(uuid,uuid)
  from public,anon;
grant execute on function public.pandora_tax_run_reconciliation_v1(uuid,uuid)
  to authenticated;

create or replace function public.pandora_tax_resolve_exception_v1(
  p_organization_id uuid,
  p_exception_id uuid,
  p_decision text,
  p_reason text,
  p_evidence_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  ex public.tax_exceptions%rowtype;
  normalized text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized not in ('resolved','waived')
     or p_reason is null or length(btrim(p_reason)) not between 2 and 2000
     or jsonb_typeof(coalesce(p_evidence_refs,'[]'::jsonb))<>'array'
  then
    raise exception 'pandora_tax_exception_resolution_invalid' using errcode='22023';
  end if;

  select * into ex
  from public.tax_exceptions
  where id=p_exception_id and organization_id=p_organization_id
  for update;
  if ex.id is null then
    raise exception 'pandora_tax_exception_not_found' using errcode='P0002';
  end if;
  if ex.status not in ('open','in_review') then
    raise exception 'pandora_tax_exception_not_open' using errcode='55000';
  end if;

  insert into public.tax_exception_resolutions(
    organization_id,exception_id,decision,reason,actor_user_id,evidence_refs
  ) values (
    p_organization_id,p_exception_id,normalized,btrim(p_reason),uid,
    coalesce(p_evidence_refs,'[]'::jsonb)
  );

  update public.tax_exceptions
  set status=normalized,
      resolution=jsonb_build_object('reason',btrim(p_reason),'actorUserId',uid),
      updated_at=clock_timestamp()
  where id=p_exception_id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,ex.tax_period_id,'tax_exception_resolved',uid,'user',
    'pandora_tax_resolve_exception_v1',ex.id::text,
    jsonb_build_object('exceptionId',ex.id,'decision',normalized,'exceptionType',ex.exception_type)
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.exception-resolution.v1',
    'exceptionId',ex.id,
    'decision',normalized,
    'resolvedBy',uid
  );
end;
$$;

revoke all on function public.pandora_tax_resolve_exception_v1(
  uuid,uuid,text,text,jsonb
) from public,anon;
grant execute on function public.pandora_tax_resolve_exception_v1(
  uuid,uuid,text,text,jsonb
) to authenticated;

create or replace function public.pandora_tax_run_rule_tests_v1(
  p_rule_pack_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $tax_rule_tests$
declare
  pack public.tax_rule_packs%rowtype;
  test_row public.tax_rule_tests%rowtype;
  rule_row public.tax_rules%rowtype;
  op text;
  actual_amount numeric;
  actual_output jsonb;
  passed integer := 0;
  failed integer := 0;
  total integer := 0;
begin
  select * into pack
  from public.tax_rule_packs
  where id=p_rule_pack_id
  for update;
  if pack.id is null then
    raise exception 'pandora_tax_rule_pack_not_found' using errcode='P0002';
  end if;
  if pack.status in ('approved','superseded') then
    raise exception 'pandora_tax_rule_pack_immutable' using errcode='42501';
  end if;

  for test_row in
    select * from public.tax_rule_tests
    where rule_pack_id=p_rule_pack_id
    order by test_key
  loop
    total := total+1;
    select * into rule_row
    from public.tax_rules
    where rule_pack_id=p_rule_pack_id and rule_key=test_row.rule_key;
    if rule_row.id is null then
      actual_output := jsonb_build_object('error','rule_not_found');
    else
      op := rule_row.deterministic_spec->>'operation';
      actual_amount := null;

      if op='sum' then
        if jsonb_typeof(test_row.input_fixture->'values')<>'array' then
          actual_output := jsonb_build_object('error','values_required');
        else
          select coalesce(sum(value::numeric),0)
          into actual_amount
          from jsonb_array_elements_text(test_row.input_fixture->'values') valueset(value);
          actual_output := jsonb_build_object('amount',round(actual_amount,2));
        end if;
      elsif op='rate' then
        if (test_row.input_fixture->>'base') is null
           or (rule_row.deterministic_spec->>'rate') is null
        then
          actual_output := jsonb_build_object('error','base_and_rate_required');
        else
          actual_amount := round(
            (test_row.input_fixture->>'base')::numeric *
            (rule_row.deterministic_spec->>'rate')::numeric,
            2
          );
          actual_output := jsonb_build_object('amount',actual_amount);
        end if;
      elsif op='difference' then
        if (test_row.input_fixture->>'left') is null
           or (test_row.input_fixture->>'right') is null
        then
          actual_output := jsonb_build_object('error','left_and_right_required');
        else
          actual_output := jsonb_build_object(
            'amount',
            round(
              (test_row.input_fixture->>'left')::numeric -
              (test_row.input_fixture->>'right')::numeric,
              2
            )
          );
        end if;
      elsif op='max_zero' then
        if (test_row.input_fixture->>'base') is null then
          actual_output := jsonb_build_object('error','base_required');
        else
          actual_output := jsonb_build_object(
            'amount',
            greatest((test_row.input_fixture->>'base')::numeric,0)
          );
        end if;
      elsif op='fixed' then
        actual_output := jsonb_build_object(
          'amount',
          round((rule_row.deterministic_spec->>'amount')::numeric,2)
        );
      else
        actual_output := jsonb_build_object('error','unsupported_test_operation','operation',op);
      end if;
    end if;

    update public.tax_rule_tests
    set status=case when actual_output=test_row.expected_output then 'passed' else 'failed' end,
        last_result=actual_output,
        last_run_at=clock_timestamp()
    where id=test_row.id;

    if actual_output=test_row.expected_output then
      passed := passed+1;
    else
      failed := failed+1;
    end if;
  end loop;

  if total=0 then
    raise exception 'pandora_tax_rule_tests_missing' using errcode='55000';
  end if;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.rule-tests.v1',
    'rulePackId',p_rule_pack_id,
    'total',total,
    'passed',passed,
    'failed',failed,
    'allPassed',failed=0
  );
end;
$tax_rule_tests$;

revoke all on function public.pandora_tax_run_rule_tests_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_tax_run_rule_tests_v1(uuid)
  to service_role;

create or replace function public.pandora_tax_record_rule_review_v1(
  p_rule_pack_id uuid,
  p_reviewer_user_id uuid,
  p_reviewer_role text,
  p_reviewer_credential_ref text,
  p_decision text,
  p_review_notes text,
  p_source_reviewed boolean,
  p_tests_reviewed boolean,
  p_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  pack public.tax_rule_packs%rowtype;
  review_row public.tax_rule_reviews%rowtype;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
  source_count integer;
  rule_count integer;
  passed_test_count integer;
begin
  if p_rule_pack_id is null
     or p_reviewer_user_id is null
     or p_reviewer_role not in ('cpa','tax_professional','legal_tax_counsel')
     or p_reviewer_credential_ref is null
     or length(btrim(p_reviewer_credential_ref)) not between 3 and 240
     or normalized_decision not in ('approve','reject','changes_required')
     or p_review_notes is null
     or length(btrim(p_review_notes)) not between 2 and 4000
     or jsonb_typeof(coalesce(p_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_rule_review_invalid' using errcode='22023';
  end if;

  select * into pack
  from public.tax_rule_packs
  where id=p_rule_pack_id
  for update;
  if pack.id is null then
    raise exception 'pandora_tax_rule_pack_not_found' using errcode='P0002';
  end if;
  if pack.status in ('approved','superseded') then
    raise exception 'pandora_tax_rule_pack_immutable' using errcode='42501';
  end if;

  select count(*)::integer into source_count
  from public.tax_rule_sources
  where rule_pack_id=p_rule_pack_id and source_scope='official';

  select count(*)::integer into rule_count
  from public.tax_rules
  where rule_pack_id=p_rule_pack_id;

  select count(*)::integer into passed_test_count
  from public.tax_rule_tests
  where rule_pack_id=p_rule_pack_id and status='passed';

  if normalized_decision='approve' and (
       p_source_reviewed is not true
       or p_tests_reviewed is not true
       or source_count=0
       or rule_count=0
       or passed_test_count<rule_count
     )
  then
    raise exception 'pandora_tax_rule_pack_not_approvable' using errcode='55000';
  end if;

  insert into public.tax_rule_reviews(
    rule_pack_id,reviewer_user_id,reviewer_role,reviewer_credential_ref,
    decision,review_notes,source_reviewed,tests_reviewed,evidence_redacted
  ) values (
    p_rule_pack_id,p_reviewer_user_id,p_reviewer_role,btrim(p_reviewer_credential_ref),
    normalized_decision,btrim(p_review_notes),p_source_reviewed,p_tests_reviewed,
    coalesce(p_evidence_redacted,'{}'::jsonb)
  )
  returning * into review_row;

  if normalized_decision='approve' then
    update public.tax_rule_packs
    set status='approved',
        review_notes=btrim(p_review_notes),
        reviewed_by=p_reviewer_user_id,
        approved_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=p_rule_pack_id;
  elsif normalized_decision='reject' then
    update public.tax_rule_packs
    set status='rejected',
        review_notes=btrim(p_review_notes),
        reviewed_by=p_reviewer_user_id,
        updated_at=clock_timestamp()
    where id=p_rule_pack_id;
  else
    update public.tax_rule_packs
    set status='in_review',
        review_notes=btrim(p_review_notes),
        reviewed_by=p_reviewer_user_id,
        updated_at=clock_timestamp()
    where id=p_rule_pack_id;
  end if;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.rule-review.v1',
    'rulePackId',p_rule_pack_id,
    'reviewId',review_row.id,
    'decision',normalized_decision,
    'status',(select status from public.tax_rule_packs where id=p_rule_pack_id),
    'officialSourceCount',source_count,
    'ruleCount',rule_count,
    'passedTestCount',passed_test_count
  );
end;
$$;

revoke all on function public.pandora_tax_record_rule_review_v1(
  uuid,uuid,text,text,text,text,boolean,boolean,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_record_rule_review_v1(
  uuid,uuid,text,text,text,text,boolean,boolean,jsonb
) to service_role;

create or replace function public.pandora_tax_calculate_period_v1(
  p_organization_id uuid,
  p_tax_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  period_row public.tax_periods%rowtype;
  pack public.tax_rule_packs%rowtype;
  rule_row public.tax_rules%rowtype;
  latest_recon public.tax_reconciliation_runs%rowtype;
  run_row public.tax_calculation_runs%rowtype;
  input_checksum_value text;
  output_checksum_value text;
  op text;
  line_key_value text;
  field_name text;
  filter_tax_category text;
  filter_accounting_category text;
  filter_entry_kind text;
  base_line_key text;
  left_line_key text;
  right_line_key text;
  amount_value numeric(20,4);
  base_amount numeric(20,4);
  left_amount numeric(20,4);
  right_amount numeric(20,4);
  rate_value numeric;
  open_blockers integer := 0;
  line_count integer := 0;
  obligation_key_value text;
  due_days integer;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;

  select * into period_row
  from public.tax_periods
  where id=p_tax_period_id and organization_id=p_organization_id
  for update;
  if period_row.id is null then
    raise exception 'pandora_tax_period_not_found' using errcode='P0002';
  end if;
  if period_row.rule_pack_id is null then
    raise exception 'pandora_tax_approved_rule_pack_required' using errcode='55000';
  end if;

  select * into pack
  from public.tax_rule_packs
  where id=period_row.rule_pack_id
    and status='approved'
    and jurisdiction_code=period_row.jurisdiction_code
    and (effective_from is null or effective_from<=period_row.period_end)
    and (effective_to is null or effective_to>=period_row.period_start);
  if pack.id is null then
    raise exception 'pandora_tax_approved_rule_pack_required' using errcode='55000';
  end if;

  select * into latest_recon
  from public.tax_reconciliation_runs
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status='complete'
  order by completed_at desc nulls last,started_at desc,id desc
  limit 1;
  if latest_recon.id is null then
    raise exception 'pandora_tax_reconciliation_required' using errcode='55000';
  end if;

  select count(*)::integer into open_blockers
  from public.tax_exceptions
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status in ('open','in_review')
    and severity in ('high','critical');
  if open_blockers>0 then
    raise exception 'pandora_tax_blocking_exceptions' using errcode='55000';
  end if;

  if exists(
    select 1 from public.tax_ledger_entries
    where organization_id=p_organization_id
      and tax_period_id=p_tax_period_id
      and treatment_state not in ('verified','excluded')
  ) then
    raise exception 'pandora_tax_unverified_ledger_entries' using errcode='55000';
  end if;

  select public.pandora_tax_period_ledger_checksum_v1(
    p_organization_id,p_tax_period_id
  ) into input_checksum_value;

  insert into public.tax_calculation_runs(
    organization_id,tax_period_id,rule_pack_id,status,input_checksum,
    assumptions,result_summary
  ) values (
    p_organization_id,p_tax_period_id,pack.id,'running',input_checksum_value,
    '[]'::jsonb,
    jsonb_build_object('engine','pandora-tax-deterministic-v1','rulePackVersion',pack.version)
  )
  returning * into run_row;

  for rule_row in
    select *
    from public.tax_rules
    where rule_pack_id=pack.id
    order by
      case
        when (deterministic_spec->>'sequence') ~ '^[0-9]+$'
          then (deterministic_spec->>'sequence')::integer
        else 1000
      end,
      rule_key
  loop
    if jsonb_typeof(rule_row.deterministic_spec->'periodTypes')='array'
       and not (rule_row.deterministic_spec->'periodTypes' ? period_row.period_type)
    then
      continue;
    end if;

    if rule_row.deterministic_spec ? 'eligibility' then
      raise exception 'pandora_tax_rule_eligibility_profile_required' using errcode='55000';
    end if;

    op := rule_row.deterministic_spec->>'operation';
    line_key_value := coalesce(rule_row.deterministic_spec->>'lineKey',rule_row.rule_key);
    amount_value := null;

    if op='sum' then
      field_name := coalesce(rule_row.deterministic_spec->>'field','gross_amount');
      filter_tax_category := nullif(rule_row.deterministic_spec->>'taxCategory','');
      filter_accounting_category := nullif(rule_row.deterministic_spec->>'accountingCategory','');
      filter_entry_kind := nullif(rule_row.deterministic_spec->>'entryKind','');

      if field_name not in ('gross_amount','net_amount','tax_amount') then
        raise exception 'pandora_tax_rule_unsupported_field' using errcode='22023';
      end if;

      select coalesce(sum(
        case field_name
          when 'gross_amount' then le.gross_amount
          when 'net_amount' then coalesce(le.net_amount,0)
          when 'tax_amount' then coalesce(le.tax_amount,0)
        end
      ),0)::numeric(20,4)
      into amount_value
      from public.tax_ledger_entries le
      where le.organization_id=p_organization_id
        and le.tax_period_id=p_tax_period_id
        and le.treatment_state='verified'
        and (filter_tax_category is null or le.tax_category=filter_tax_category)
        and (filter_accounting_category is null or le.accounting_category=filter_accounting_category)
        and (filter_entry_kind is null or le.entry_kind=filter_entry_kind);

    elsif op='rate' then
      base_line_key := rule_row.deterministic_spec->>'baseLineKey';
      if base_line_key is null
         or (rule_row.deterministic_spec->>'rate') is null
      then
        raise exception 'pandora_tax_rule_invalid_rate' using errcode='22023';
      end if;
      rate_value := (rule_row.deterministic_spec->>'rate')::numeric;
      if rate_value<0 or rate_value>1 then
        raise exception 'pandora_tax_rule_invalid_rate' using errcode='22023';
      end if;
      select amount into base_amount
      from public.tax_calculation_lines
      where calculation_run_id=run_row.id and line_key=base_line_key;
      if base_amount is null then
        raise exception 'pandora_tax_rule_missing_base_line' using errcode='55000';
      end if;
      amount_value := round(base_amount*rate_value,2);

    elsif op='difference' then
      left_line_key := rule_row.deterministic_spec->>'leftLineKey';
      right_line_key := rule_row.deterministic_spec->>'rightLineKey';
      select amount into left_amount
      from public.tax_calculation_lines
      where calculation_run_id=run_row.id and line_key=left_line_key;
      select amount into right_amount
      from public.tax_calculation_lines
      where calculation_run_id=run_row.id and line_key=right_line_key;
      if left_amount is null or right_amount is null then
        raise exception 'pandora_tax_rule_missing_difference_line' using errcode='55000';
      end if;
      amount_value := round(left_amount-right_amount,2);

    elsif op='max_zero' then
      base_line_key := rule_row.deterministic_spec->>'baseLineKey';
      select amount into base_amount
      from public.tax_calculation_lines
      where calculation_run_id=run_row.id and line_key=base_line_key;
      if base_amount is null then
        raise exception 'pandora_tax_rule_missing_base_line' using errcode='55000';
      end if;
      amount_value := greatest(base_amount,0);

    elsif op='fixed' then
      if (rule_row.deterministic_spec->>'amount') is null then
        raise exception 'pandora_tax_rule_invalid_fixed' using errcode='22023';
      end if;
      amount_value := round((rule_row.deterministic_spec->>'amount')::numeric,2);

    elsif op='deadline' then
      amount_value := null;

    else
      raise exception 'pandora_tax_rule_unsupported_operation' using errcode='22023';
    end if;

    insert into public.tax_calculation_lines(
      organization_id,calculation_run_id,line_key,amount,currency_code,
      rule_key,source_refs,calculation_trace
    ) values (
      p_organization_id,run_row.id,line_key_value,amount_value,
      case when amount_value is null then null else
        (select currency_code from public.tax_jurisdictions where code=period_row.jurisdiction_code)
      end,
      rule_row.rule_key,
      jsonb_build_array(jsonb_build_object('ruleId',rule_row.id,'rulePackId',pack.id)),
      jsonb_build_object(
        'operation',op,
        'deterministicSpec',rule_row.deterministic_spec,
        'inputChecksum',input_checksum_value
      )
    );

    line_count := line_count+1;

    obligation_key_value := nullif(rule_row.deterministic_spec->>'obligationKey','');
    if obligation_key_value is not null and amount_value is not null then
      due_days := case
        when (rule_row.deterministic_spec->>'deadlineDaysAfterPeriodEnd') ~ '^[0-9]+$'
          then (rule_row.deterministic_spec->>'deadlineDaysAfterPeriodEnd')::integer
        else null
      end;
      insert into public.tax_obligations(
        organization_id,tax_period_id,calculation_run_id,
        obligation_key,due_date,amount_due,currency_code,status,
        filing_channel,metadata_redacted
      ) values (
        p_organization_id,p_tax_period_id,run_row.id,
        obligation_key_value,
        case when due_days is null then null else period_row.period_end+due_days end,
        amount_value,
        (select currency_code from public.tax_jurisdictions where code=period_row.jurisdiction_code),
        'review_required',
        null,
        jsonb_build_object('ruleKey',rule_row.rule_key,'rulePackVersion',pack.version)
      )
      on conflict (organization_id,tax_period_id,obligation_key)
      do update set
        calculation_run_id=excluded.calculation_run_id,
        due_date=excluded.due_date,
        amount_due=excluded.amount_due,
        status='review_required',
        metadata_redacted=excluded.metadata_redacted,
        updated_at=clock_timestamp();
    end if;
  end loop;

  select encode(
    extensions.digest(
      convert_to(coalesce(string_agg(
        concat_ws('|',line_key,coalesce(amount::text,''),coalesce(currency_code,''),coalesce(rule_key,'')),
        E'\n'
        order by line_key
      ),''),'UTF8'),
      'sha256'
    ),
    'hex'
  )
  into output_checksum_value
  from public.tax_calculation_lines
  where calculation_run_id=run_row.id;

  update public.tax_calculation_runs
  set status='complete',
      output_checksum=output_checksum_value,
      completed_at=clock_timestamp(),
      result_summary=jsonb_build_object(
        'engine','pandora-tax-deterministic-v1',
        'rulePackVersion',pack.version,
        'lineCount',line_count,
        'inputChecksum',input_checksum_value,
        'outputChecksum',output_checksum_value
      )
  where id=run_row.id and organization_id=p_organization_id
  returning * into run_row;

  update public.tax_periods
  set calculation_checksum=output_checksum_value,
      status='review_required',
      updated_at=clock_timestamp()
  where id=p_tax_period_id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,p_tax_period_id,'tax_calculation_completed',uid,'user',
    'pandora_tax_calculate_period_v1',run_row.id::text,
    jsonb_build_object(
      'calculationRunId',run_row.id,
      'rulePackId',pack.id,
      'rulePackVersion',pack.version,
      'inputChecksum',input_checksum_value,
      'outputChecksum',output_checksum_value,
      'lineCount',line_count
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.calculation.v1',
    'calculationRunId',run_row.id,
    'status',run_row.status,
    'rulePackId',pack.id,
    'rulePackVersion',pack.version,
    'inputChecksum',input_checksum_value,
    'outputChecksum',output_checksum_value,
    'lineCount',line_count,
    'filingEnabled',false,
    'paymentEnabled',false
  );
exception
  when others then
    if run_row.id is not null then
      update public.tax_calculation_runs
      set status='failed',
          completed_at=clock_timestamp(),
          result_summary=jsonb_build_object('errorCode',sqlstate)
      where id=run_row.id and organization_id=p_organization_id;
    end if;
    raise;
end;
$$;

revoke all on function public.pandora_tax_calculate_period_v1(uuid,uuid)
  from public,anon;
grant execute on function public.pandora_tax_calculate_period_v1(uuid,uuid)
  to authenticated;

create or replace function public.pandora_tax_build_filing_package_v1(
  p_organization_id uuid,
  p_tax_period_id uuid,
  p_form_key text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  period_row public.tax_periods%rowtype;
  calc public.tax_calculation_runs%rowtype;
  pack public.tax_rule_packs%rowtype;
  latest_recon public.tax_reconciliation_runs%rowtype;
  blocker_count integer := 0;
  version_value integer := 1;
  return_payload jsonb;
  evidence_index jsonb;
  package_hash text;
  return_row public.tax_return_versions%rowtype;
  package_row public.tax_filing_packages%rowtype;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if p_form_key is null or length(btrim(p_form_key)) not between 2 and 80 then
    raise exception 'pandora_tax_form_key_invalid' using errcode='22023';
  end if;

  select * into period_row
  from public.tax_periods
  where id=p_tax_period_id and organization_id=p_organization_id
  for update;
  if period_row.id is null then
    raise exception 'pandora_tax_period_not_found' using errcode='P0002';
  end if;

  select * into calc
  from public.tax_calculation_runs
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status='complete'
  order by completed_at desc nulls last,started_at desc,id desc
  limit 1;
  if calc.id is null then
    raise exception 'pandora_tax_completed_calculation_required' using errcode='55000';
  end if;

  select * into pack
  from public.tax_rule_packs
  where id=calc.rule_pack_id and status='approved';
  if pack.id is null then
    raise exception 'pandora_tax_approved_rule_pack_required' using errcode='55000';
  end if;

  select * into latest_recon
  from public.tax_reconciliation_runs
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status='complete'
  order by completed_at desc nulls last,started_at desc,id desc
  limit 1;
  if latest_recon.id is null then
    raise exception 'pandora_tax_reconciliation_required' using errcode='55000';
  end if;

  select count(*)::integer into blocker_count
  from public.tax_exceptions
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and status in ('open','in_review')
    and severity in ('high','critical');
  if blocker_count>0 then
    raise exception 'pandora_tax_blocking_exceptions' using errcode='55000';
  end if;

  select coalesce(max(version),0)+1 into version_value
  from public.tax_return_versions
  where organization_id=p_organization_id
    and tax_period_id=p_tax_period_id
    and form_key=btrim(p_form_key);

  select jsonb_build_object(
    'schemaVersion','pandora.tax.return-package.v1',
    'organizationId',p_organization_id,
    'taxPeriodId',p_tax_period_id,
    'formKey',btrim(p_form_key),
    'periodStart',period_row.period_start,
    'periodEnd',period_row.period_end,
    'jurisdiction',period_row.jurisdiction_code,
    'rulePack',jsonb_build_object('id',pack.id,'version',pack.version),
    'calculation',jsonb_build_object(
      'id',calc.id,
      'inputChecksum',calc.input_checksum,
      'outputChecksum',calc.output_checksum,
      'lines',coalesce((
        select jsonb_agg(jsonb_build_object(
          'lineKey',cl.line_key,
          'amount',cl.amount,
          'currency',cl.currency_code,
          'ruleKey',cl.rule_key
        ) order by cl.line_key)
        from public.tax_calculation_lines cl
        where cl.calculation_run_id=calc.id
      ),'[]'::jsonb)
    ),
    'reconciliation',jsonb_build_object(
      'runId',latest_recon.id,
      'matchedCount',latest_recon.matched_count,
      'exceptionCount',latest_recon.exception_count
    ),
    'filingAdapterState','disabled',
    'requiresAccountantReview',true,
    'requiresOwnerApproval',true
  )
  into return_payload;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into evidence_index
  from (
    select jsonb_build_object(
      'documentId',d.id,
      'contentSha256',d.content_sha256,
      'documentType',d.document_type,
      'documentDate',d.document_date
    ) as x
    from public.tax_documents d
    where d.organization_id=p_organization_id
      and d.id in (
        select distinct le.document_id
        from public.tax_ledger_entries le
        where le.organization_id=p_organization_id
          and le.tax_period_id=p_tax_period_id
          and le.document_id is not null
      )
    order by d.document_date nulls last,d.id
  ) q;

  package_hash := encode(
    extensions.digest(
      convert_to(return_payload::text||'|'||evidence_index::text||'|'||version_value::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into public.tax_return_versions(
    organization_id,tax_period_id,calculation_run_id,version,form_key,
    status,return_payload_redacted,package_sha256,created_by
  ) values (
    p_organization_id,p_tax_period_id,calc.id,version_value,btrim(p_form_key),
    'review_required',return_payload,package_hash,uid
  )
  returning * into return_row;

  insert into public.tax_return_schedules(
    organization_id,return_version_id,schedule_key,payload_redacted,checksum_sha256
  ) values (
    p_organization_id,return_row.id,'evidence-index',
    jsonb_build_object('documents',evidence_index),
    encode(extensions.digest(convert_to(evidence_index::text,'UTF8'),'sha256'),'hex')
  );

  insert into public.tax_filing_packages(
    organization_id,tax_period_id,calculation_run_id,package_version,
    status,package_sha256,summary_redacted,evidence_index_redacted,
    filing_adapter_state,created_by
  ) values (
    p_organization_id,p_tax_period_id,calc.id,version_value,
    'review_required',package_hash,
    jsonb_build_object(
      'formKey',btrim(p_form_key),
      'returnVersionId',return_row.id,
      'rulePackVersion',pack.version,
      'calculationOutputChecksum',calc.output_checksum,
      'blockingExceptions',blocker_count
    ),
    evidence_index,'disabled',uid
  )
  returning * into package_row;

  update public.tax_periods
  set status='review_required',updated_at=clock_timestamp()
  where id=p_tax_period_id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,p_tax_period_id,'tax_filing_package_built',uid,'user',
    'pandora_tax_build_filing_package_v1',package_row.id::text,
    jsonb_build_object(
      'filingPackageId',package_row.id,
      'returnVersionId',return_row.id,
      'packageVersion',version_value,
      'packageSha256',package_hash,
      'formKey',btrim(p_form_key),
      'filingAdapterState','disabled'
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.filing-package.v1',
    'filingPackageId',package_row.id,
    'returnVersionId',return_row.id,
    'packageVersion',version_value,
    'packageSha256',package_hash,
    'status',package_row.status,
    'requiresAccountantReview',true,
    'requiresOwnerApproval',true,
    'filingEnabled',false,
    'paymentEnabled',false
  );
end;
$$;

revoke all on function public.pandora_tax_build_filing_package_v1(uuid,uuid,text)
  from public,anon;
grant execute on function public.pandora_tax_build_filing_package_v1(uuid,uuid,text)
  to authenticated;

create or replace function public.pandora_tax_record_filing_package_review_v1(
  p_organization_id uuid,
  p_filing_package_id uuid,
  p_reviewer_user_id uuid,
  p_reviewer_role text,
  p_reviewer_credential_ref text,
  p_decision text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  package_row public.tax_filing_packages%rowtype;
  review_row public.tax_reviews%rowtype;
  normalized text := lower(btrim(coalesce(p_decision,'')));
begin
  if p_reviewer_user_id is null
     or p_reviewer_role not in ('cpa','accountant','tax_professional')
     or p_reviewer_credential_ref is null
     or length(btrim(p_reviewer_credential_ref)) not between 3 and 240
     or normalized not in ('approved','changes_requested','rejected')
     or p_notes is null
     or length(btrim(p_notes)) not between 2 and 4000
  then
    raise exception 'pandora_tax_filing_review_invalid' using errcode='22023';
  end if;

  select * into package_row
  from public.tax_filing_packages
  where id=p_filing_package_id and organization_id=p_organization_id
  for update;
  if package_row.id is null then
    raise exception 'pandora_tax_filing_package_not_found' using errcode='P0002';
  end if;
  if package_row.status not in ('review_required','accountant_approved') then
    raise exception 'pandora_tax_filing_package_not_reviewable' using errcode='55000';
  end if;

  insert into public.tax_reviews(
    organization_id,tax_period_id,review_type,status,
    reviewer_user_id,notes,completed_at,professional_credential_ref
  ) values (
    p_organization_id,package_row.tax_period_id,
    case when p_reviewer_role='cpa' then 'cpa' else 'accountant' end,
    case normalized
      when 'approved' then 'approved'
      when 'changes_requested' then 'changes_requested'
      else 'rejected'
    end,
    p_reviewer_user_id,
    btrim(p_notes),
    clock_timestamp(),
    btrim(p_reviewer_credential_ref)
  )
  returning * into review_row;

  update public.tax_filing_packages
  set status=case
        when normalized='approved' then 'accountant_approved'
        else 'review_required'
      end,
      accountant_review_id=review_row.id,
      updated_at=clock_timestamp()
  where id=package_row.id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,package_row.tax_period_id,'tax_filing_package_professional_reviewed',
    p_reviewer_user_id,'accountant',
    'pandora_tax_record_filing_package_review_v1',package_row.id::text,
    jsonb_build_object(
      'filingPackageId',package_row.id,
      'reviewId',review_row.id,
      'reviewerRole',p_reviewer_role,
      'decision',normalized
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.filing-review.v1',
    'filingPackageId',package_row.id,
    'reviewId',review_row.id,
    'decision',normalized,
    'status',(select status from public.tax_filing_packages where id=package_row.id)
  );
end;
$$;

revoke all on function public.pandora_tax_record_filing_package_review_v1(
  uuid,uuid,uuid,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_tax_record_filing_package_review_v1(
  uuid,uuid,uuid,text,text,text,text
) to service_role;

create or replace function public.pandora_tax_approve_filing_package_v1(
  p_organization_id uuid,
  p_filing_package_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  package_row public.tax_filing_packages%rowtype;
  approval_row public.tax_approvals%rowtype;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;

  select * into package_row
  from public.tax_filing_packages
  where id=p_filing_package_id and organization_id=p_organization_id
  for update;
  if package_row.id is null then
    raise exception 'pandora_tax_filing_package_not_found' using errcode='P0002';
  end if;
  if package_row.status<>'accountant_approved'
     or package_row.accountant_review_id is null
  then
    raise exception 'pandora_tax_accountant_approval_required' using errcode='55000';
  end if;

  insert into public.tax_approvals(
    organization_id,tax_period_id,approval_type,status,
    approved_by,approved_at,evidence_refs
  ) values (
    p_organization_id,package_row.tax_period_id,'ready_for_filing','approved',
    uid,clock_timestamp(),
    jsonb_build_array(jsonb_build_object(
      'type','filing_package','id',package_row.id,'sha256',package_row.package_sha256
    ))
  )
  returning * into approval_row;

  update public.tax_filing_packages
  set status='submission_disabled',
      owner_approval_id=approval_row.id,
      updated_at=clock_timestamp()
  where id=package_row.id and organization_id=p_organization_id;

  update public.tax_periods
  set status='ready_for_approval',updated_at=clock_timestamp()
  where id=package_row.tax_period_id and organization_id=p_organization_id;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,package_row.tax_period_id,'tax_filing_package_owner_approved',
    uid,'signatory',
    'pandora_tax_approve_filing_package_v1',package_row.id::text,
    jsonb_build_object(
      'filingPackageId',package_row.id,
      'approvalId',approval_row.id,
      'packageSha256',package_row.package_sha256,
      'filingEnabled',false,
      'paymentEnabled',false
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.filing-approval.v1',
    'filingPackageId',package_row.id,
    'approvalId',approval_row.id,
    'status','submission_disabled',
    'filingEnabled',false,
    'paymentEnabled',false,
    'nextAction','Use a separately verified filing adapter or supervised external filing process.'
  );
end;
$$;

revoke all on function public.pandora_tax_approve_filing_package_v1(uuid,uuid)
  from public,anon;
grant execute on function public.pandora_tax_approve_filing_package_v1(uuid,uuid)
  to authenticated;

create or replace function public.pandora_tax_command_center_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  latest_period jsonb;
  latest_recon jsonb;
  latest_calc jsonb;
  latest_package jsonb;
  evidence_summary jsonb;
  ledger_summary jsonb;
  exception_summary jsonb;
  rule_summary jsonb;
  next_obligation jsonb;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select to_jsonb(x) into latest_period
  from (
    select id,jurisdiction_code,period_type,period_start,period_end,status,
           source_sync_state,rule_pack_id,calculation_checksum,updated_at
    from public.tax_periods
    where organization_id=p_organization_id
    order by period_end desc,updated_at desc,id desc
    limit 1
  ) x;

  select jsonb_build_object(
    'documents',count(*)::integer,
    'verified',count(*) filter (where extraction_state='verified')::integer,
    'needsReview',count(*) filter (where extraction_state='review_required')::integer,
    'pendingOrFailed',count(*) filter (where extraction_state in ('pending','processing','failed'))::integer
  ) into evidence_summary
  from public.tax_documents
  where organization_id=p_organization_id;

  select jsonb_build_object(
    'entries',count(*)::integer,
    'verified',count(*) filter (where treatment_state='verified')::integer,
    'needsReview',count(*) filter (where treatment_state in ('unclassified','suggested','review_required'))::integer,
    'excluded',count(*) filter (where treatment_state='excluded')::integer
  ) into ledger_summary
  from public.tax_ledger_entries
  where organization_id=p_organization_id;

  select jsonb_build_object(
    'open',count(*) filter (where status in ('open','in_review'))::integer,
    'critical',count(*) filter (where status in ('open','in_review') and severity='critical')::integer,
    'high',count(*) filter (where status in ('open','in_review') and severity='high')::integer
  ) into exception_summary
  from public.tax_exceptions
  where organization_id=p_organization_id;

  select jsonb_build_object(
    'jurisdictionStatus',(select status from public.tax_jurisdictions where code='PH'),
    'approvedPackId',(
      select id from public.tax_rule_packs
      where jurisdiction_code='PH' and status='approved'
      order by approved_at desc nulls last,created_at desc limit 1
    ),
    'inReviewPackId',(
      select id from public.tax_rule_packs
      where jurisdiction_code='PH' and status='in_review'
      order by created_at desc limit 1
    ),
    'liveCalculationEnabled',exists(
      select 1 from public.tax_rule_packs
      where jurisdiction_code='PH' and status='approved'
    )
  ) into rule_summary;

  if latest_period is not null then
    select to_jsonb(x) into latest_recon
    from (
      select id,status,matched_count,exception_count,completed_at,summary
      from public.tax_reconciliation_runs
      where organization_id=p_organization_id
        and tax_period_id=(latest_period->>'id')::uuid
      order by started_at desc,id desc
      limit 1
    ) x;

    select to_jsonb(x) into latest_calc
    from (
      select id,status,rule_pack_id,input_checksum,output_checksum,
             result_summary,completed_at
      from public.tax_calculation_runs
      where organization_id=p_organization_id
        and tax_period_id=(latest_period->>'id')::uuid
      order by started_at desc,id desc
      limit 1
    ) x;

    select to_jsonb(x) into latest_package
    from (
      select id,package_version,status,package_sha256,filing_adapter_state,
             accountant_review_id,owner_approval_id,updated_at
      from public.tax_filing_packages
      where organization_id=p_organization_id
        and tax_period_id=(latest_period->>'id')::uuid
      order by package_version desc,id desc
      limit 1
    ) x;
  end if;

  select to_jsonb(x) into next_obligation
  from (
    select id,obligation_key,due_date,amount_due,currency_code,status
    from public.tax_obligations
    where organization_id=p_organization_id
      and status not in ('paid','completed','superseded')
    order by due_date nulls last,created_at,id
    limit 1
  ) x;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.command-center.v1',
    'generatedAt',clock_timestamp(),
    'organizationId',p_organization_id,
    'evidence',evidence_summary,
    'ledger',ledger_summary,
    'exceptions',exception_summary,
    'rules',rule_summary,
    'latestPeriod',latest_period,
    'latestReconciliation',latest_recon,
    'latestCalculation',latest_calc,
    'latestFilingPackage',latest_package,
    'nextObligation',next_obligation,
    'capabilities',jsonb_build_object(
      'preparePeriod',true,
      'evidenceInbox',true,
      'canonicalLedger',true,
      'reconciliation',true,
      'deterministicCalculation',(rule_summary->>'liveCalculationEnabled')::boolean,
      'filingPackage',true,
      'professionalReview',true,
      'ownerApproval',true,
      'filingSubmission',false,
      'paymentExecution',false
    ),
    'nextActions',jsonb_build_array(
      case
        when (rule_summary->>'liveCalculationEnabled')::boolean is false
          then 'Professional review and approval of the current Philippines rule pack is required before live calculation.'
        else 'Prepare or reconcile the active tax period.'
      end,
      'Filing submission and tax payment remain disabled until separate verified adapters exist.'
    )
  );
end;
$$;

revoke all on function public.pandora_tax_command_center_v1(uuid)
  from public,anon;
grant execute on function public.pandora_tax_command_center_v1(uuid)
  to authenticated;

create or replace function private.pandora_tax_chat_persist_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid,
  p_project_id uuid,
  p_reply text,
  p_intent text,
  p_readback jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth'
as $tax_chat_persist$
declare
  uid uuid := auth.uid();
  tid uuid := p_thread_id;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;

  if tid is not null then
    if not exists(
      select 1
      from public.pandora_intelligence_threads t
      where t.id=tid
        and t.organization_id=p_organization_id
        and t.created_by=uid
        and t.status='active'
    ) then
      raise exception 'pandora_tax_thread_not_found' using errcode='P0002';
    end if;
  else
    insert into public.pandora_intelligence_threads(
      organization_id,project_id,created_by,title
    ) values (
      p_organization_id,p_project_id,uid,
      left(regexp_replace(btrim(p_message),'[[:space:]]+',' ','g'),80)
    )
    returning id into tid;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values (
    tid,p_organization_id,p_project_id,'user',p_message,'[]'::jsonb
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,
    structured_response,provider,model
  ) values (
    tid,p_organization_id,p_project_id,'assistant',p_reply,
    jsonb_build_object(
      'intent',p_intent,
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'handoff',null,
      'providerReadback',coalesce(p_readback,'{}'::jsonb)
    ),
    'pandora_tax_runtime','deterministic-tax-runtime-v1'
  );

  update public.pandora_intelligence_threads
  set last_message_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=tid;

  return jsonb_build_object(
    'handled',true,
    'threadId',tid,
    'reply',p_reply,
    'intent',p_intent,
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'conversationLane','tax_compliance',
    'handoff',null,
    'providerReadback',coalesce(p_readback,'{}'::jsonb)
  );
end;
$tax_chat_persist$;

revoke all on function private.pandora_tax_chat_persist_v1(
  uuid,text,uuid,uuid,text,text,jsonb
) from public,anon,authenticated,service_role;

create or replace function private.pandora_tax_chat_dispatch_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth'
as $tax_chat_dispatch$
declare
  norm text := lower(regexp_replace(btrim(coalesce(p_message,'')),'[[:space:]]+',' ','g'));
  center jsonb;
  period_id uuid;
  recon jsonb;
  calc jsonb;
  package_result jsonb;
  obligation jsonb;
  form_key text;
  reply text;
begin
  if auth.uid() is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;

  if not (
    norm ~ '\m(tax|taxes|vat|bir|filing|reconciliation)\M'
    or norm ~ '\m(2550q|2551q|1702q|1702-rt|1601-eq)\M'
  ) then
    return jsonb_build_object('handled',false);
  end if;

  center := public.pandora_tax_command_center_v1(p_organization_id);
  period_id := nullif(center#>>'{latestPeriod,id}','')::uuid;
  obligation := coalesce(center->'nextObligation','{}'::jsonb);

  if norm ~ '\m(file|submit|sign|otp|pay|payment)\M'
     and norm ~ '\m(tax|taxes|vat|bir|return|filing)\M'
  then
    reply := 'Pandora has not submitted or paid anything. Tax filing, signature/OTP, and payment execution remain disabled until a separately verified official filing or payment adapter is available.';
    return private.pandora_tax_chat_persist_v1(
      p_organization_id,p_message,p_thread_id,p_project_id,reply,'tax_guardrail',
      jsonb_build_object(
        'capability','tax.legal_action.guardrail',
        'verified',true,
        'filingEnabled',false,
        'paymentEnabled',false
      )
    );
  end if;

  if norm ~ '\m(reconcile|reconciliation)\M' then
    if period_id is null then
      reply := 'There is no prepared tax period to reconcile yet. Prepare the correct tax period first so Pandora does not assume a filing period.';
      return private.pandora_tax_chat_persist_v1(
        p_organization_id,p_message,p_thread_id,p_project_id,reply,'clarify',
        jsonb_build_object('capability','tax.reconcile','verified',true,'executed',false)
      );
    end if;
    begin
      recon := public.pandora_tax_run_reconciliation_v1(p_organization_id,period_id);
      reply := 'Tax reconciliation finished. Matched: '||
        coalesce(recon->>'matchedCount','0')||
        '. Open exceptions: '||coalesce(recon->>'exceptionCount','0')||
        '. Pandora will not calculate or prepare a filing package until the required review gates are satisfied.';
    exception when others then
      reply := 'Pandora did not complete tax reconciliation because a required control blocked it. No filing or payment action was taken.';
      recon := jsonb_build_object('errorCode',sqlstate,'executed',false);
    end;
    return private.pandora_tax_chat_persist_v1(
      p_organization_id,p_message,p_thread_id,p_project_id,reply,'act',
      jsonb_build_object('capability','tax.reconcile','verified',true,'result',recon)
    );
  end if;

  if norm ~ '\m(calculate|calculation|compute)\M'
     and norm ~ '\m(tax|taxes|vat)\M'
  then
    if period_id is null then
      reply := 'There is no prepared tax period to calculate yet. Pandora will not guess the legal filing period.';
      return private.pandora_tax_chat_persist_v1(
        p_organization_id,p_message,p_thread_id,p_project_id,reply,'clarify',
        jsonb_build_object('capability','tax.calculate','verified',true,'executed',false)
      );
    end if;
    if coalesce((center#>>'{rules,liveCalculationEnabled}')::boolean,false) is false then
      reply := 'Live tax calculation is still locked because no professionally approved Philippines rule pack is active. The current draft rules cannot be used as authoritative tax output.';
      return private.pandora_tax_chat_persist_v1(
        p_organization_id,p_message,p_thread_id,p_project_id,reply,'tax_guardrail',
        jsonb_build_object('capability','tax.calculate','verified',true,'executed',false,'rulePackApproved',false)
      );
    end if;
    begin
      calc := public.pandora_tax_calculate_period_v1(p_organization_id,period_id);
      reply := 'The deterministic tax calculation completed from the approved rule pack and reconciled ledger. Calculation run: '||
        coalesce(calc->>'calculationRunId','unknown')||
        '. Filing and payment remain disabled.';
    exception when others then
      reply := 'Pandora did not calculate taxes because a required reconciliation, evidence, rule, or exception control blocked the run. No filing or payment action was taken.';
      calc := jsonb_build_object('errorCode',sqlstate,'executed',false);
    end;
    return private.pandora_tax_chat_persist_v1(
      p_organization_id,p_message,p_thread_id,p_project_id,reply,'act',
      jsonb_build_object('capability','tax.calculate','verified',true,'result',calc)
    );
  end if;

  if norm ~ '\m(prepare|build|create)\M'
     and norm ~ '\m(filing|return|package)\M'
  then
    form_key := upper((regexp_match(norm,'(2550q|2551q|1702q|1702-rt|1601-eq)'))[1]);
    if period_id is null then
      reply := 'There is no prepared tax period to package yet. Prepare and reconcile the correct period first.';
      return private.pandora_tax_chat_persist_v1(
        p_organization_id,p_message,p_thread_id,p_project_id,reply,'clarify',
        jsonb_build_object('capability','tax.filing-package.prepare','verified',true,'executed',false)
      );
    end if;
    if form_key is null then
      reply := 'Tell me the exact return form you want prepared, such as 2550Q, 2551Q, 1702Q, 1702-RT, or 1601-EQ. Pandora will not guess the legal form.';
      return private.pandora_tax_chat_persist_v1(
        p_organization_id,p_message,p_thread_id,p_project_id,reply,'clarify',
        jsonb_build_object('capability','tax.filing-package.prepare','verified',true,'executed',false)
      );
    end if;
    begin
      package_result := public.pandora_tax_build_filing_package_v1(
        p_organization_id,period_id,form_key
      );
      reply := form_key||' review package prepared. It still requires professional review and owner approval. Submission and payment remain disabled.';
    exception when others then
      reply := 'Pandora did not build the filing package because a required calculation, reconciliation, evidence, or rule control is not satisfied. Nothing was filed or paid.';
      package_result := jsonb_build_object('errorCode',sqlstate,'executed',false);
    end;
    return private.pandora_tax_chat_persist_v1(
      p_organization_id,p_message,p_thread_id,p_project_id,reply,'act',
      jsonb_build_object('capability','tax.filing-package.prepare','verified',true,'formKey',form_key,'result',package_result)
    );
  end if;

  if jsonb_typeof(obligation)='object' and coalesce(obligation->>'id','')<>'' then
    reply := 'Tax command center is live. The next recorded obligation is '||
      coalesce(obligation->>'obligation_key','tax obligation')||
      case when obligation->>'amount_due' is null then ''
        else ' for '||coalesce(obligation->>'currency_code','')||' '||obligation->>'amount_due'
      end||
      case when obligation->>'due_date' is null then ''
        else ', due '||obligation->>'due_date'
      end||
      '. Filing and payment are not automatic.';
  else
    reply := case
      when coalesce((center#>>'{rules,liveCalculationEnabled}')::boolean,false)
        then 'Tax command center is live. Review the active period, evidence, ledger treatment, reconciliation exceptions, and the approved deterministic calculation before any filing decision.'
      else 'Tax command center is live, but live Philippines tax calculation is still locked pending professional approval of the rule pack. Evidence, ledger and reconciliation work can continue safely.'
    end;
  end if;

  return private.pandora_tax_chat_persist_v1(
    p_organization_id,p_message,p_thread_id,p_project_id,reply,'read',
    jsonb_build_object('capability','tax.command-center.read','verified',true,'snapshot',center)
  );
end;
$tax_chat_dispatch$;

revoke all on function private.pandora_tax_chat_dispatch_v1(uuid,text,uuid,uuid)
  from public,anon,authenticated,service_role;

-- Extend the active universal chat dispatcher with guarded tax operations.
create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth','pg_temp'
as $tax_universal_dispatch$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_direct_action boolean := false;
  v_plp_explicit boolean := false;
  v_box_explicit boolean := false;
  v_plp_context boolean := false;
  v_box_context boolean := false;
  v_tax_operation boolean := false;
  v_tax jsonb;
  v_capability jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;

  if v_norm='' or length(v_norm)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_direct_action := v_norm ~ '\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|refactor|rewrite|finish|complete|make)\M';
  v_plp_explicit := v_norm ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M';
  v_box_explicit := v_norm ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo|this[[:space:]]+repo)\M';
  v_tax_operation := (
    v_norm ~ '\m(2550q|2551q|1702q|1702-rt|1601-eq)\M'
    or (
      v_norm ~ '\m(tax|taxes|vat|bir)\M'
      and v_norm ~ '\m(status|overview|position|ready|owe|due|reconcile|reconciliation|calculate|calculation|compute|file|filing|submit|sign|otp|pay|payment|prepare|build|create|package|return)\M'
    )
  );

  if v_tax_operation then
    v_tax := private.pandora_tax_chat_dispatch_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
    if coalesce((v_tax->>'handled')::boolean,false) then
      return v_tax;
    end if;
  end if;

  if p_thread_id is not null and (not v_plp_explicit or not v_box_explicit) then
    select
      coalesce(bool_or(lower(recent.content) ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M'),false),
      coalesce(bool_or(lower(recent.content) ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo)\M'),false)
    into v_plp_context,v_box_context
    from (
      select m.content
      from public.pandora_intelligence_messages m
      join public.pandora_intelligence_threads t on t.id=m.thread_id
      where m.thread_id=p_thread_id
        and m.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
      order by m.created_at desc
      limit 12
    ) recent;
  end if;

  if v_direct_action and (v_plp_explicit or (v_plp_context and not v_box_explicit)) then
    return private.pandora_direct_plp_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  if v_direct_action and (v_box_explicit or v_box_context) then
    return private.pandora_direct_box_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  v_capability := public.pandora_chat_capability_dispatch_native_v1(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
  if coalesce((v_capability->>'handled')::boolean,false) then
    return v_capability;
  end if;

  return jsonb_build_object(
    'handled',false,
    'routing','pandora_native_intelligence',
    'projectId',p_project_id,
    'projectRequired',false,
    'requestMode','intelligence'
  );
end;
$tax_universal_dispatch$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  to authenticated;

-- Philippines 2026 authoritative draft pack.
-- This is intentionally IN_REVIEW: source capture is not professional approval.
insert into public.tax_rule_packs(
  jurisdiction_code,version,status,effective_from,effective_to,
  official_sources,review_notes
)
select
  'PH','ph-2026-authoritative-draft-v1','in_review','2026-01-01','2026-12-31',
  jsonb_build_array(
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','BIR Form 2550Q Guidelines and Instructions',
      'url','https://efps.bir.gov.ph/efps-war/EFPSWeb_war/help/help2550q2006.html',
      'capturedOn','2026-09-25'
    ),
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','BIR Form 2551Q Guidelines and Instructions',
      'url','https://efps.bir.gov.ph/efps-war/EFPSWeb_war/forms2018Version/2551Q/2551q_guidelines.html',
      'capturedOn','2026-09-25'
    ),
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','RMC No. 3-2024 Annex A / Section 116',
      'url','https://bir-cdn.bir.gov.ph/local/pdf/RMC%20No.%203-2024%20Annex%20A.pdf',
      'capturedOn','2026-09-25'
    ),
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','BIR Form 1702-RT / 1702Q information',
      'url','https://www.bir.gov.ph/bir-forms',
      'capturedOn','2026-09-25'
    ),
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','BIR Form 1601-EQ Guidelines',
      'url','https://efps.bir.gov.ph/efps-war/forms2018Version/1601EQ/1601eq_guidelines.html',
      'capturedOn','2026-09-25'
    ),
    jsonb_build_object(
      'authority','Bureau of Internal Revenue',
      'title','RMC No. 89-2021 / CREATE corporate income tax rates',
      'url','https://bir-cdn.bir.gov.ph/local/pdf/RMC%20No.%2089-2021.pdf',
      'capturedOn','2026-09-25'
    )
  ),
  'Authoritative-source draft only. Requires CPA/tax-professional review plus passing rule tests before approval.'
where not exists (
  select 1 from public.tax_rule_packs
  where jurisdiction_code='PH' and version='ph-2026-authoritative-draft-v1'
);

insert into public.tax_rule_sources(
  rule_pack_id,source_key,authority,title,source_url,published_on,retrieved_on,source_scope,notes
)
select rp.id,v.source_key,'Bureau of Internal Revenue',v.title,v.url,v.published_on,'2026-09-25','official',v.notes
from public.tax_rule_packs rp
cross join (
  values
    ('bir-2550q','BIR Form 2550Q Guidelines and Instructions','https://efps.bir.gov.ph/efps-war/help/help2550q2006.html',null::date,'Official BIR source states 12% VAT on taxable sales/services/imports and quarterly filing within 25 days after quarter close.'),
    ('bir-2551q','BIR Form 2551Q Guidelines and Instructions','https://efps.bir.gov.ph/efps-war/EFPSWeb_war/forms2018Version/2551Q/2551q_guidelines.html',null::date,'Official BIR 2551Q guidance covers quarterly percentage-tax filing and taxpayer applicability; application still requires taxpayer-profile review.'),
    ('bir-rmc-3-2024-annex-a','RMC No. 3-2024 Annex A / Section 116','https://bir-cdn.bir.gov.ph/local/pdf/RMC%20No.%203-2024%20Annex%20A.pdf',null::date,'Official BIR circular text states Section 116 percentage tax at three percent of gross quarterly sales for qualifying non-VAT persons.'),
    ('bir-1702','BIR corporate income tax forms','https://www.bir.gov.ph/bir-forms',null::date,'Official BIR forms page identifies 25% regular corporate rate and 20% rate for qualifying small corporations, and 1702Q within 60 days after first three quarters.'),
    ('bir-1601eq','BIR Form 1601-EQ Guidelines','https://efps.bir.gov.ph/efps-war/forms2018Version/1601EQ/1601eq_guidelines.html',null::date,'Official BIR guidance states 1601-EQ is due not later than the last day of the month following quarter close.'),
    ('bir-create','RMC No. 89-2021 - CREATE','https://bir-cdn.bir.gov.ph/local/pdf/RMC%20No.%2089-2021.pdf','2021-07-19'::date,'Official BIR circularizes CREATE corporate income tax rate changes.')
) as v(source_key,title,url,published_on,notes)
where rp.jurisdiction_code='PH'
  and rp.version='ph-2026-authoritative-draft-v1'
on conflict (rule_pack_id,source_key) do nothing;

insert into public.tax_rules(
  rule_pack_id,rule_key,rule_type,deterministic_spec,official_source_ref,effective_from,effective_to
)
select rp.id,v.rule_key,v.rule_type,v.spec,v.source_ref,'2026-01-01','2026-12-31'
from public.tax_rule_packs rp
cross join (
  values
    (
      'ph.vat.taxable_sales_base','formula',
      '{"operation":"sum","sequence":10,"lineKey":"vat_taxable_sales","field":"net_amount","taxCategory":"vat_taxable_sale","periodTypes":["quarterly"]}'::jsonb,
      '{"sourceRef":"bir-2550q","statement":"Taxable sale/service base for standard VAT draft rule."}'::jsonb
    ),
    (
      'ph.vat.output_tax_12','rate',
      '{"operation":"rate","sequence":20,"lineKey":"output_vat","baseLineKey":"vat_taxable_sales","rate":0.12,"obligationKey":"vat_output_tax","deadlineDaysAfterPeriodEnd":25,"periodTypes":["quarterly"]}'::jsonb,
      '{"sourceRef":"bir-2550q","statement":"Official BIR 2550Q guidance states 12% VAT and quarterly filing within 25 days after quarter close."}'::jsonb
    ),
    (
      'ph.percentage_tax.sales_base','formula',
      '{"operation":"sum","sequence":30,"lineKey":"percentage_tax_sales","field":"gross_amount","taxCategory":"percentage_taxable_sale","periodTypes":["quarterly"]}'::jsonb,
      '{"sourceRef":"bir-2551q","statement":"Percentage-tax base is a separate draft category. Taxpayer registration and Section 116 applicability require professional review before approval."}'::jsonb
    ),
    (
      'ph.percentage_tax.standard_3','rate',
      '{"operation":"rate","sequence":40,"lineKey":"percentage_tax_due","baseLineKey":"percentage_tax_sales","rate":0.03,"obligationKey":"percentage_tax","deadlineDaysAfterPeriodEnd":25,"periodTypes":["quarterly"]}'::jsonb,
      '{"sourceRef":"bir-rmc-3-2024-annex-a","statement":"Draft 3% Section 116 rule. Eligibility, VAT status, and any elective income-tax treatment must be professionally confirmed before approval."}'::jsonb
    ),
    (
      'ph.cit.taxable_income_base','formula',
      '{"operation":"sum","sequence":50,"lineKey":"corporate_taxable_income","field":"net_amount","taxCategory":"corporate_taxable_income","periodTypes":["quarterly"]}'::jsonb,
      '{"sourceRef":"bir-create","statement":"Draft corporate taxable-income base category; accounting mapping requires professional review."}'::jsonb
    ),
    (
      'ph.cit.general_25','rate',
      '{"operation":"rate","sequence":60,"lineKey":"corporate_income_tax_general","baseLineKey":"corporate_taxable_income","rate":0.25,"obligationKey":"corporate_income_tax","deadlineDaysAfterPeriodEnd":60,"periodTypes":["quarterly"],"eligibility":"regular_corporation_not_qualifying_for_20_percent_rate"}'::jsonb,
      '{"sourceRef":"bir-1702","statement":"Official BIR corporate forms describe the regular 25% rate; small-corporation eligibility is separate and must be reviewed."}'::jsonb
    )
) as v(rule_key,rule_type,spec,source_ref)
where rp.jurisdiction_code='PH'
  and rp.version='ph-2026-authoritative-draft-v1'
on conflict (rule_pack_id,rule_key) do nothing;

insert into public.tax_rule_tests(
  rule_pack_id,test_key,rule_key,input_fixture,expected_output,status,last_result,last_run_at
)
select rp.id,v.test_key,v.rule_key,v.input_fixture,v.expected_output,'pending',null,null
from public.tax_rule_packs rp
cross join (
  values
    ('vat-base-1000','ph.vat.taxable_sales_base','{"values":[600.00,400.00]}'::jsonb,'{"amount":1000.00}'::jsonb),
    ('vat-rate-1000','ph.vat.output_tax_12','{"base":1000.00}'::jsonb,'{"amount":120.00}'::jsonb),
    ('percentage-base-1000','ph.percentage_tax.sales_base','{"values":[700.00,300.00]}'::jsonb,'{"amount":1000.00}'::jsonb),
    ('percentage-rate-1000','ph.percentage_tax.standard_3','{"base":1000.00}'::jsonb,'{"amount":30.00}'::jsonb),
    ('cit-base-1000','ph.cit.taxable_income_base','{"values":[1200.00,-200.00]}'::jsonb,'{"amount":1000.00}'::jsonb),
    ('cit-general-1000','ph.cit.general_25','{"base":1000.00}'::jsonb,'{"amount":250.00}'::jsonb)
) as v(test_key,rule_key,input_fixture,expected_output)
where rp.jurisdiction_code='PH'
  and rp.version='ph-2026-authoritative-draft-v1'
on conflict (rule_pack_id,test_key) do nothing;

update public.tax_jurisdictions
set source_policy=jsonb_build_object(
      'policy','authoritative_source_and_professional_review_required',
      'ratesEmbedded',true,
      'embeddedPackStatus','in_review',
      'draftPackVersion','ph-2026-authoritative-draft-v1',
      'liveCalculationEnabled',exists(
        select 1 from public.tax_rule_packs
        where jurisdiction_code='PH' and status='approved'
      ),
      'sourceSnapshotDate','2026-09-25'
    ),
    updated_at=clock_timestamp()
where code='PH' and status='draft';

comment on function public.pandora_tax_calculate_period_v1(uuid,uuid) is
  'Deterministic tax calculator. It refuses unapproved rule packs, blocking exceptions, and unverified ledger entries.';
comment on function public.pandora_tax_build_filing_package_v1(uuid,uuid,text) is
  'Builds a review package only. It does not file, sign, submit, or pay tax.';
comment on function public.pandora_tax_command_center_v1(uuid) is
  'Tax command-center projection for the authenticated owner/admin data plane.';
