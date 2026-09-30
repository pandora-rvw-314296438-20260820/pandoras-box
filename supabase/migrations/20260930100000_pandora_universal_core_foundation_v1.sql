-- Pandora Universal Enterprise Core Foundation v1.
-- Phase 1A: thin entity identity, typed Person, source bindings,
-- keyed-HMAC identity signals, relationships, authority, and field provenance.
--
-- Safe convergence rules:
-- * public.organizations remains the tenant root.
-- * public.enterprise_source_connections already exists as a hospitality projection.
--   This migration does NOT rename or redefine it.
-- * the universal connection table is public.enterprise_integration_connections.
-- * no generic business-payload JSONB/EAV table is created.
-- * client writes are denied; service_role performs bounded writes.
-- * raw identity evidence is not stored in the resolution ledger.
-- * low-entropy identity/field values use keyed HMAC-SHA256 fingerprints; raw SHA-256 is not sufficient.

create table if not exists public.enterprise_entity_type_registry (
  entity_kind text primary key
    check (entity_kind ~ '^[a-z][a-z0-9_]{0,63}$'),
  namespace text not null
    check (namespace ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  display_name text not null
    check (char_length(display_name) between 1 and 160),
  schema_version text not null
    check (schema_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  created_at timestamptz not null default clock_timestamp()
);

insert into public.enterprise_entity_type_registry(
  entity_kind,namespace,display_name,schema_version
) values (
  'person','core','Person','1.0.0'
)
on conflict (entity_kind) do nothing;

create table if not exists public.enterprise_relationship_type_registry (
  relation_type text primary key
    check (relation_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  namespace text not null
    check (namespace ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  display_name text not null
    check (char_length(display_name) between 1 and 160),
  schema_version text not null
    check (schema_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists public.enterprise_entities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  entity_kind text not null
    references public.enterprise_entity_type_registry(entity_kind) on delete restrict,
  schema_version text not null default '1.0.0'
    check (schema_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','archived','superseded')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  archived_at timestamptz,
  unique (id,organization_id),
  unique (id,organization_id,entity_kind),
  check (
    (lifecycle_state='archived' and archived_at is not null)
    or
    (lifecycle_state<>'archived' and archived_at is null)
  )
);

create index if not exists enterprise_entities_org_kind_idx
  on public.enterprise_entities(organization_id,entity_kind,lifecycle_state);

create table if not exists public.enterprise_people (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'person'
    check (entity_kind='person'),
  display_name text
    check (display_name is null or char_length(display_name) between 1 and 320),
  first_name text
    check (first_name is null or char_length(first_name) between 1 and 160),
  last_name text
    check (last_name is null or char_length(last_name) between 1 and 160),
  primary_email text
    check (primary_email is null or char_length(primary_email) <= 320),
  primary_phone text
    check (primary_phone is null or char_length(primary_phone) <= 64),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (entity_id,organization_id),
  constraint enterprise_people_entity_org_kind_fkey
    foreign key (entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade
);

create table if not exists public.enterprise_integration_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  source_system_key text not null
    check (source_system_key ~ '^[a-z][a-z0-9_.:-]{1,127}$'),
  display_name text not null
    check (char_length(display_name) between 1 and 200),
  connection_key text not null
    check (connection_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$'),
  coexistence_mode text not null default 'observe'
    check (coexistence_mode in ('observe','synchronize','coordinate','replace')),
  capability_state text not null default 'configured'
    check (capability_state in ('configured','connecting','healthy','stale','error','revoked')),
  granted_scopes jsonb not null default '[]'::jsonb
    check (jsonb_typeof(granted_scopes)='array' and jsonb_array_length(granted_scopes)<=128),
  metadata_redacted jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata_redacted)='object'),
  last_synced_at timestamptz,
  last_error_code text
    check (last_error_code is null or char_length(last_error_code)<=160),
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,source_system_key,connection_key),
  unique (id,organization_id),
  check (
    (capability_state='revoked' and revoked_at is not null)
    or
    (capability_state<>'revoked' and revoked_at is null)
  )
);

create table if not exists public.enterprise_source_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  source_connection_id uuid not null,
  source_object_id text not null
    check (char_length(source_object_id) between 1 and 500),
  object_type text not null
    check (object_type ~ '^[a-z][a-z0-9_.:-]{0,127}$'),
  source_schema_version text
    check (source_schema_version is null or char_length(source_schema_version)<=80),
  source_observed_at timestamptz not null,
  content_sha256 text not null
    check (content_sha256 ~ '^[0-9a-f]{64}$'),
  source_locator text
    check (source_locator is null or char_length(source_locator)<=1000),
  payload_metadata_redacted jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload_metadata_redacted)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  unique (organization_id,source_connection_id,source_object_id,content_sha256),
  constraint enterprise_source_records_connection_org_fkey
    foreign key (source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict
);

create index if not exists enterprise_source_records_lookup_idx
  on public.enterprise_source_records(
    organization_id,source_connection_id,object_type,source_object_id,source_observed_at desc
  );

create table if not exists public.enterprise_identity_signals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  source_record_id uuid not null,
  signal_type text not null
    check (signal_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  normalized_value_hmac_sha256 text not null
    check (normalized_value_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  verification_state text not null default 'unverified'
    check (verification_state in ('unverified','verified','rejected','revoked')),
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=32),
  observed_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (id,organization_id),
  unique (organization_id,source_record_id,signal_type,normalized_value_hmac_sha256),
  constraint enterprise_identity_signals_source_org_fkey
    foreign key (source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict
);

create index if not exists enterprise_identity_signals_hash_idx
  on public.enterprise_identity_signals(
    organization_id,signal_type,normalized_value_hmac_sha256,verification_state
  );

create table if not exists public.enterprise_entity_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  source_record_id uuid not null,
  pandora_entity_id uuid not null,
  binding_state text not null default 'candidate'
    check (binding_state in ('candidate','confirmed','rejected','superseded')),
  binding_method text not null
    check (binding_method ~ '^[a-z][a-z0-9_]{0,63}$'),
  confidence_state text not null default 'unverified'
    check (confidence_state in ('unverified','verified','disputed')),
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=32),
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  unique (id,organization_id),
  constraint enterprise_entity_bindings_source_org_fkey
    foreign key (source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_entity_bindings_entity_org_fkey
    foreign key (pandora_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (
    (binding_state='superseded' and superseded_at is not null)
    or
    (binding_state<>'superseded' and superseded_at is null)
  )
);

create unique index if not exists enterprise_entity_bindings_confirmed_source_uniq
  on public.enterprise_entity_bindings(organization_id,source_record_id)
  where binding_state='confirmed' and superseded_at is null;

create index if not exists enterprise_entity_bindings_entity_idx
  on public.enterprise_entity_bindings(
    organization_id,pandora_entity_id,binding_state
  );

create table if not exists public.enterprise_relationships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  subject_entity_id uuid not null,
  relation_type text not null
    references public.enterprise_relationship_type_registry(relation_type) on delete restrict,
  object_entity_id uuid not null,
  valid_from timestamptz not null default clock_timestamp(),
  valid_to timestamptz,
  source_binding_id uuid,
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=32),
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  unique (id,organization_id),
  constraint enterprise_relationships_subject_org_fkey
    foreign key (subject_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_relationships_object_org_fkey
    foreign key (object_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_relationships_binding_org_fkey
    foreign key (source_binding_id,organization_id)
    references public.enterprise_entity_bindings(id,organization_id)
    on delete restrict,
  check (valid_to is null or valid_to>=valid_from)
);

create index if not exists enterprise_relationships_subject_idx
  on public.enterprise_relationships(
    organization_id,subject_entity_id,relation_type,valid_from desc
  );
create index if not exists enterprise_relationships_object_idx
  on public.enterprise_relationships(
    organization_id,object_entity_id,relation_type,valid_from desc
  );

create table if not exists public.enterprise_authority_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  entity_kind text not null
    references public.enterprise_entity_type_registry(entity_kind) on delete restrict,
  field_path text not null default '*'
    check (field_path='*' or field_path ~ '^[a-z][a-z0-9_.]{0,254}$'),
  authority_kind text not null
    check (authority_kind in ('source_of_record','pandora_derived','advisory','fallback_source')),
  source_connection_id uuid,
  verification_required boolean not null default true,
  conflict_action text not null default 'manual_review'
    check (conflict_action in ('block','manual_review','retain_current','recompute')),
  policy_version text not null
    check (policy_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  conditions_redacted jsonb not null default '{}'::jsonb
    check (jsonb_typeof(conditions_redacted)='object'),
  effective_from timestamptz not null default clock_timestamp(),
  effective_to timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  unique (id,organization_id),
  constraint enterprise_authority_policies_connection_org_fkey
    foreign key (source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict,
  check (effective_to is null or effective_to>=effective_from),
  check (
    (authority_kind='pandora_derived' and source_connection_id is null)
    or
    (authority_kind in ('source_of_record','advisory','fallback_source') and source_connection_id is not null)
  )
);

create index if not exists enterprise_authority_policies_lookup_idx
  on public.enterprise_authority_policies(
    organization_id,entity_kind,field_path,effective_from desc
  );

create table if not exists public.enterprise_field_provenance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  entity_id uuid not null,
  field_path text not null
    check (field_path ~ '^[a-z][a-z0-9_.]{0,254}$'),
  source_record_id uuid,
  source_connection_id uuid,
  observed_at timestamptz not null,
  effective_at timestamptz not null,
  verified_at timestamptz,
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=32),
  value_hmac_sha256 text not null
    check (value_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  confidence_state text not null default 'unverified'
    check (confidence_state in ('unverified','verified','disputed','superseded')),
  authority_policy_id uuid not null,
  supersedes_provenance_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  unique (id,organization_id),
  constraint enterprise_field_provenance_entity_org_fkey
    foreign key (entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_field_provenance_source_org_fkey
    foreign key (source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_field_provenance_connection_org_fkey
    foreign key (source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict,
  constraint enterprise_field_provenance_authority_org_fkey
    foreign key (authority_policy_id,organization_id)
    references public.enterprise_authority_policies(id,organization_id)
    on delete restrict,
  constraint enterprise_field_provenance_supersedes_org_fkey
    foreign key (supersedes_provenance_id,organization_id)
    references public.enterprise_field_provenance(id,organization_id)
    on delete restrict,
  check (
    (confidence_state='superseded' and superseded_at is not null)
    or
    (confidence_state<>'superseded' and superseded_at is null)
  )
);

create index if not exists enterprise_field_provenance_lookup_idx
  on public.enterprise_field_provenance(
    organization_id,entity_id,field_path,effective_at desc,created_at desc
  );

create table if not exists public.enterprise_identity_resolutions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  idempotency_key text not null
    check (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,159}$'),
  source_record_a_id uuid not null,
  source_record_b_id uuid not null,
  resolution_decision text not null
    check (resolution_decision in ('merge','separate','review_required')),
  canonical_entity_id uuid,
  resolution_method text not null
    check (resolution_method ~ '^[a-z][a-z0-9_]{0,63}$'),
  resolver_identity text not null
    check (resolver_identity ~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,159}$'),
  reason_codes text[] not null default '{}'::text[]
    check (cardinality(reason_codes)<=16),
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)<=32),
  decision_evidence_sha256 text not null
    check (decision_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  resolved_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  unique (organization_id,idempotency_key),
  unique (id,organization_id),
  constraint enterprise_identity_resolutions_source_a_org_fkey
    foreign key (source_record_a_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_identity_resolutions_source_b_org_fkey
    foreign key (source_record_b_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_identity_resolutions_entity_org_fkey
    foreign key (canonical_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (source_record_a_id < source_record_b_id),
  check (
    (resolution_decision='merge' and canonical_entity_id is not null)
    or
    (resolution_decision in ('separate','review_required') and canonical_entity_id is null)
  )
);

create index if not exists enterprise_identity_resolutions_pair_idx
  on public.enterprise_identity_resolutions(
    organization_id,source_record_a_id,source_record_b_id,resolved_at desc
  );

create or replace function public.pandora_enterprise_resolve_identity_v1(
  p_organization_id uuid,
  p_source_record_a_id uuid,
  p_source_record_b_id uuid,
  p_resolution_decision text,
  p_idempotency_key text,
  p_decision_evidence_sha256 text,
  p_resolver_identity text,
  p_canonical_entity_id uuid default null,
  p_resolution_method text default 'manual_review',
  p_reason_codes text[] default '{}'::text[],
  p_evidence_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $resolver$
declare
  v_a uuid;
  v_b uuid;
  v_decision text:=lower(trim(coalesce(p_resolution_decision,'')));
  v_method text:=lower(trim(coalesce(p_resolution_method,'')));
  v_resolver text:=trim(coalesce(p_resolver_identity,''));
  v_shared_verified boolean:=false;
  v_existing public.enterprise_identity_resolutions%rowtype;
  v_resolution_id uuid;
begin
  if p_organization_id is null
     or p_source_record_a_id is null
     or p_source_record_b_id is null
     or p_source_record_a_id=p_source_record_b_id then
    raise exception 'enterprise_identity_invalid_source_pair' using errcode='22023';
  end if;

  if p_source_record_a_id < p_source_record_b_id then
    v_a:=p_source_record_a_id;
    v_b:=p_source_record_b_id;
  else
    v_a:=p_source_record_b_id;
    v_b:=p_source_record_a_id;
  end if;

  if v_decision not in ('merge','separate','review_required')
     or coalesce(p_idempotency_key,'') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{15,159}$'
     or coalesce(p_decision_evidence_sha256,'') !~ '^[0-9a-f]{64}$'
     or v_method !~ '^[a-z][a-z0-9_]{0,63}$'
     or v_resolver !~ '^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,159}$'
     or jsonb_typeof(coalesce(p_evidence_refs,'null'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_evidence_refs,'[]'::jsonb))>32
     or coalesce(cardinality(p_reason_codes),0)>16 then
    raise exception 'enterprise_identity_invalid_resolution' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.enterprise_source_records s
    where s.id=v_a and s.organization_id=p_organization_id
  ) or not exists(
    select 1 from public.enterprise_source_records s
    where s.id=v_b and s.organization_id=p_organization_id
  ) then
    raise exception 'enterprise_identity_source_not_found' using errcode='22023';
  end if;

  select * into v_existing
  from public.enterprise_identity_resolutions r
  where r.organization_id=p_organization_id
    and r.idempotency_key=p_idempotency_key;

  if found then
    if v_existing.source_record_a_id is distinct from v_a
       or v_existing.source_record_b_id is distinct from v_b
       or v_existing.resolution_decision is distinct from v_decision
       or v_existing.canonical_entity_id is distinct from p_canonical_entity_id
       or v_existing.resolution_method is distinct from v_method
       or v_existing.resolver_identity is distinct from v_resolver
       or v_existing.reason_codes is distinct from coalesce(p_reason_codes,'{}'::text[])
       or v_existing.evidence_refs is distinct from coalesce(p_evidence_refs,'[]'::jsonb)
       or v_existing.decision_evidence_sha256 is distinct from p_decision_evidence_sha256 then
      raise exception 'enterprise_identity_idempotency_conflict' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,
      'mode','replay',
      'resolutionId',v_existing.id,
      'decision',v_existing.resolution_decision,
      'canonicalEntityId',v_existing.canonical_entity_id
    );
  end if;

  if v_decision='merge' then
    if p_canonical_entity_id is null
       or not exists(
         select 1 from public.enterprise_entities e
         where e.id=p_canonical_entity_id
           and e.organization_id=p_organization_id
           and e.lifecycle_state='active'
       ) then
      raise exception 'enterprise_identity_canonical_entity_invalid' using errcode='22023';
    end if;

    select exists(
      select 1
      from public.enterprise_identity_signals a
      join public.enterprise_identity_signals b
        on b.organization_id=a.organization_id
       and b.signal_type=a.signal_type
       and b.normalized_value_hmac_sha256=a.normalized_value_hmac_sha256
       and b.source_record_id=v_b
       and b.verification_state='verified'
      where a.organization_id=p_organization_id
        and a.source_record_id=v_a
        and a.verification_state='verified'
    ) into v_shared_verified;

    if not v_shared_verified then
      raise exception 'enterprise_identity_merge_requires_shared_verified_signal'
        using errcode='22023';
    end if;

    if jsonb_array_length(coalesce(p_evidence_refs,'[]'::jsonb))=0 then
      raise exception 'enterprise_identity_merge_requires_evidence_refs'
        using errcode='22023';
    end if;

    if exists(
      select 1 from public.enterprise_entity_bindings b
      where b.organization_id=p_organization_id
        and b.source_record_id in (v_a,v_b)
        and b.binding_state='confirmed'
        and b.superseded_at is null
        and b.pandora_entity_id<>p_canonical_entity_id
    ) then
      raise exception 'enterprise_identity_confirmed_binding_conflict'
        using errcode='23505';
    end if;
  elsif p_canonical_entity_id is not null then
    raise exception 'enterprise_identity_non_merge_canonical_entity_forbidden'
      using errcode='22023';
  end if;

  insert into public.enterprise_identity_resolutions(
    organization_id,idempotency_key,
    source_record_a_id,source_record_b_id,
    resolution_decision,canonical_entity_id,
    resolution_method,resolver_identity,
    reason_codes,evidence_refs,decision_evidence_sha256
  ) values (
    p_organization_id,p_idempotency_key,
    v_a,v_b,
    v_decision,p_canonical_entity_id,
    v_method,v_resolver,
    coalesce(p_reason_codes,'{}'::text[]),
    coalesce(p_evidence_refs,'[]'::jsonb),
    p_decision_evidence_sha256
  ) returning id into v_resolution_id;

  if v_decision='merge' then
    insert into public.enterprise_entity_bindings(
      organization_id,source_record_id,pandora_entity_id,
      binding_state,binding_method,confidence_state,evidence_refs
    )
    select
      p_organization_id,s.source_record_id,p_canonical_entity_id,
      'confirmed','shared_verified_signal','verified',
      coalesce(p_evidence_refs,'[]'::jsonb)
    from (values (v_a),(v_b)) as s(source_record_id)
    where not exists(
      select 1 from public.enterprise_entity_bindings b
      where b.organization_id=p_organization_id
        and b.source_record_id=s.source_record_id
        and b.binding_state='confirmed'
        and b.superseded_at is null
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'mode','created',
    'resolutionId',v_resolution_id,
    'decision',v_decision,
    'canonicalEntityId',p_canonical_entity_id
  );
end;
$resolver$;

revoke all on table
  public.enterprise_entity_type_registry,
  public.enterprise_relationship_type_registry
from public,anon,authenticated;

grant select on table
  public.enterprise_entity_type_registry,
  public.enterprise_relationship_type_registry
to authenticated,service_role;

grant insert,update,delete on table
  public.enterprise_entity_type_registry,
  public.enterprise_relationship_type_registry
to service_role;

alter table public.enterprise_entities enable row level security;
alter table public.enterprise_people enable row level security;
alter table public.enterprise_integration_connections enable row level security;
alter table public.enterprise_source_records enable row level security;
alter table public.enterprise_identity_signals enable row level security;
alter table public.enterprise_entity_bindings enable row level security;
alter table public.enterprise_relationships enable row level security;
alter table public.enterprise_authority_policies enable row level security;
alter table public.enterprise_field_provenance enable row level security;
alter table public.enterprise_identity_resolutions enable row level security;

revoke all on table
  public.enterprise_entities,
  public.enterprise_people,
  public.enterprise_integration_connections,
  public.enterprise_source_records,
  public.enterprise_identity_signals,
  public.enterprise_entity_bindings,
  public.enterprise_relationships,
  public.enterprise_authority_policies,
  public.enterprise_field_provenance,
  public.enterprise_identity_resolutions
from public,anon,authenticated;

grant select on table
  public.enterprise_entities,
  public.enterprise_people,
  public.enterprise_integration_connections,
  public.enterprise_source_records,
  public.enterprise_identity_signals,
  public.enterprise_entity_bindings,
  public.enterprise_relationships,
  public.enterprise_authority_policies,
  public.enterprise_field_provenance,
  public.enterprise_identity_resolutions
to authenticated;

grant select,insert,update on table
  public.enterprise_entities,
  public.enterprise_people,
  public.enterprise_integration_connections,
  public.enterprise_source_records,
  public.enterprise_identity_signals,
  public.enterprise_entity_bindings,
  public.enterprise_relationships,
  public.enterprise_authority_policies,
  public.enterprise_field_provenance,
  public.enterprise_identity_resolutions
to service_role;

drop policy if exists enterprise_entities_member_select on public.enterprise_entities;
create policy enterprise_entities_member_select
on public.enterprise_entities for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_entities.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_entities_service_all on public.enterprise_entities;
create policy enterprise_entities_service_all
on public.enterprise_entities for all to service_role using(true) with check(true);

drop policy if exists enterprise_people_member_select on public.enterprise_people;
create policy enterprise_people_member_select
on public.enterprise_people for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_people.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_people_service_all on public.enterprise_people;
create policy enterprise_people_service_all
on public.enterprise_people for all to service_role using(true) with check(true);

drop policy if exists enterprise_integration_connections_member_select on public.enterprise_integration_connections;
create policy enterprise_integration_connections_member_select
on public.enterprise_integration_connections for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_integration_connections.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_integration_connections_service_all on public.enterprise_integration_connections;
create policy enterprise_integration_connections_service_all
on public.enterprise_integration_connections for all to service_role using(true) with check(true);

drop policy if exists enterprise_source_records_member_select on public.enterprise_source_records;
create policy enterprise_source_records_member_select
on public.enterprise_source_records for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_source_records.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_source_records_service_all on public.enterprise_source_records;
create policy enterprise_source_records_service_all
on public.enterprise_source_records for all to service_role using(true) with check(true);

drop policy if exists enterprise_identity_signals_member_select on public.enterprise_identity_signals;
create policy enterprise_identity_signals_member_select
on public.enterprise_identity_signals for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_identity_signals.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_identity_signals_service_all on public.enterprise_identity_signals;
create policy enterprise_identity_signals_service_all
on public.enterprise_identity_signals for all to service_role using(true) with check(true);

drop policy if exists enterprise_entity_bindings_member_select on public.enterprise_entity_bindings;
create policy enterprise_entity_bindings_member_select
on public.enterprise_entity_bindings for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_entity_bindings.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_entity_bindings_service_all on public.enterprise_entity_bindings;
create policy enterprise_entity_bindings_service_all
on public.enterprise_entity_bindings for all to service_role using(true) with check(true);

drop policy if exists enterprise_relationships_member_select on public.enterprise_relationships;
create policy enterprise_relationships_member_select
on public.enterprise_relationships for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_relationships.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_relationships_service_all on public.enterprise_relationships;
create policy enterprise_relationships_service_all
on public.enterprise_relationships for all to service_role using(true) with check(true);

drop policy if exists enterprise_authority_policies_member_select on public.enterprise_authority_policies;
create policy enterprise_authority_policies_member_select
on public.enterprise_authority_policies for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_authority_policies.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_authority_policies_service_all on public.enterprise_authority_policies;
create policy enterprise_authority_policies_service_all
on public.enterprise_authority_policies for all to service_role using(true) with check(true);

drop policy if exists enterprise_field_provenance_member_select on public.enterprise_field_provenance;
create policy enterprise_field_provenance_member_select
on public.enterprise_field_provenance for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_field_provenance.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_field_provenance_service_all on public.enterprise_field_provenance;
create policy enterprise_field_provenance_service_all
on public.enterprise_field_provenance for all to service_role using(true) with check(true);

drop policy if exists enterprise_identity_resolutions_member_select on public.enterprise_identity_resolutions;
create policy enterprise_identity_resolutions_member_select
on public.enterprise_identity_resolutions for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_identity_resolutions.organization_id
    and m.user_id=auth.uid() and m.status='active'
));
drop policy if exists enterprise_identity_resolutions_service_all on public.enterprise_identity_resolutions;
create policy enterprise_identity_resolutions_service_all
on public.enterprise_identity_resolutions for all to service_role using(true) with check(true);

revoke all on function public.pandora_enterprise_resolve_identity_v1(
  uuid,uuid,uuid,text,text,text,text,uuid,text,text[],jsonb
) from public,anon,authenticated;

grant execute on function public.pandora_enterprise_resolve_identity_v1(
  uuid,uuid,uuid,text,text,text,text,uuid,text,text[],jsonb
) to service_role;
