-- Pandora Tax & Compliance Operating System foundation v1.
-- Owner-approved architecture: pandoras-box-memory/docs/roadmap/PANDORA_TAX_COMPLIANCE_OPERATING_SYSTEM_MASTER_PLAN_V1.md
--
-- Safety boundary:
-- * no tax rates are hard-coded here;
-- * rule packs begin unapproved;
-- * authenticated clients receive read-only organization-scoped access;
-- * material writes flow through bounded RPCs or service_role;
-- * filing and payment are intentionally not enabled by this migration;
-- * audit events are append-only.

create table if not exists public.tax_jurisdictions (
  code text primary key,
  display_name text not null,
  currency_code text not null,
  status text not null default 'draft'
    check (status in ('draft','active','retired')),
  source_policy jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.tax_rule_packs (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.tax_jurisdictions(code) on delete restrict,
  version text not null,
  status text not null default 'draft'
    check (status in ('draft','in_review','approved','superseded','rejected')),
  effective_from date,
  effective_to date,
  official_sources jsonb not null default '[]'::jsonb,
  review_notes text,
  reviewed_by uuid,
  approved_at timestamptz,
  superseded_by uuid references public.tax_rule_packs(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (jurisdiction_code,version),
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (
    (status <> 'approved')
    or (
      approved_at is not null
      and jsonb_typeof(official_sources)='array'
      and jsonb_array_length(official_sources)>0
    )
  )
);

create table if not exists public.tax_rules (
  id uuid primary key default gen_random_uuid(),
  rule_pack_id uuid not null references public.tax_rule_packs(id) on delete cascade,
  rule_key text not null,
  rule_type text not null
    check (rule_type in ('rate','threshold','formula','eligibility','deadline','classification','carryover','rounding','validation')),
  deterministic_spec jsonb not null,
  official_source_ref jsonb not null,
  effective_from date,
  effective_to date,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (rule_pack_id,rule_key),
  check (effective_to is null or effective_from is null or effective_to >= effective_from)
);

create table if not exists public.tax_source_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null,
  connection_key text not null,
  capability_state text not null default 'configured'
    check (capability_state in ('configured','connecting','healthy','stale','error','revoked')),
  granted_scopes jsonb not null default '[]'::jsonb,
  last_synced_at timestamptz,
  last_error_code text,
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,provider,connection_key),
  unique (id,organization_id)
);

create table if not exists public.tax_source_objects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid,
  source_object_id text not null,
  object_type text not null,
  source_observed_at timestamptz not null,
  content_sha256 text not null
    check (content_sha256 ~ '^[0-9a-f]{64}$'),
  source_locator text,
  payload_metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,source_object_id,content_sha256),
  unique (id,organization_id),
  constraint tax_source_objects_connection_org_fkey
    foreign key (source_connection_id,organization_id)
    references public.tax_source_connections(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_object_id uuid,
  document_type text not null,
  document_date date,
  content_sha256 text not null
    check (content_sha256 ~ '^[0-9a-f]{64}$'),
  storage_bucket text,
  storage_path text,
  extraction_state text not null default 'pending'
    check (extraction_state in ('pending','processing','review_required','verified','failed')),
  extraction_confidence numeric(5,4)
    check (extraction_confidence is null or extraction_confidence between 0 and 1),
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,content_sha256),
  unique (id,organization_id),
  constraint tax_documents_source_org_fkey
    foreign key (source_object_id,organization_id)
    references public.tax_source_objects(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  jurisdiction_code text not null references public.tax_jurisdictions(code) on delete restrict,
  period_type text not null
    check (period_type in ('monthly','quarterly','annual','custom')),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft'
    check (status in (
      'draft','data_incomplete','reconciling','review_required',
      'ready_for_approval','approved_for_filing','submitted',
      'accepted','paid','completed','amended','superseded'
    )),
  source_sync_state text not null default 'not_started'
    check (source_sync_state in ('not_started','running','complete','partial','failed','waived')),
  rule_pack_id uuid references public.tax_rule_packs(id) on delete restrict,
  calculation_checksum text
    check (calculation_checksum is null or calculation_checksum ~ '^[0-9a-f]{64}$'),
  created_by uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,jurisdiction_code,period_type,period_start,period_end),
  unique (id,organization_id),
  check (period_end >= period_start)
);

create table if not exists public.tax_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid,
  source_object_id uuid,
  document_id uuid,
  transaction_date date not null,
  counterparty_ref text,
  currency_code text not null,
  gross_amount numeric(20,4) not null,
  net_amount numeric(20,4),
  tax_amount numeric(20,4),
  accounting_category text,
  tax_category text,
  business_purpose text,
  treatment_state text not null default 'unclassified'
    check (treatment_state in ('unclassified','suggested','review_required','verified','excluded')),
  classification_confidence numeric(5,4)
    check (classification_confidence is null or classification_confidence between 0 and 1),
  rule_pack_id uuid references public.tax_rule_packs(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  constraint tax_ledger_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete restrict,
  constraint tax_ledger_source_org_fkey
    foreign key (source_object_id,organization_id)
    references public.tax_source_objects(id,organization_id)
    on delete restrict,
  constraint tax_ledger_document_org_fkey
    foreign key (document_id,organization_id)
    references public.tax_documents(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  status text not null default 'running'
    check (status in ('running','complete','partial','failed')),
  matched_count integer not null default 0 check (matched_count >= 0),
  exception_count integer not null default 0 check (exception_count >= 0),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  unique (id,organization_id),
  constraint tax_reconciliation_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade
);

create table if not exists public.tax_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid,
  ledger_entry_id uuid,
  exception_type text not null
    check (exception_type in (
      'missing_receipt','duplicate_invoice','unmatched_payment','tax_id_mismatch',
      'missing_withholding_certificate','unknown_tax_category','rule_ambiguity',
      'period_mismatch','currency_mismatch','filing_mismatch','payment_mismatch',
      'provider_error','stale_tax_rule','professional_judgment_required'
    )),
  severity text not null default 'medium'
    check (severity in ('low','medium','high','critical')),
  amount_at_risk numeric(20,4),
  due_at timestamptz,
  status text not null default 'open'
    check (status in ('open','in_review','resolved','waived','superseded')),
  recommended_next_action text,
  evidence_refs jsonb not null default '[]'::jsonb,
  resolution jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  constraint tax_exceptions_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade,
  constraint tax_exceptions_ledger_org_fkey
    foreign key (ledger_entry_id,organization_id)
    references public.tax_ledger_entries(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_calculation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  rule_pack_id uuid not null references public.tax_rule_packs(id) on delete restrict,
  status text not null default 'running'
    check (status in ('running','complete','blocked','failed','superseded')),
  input_checksum text not null
    check (input_checksum ~ '^[0-9a-f]{64}$'),
  output_checksum text
    check (output_checksum is null or output_checksum ~ '^[0-9a-f]{64}$'),
  assumptions jsonb not null default '[]'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique (id,organization_id),
  constraint tax_calculation_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade
);

create table if not exists public.tax_calculation_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  calculation_run_id uuid not null,
  line_key text not null,
  amount numeric(20,4),
  currency_code text,
  rule_key text,
  source_refs jsonb not null default '[]'::jsonb,
  calculation_trace jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (calculation_run_id,line_key),
  constraint tax_calculation_lines_run_org_fkey
    foreign key (calculation_run_id,organization_id)
    references public.tax_calculation_runs(id,organization_id)
    on delete cascade
);

create table if not exists public.tax_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  calculation_run_id uuid,
  obligation_key text not null,
  due_date date,
  amount_due numeric(20,4),
  currency_code text not null,
  status text not null default 'estimated'
    check (status in ('estimated','review_required','ready_for_approval','approved','submitted','accepted','paid','completed','superseded')),
  filing_channel text,
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,tax_period_id,obligation_key),
  unique (id,organization_id),
  constraint tax_obligations_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade,
  constraint tax_obligations_calc_org_fkey
    foreign key (calculation_run_id,organization_id)
    references public.tax_calculation_runs(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  review_type text not null
    check (review_type in ('internal','accountant','cpa','signatory','audit')),
  status text not null default 'requested'
    check (status in ('requested','in_review','changes_requested','approved','rejected','superseded')),
  reviewer_user_id uuid,
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique (id,organization_id),
  constraint tax_reviews_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade
);

create table if not exists public.tax_approvals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  tax_period_id uuid not null,
  approval_type text not null
    check (approval_type in ('ready_for_filing','filing','payment','amendment','material_adjustment')),
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','expired','superseded')),
  approved_by uuid,
  approved_at timestamptz,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  constraint tax_approvals_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete cascade,
  check (
    (status='approved' and approved_by is not null and approved_at is not null)
    or status<>'approved'
  )
);

create table if not exists public.tax_audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  tax_period_id uuid,
  event_type text not null,
  actor_user_id uuid,
  actor_type text not null
    check (actor_type in ('user','system','provider','accountant','signatory')),
  source_type text not null,
  source_ref text,
  event_payload_redacted jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  constraint tax_audit_period_org_fkey
    foreign key (tax_period_id,organization_id)
    references public.tax_periods(id,organization_id)
    on delete restrict
);

create or replace function private.pandora_tax_rule_pack_immutability_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $tax_rule_pack_guard$
begin
  if tg_op='DELETE' then
    if old.status in ('approved','superseded') then
      raise exception 'approved tax rule packs are immutable history' using errcode='42501';
    end if;
    return old;
  end if;

  if old.status='superseded' then
    raise exception 'superseded tax rule packs are immutable history' using errcode='42501';
  end if;

  if old.status='approved' then
    if new.status='superseded'
       and new.superseded_by is not null
       and new.jurisdiction_code is not distinct from old.jurisdiction_code
       and new.version is not distinct from old.version
       and new.effective_from is not distinct from old.effective_from
       and new.effective_to is not distinct from old.effective_to
       and new.official_sources is not distinct from old.official_sources
       and new.review_notes is not distinct from old.review_notes
       and new.reviewed_by is not distinct from old.reviewed_by
       and new.approved_at is not distinct from old.approved_at
       and new.created_at is not distinct from old.created_at
    then
      return new;
    end if;
    raise exception 'approved tax rule packs may only transition immutably to superseded' using errcode='42501';
  end if;

  return new;
end;
$tax_rule_pack_guard$;

create or replace function private.pandora_tax_rule_immutability_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $tax_rule_guard$
declare
  pack_id uuid;
  pack_status text;
begin
  pack_id := case when tg_op='DELETE' then old.rule_pack_id else new.rule_pack_id end;

  select rp.status into pack_status
  from public.tax_rule_packs rp
  where rp.id=pack_id;

  if pack_status in ('approved','superseded') then
    raise exception 'tax rules in approved or superseded packs are immutable' using errcode='42501';
  end if;

  if tg_op='DELETE' then
    return old;
  end if;
  return new;
end;
$tax_rule_guard$;

drop trigger if exists pandora_tax_rule_pack_immutability_v1 on public.tax_rule_packs;
create trigger pandora_tax_rule_pack_immutability_v1
before update or delete on public.tax_rule_packs
for each row execute function private.pandora_tax_rule_pack_immutability_v1();

drop trigger if exists pandora_tax_rule_immutability_v1 on public.tax_rules;
create trigger pandora_tax_rule_immutability_v1
before insert or update or delete on public.tax_rules
for each row execute function private.pandora_tax_rule_immutability_v1();

revoke all on function private.pandora_tax_rule_pack_immutability_v1()
  from public,anon,authenticated,service_role;
revoke all on function private.pandora_tax_rule_immutability_v1()
  from public,anon,authenticated,service_role;

create index if not exists tax_rule_packs_lookup_idx
  on public.tax_rule_packs(jurisdiction_code,status,effective_from,effective_to);
create index if not exists tax_rules_pack_idx
  on public.tax_rules(rule_pack_id,rule_key);
create index if not exists tax_source_connections_org_idx
  on public.tax_source_connections(organization_id,capability_state);
create index if not exists tax_source_objects_org_observed_idx
  on public.tax_source_objects(organization_id,source_observed_at desc);
create index if not exists tax_documents_org_date_idx
  on public.tax_documents(organization_id,document_date desc);
create index if not exists tax_periods_org_status_idx
  on public.tax_periods(organization_id,status,period_end desc);
create index if not exists tax_ledger_org_period_date_idx
  on public.tax_ledger_entries(organization_id,tax_period_id,transaction_date desc);
create index if not exists tax_exceptions_open_idx
  on public.tax_exceptions(organization_id,status,severity,due_at)
  where status in ('open','in_review');
create index if not exists tax_calculation_runs_period_idx
  on public.tax_calculation_runs(organization_id,tax_period_id,started_at desc);
create index if not exists tax_obligations_due_idx
  on public.tax_obligations(organization_id,status,due_date);
create index if not exists tax_reviews_period_idx
  on public.tax_reviews(organization_id,tax_period_id,status);
create index if not exists tax_approvals_period_idx
  on public.tax_approvals(organization_id,tax_period_id,status);
create index if not exists tax_audit_events_org_time_idx
  on public.tax_audit_events(organization_id,occurred_at desc,id desc);

insert into public.tax_jurisdictions(code,display_name,currency_code,status,source_policy)
values (
  'PH',
  'Philippines',
  'PHP',
  'draft',
  jsonb_build_object(
    'policy','authoritative_source_and_professional_review_required',
    'ratesEmbedded',false,
    'liveCalculationEnabled',false
  )
)
on conflict (code) do update
set display_name=excluded.display_name,
    currency_code=excluded.currency_code,
    source_policy=excluded.source_policy,
    updated_at=clock_timestamp()
where public.tax_jurisdictions.status='draft';

create or replace function public.pandora_tax_can_read_org_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
  select exists(
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
  )
$$;

create or replace function public.pandora_tax_can_manage_org_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
  select exists(
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
      and lower(m.role::text) in ('owner','admin')
  )
$$;

revoke all on function public.pandora_tax_can_read_org_v1(uuid) from public,anon;
revoke all on function public.pandora_tax_can_manage_org_v1(uuid) from public,anon;
grant execute on function public.pandora_tax_can_read_org_v1(uuid) to authenticated,service_role;
grant execute on function public.pandora_tax_can_manage_org_v1(uuid) to authenticated,service_role;

alter table public.tax_jurisdictions enable row level security;
alter table public.tax_rule_packs enable row level security;
alter table public.tax_rules enable row level security;
alter table public.tax_source_connections enable row level security;
alter table public.tax_source_objects enable row level security;
alter table public.tax_documents enable row level security;
alter table public.tax_periods enable row level security;
alter table public.tax_ledger_entries enable row level security;
alter table public.tax_reconciliation_runs enable row level security;
alter table public.tax_exceptions enable row level security;
alter table public.tax_calculation_runs enable row level security;
alter table public.tax_calculation_lines enable row level security;
alter table public.tax_obligations enable row level security;
alter table public.tax_reviews enable row level security;
alter table public.tax_approvals enable row level security;
alter table public.tax_audit_events enable row level security;

drop policy if exists tax_jurisdictions_authenticated_read on public.tax_jurisdictions;
create policy tax_jurisdictions_authenticated_read
on public.tax_jurisdictions for select to authenticated
using (status='active');

drop policy if exists tax_rule_packs_authenticated_read on public.tax_rule_packs;
create policy tax_rule_packs_authenticated_read
on public.tax_rule_packs for select to authenticated
using (status='approved');

drop policy if exists tax_rules_authenticated_read on public.tax_rules;
create policy tax_rules_authenticated_read
on public.tax_rules for select to authenticated
using (
  exists(
    select 1 from public.tax_rule_packs rp
    where rp.id=tax_rules.rule_pack_id
      and rp.status='approved'
  )
);

drop policy if exists tax_source_connections_org_read on public.tax_source_connections;
create policy tax_source_connections_org_read
on public.tax_source_connections for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_source_objects_org_read on public.tax_source_objects;
create policy tax_source_objects_org_read
on public.tax_source_objects for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_documents_org_read on public.tax_documents;
create policy tax_documents_org_read
on public.tax_documents for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_periods_org_read on public.tax_periods;
create policy tax_periods_org_read
on public.tax_periods for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_ledger_entries_org_read on public.tax_ledger_entries;
create policy tax_ledger_entries_org_read
on public.tax_ledger_entries for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_reconciliation_runs_org_read on public.tax_reconciliation_runs;
create policy tax_reconciliation_runs_org_read
on public.tax_reconciliation_runs for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_exceptions_org_read on public.tax_exceptions;
create policy tax_exceptions_org_read
on public.tax_exceptions for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_calculation_runs_org_read on public.tax_calculation_runs;
create policy tax_calculation_runs_org_read
on public.tax_calculation_runs for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_calculation_lines_org_read on public.tax_calculation_lines;
create policy tax_calculation_lines_org_read
on public.tax_calculation_lines for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_obligations_org_read on public.tax_obligations;
create policy tax_obligations_org_read
on public.tax_obligations for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_reviews_org_read on public.tax_reviews;
create policy tax_reviews_org_read
on public.tax_reviews for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_approvals_org_read on public.tax_approvals;
create policy tax_approvals_org_read
on public.tax_approvals for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_audit_events_org_read on public.tax_audit_events;
create policy tax_audit_events_org_read
on public.tax_audit_events for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

revoke all on table public.tax_jurisdictions from public,anon,authenticated;
revoke all on table public.tax_rule_packs from public,anon,authenticated;
revoke all on table public.tax_rules from public,anon,authenticated;
revoke all on table public.tax_source_connections from public,anon,authenticated;
revoke all on table public.tax_source_objects from public,anon,authenticated;
revoke all on table public.tax_documents from public,anon,authenticated;
revoke all on table public.tax_periods from public,anon,authenticated;
revoke all on table public.tax_ledger_entries from public,anon,authenticated;
revoke all on table public.tax_reconciliation_runs from public,anon,authenticated;
revoke all on table public.tax_exceptions from public,anon,authenticated;
revoke all on table public.tax_calculation_runs from public,anon,authenticated;
revoke all on table public.tax_calculation_lines from public,anon,authenticated;
revoke all on table public.tax_obligations from public,anon,authenticated;
revoke all on table public.tax_reviews from public,anon,authenticated;
revoke all on table public.tax_approvals from public,anon,authenticated;
revoke all on table public.tax_audit_events from public,anon,authenticated;

grant select on table public.tax_jurisdictions to authenticated;
grant select on table public.tax_rule_packs to authenticated;
grant select on table public.tax_rules to authenticated;
grant select on table public.tax_source_connections to authenticated;
grant select on table public.tax_source_objects to authenticated;
grant select on table public.tax_documents to authenticated;
grant select on table public.tax_periods to authenticated;
grant select on table public.tax_ledger_entries to authenticated;
grant select on table public.tax_reconciliation_runs to authenticated;
grant select on table public.tax_exceptions to authenticated;
grant select on table public.tax_calculation_runs to authenticated;
grant select on table public.tax_calculation_lines to authenticated;
grant select on table public.tax_obligations to authenticated;
grant select on table public.tax_reviews to authenticated;
grant select on table public.tax_approvals to authenticated;
grant select on table public.tax_audit_events to authenticated;

grant select,insert,update,delete on table public.tax_jurisdictions to service_role;
grant select,insert,update,delete on table public.tax_rule_packs to service_role;
grant select,insert,update,delete on table public.tax_rules to service_role;
grant select,insert,update,delete on table public.tax_source_connections to service_role;
grant select,insert,update,delete on table public.tax_source_objects to service_role;
grant select,insert,update,delete on table public.tax_documents to service_role;
grant select,insert,update,delete on table public.tax_periods to service_role;
grant select,insert,update,delete on table public.tax_ledger_entries to service_role;
grant select,insert,update,delete on table public.tax_reconciliation_runs to service_role;
grant select,insert,update,delete on table public.tax_exceptions to service_role;
grant select,insert,update,delete on table public.tax_calculation_runs to service_role;
grant select,insert,update,delete on table public.tax_calculation_lines to service_role;
grant select,insert,update,delete on table public.tax_obligations to service_role;
grant select,insert,update,delete on table public.tax_reviews to service_role;
grant select,insert,update,delete on table public.tax_approvals to service_role;
grant select,insert on table public.tax_audit_events to service_role;
grant usage,select on sequence public.tax_audit_events_id_seq to service_role;

create or replace function private.pandora_tax_audit_append_only_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
begin
  raise exception 'tax audit events are append-only' using errcode='42501';
end;
$$;

drop trigger if exists pandora_tax_audit_append_only_v1 on public.tax_audit_events;
create trigger pandora_tax_audit_append_only_v1
before update or delete on public.tax_audit_events
for each row execute function private.pandora_tax_audit_append_only_v1();

revoke all on function private.pandora_tax_audit_append_only_v1() from public,anon,authenticated,service_role;

create or replace function public.pandora_tax_prepare_period_v1(
  p_organization_id uuid,
  p_period_start date,
  p_period_end date,
  p_jurisdiction_code text default 'PH',
  p_period_type text default 'monthly'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  period_row public.tax_periods%rowtype;
  selected_rule_pack_id uuid;
  rules_ready boolean := false;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'pandora_tax_invalid_period' using errcode='22023';
  end if;
  if p_period_type not in ('monthly','quarterly','annual','custom') then
    raise exception 'pandora_tax_invalid_period_type' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.tax_jurisdictions j
    where j.code=upper(trim(p_jurisdiction_code))
  ) then
    raise exception 'pandora_tax_unknown_jurisdiction' using errcode='22023';
  end if;

  select rp.id
  into selected_rule_pack_id
  from public.tax_rule_packs rp
  where rp.jurisdiction_code=upper(trim(p_jurisdiction_code))
    and rp.status='approved'
    and (rp.effective_from is null or rp.effective_from<=p_period_end)
    and (rp.effective_to is null or rp.effective_to>=p_period_start)
  order by rp.effective_from desc nulls last, rp.approved_at desc, rp.created_at desc, rp.id desc
  limit 1;

  rules_ready := selected_rule_pack_id is not null;

  insert into public.tax_periods(
    organization_id,jurisdiction_code,period_type,period_start,period_end,
    status,source_sync_state,rule_pack_id,created_by
  ) values (
    p_organization_id,upper(trim(p_jurisdiction_code)),p_period_type,
    p_period_start,p_period_end,
    case when rules_ready then 'draft' else 'review_required' end,
    'not_started',selected_rule_pack_id,uid
  )
  on conflict (organization_id,jurisdiction_code,period_type,period_start,period_end)
  do update set
    rule_pack_id=coalesce(public.tax_periods.rule_pack_id,excluded.rule_pack_id),
    status=case
      when public.tax_periods.status='review_required'
       and excluded.rule_pack_id is not null
        then 'draft'
      else public.tax_periods.status
    end,
    updated_at=clock_timestamp()
  returning * into period_row;

  insert into public.tax_audit_events(
    organization_id,tax_period_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,period_row.id,'tax_period_preparation_requested',uid,'user',
    'pandora_rpc','pandora_tax_prepare_period_v1',
    jsonb_build_object(
      'periodStart',p_period_start,
      'periodEnd',p_period_end,
      'periodType',p_period_type,
      'jurisdiction',upper(trim(p_jurisdiction_code)),
      'rulesReady',rules_ready,
      'rulePackId',period_row.rule_pack_id,
      'filingEnabled',false,
      'paymentEnabled',false
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.period.v1',
    'periodId',period_row.id,
    'organizationId',period_row.organization_id,
    'jurisdiction',period_row.jurisdiction_code,
    'periodType',period_row.period_type,
    'periodStart',period_row.period_start,
    'periodEnd',period_row.period_end,
    'status',period_row.status,
    'sourceSyncState',period_row.source_sync_state,
    'rulesReady',rules_ready,
    'rulePackId',period_row.rule_pack_id,
    'calculationEnabled',rules_ready,
    'filingEnabled',false,
    'paymentEnabled',false,
    'nextAction',case
      when rules_ready then 'ingest_and_reconcile_sources'
      else 'approve_current_rule_pack_before_calculation'
    end
  );
end;
$$;

revoke all on function public.pandora_tax_prepare_period_v1(uuid,date,date,text,text)
  from public,anon;
grant execute on function public.pandora_tax_prepare_period_v1(uuid,date,date,text,text)
  to authenticated;

create or replace function public.pandora_tax_workspace_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  open_exception_count integer := 0;
  critical_exception_count integer := 0;
  ready_count integer := 0;
  latest_period jsonb := null;
  next_obligation jsonb := null;
  ph_rules_ready boolean := false;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select count(*)::integer,
         count(*) filter (where severity='critical')::integer
  into open_exception_count,critical_exception_count
  from public.tax_exceptions
  where organization_id=p_organization_id
    and status in ('open','in_review');

  select count(*)::integer
  into ready_count
  from public.tax_periods
  where organization_id=p_organization_id
    and status in ('ready_for_approval','approved_for_filing');

  select to_jsonb(p) into latest_period
  from (
    select id,jurisdiction_code,period_type,period_start,period_end,status,
           source_sync_state,rule_pack_id,updated_at
    from public.tax_periods
    where organization_id=p_organization_id
    order by period_end desc,updated_at desc,id desc
    limit 1
  ) p;

  select to_jsonb(o) into next_obligation
  from (
    select id,obligation_key,due_date,amount_due,currency_code,status
    from public.tax_obligations
    where organization_id=p_organization_id
      and status not in ('paid','completed','superseded')
    order by due_date nulls last,created_at,id
    limit 1
  ) o;

  select exists(
    select 1 from public.tax_rule_packs rp
    where rp.jurisdiction_code='PH'
      and rp.status='approved'
      and (rp.effective_to is null or rp.effective_to>=current_date)
  ) into ph_rules_ready;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.workspace.v1',
    'generatedAt',clock_timestamp(),
    'organizationId',p_organization_id,
    'rules',jsonb_build_object(
      'philippinesApproved',ph_rules_ready,
      'calculationEnabled',ph_rules_ready
    ),
    'filing',jsonb_build_object(
      'enabled',false,
      'reason','No verified filing adapter is enabled by foundation v1.'
    ),
    'payments',jsonb_build_object(
      'enabled',false,
      'reason','Tax payment execution requires a separately verified adapter and explicit approval.'
    ),
    'summary',jsonb_build_object(
      'openExceptions',open_exception_count,
      'criticalExceptions',critical_exception_count,
      'readyForApproval',ready_count
    ),
    'latestPeriod',latest_period,
    'nextObligation',next_obligation
  );
end;
$$;

revoke all on function public.pandora_tax_workspace_v1(uuid) from public,anon;
grant execute on function public.pandora_tax_workspace_v1(uuid) to authenticated;

comment on table public.tax_rule_packs is
  'Versioned deterministic tax rule packs. Approval requires authoritative-source and professional review evidence.';
comment on table public.tax_ledger_entries is
  'Canonical tax ledger entries linked to source evidence. AI suggestions are not authoritative calculation rules.';
comment on table public.tax_audit_events is
  'Append-only tax execution/review audit trail. Raw credentials, OTPs, and unredacted customer evidence are forbidden.';
comment on function public.pandora_tax_prepare_period_v1(uuid,date,date,text,text) is
  'Creates or reopens a bounded tax preparation period. Does not calculate, file, sign, or pay taxes.';
comment on function public.pandora_tax_workspace_v1(uuid) is
  'Organization-scoped tax command-center projection. Filing/payment stay disabled until separately verified.';
