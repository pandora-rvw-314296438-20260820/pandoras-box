-- Pandora Tax & Compliance OS — Evidence Inbox V1
-- Phase 1 of the owner-approved tax roadmap.
--
-- Truth/safety boundaries:
-- * raw file bytes are NOT accepted by these RPCs;
-- * evidence identity is SHA-256 bound and tenant-scoped;
-- * duplicate evidence reuses one canonical document;
-- * model/provider extraction can only reach review_required, never verified;
-- * verified extraction requires an authenticated owner/admin review action;
-- * audit payloads contain identifiers/status only, never extracted financial fields.

create or replace function public.pandora_tax_can_read_org_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public','auth'
as $
  select exists(
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=auth.uid()
      and m.status::text='active'
      and lower(m.role::text) in ('owner','admin')
  )
$;

revoke all on function public.pandora_tax_can_read_org_v1(uuid) from public,anon;
grant execute on function public.pandora_tax_can_read_org_v1(uuid) to authenticated,service_role;

create table if not exists public.tax_ingestion_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid,
  batch_key text not null,
  status text not null default 'running'
    check (status in ('running','complete','partial','failed','cancelled')),
  expected_count integer check (expected_count is null or expected_count >= 0),
  observed_count integer not null default 0 check (observed_count >= 0),
  canonical_document_count integer not null default 0 check (canonical_document_count >= 0),
  duplicate_count integer not null default 0 check (duplicate_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  error_code text,
  metadata_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,batch_key),
  unique (id,organization_id),
  constraint tax_ingestion_batches_connection_org_fkey
    foreign key (source_connection_id,organization_id)
    references public.tax_source_connections(id,organization_id)
    on delete restrict,
  check (jsonb_typeof(metadata_redacted)='object')
);

create table if not exists public.tax_evidence_hashes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size between 1 and 52428800),
  media_type text not null,
  canonical_document_id uuid not null,
  first_source_object_id uuid not null,
  first_observed_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,content_sha256),
  unique (id,organization_id),
  constraint tax_evidence_hashes_document_org_fkey
    foreign key (canonical_document_id,organization_id)
    references public.tax_documents(id,organization_id)
    on delete restrict,
  constraint tax_evidence_hashes_source_org_fkey
    foreign key (first_source_object_id,organization_id)
    references public.tax_source_objects(id,organization_id)
    on delete restrict
);

create table if not exists public.tax_document_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null,
  linked_entity_type text not null
    check (linked_entity_type in ('source_object','ledger_entry','tax_period','exception','filing_package')),
  linked_entity_id uuid not null,
  link_type text not null
    check (link_type in ('source_evidence','supports','matches','duplicate_source','derived_from')),
  confidence numeric(5,4) check (confidence is null or confidence between 0 and 1),
  provenance_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,document_id,linked_entity_type,linked_entity_id,link_type),
  unique (id,organization_id),
  constraint tax_document_links_document_org_fkey
    foreign key (document_id,organization_id)
    references public.tax_documents(id,organization_id)
    on delete cascade,
  check (jsonb_typeof(provenance_redacted)='object')
);

create table if not exists public.tax_document_extractions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null,
  document_sha256 text not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  extractor_kind text not null
    check (extractor_kind in ('local_model','cloud_model','deterministic_parser','provider_ocr','manual_import')),
  extractor_provider text,
  extractor_model text,
  extractor_version text not null,
  extracted_fields jsonb not null,
  field_confidences jsonb not null default '{}'::jsonb,
  overall_confidence numeric(5,4) not null check (overall_confidence between 0 and 1),
  status text not null default 'review_required'
    check (status in ('review_required','verified','rejected','superseded')),
  extraction_sha256 text not null check (extraction_sha256 ~ '^[0-9a-f]{64}$'),
  provider_evidence_redacted jsonb not null default '{}'::jsonb,
  reviewed_by uuid,
  reviewed_at timestamptz,
  superseded_by uuid references public.tax_document_extractions(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (organization_id,document_id,extractor_version,extraction_sha256),
  unique (id,organization_id),
  constraint tax_document_extractions_document_org_fkey
    foreign key (document_id,organization_id)
    references public.tax_documents(id,organization_id)
    on delete cascade,
  check (jsonb_typeof(extracted_fields)='object'),
  check (jsonb_typeof(field_confidences)='object'),
  check (jsonb_typeof(provider_evidence_redacted)='object'),
  check (
    (status='verified' and reviewed_by is not null and reviewed_at is not null)
    or status<>'verified'
  )
);

create table if not exists public.tax_document_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null,
  extraction_id uuid not null,
  decision text not null check (decision in ('verified','rejected')),
  reviewer_user_id uuid not null,
  review_notes text,
  reviewed_at timestamptz not null default clock_timestamp(),
  evidence_redacted jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (organization_id,extraction_id),
  unique (id,organization_id),
  constraint tax_document_reviews_document_org_fkey
    foreign key (document_id,organization_id)
    references public.tax_documents(id,organization_id)
    on delete cascade,
  constraint tax_document_reviews_extraction_org_fkey
    foreign key (extraction_id,organization_id)
    references public.tax_document_extractions(id,organization_id)
    on delete cascade,
  check (review_notes is null or length(review_notes)<=2000),
  check (jsonb_typeof(evidence_redacted)='object')
);

create index if not exists tax_ingestion_batches_org_status_idx
  on public.tax_ingestion_batches(organization_id,status,started_at desc);
create index if not exists tax_evidence_hashes_org_observed_idx
  on public.tax_evidence_hashes(organization_id,first_observed_at desc);
create index if not exists tax_document_links_doc_idx
  on public.tax_document_links(organization_id,document_id,linked_entity_type);
create index if not exists tax_document_extractions_review_idx
  on public.tax_document_extractions(organization_id,status,created_at desc);
create index if not exists tax_document_reviews_doc_idx
  on public.tax_document_reviews(organization_id,document_id,reviewed_at desc);

alter table public.tax_ingestion_batches enable row level security;
alter table public.tax_evidence_hashes enable row level security;
alter table public.tax_document_links enable row level security;
alter table public.tax_document_extractions enable row level security;
alter table public.tax_document_reviews enable row level security;

drop policy if exists tax_ingestion_batches_org_read on public.tax_ingestion_batches;
create policy tax_ingestion_batches_org_read
on public.tax_ingestion_batches for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_evidence_hashes_org_read on public.tax_evidence_hashes;
create policy tax_evidence_hashes_org_read
on public.tax_evidence_hashes for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_document_links_org_read on public.tax_document_links;
create policy tax_document_links_org_read
on public.tax_document_links for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_document_extractions_org_read on public.tax_document_extractions;
create policy tax_document_extractions_org_read
on public.tax_document_extractions for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

drop policy if exists tax_document_reviews_org_read on public.tax_document_reviews;
create policy tax_document_reviews_org_read
on public.tax_document_reviews for select to authenticated
using (public.pandora_tax_can_read_org_v1(organization_id));

revoke all on table public.tax_ingestion_batches from public,anon,authenticated;
revoke all on table public.tax_evidence_hashes from public,anon,authenticated;
revoke all on table public.tax_document_links from public,anon,authenticated;
revoke all on table public.tax_document_extractions from public,anon,authenticated;
revoke all on table public.tax_document_reviews from public,anon,authenticated;

grant select on table public.tax_ingestion_batches to authenticated;
grant select on table public.tax_evidence_hashes to authenticated;
grant select on table public.tax_document_links to authenticated;
grant select on table public.tax_document_extractions to authenticated;
grant select on table public.tax_document_reviews to authenticated;

grant select,insert,update,delete on table public.tax_ingestion_batches to service_role;
grant select,insert,update,delete on table public.tax_evidence_hashes to service_role;
grant select,insert,update,delete on table public.tax_document_links to service_role;
grant select,insert,update,delete on table public.tax_document_extractions to service_role;
grant select,insert,update,delete on table public.tax_document_reviews to service_role;

create or replace function public.pandora_tax_register_evidence_v1(
  p_organization_id uuid,
  p_source_connection_id uuid,
  p_source_external_id text,
  p_object_type text,
  p_source_observed_at timestamptz,
  p_content_sha256 text,
  p_byte_size bigint,
  p_media_type text,
  p_document_type text,
  p_document_date date default null,
  p_storage_bucket text default null,
  p_storage_path text default null,
  p_metadata_redacted jsonb default '{}'::jsonb,
  p_batch_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  source_row public.tax_source_objects%rowtype;
  document_row public.tax_documents%rowtype;
  evidence_row public.tax_evidence_hashes%rowtype;
  batch_row public.tax_ingestion_batches%rowtype;
  connection_provider text := 'direct';
  canonical_source_id text;
  is_duplicate boolean := false;
  is_replayed boolean := false;
begin
  if p_organization_id is null
     or p_source_external_id is null
     or length(btrim(p_source_external_id)) not between 1 and 500
     or p_object_type is null
     or length(btrim(p_object_type)) not between 1 and 100
     or p_source_observed_at is null
     or p_source_observed_at > clock_timestamp()+interval '5 minutes'
     or p_content_sha256 is null
     or p_content_sha256 !~ '^[0-9a-f]{64}
     or p_media_type is null
     or length(btrim(p_media_type)) not between 1 and 160
     or p_document_type is null
     or length(btrim(p_document_type)) not between 1 and 120
     or jsonb_typeof(coalesce(p_metadata_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_evidence_invalid' using errcode='22023';
  end if;

  if p_storage_bucket is not null and (
       length(p_storage_bucket) not between 1 and 100
       or p_storage_bucket !~ '^[A-Za-z0-9._-]+$'
     ) then
    raise exception 'pandora_tax_evidence_storage_bucket_invalid' using errcode='22023';
  end if;
  if p_storage_path is not null and (
       length(p_storage_path) not between 1 and 1024
       or left(p_storage_path,1)='/'
       or position(E'\\' in p_storage_path)>0
       or exists(
         select 1 from unnest(string_to_array(p_storage_path,'/')) seg(part)
         where part in ('','.', '..') or length(part)>255
       )
     ) then
    raise exception 'pandora_tax_evidence_storage_path_invalid' using errcode='22023';
  end if;
  if (p_storage_bucket is null) <> (p_storage_path is null) then
    raise exception 'pandora_tax_evidence_storage_pair_required' using errcode='22023';
  end if;

  if p_source_connection_id is not null then
    select provider into connection_provider
    from public.tax_source_connections
    where id=p_source_connection_id
      and organization_id=p_organization_id;
    if not found then
      raise exception 'pandora_tax_source_connection_mismatch' using errcode='42501';
    end if;
  end if;

  if p_batch_id is not null then
    select * into batch_row
    from public.tax_ingestion_batches
    where id=p_batch_id and organization_id=p_organization_id
    for update;
    if not found or batch_row.status<>'running' then
      raise exception 'pandora_tax_ingestion_batch_unavailable' using errcode='55000';
    end if;
    if batch_row.source_connection_id is distinct from p_source_connection_id then
      raise exception 'pandora_tax_ingestion_batch_source_mismatch' using errcode='23514';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text||':'||p_content_sha256,0)
  );

  canonical_source_id :=
    left(lower(regexp_replace(connection_provider,'[^a-zA-Z0-9._-]+','_','g')),120)
    ||':'||btrim(p_source_external_id);

  select * into source_row
  from public.tax_source_objects
  where organization_id=p_organization_id
    and source_object_id=canonical_source_id
    and content_sha256=p_content_sha256
  order by created_at
  limit 1;

  if source_row.id is null then
    insert into public.tax_source_objects(
      organization_id,source_connection_id,source_object_id,object_type,
      source_observed_at,content_sha256,source_locator,payload_metadata_redacted
    ) values (
      p_organization_id,p_source_connection_id,canonical_source_id,btrim(p_object_type),
      p_source_observed_at,p_content_sha256,
      case when p_storage_path is null then null else 'supabase-storage://'||
        p_storage_bucket||'/'||p_storage_path end,
      coalesce(p_metadata_redacted,'{}'::jsonb)
    )
    returning * into source_row;
  else
    is_replayed := true;
  end if;

  select * into evidence_row
  from public.tax_evidence_hashes
  where organization_id=p_organization_id
    and content_sha256=p_content_sha256
  for update;

  if evidence_row.id is not null then
    select * into document_row
    from public.tax_documents
    where id=evidence_row.canonical_document_id
      and organization_id=p_organization_id;
    if document_row.id is null
       or document_row.content_sha256<>p_content_sha256
       or evidence_row.byte_size<>p_byte_size
       or evidence_row.media_type<>btrim(p_media_type)
    then
      raise exception 'pandora_tax_evidence_hash_binding_drift' using errcode='55000';
    end if;
    is_duplicate := evidence_row.first_source_object_id<>source_row.id;
  else
    select * into document_row
    from public.tax_documents
    where organization_id=p_organization_id
      and content_sha256=p_content_sha256
    for update;

    if document_row.id is null then
      insert into public.tax_documents(
        organization_id,source_object_id,document_type,document_date,
        content_sha256,storage_bucket,storage_path,extraction_state,
        extraction_confidence,metadata_redacted
      ) values (
        p_organization_id,source_row.id,btrim(p_document_type),p_document_date,
        p_content_sha256,p_storage_bucket,p_storage_path,'pending',
        null,coalesce(p_metadata_redacted,'{}'::jsonb)
      )
      returning * into document_row;
    else
      is_duplicate := document_row.source_object_id is distinct from source_row.id;
    end if;

    insert into public.tax_evidence_hashes(
      organization_id,content_sha256,byte_size,media_type,
      canonical_document_id,first_source_object_id,first_observed_at
    ) values (
      p_organization_id,p_content_sha256,p_byte_size,btrim(p_media_type),
      document_row.id,source_row.id,p_source_observed_at
    )
    returning * into evidence_row;
  end if;

  insert into public.tax_document_links(
    organization_id,document_id,linked_entity_type,linked_entity_id,
    link_type,confidence,provenance_redacted
  ) values (
    p_organization_id,document_row.id,'source_object',source_row.id,
    case when evidence_row.first_source_object_id=source_row.id
      then 'source_evidence' else 'duplicate_source' end,
    1.0000,
    jsonb_build_object(
      'sourceProvider',connection_provider,
      'sourceObservedAt',p_source_observed_at,
      'contentSha256',p_content_sha256
    )
  )
  on conflict (organization_id,document_id,linked_entity_type,linked_entity_id,link_type)
  do nothing;

  if p_batch_id is not null and not is_replayed then
    update public.tax_ingestion_batches
    set observed_count=observed_count+1,
        canonical_document_count=canonical_document_count+
          case when is_duplicate then 0 else 1 end,
        duplicate_count=duplicate_count+
          case when is_duplicate then 1 else 0 end,
        updated_at=clock_timestamp()
    where id=p_batch_id and organization_id=p_organization_id;
  end if;

  if not is_replayed then
    insert into public.tax_audit_events(
      organization_id,event_type,actor_user_id,actor_type,
      source_type,source_ref,event_payload_redacted
    ) values (
      p_organization_id,'tax_evidence_registered',null,'system',
      'pandora_tax_register_evidence_v1',source_row.id::text,
      jsonb_build_object(
        'documentId',document_row.id,
        'sourceObjectId',source_row.id,
        'contentSha256',p_content_sha256,
        'byteSize',p_byte_size,
        'mediaType',btrim(p_media_type),
        'documentType',btrim(p_document_type),
        'duplicate',is_duplicate,
        'batchId',p_batch_id
      )
    );
  end if;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence.v1',
    'organizationId',p_organization_id,
    'sourceObjectId',source_row.id,
    'documentId',document_row.id,
    'contentSha256',p_content_sha256,
    'canonical',not is_duplicate,
    'duplicate',is_duplicate,
    'replayed',is_replayed,
    'extractionState',document_row.extraction_state,
    'storageBound',p_storage_path is not null
  );
end;
$$;

revoke all on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) to service_role;

create or replace function public.pandora_tax_commit_document_extraction_v1(
  p_organization_id uuid,
  p_document_id uuid,
  p_expected_document_sha256 text,
  p_extractor_kind text,
  p_extractor_provider text,
  p_extractor_model text,
  p_extractor_version text,
  p_extracted_fields jsonb,
  p_field_confidences jsonb,
  p_overall_confidence numeric,
  p_extraction_sha256 text,
  p_provider_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  document_row public.tax_documents%rowtype;
  extraction_row public.tax_document_extractions%rowtype;
begin
  if p_organization_id is null
     or p_document_id is null
     or p_expected_document_sha256 !~ '^[0-9a-f]{64}$'
     or p_extractor_kind not in ('local_model','cloud_model','deterministic_parser','provider_ocr','manual_import')
     or p_extractor_version is null
     or length(btrim(p_extractor_version)) not between 1 and 160
     or jsonb_typeof(p_extracted_fields)<>'object'
     or p_extracted_fields='{}'::jsonb
     or jsonb_typeof(coalesce(p_field_confidences,'{}'::jsonb))<>'object'
     or p_overall_confidence is null
     or p_overall_confidence not between 0 and 1
     or p_extraction_sha256 is null
     or p_extraction_sha256 !~ '^[0-9a-f]{64}
     or jsonb_typeof(coalesce(p_provider_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_extraction_invalid' using errcode='22023';
  end if;

  select * into document_row
  from public.tax_documents
  where id=p_document_id and organization_id=p_organization_id
  for update;

  if document_row.id is null then
    raise exception 'pandora_tax_document_not_found' using errcode='P0002';
  end if;
  if document_row.content_sha256<>p_expected_document_sha256 then
    raise exception 'pandora_tax_document_hash_mismatch' using errcode='23514';
  end if;

  insert into public.tax_document_extractions(
    organization_id,document_id,document_sha256,extractor_kind,
    extractor_provider,extractor_model,extractor_version,
    extracted_fields,field_confidences,overall_confidence,
    status,extraction_sha256,provider_evidence_redacted
  ) values (
    p_organization_id,p_document_id,p_expected_document_sha256,p_extractor_kind,
    nullif(btrim(coalesce(p_extractor_provider,'')),''),
    nullif(btrim(coalesce(p_extractor_model,'')),''),
    btrim(p_extractor_version),
    p_extracted_fields,coalesce(p_field_confidences,'{}'::jsonb),p_overall_confidence,
    'review_required',p_extraction_sha256,
    coalesce(p_provider_evidence_redacted,'{}'::jsonb)
  )
  on conflict (organization_id,document_id,extractor_version,extraction_sha256)
  do update set updated_at=clock_timestamp()
  returning * into extraction_row;

  update public.tax_documents
  set extraction_state='review_required',
      extraction_confidence=extraction_row.overall_confidence,
      updated_at=clock_timestamp()
  where id=p_document_id and organization_id=p_organization_id
    and extraction_state<>'verified';

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extracted',null,'provider',
    'pandora_tax_commit_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',p_document_id,
      'extractionId',extraction_row.id,
      'documentSha256',p_expected_document_sha256,
      'extractorKind',p_extractor_kind,
      'extractorProvider',nullif(btrim(coalesce(p_extractor_provider,'')),''),
      'extractorModel',nullif(btrim(coalesce(p_extractor_model,'')),''),
      'extractorVersion',btrim(p_extractor_version),
      'overallConfidence',p_overall_confidence,
      'reviewRequired',true
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.extraction.v1',
    'documentId',p_document_id,
    'extractionId',extraction_row.id,
    'status','review_required',
    'overallConfidence',extraction_row.overall_confidence,
    'humanReviewRequired',true,
    'autoVerified',false
  );
end;
$$;

revoke all on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) to service_role;

create or replace function public.pandora_tax_review_document_extraction_v1(
  p_organization_id uuid,
  p_extraction_id uuid,
  p_decision text,
  p_review_notes text default null,
  p_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  extraction_row public.tax_document_extractions%rowtype;
  document_row public.tax_documents%rowtype;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized_decision not in ('verified','rejected')
     or p_review_notes is not null and length(p_review_notes)>2000
     or jsonb_typeof(coalesce(p_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_review_invalid' using errcode='22023';
  end if;

  select * into extraction_row
  from public.tax_document_extractions
  where id=p_extraction_id and organization_id=p_organization_id
  for update;

  if extraction_row.id is null then
    raise exception 'pandora_tax_extraction_not_found' using errcode='P0002';
  end if;

  if extraction_row.status in ('verified','rejected') then
    if extraction_row.status=normalized_decision
       and extraction_row.reviewed_by=uid
    then
      return jsonb_build_object(
        'schemaVersion','pandora.tax.review.v1',
        'extractionId',extraction_row.id,
        'documentId',extraction_row.document_id,
        'decision',extraction_row.status,
        'replayed',true
      );
    end if;
    raise exception 'pandora_tax_extraction_already_reviewed' using errcode='23505';
  end if;
  if extraction_row.status<>'review_required' then
    raise exception 'pandora_tax_extraction_not_reviewable' using errcode='55000';
  end if;

  select * into document_row
  from public.tax_documents
  where id=extraction_row.document_id
    and organization_id=p_organization_id
  for update;
  if document_row.id is null
     or document_row.content_sha256<>extraction_row.document_sha256
  then
    raise exception 'pandora_tax_extraction_document_binding_drift' using errcode='55000';
  end if;

  update public.tax_document_extractions
  set status=normalized_decision,
      reviewed_by=uid,
      reviewed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=extraction_row.id and organization_id=p_organization_id
  returning * into extraction_row;

  insert into public.tax_document_reviews(
    organization_id,document_id,extraction_id,decision,
    reviewer_user_id,review_notes,evidence_redacted
  ) values (
    p_organization_id,document_row.id,extraction_row.id,normalized_decision,
    uid,p_review_notes,coalesce(p_evidence_redacted,'{}'::jsonb)
  );

  if normalized_decision='verified' then
    update public.tax_document_extractions
    set status='superseded',updated_at=clock_timestamp()
    where organization_id=p_organization_id
      and document_id=document_row.id
      and id<>extraction_row.id
      and status='verified';

    update public.tax_documents
    set extraction_state='verified',
        extraction_confidence=extraction_row.overall_confidence,
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  else
    update public.tax_documents
    set extraction_state='review_required',
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  end if;

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extraction_reviewed',uid,'user',
    'pandora_tax_review_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',document_row.id,
      'extractionId',extraction_row.id,
      'decision',normalized_decision
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.review.v1',
    'extractionId',extraction_row.id,
    'documentId',document_row.id,
    'decision',normalized_decision,
    'reviewedBy',uid,
    'replayed',false
  );
end;
$$;

revoke all on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) from public,anon;
grant execute on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) to authenticated;

create or replace function public.pandora_tax_evidence_inbox_v1(
  p_organization_id uuid,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  bounded_limit integer := least(greatest(coalesce(p_limit,25),1),100);
  pending_count integer;
  review_count integer;
  verified_count integer;
  duplicate_source_count integer;
  recent_documents jsonb;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select
    count(*) filter (where extraction_state in ('pending','processing','failed'))::integer,
    count(*) filter (where extraction_state='review_required')::integer,
    count(*) filter (where extraction_state='verified')::integer
  into pending_count,review_count,verified_count
  from public.tax_documents
  where organization_id=p_organization_id;

  select count(*)::integer into duplicate_source_count
  from public.tax_document_links
  where organization_id=p_organization_id
    and link_type='duplicate_source';

  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc,d.id desc),'[]'::jsonb)
  into recent_documents
  from (
    select
      td.id,
      td.document_type,
      td.document_date,
      td.extraction_state,
      td.extraction_confidence,
      left(td.content_sha256,16) as content_sha256_prefix,
      td.created_at,
      (
        select count(*)::integer
        from public.tax_document_links l
        where l.organization_id=td.organization_id
          and l.document_id=td.id
          and l.linked_entity_type='source_object'
      ) as source_count
    from public.tax_documents td
    where td.organization_id=p_organization_id
    order by td.created_at desc,td.id desc
    limit bounded_limit
  ) d;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence-inbox.v1',
    'organizationId',p_organization_id,
    'generatedAt',clock_timestamp(),
    'summary',jsonb_build_object(
      'pendingOrFailed',pending_count,
      'needsReview',review_count,
      'verified',verified_count,
      'duplicateSources',duplicate_source_count
    ),
    'documents',recent_documents,
    'rawEvidenceIncluded',false
  );
end;
$$;

revoke all on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  from public,anon;
grant execute on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  to authenticated;

comment on table public.tax_evidence_hashes is
  'Tenant-scoped SHA-256 evidence registry. One content hash maps to one canonical tax document per organization.';
comment on table public.tax_document_extractions is
  'Provider/model/parser output. New extraction attempts are review_required and cannot self-verify.';
comment on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) is
  'Service-role evidence registrar. Accepts metadata and an already-computed SHA-256 only; raw file bytes stay in authorized storage.';
comment on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) is
  'Service-role extraction commit. Always produces review_required; model/provider output never becomes verified by itself.';
comment on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) is
  'Owner/admin human review boundary for tax document extraction.';

     or p_byte_size is null
     or p_byte_size not between 1 and 52428800
     or p_media_type is null
     or length(btrim(p_media_type)) not between 1 and 160
     or p_document_type is null
     or length(btrim(p_document_type)) not between 1 and 120
     or jsonb_typeof(coalesce(p_metadata_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_evidence_invalid' using errcode='22023';
  end if;

  if p_storage_bucket is not null and (
       length(p_storage_bucket) not between 1 and 100
       or p_storage_bucket !~ '^[A-Za-z0-9._-]+$'
     ) then
    raise exception 'pandora_tax_evidence_storage_bucket_invalid' using errcode='22023';
  end if;
  if p_storage_path is not null and (
       length(p_storage_path) not between 1 and 1024
       or left(p_storage_path,1)='/'
       or position(E'\\' in p_storage_path)>0
       or exists(
         select 1 from unnest(string_to_array(p_storage_path,'/')) seg(part)
         where part in ('','.', '..') or length(part)>255
       )
     ) then
    raise exception 'pandora_tax_evidence_storage_path_invalid' using errcode='22023';
  end if;
  if (p_storage_bucket is null) <> (p_storage_path is null) then
    raise exception 'pandora_tax_evidence_storage_pair_required' using errcode='22023';
  end if;

  if p_source_connection_id is not null then
    select provider into connection_provider
    from public.tax_source_connections
    where id=p_source_connection_id
      and organization_id=p_organization_id;
    if not found then
      raise exception 'pandora_tax_source_connection_mismatch' using errcode='42501';
    end if;
  end if;

  if p_batch_id is not null then
    select * into batch_row
    from public.tax_ingestion_batches
    where id=p_batch_id and organization_id=p_organization_id
    for update;
    if not found or batch_row.status<>'running' then
      raise exception 'pandora_tax_ingestion_batch_unavailable' using errcode='55000';
    end if;
    if batch_row.source_connection_id is distinct from p_source_connection_id then
      raise exception 'pandora_tax_ingestion_batch_source_mismatch' using errcode='23514';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text||':'||p_content_sha256,0)
  );

  canonical_source_id :=
    lower(regexp_replace(connection_provider,'[^a-zA-Z0-9._-]+','_','g'))
    ||':'||btrim(p_source_external_id);

  select * into source_row
  from public.tax_source_objects
  where organization_id=p_organization_id
    and source_object_id=canonical_source_id
    and content_sha256=p_content_sha256
  order by created_at
  limit 1;

  if source_row.id is null then
    insert into public.tax_source_objects(
      organization_id,source_connection_id,source_object_id,object_type,
      source_observed_at,content_sha256,source_locator,payload_metadata_redacted
    ) values (
      p_organization_id,p_source_connection_id,canonical_source_id,btrim(p_object_type),
      p_source_observed_at,p_content_sha256,
      case when p_storage_path is null then null else 'supabase-storage://'||
        p_storage_bucket||'/'||p_storage_path end,
      coalesce(p_metadata_redacted,'{}'::jsonb)
    )
    returning * into source_row;
  else
    is_replayed := true;
  end if;

  select * into evidence_row
  from public.tax_evidence_hashes
  where organization_id=p_organization_id
    and content_sha256=p_content_sha256
  for update;

  if evidence_row.id is not null then
    select * into document_row
    from public.tax_documents
    where id=evidence_row.canonical_document_id
      and organization_id=p_organization_id;
    if document_row.id is null
       or document_row.content_sha256<>p_content_sha256
       or evidence_row.byte_size<>p_byte_size
       or evidence_row.media_type<>btrim(p_media_type)
    then
      raise exception 'pandora_tax_evidence_hash_binding_drift' using errcode='55000';
    end if;
    is_duplicate := evidence_row.first_source_object_id<>source_row.id;
  else
    select * into document_row
    from public.tax_documents
    where organization_id=p_organization_id
      and content_sha256=p_content_sha256
    for update;

    if document_row.id is null then
      insert into public.tax_documents(
        organization_id,source_object_id,document_type,document_date,
        content_sha256,storage_bucket,storage_path,extraction_state,
        extraction_confidence,metadata_redacted
      ) values (
        p_organization_id,source_row.id,btrim(p_document_type),p_document_date,
        p_content_sha256,p_storage_bucket,p_storage_path,'pending',
        null,coalesce(p_metadata_redacted,'{}'::jsonb)
      )
      returning * into document_row;
    else
      is_duplicate := document_row.source_object_id is distinct from source_row.id;
    end if;

    insert into public.tax_evidence_hashes(
      organization_id,content_sha256,byte_size,media_type,
      canonical_document_id,first_source_object_id,first_observed_at
    ) values (
      p_organization_id,p_content_sha256,p_byte_size,btrim(p_media_type),
      document_row.id,source_row.id,p_source_observed_at
    )
    returning * into evidence_row;
  end if;

  insert into public.tax_document_links(
    organization_id,document_id,linked_entity_type,linked_entity_id,
    link_type,confidence,provenance_redacted
  ) values (
    p_organization_id,document_row.id,'source_object',source_row.id,
    case when evidence_row.first_source_object_id=source_row.id
      then 'source_evidence' else 'duplicate_source' end,
    1.0000,
    jsonb_build_object(
      'sourceProvider',connection_provider,
      'sourceObservedAt',p_source_observed_at,
      'contentSha256',p_content_sha256
    )
  )
  on conflict (organization_id,document_id,linked_entity_type,linked_entity_id,link_type)
  do nothing;

  if p_batch_id is not null and not is_replayed then
    update public.tax_ingestion_batches
    set observed_count=observed_count+1,
        canonical_document_count=canonical_document_count+
          case when is_duplicate then 0 else 1 end,
        duplicate_count=duplicate_count+
          case when is_duplicate then 1 else 0 end,
        updated_at=clock_timestamp()
    where id=p_batch_id and organization_id=p_organization_id;
  end if;

  if not is_replayed then
    insert into public.tax_audit_events(
      organization_id,event_type,actor_user_id,actor_type,
      source_type,source_ref,event_payload_redacted
    ) values (
      p_organization_id,'tax_evidence_registered',null,'system',
      'pandora_tax_register_evidence_v1',source_row.id::text,
      jsonb_build_object(
        'documentId',document_row.id,
        'sourceObjectId',source_row.id,
        'contentSha256',p_content_sha256,
        'byteSize',p_byte_size,
        'mediaType',btrim(p_media_type),
        'documentType',btrim(p_document_type),
        'duplicate',is_duplicate,
        'batchId',p_batch_id
      )
    );
  end if;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence.v1',
    'organizationId',p_organization_id,
    'sourceObjectId',source_row.id,
    'documentId',document_row.id,
    'contentSha256',p_content_sha256,
    'canonical',not is_duplicate,
    'duplicate',is_duplicate,
    'replayed',is_replayed,
    'extractionState',document_row.extraction_state,
    'storageBound',p_storage_path is not null
  );
end;
$$;

revoke all on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) to service_role;

create or replace function public.pandora_tax_commit_document_extraction_v1(
  p_organization_id uuid,
  p_document_id uuid,
  p_expected_document_sha256 text,
  p_extractor_kind text,
  p_extractor_provider text,
  p_extractor_model text,
  p_extractor_version text,
  p_extracted_fields jsonb,
  p_field_confidences jsonb,
  p_overall_confidence numeric,
  p_extraction_sha256 text,
  p_provider_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  document_row public.tax_documents%rowtype;
  extraction_row public.tax_document_extractions%rowtype;
begin
  if p_organization_id is null
     or p_document_id is null
     or p_expected_document_sha256 !~ '^[0-9a-f]{64}$'
     or p_extractor_kind not in ('local_model','cloud_model','deterministic_parser','provider_ocr','manual_import')
     or p_extractor_version is null
     or length(btrim(p_extractor_version)) not between 1 and 160
     or jsonb_typeof(p_extracted_fields)<>'object'
     or p_extracted_fields='{}'::jsonb
     or jsonb_typeof(coalesce(p_field_confidences,'{}'::jsonb))<>'object'
     or p_overall_confidence not between 0 and 1
     or p_extraction_sha256 !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(coalesce(p_provider_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_extraction_invalid' using errcode='22023';
  end if;

  select * into document_row
  from public.tax_documents
  where id=p_document_id and organization_id=p_organization_id
  for update;

  if document_row.id is null then
    raise exception 'pandora_tax_document_not_found' using errcode='P0002';
  end if;
  if document_row.content_sha256<>p_expected_document_sha256 then
    raise exception 'pandora_tax_document_hash_mismatch' using errcode='23514';
  end if;

  insert into public.tax_document_extractions(
    organization_id,document_id,document_sha256,extractor_kind,
    extractor_provider,extractor_model,extractor_version,
    extracted_fields,field_confidences,overall_confidence,
    status,extraction_sha256,provider_evidence_redacted
  ) values (
    p_organization_id,p_document_id,p_expected_document_sha256,p_extractor_kind,
    nullif(btrim(coalesce(p_extractor_provider,'')),''),
    nullif(btrim(coalesce(p_extractor_model,'')),''),
    btrim(p_extractor_version),
    p_extracted_fields,coalesce(p_field_confidences,'{}'::jsonb),p_overall_confidence,
    'review_required',p_extraction_sha256,
    coalesce(p_provider_evidence_redacted,'{}'::jsonb)
  )
  on conflict (organization_id,document_id,extractor_version,extraction_sha256)
  do update set updated_at=clock_timestamp()
  returning * into extraction_row;

  update public.tax_documents
  set extraction_state='review_required',
      extraction_confidence=extraction_row.overall_confidence,
      updated_at=clock_timestamp()
  where id=p_document_id and organization_id=p_organization_id
    and extraction_state<>'verified';

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extracted',null,'provider',
    'pandora_tax_commit_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',p_document_id,
      'extractionId',extraction_row.id,
      'documentSha256',p_expected_document_sha256,
      'extractorKind',p_extractor_kind,
      'extractorProvider',nullif(btrim(coalesce(p_extractor_provider,'')),''),
      'extractorModel',nullif(btrim(coalesce(p_extractor_model,'')),''),
      'extractorVersion',btrim(p_extractor_version),
      'overallConfidence',p_overall_confidence,
      'reviewRequired',true
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.extraction.v1',
    'documentId',p_document_id,
    'extractionId',extraction_row.id,
    'status','review_required',
    'overallConfidence',extraction_row.overall_confidence,
    'humanReviewRequired',true,
    'autoVerified',false
  );
end;
$$;

revoke all on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) to service_role;

create or replace function public.pandora_tax_review_document_extraction_v1(
  p_organization_id uuid,
  p_extraction_id uuid,
  p_decision text,
  p_review_notes text default null,
  p_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  extraction_row public.tax_document_extractions%rowtype;
  document_row public.tax_documents%rowtype;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized_decision not in ('verified','rejected')
     or p_review_notes is not null and length(p_review_notes)>2000
     or jsonb_typeof(coalesce(p_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_review_invalid' using errcode='22023';
  end if;

  select * into extraction_row
  from public.tax_document_extractions
  where id=p_extraction_id and organization_id=p_organization_id
  for update;

  if extraction_row.id is null then
    raise exception 'pandora_tax_extraction_not_found' using errcode='P0002';
  end if;

  if extraction_row.status in ('verified','rejected') then
    if extraction_row.status=normalized_decision
       and extraction_row.reviewed_by=uid
    then
      return jsonb_build_object(
        'schemaVersion','pandora.tax.review.v1',
        'extractionId',extraction_row.id,
        'documentId',extraction_row.document_id,
        'decision',extraction_row.status,
        'replayed',true
      );
    end if;
    raise exception 'pandora_tax_extraction_already_reviewed' using errcode='23505';
  end if;
  if extraction_row.status<>'review_required' then
    raise exception 'pandora_tax_extraction_not_reviewable' using errcode='55000';
  end if;

  select * into document_row
  from public.tax_documents
  where id=extraction_row.document_id
    and organization_id=p_organization_id
  for update;
  if document_row.id is null
     or document_row.content_sha256<>extraction_row.document_sha256
  then
    raise exception 'pandora_tax_extraction_document_binding_drift' using errcode='55000';
  end if;

  update public.tax_document_extractions
  set status=normalized_decision,
      reviewed_by=uid,
      reviewed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=extraction_row.id and organization_id=p_organization_id
  returning * into extraction_row;

  insert into public.tax_document_reviews(
    organization_id,document_id,extraction_id,decision,
    reviewer_user_id,review_notes,evidence_redacted
  ) values (
    p_organization_id,document_row.id,extraction_row.id,normalized_decision,
    uid,p_review_notes,coalesce(p_evidence_redacted,'{}'::jsonb)
  );

  if normalized_decision='verified' then
    update public.tax_document_extractions
    set status='superseded',updated_at=clock_timestamp()
    where organization_id=p_organization_id
      and document_id=document_row.id
      and id<>extraction_row.id
      and status='verified';

    update public.tax_documents
    set extraction_state='verified',
        extraction_confidence=extraction_row.overall_confidence,
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  else
    update public.tax_documents
    set extraction_state='review_required',
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  end if;

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extraction_reviewed',uid,'user',
    'pandora_tax_review_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',document_row.id,
      'extractionId',extraction_row.id,
      'decision',normalized_decision
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.review.v1',
    'extractionId',extraction_row.id,
    'documentId',document_row.id,
    'decision',normalized_decision,
    'reviewedBy',uid,
    'replayed',false
  );
end;
$$;

revoke all on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) from public,anon;
grant execute on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) to authenticated;

create or replace function public.pandora_tax_evidence_inbox_v1(
  p_organization_id uuid,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  bounded_limit integer := least(greatest(coalesce(p_limit,25),1),100);
  pending_count integer;
  review_count integer;
  verified_count integer;
  duplicate_source_count integer;
  recent_documents jsonb;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select
    count(*) filter (where extraction_state in ('pending','processing','failed'))::integer,
    count(*) filter (where extraction_state='review_required')::integer,
    count(*) filter (where extraction_state='verified')::integer
  into pending_count,review_count,verified_count
  from public.tax_documents
  where organization_id=p_organization_id;

  select count(*)::integer into duplicate_source_count
  from public.tax_document_links
  where organization_id=p_organization_id
    and link_type='duplicate_source';

  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc,d.id desc),'[]'::jsonb)
  into recent_documents
  from (
    select
      td.id,
      td.document_type,
      td.document_date,
      td.extraction_state,
      td.extraction_confidence,
      left(td.content_sha256,16) as content_sha256_prefix,
      td.created_at,
      (
        select count(*)::integer
        from public.tax_document_links l
        where l.organization_id=td.organization_id
          and l.document_id=td.id
          and l.linked_entity_type='source_object'
      ) as source_count
    from public.tax_documents td
    where td.organization_id=p_organization_id
    order by td.created_at desc,td.id desc
    limit bounded_limit
  ) d;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence-inbox.v1',
    'organizationId',p_organization_id,
    'generatedAt',clock_timestamp(),
    'summary',jsonb_build_object(
      'pendingOrFailed',pending_count,
      'needsReview',review_count,
      'verified',verified_count,
      'duplicateSources',duplicate_source_count
    ),
    'documents',recent_documents,
    'rawEvidenceIncluded',false
  );
end;
$$;

revoke all on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  from public,anon;
grant execute on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  to authenticated;

comment on table public.tax_evidence_hashes is
  'Tenant-scoped SHA-256 evidence registry. One content hash maps to one canonical tax document per organization.';
comment on table public.tax_document_extractions is
  'Provider/model/parser output. New extraction attempts are review_required and cannot self-verify.';
comment on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) is
  'Service-role evidence registrar. Accepts metadata and an already-computed SHA-256 only; raw file bytes stay in authorized storage.';
comment on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) is
  'Service-role extraction commit. Always produces review_required; model/provider output never becomes verified by itself.';
comment on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) is
  'Owner/admin human review boundary for tax document extraction.';

     or jsonb_typeof(coalesce(p_provider_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_extraction_invalid' using errcode='22023';
  end if;

  select * into document_row
  from public.tax_documents
  where id=p_document_id and organization_id=p_organization_id
  for update;

  if document_row.id is null then
    raise exception 'pandora_tax_document_not_found' using errcode='P0002';
  end if;
  if document_row.content_sha256<>p_expected_document_sha256 then
    raise exception 'pandora_tax_document_hash_mismatch' using errcode='23514';
  end if;

  insert into public.tax_document_extractions(
    organization_id,document_id,document_sha256,extractor_kind,
    extractor_provider,extractor_model,extractor_version,
    extracted_fields,field_confidences,overall_confidence,
    status,extraction_sha256,provider_evidence_redacted
  ) values (
    p_organization_id,p_document_id,p_expected_document_sha256,p_extractor_kind,
    nullif(btrim(coalesce(p_extractor_provider,'')),''),
    nullif(btrim(coalesce(p_extractor_model,'')),''),
    btrim(p_extractor_version),
    p_extracted_fields,coalesce(p_field_confidences,'{}'::jsonb),p_overall_confidence,
    'review_required',p_extraction_sha256,
    coalesce(p_provider_evidence_redacted,'{}'::jsonb)
  )
  on conflict (organization_id,document_id,extractor_version,extraction_sha256)
  do update set updated_at=clock_timestamp()
  returning * into extraction_row;

  update public.tax_documents
  set extraction_state='review_required',
      extraction_confidence=extraction_row.overall_confidence,
      updated_at=clock_timestamp()
  where id=p_document_id and organization_id=p_organization_id
    and extraction_state<>'verified';

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extracted',null,'provider',
    'pandora_tax_commit_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',p_document_id,
      'extractionId',extraction_row.id,
      'documentSha256',p_expected_document_sha256,
      'extractorKind',p_extractor_kind,
      'extractorProvider',nullif(btrim(coalesce(p_extractor_provider,'')),''),
      'extractorModel',nullif(btrim(coalesce(p_extractor_model,'')),''),
      'extractorVersion',btrim(p_extractor_version),
      'overallConfidence',p_overall_confidence,
      'reviewRequired',true
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.extraction.v1',
    'documentId',p_document_id,
    'extractionId',extraction_row.id,
    'status','review_required',
    'overallConfidence',extraction_row.overall_confidence,
    'humanReviewRequired',true,
    'autoVerified',false
  );
end;
$$;

revoke all on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) to service_role;

create or replace function public.pandora_tax_review_document_extraction_v1(
  p_organization_id uuid,
  p_extraction_id uuid,
  p_decision text,
  p_review_notes text default null,
  p_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  extraction_row public.tax_document_extractions%rowtype;
  document_row public.tax_documents%rowtype;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized_decision not in ('verified','rejected')
     or p_review_notes is not null and length(p_review_notes)>2000
     or jsonb_typeof(coalesce(p_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_review_invalid' using errcode='22023';
  end if;

  select * into extraction_row
  from public.tax_document_extractions
  where id=p_extraction_id and organization_id=p_organization_id
  for update;

  if extraction_row.id is null then
    raise exception 'pandora_tax_extraction_not_found' using errcode='P0002';
  end if;

  if extraction_row.status in ('verified','rejected') then
    if extraction_row.status=normalized_decision
       and extraction_row.reviewed_by=uid
    then
      return jsonb_build_object(
        'schemaVersion','pandora.tax.review.v1',
        'extractionId',extraction_row.id,
        'documentId',extraction_row.document_id,
        'decision',extraction_row.status,
        'replayed',true
      );
    end if;
    raise exception 'pandora_tax_extraction_already_reviewed' using errcode='23505';
  end if;
  if extraction_row.status<>'review_required' then
    raise exception 'pandora_tax_extraction_not_reviewable' using errcode='55000';
  end if;

  select * into document_row
  from public.tax_documents
  where id=extraction_row.document_id
    and organization_id=p_organization_id
  for update;
  if document_row.id is null
     or document_row.content_sha256<>extraction_row.document_sha256
  then
    raise exception 'pandora_tax_extraction_document_binding_drift' using errcode='55000';
  end if;

  update public.tax_document_extractions
  set status=normalized_decision,
      reviewed_by=uid,
      reviewed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=extraction_row.id and organization_id=p_organization_id
  returning * into extraction_row;

  insert into public.tax_document_reviews(
    organization_id,document_id,extraction_id,decision,
    reviewer_user_id,review_notes,evidence_redacted
  ) values (
    p_organization_id,document_row.id,extraction_row.id,normalized_decision,
    uid,p_review_notes,coalesce(p_evidence_redacted,'{}'::jsonb)
  );

  if normalized_decision='verified' then
    update public.tax_document_extractions
    set status='superseded',updated_at=clock_timestamp()
    where organization_id=p_organization_id
      and document_id=document_row.id
      and id<>extraction_row.id
      and status='verified';

    update public.tax_documents
    set extraction_state='verified',
        extraction_confidence=extraction_row.overall_confidence,
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  else
    update public.tax_documents
    set extraction_state='review_required',
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  end if;

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extraction_reviewed',uid,'user',
    'pandora_tax_review_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',document_row.id,
      'extractionId',extraction_row.id,
      'decision',normalized_decision
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.review.v1',
    'extractionId',extraction_row.id,
    'documentId',document_row.id,
    'decision',normalized_decision,
    'reviewedBy',uid,
    'replayed',false
  );
end;
$$;

revoke all on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) from public,anon;
grant execute on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) to authenticated;

create or replace function public.pandora_tax_evidence_inbox_v1(
  p_organization_id uuid,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  bounded_limit integer := least(greatest(coalesce(p_limit,25),1),100);
  pending_count integer;
  review_count integer;
  verified_count integer;
  duplicate_source_count integer;
  recent_documents jsonb;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select
    count(*) filter (where extraction_state in ('pending','processing','failed'))::integer,
    count(*) filter (where extraction_state='review_required')::integer,
    count(*) filter (where extraction_state='verified')::integer
  into pending_count,review_count,verified_count
  from public.tax_documents
  where organization_id=p_organization_id;

  select count(*)::integer into duplicate_source_count
  from public.tax_document_links
  where organization_id=p_organization_id
    and link_type='duplicate_source';

  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc,d.id desc),'[]'::jsonb)
  into recent_documents
  from (
    select
      td.id,
      td.document_type,
      td.document_date,
      td.extraction_state,
      td.extraction_confidence,
      left(td.content_sha256,16) as content_sha256_prefix,
      td.created_at,
      (
        select count(*)::integer
        from public.tax_document_links l
        where l.organization_id=td.organization_id
          and l.document_id=td.id
          and l.linked_entity_type='source_object'
      ) as source_count
    from public.tax_documents td
    where td.organization_id=p_organization_id
    order by td.created_at desc,td.id desc
    limit bounded_limit
  ) d;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence-inbox.v1',
    'organizationId',p_organization_id,
    'generatedAt',clock_timestamp(),
    'summary',jsonb_build_object(
      'pendingOrFailed',pending_count,
      'needsReview',review_count,
      'verified',verified_count,
      'duplicateSources',duplicate_source_count
    ),
    'documents',recent_documents,
    'rawEvidenceIncluded',false
  );
end;
$$;

revoke all on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  from public,anon;
grant execute on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  to authenticated;

comment on table public.tax_evidence_hashes is
  'Tenant-scoped SHA-256 evidence registry. One content hash maps to one canonical tax document per organization.';
comment on table public.tax_document_extractions is
  'Provider/model/parser output. New extraction attempts are review_required and cannot self-verify.';
comment on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) is
  'Service-role evidence registrar. Accepts metadata and an already-computed SHA-256 only; raw file bytes stay in authorized storage.';
comment on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) is
  'Service-role extraction commit. Always produces review_required; model/provider output never becomes verified by itself.';
comment on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) is
  'Owner/admin human review boundary for tax document extraction.';

     or p_byte_size is null
     or p_byte_size not between 1 and 52428800
     or p_media_type is null
     or length(btrim(p_media_type)) not between 1 and 160
     or p_document_type is null
     or length(btrim(p_document_type)) not between 1 and 120
     or jsonb_typeof(coalesce(p_metadata_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_evidence_invalid' using errcode='22023';
  end if;

  if p_storage_bucket is not null and (
       length(p_storage_bucket) not between 1 and 100
       or p_storage_bucket !~ '^[A-Za-z0-9._-]+$'
     ) then
    raise exception 'pandora_tax_evidence_storage_bucket_invalid' using errcode='22023';
  end if;
  if p_storage_path is not null and (
       length(p_storage_path) not between 1 and 1024
       or left(p_storage_path,1)='/'
       or position(E'\\' in p_storage_path)>0
       or exists(
         select 1 from unnest(string_to_array(p_storage_path,'/')) seg(part)
         where part in ('','.', '..') or length(part)>255
       )
     ) then
    raise exception 'pandora_tax_evidence_storage_path_invalid' using errcode='22023';
  end if;
  if (p_storage_bucket is null) <> (p_storage_path is null) then
    raise exception 'pandora_tax_evidence_storage_pair_required' using errcode='22023';
  end if;

  if p_source_connection_id is not null then
    select provider into connection_provider
    from public.tax_source_connections
    where id=p_source_connection_id
      and organization_id=p_organization_id;
    if not found then
      raise exception 'pandora_tax_source_connection_mismatch' using errcode='42501';
    end if;
  end if;

  if p_batch_id is not null then
    select * into batch_row
    from public.tax_ingestion_batches
    where id=p_batch_id and organization_id=p_organization_id
    for update;
    if not found or batch_row.status<>'running' then
      raise exception 'pandora_tax_ingestion_batch_unavailable' using errcode='55000';
    end if;
    if batch_row.source_connection_id is distinct from p_source_connection_id then
      raise exception 'pandora_tax_ingestion_batch_source_mismatch' using errcode='23514';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text||':'||p_content_sha256,0)
  );

  canonical_source_id :=
    lower(regexp_replace(connection_provider,'[^a-zA-Z0-9._-]+','_','g'))
    ||':'||btrim(p_source_external_id);

  select * into source_row
  from public.tax_source_objects
  where organization_id=p_organization_id
    and source_object_id=canonical_source_id
    and content_sha256=p_content_sha256
  order by created_at
  limit 1;

  if source_row.id is null then
    insert into public.tax_source_objects(
      organization_id,source_connection_id,source_object_id,object_type,
      source_observed_at,content_sha256,source_locator,payload_metadata_redacted
    ) values (
      p_organization_id,p_source_connection_id,canonical_source_id,btrim(p_object_type),
      p_source_observed_at,p_content_sha256,
      case when p_storage_path is null then null else 'supabase-storage://'||
        p_storage_bucket||'/'||p_storage_path end,
      coalesce(p_metadata_redacted,'{}'::jsonb)
    )
    returning * into source_row;
  else
    is_replayed := true;
  end if;

  select * into evidence_row
  from public.tax_evidence_hashes
  where organization_id=p_organization_id
    and content_sha256=p_content_sha256
  for update;

  if evidence_row.id is not null then
    select * into document_row
    from public.tax_documents
    where id=evidence_row.canonical_document_id
      and organization_id=p_organization_id;
    if document_row.id is null
       or document_row.content_sha256<>p_content_sha256
       or evidence_row.byte_size<>p_byte_size
       or evidence_row.media_type<>btrim(p_media_type)
    then
      raise exception 'pandora_tax_evidence_hash_binding_drift' using errcode='55000';
    end if;
    is_duplicate := evidence_row.first_source_object_id<>source_row.id;
  else
    select * into document_row
    from public.tax_documents
    where organization_id=p_organization_id
      and content_sha256=p_content_sha256
    for update;

    if document_row.id is null then
      insert into public.tax_documents(
        organization_id,source_object_id,document_type,document_date,
        content_sha256,storage_bucket,storage_path,extraction_state,
        extraction_confidence,metadata_redacted
      ) values (
        p_organization_id,source_row.id,btrim(p_document_type),p_document_date,
        p_content_sha256,p_storage_bucket,p_storage_path,'pending',
        null,coalesce(p_metadata_redacted,'{}'::jsonb)
      )
      returning * into document_row;
    else
      is_duplicate := document_row.source_object_id is distinct from source_row.id;
    end if;

    insert into public.tax_evidence_hashes(
      organization_id,content_sha256,byte_size,media_type,
      canonical_document_id,first_source_object_id,first_observed_at
    ) values (
      p_organization_id,p_content_sha256,p_byte_size,btrim(p_media_type),
      document_row.id,source_row.id,p_source_observed_at
    )
    returning * into evidence_row;
  end if;

  insert into public.tax_document_links(
    organization_id,document_id,linked_entity_type,linked_entity_id,
    link_type,confidence,provenance_redacted
  ) values (
    p_organization_id,document_row.id,'source_object',source_row.id,
    case when evidence_row.first_source_object_id=source_row.id
      then 'source_evidence' else 'duplicate_source' end,
    1.0000,
    jsonb_build_object(
      'sourceProvider',connection_provider,
      'sourceObservedAt',p_source_observed_at,
      'contentSha256',p_content_sha256
    )
  )
  on conflict (organization_id,document_id,linked_entity_type,linked_entity_id,link_type)
  do nothing;

  if p_batch_id is not null and not is_replayed then
    update public.tax_ingestion_batches
    set observed_count=observed_count+1,
        canonical_document_count=canonical_document_count+
          case when is_duplicate then 0 else 1 end,
        duplicate_count=duplicate_count+
          case when is_duplicate then 1 else 0 end,
        updated_at=clock_timestamp()
    where id=p_batch_id and organization_id=p_organization_id;
  end if;

  if not is_replayed then
    insert into public.tax_audit_events(
      organization_id,event_type,actor_user_id,actor_type,
      source_type,source_ref,event_payload_redacted
    ) values (
      p_organization_id,'tax_evidence_registered',null,'system',
      'pandora_tax_register_evidence_v1',source_row.id::text,
      jsonb_build_object(
        'documentId',document_row.id,
        'sourceObjectId',source_row.id,
        'contentSha256',p_content_sha256,
        'byteSize',p_byte_size,
        'mediaType',btrim(p_media_type),
        'documentType',btrim(p_document_type),
        'duplicate',is_duplicate,
        'batchId',p_batch_id
      )
    );
  end if;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence.v1',
    'organizationId',p_organization_id,
    'sourceObjectId',source_row.id,
    'documentId',document_row.id,
    'contentSha256',p_content_sha256,
    'canonical',not is_duplicate,
    'duplicate',is_duplicate,
    'replayed',is_replayed,
    'extractionState',document_row.extraction_state,
    'storageBound',p_storage_path is not null
  );
end;
$$;

revoke all on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) to service_role;

create or replace function public.pandora_tax_commit_document_extraction_v1(
  p_organization_id uuid,
  p_document_id uuid,
  p_expected_document_sha256 text,
  p_extractor_kind text,
  p_extractor_provider text,
  p_extractor_model text,
  p_extractor_version text,
  p_extracted_fields jsonb,
  p_field_confidences jsonb,
  p_overall_confidence numeric,
  p_extraction_sha256 text,
  p_provider_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  document_row public.tax_documents%rowtype;
  extraction_row public.tax_document_extractions%rowtype;
begin
  if p_organization_id is null
     or p_document_id is null
     or p_expected_document_sha256 !~ '^[0-9a-f]{64}$'
     or p_extractor_kind not in ('local_model','cloud_model','deterministic_parser','provider_ocr','manual_import')
     or p_extractor_version is null
     or length(btrim(p_extractor_version)) not between 1 and 160
     or jsonb_typeof(p_extracted_fields)<>'object'
     or p_extracted_fields='{}'::jsonb
     or jsonb_typeof(coalesce(p_field_confidences,'{}'::jsonb))<>'object'
     or p_overall_confidence not between 0 and 1
     or p_extraction_sha256 !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(coalesce(p_provider_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_extraction_invalid' using errcode='22023';
  end if;

  select * into document_row
  from public.tax_documents
  where id=p_document_id and organization_id=p_organization_id
  for update;

  if document_row.id is null then
    raise exception 'pandora_tax_document_not_found' using errcode='P0002';
  end if;
  if document_row.content_sha256<>p_expected_document_sha256 then
    raise exception 'pandora_tax_document_hash_mismatch' using errcode='23514';
  end if;

  insert into public.tax_document_extractions(
    organization_id,document_id,document_sha256,extractor_kind,
    extractor_provider,extractor_model,extractor_version,
    extracted_fields,field_confidences,overall_confidence,
    status,extraction_sha256,provider_evidence_redacted
  ) values (
    p_organization_id,p_document_id,p_expected_document_sha256,p_extractor_kind,
    nullif(btrim(coalesce(p_extractor_provider,'')),''),
    nullif(btrim(coalesce(p_extractor_model,'')),''),
    btrim(p_extractor_version),
    p_extracted_fields,coalesce(p_field_confidences,'{}'::jsonb),p_overall_confidence,
    'review_required',p_extraction_sha256,
    coalesce(p_provider_evidence_redacted,'{}'::jsonb)
  )
  on conflict (organization_id,document_id,extractor_version,extraction_sha256)
  do update set updated_at=clock_timestamp()
  returning * into extraction_row;

  update public.tax_documents
  set extraction_state='review_required',
      extraction_confidence=extraction_row.overall_confidence,
      updated_at=clock_timestamp()
  where id=p_document_id and organization_id=p_organization_id
    and extraction_state<>'verified';

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extracted',null,'provider',
    'pandora_tax_commit_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',p_document_id,
      'extractionId',extraction_row.id,
      'documentSha256',p_expected_document_sha256,
      'extractorKind',p_extractor_kind,
      'extractorProvider',nullif(btrim(coalesce(p_extractor_provider,'')),''),
      'extractorModel',nullif(btrim(coalesce(p_extractor_model,'')),''),
      'extractorVersion',btrim(p_extractor_version),
      'overallConfidence',p_overall_confidence,
      'reviewRequired',true
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.extraction.v1',
    'documentId',p_document_id,
    'extractionId',extraction_row.id,
    'status','review_required',
    'overallConfidence',extraction_row.overall_confidence,
    'humanReviewRequired',true,
    'autoVerified',false
  );
end;
$$;

revoke all on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) from public,anon,authenticated;
grant execute on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) to service_role;

create or replace function public.pandora_tax_review_document_extraction_v1(
  p_organization_id uuid,
  p_extraction_id uuid,
  p_decision text,
  p_review_notes text default null,
  p_evidence_redacted jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  extraction_row public.tax_document_extractions%rowtype;
  document_row public.tax_documents%rowtype;
  normalized_decision text := lower(btrim(coalesce(p_decision,'')));
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_manage_org_v1(p_organization_id) then
    raise exception 'pandora_tax_manager_required' using errcode='42501';
  end if;
  if normalized_decision not in ('verified','rejected')
     or p_review_notes is not null and length(p_review_notes)>2000
     or jsonb_typeof(coalesce(p_evidence_redacted,'{}'::jsonb))<>'object'
  then
    raise exception 'pandora_tax_review_invalid' using errcode='22023';
  end if;

  select * into extraction_row
  from public.tax_document_extractions
  where id=p_extraction_id and organization_id=p_organization_id
  for update;

  if extraction_row.id is null then
    raise exception 'pandora_tax_extraction_not_found' using errcode='P0002';
  end if;

  if extraction_row.status in ('verified','rejected') then
    if extraction_row.status=normalized_decision
       and extraction_row.reviewed_by=uid
    then
      return jsonb_build_object(
        'schemaVersion','pandora.tax.review.v1',
        'extractionId',extraction_row.id,
        'documentId',extraction_row.document_id,
        'decision',extraction_row.status,
        'replayed',true
      );
    end if;
    raise exception 'pandora_tax_extraction_already_reviewed' using errcode='23505';
  end if;
  if extraction_row.status<>'review_required' then
    raise exception 'pandora_tax_extraction_not_reviewable' using errcode='55000';
  end if;

  select * into document_row
  from public.tax_documents
  where id=extraction_row.document_id
    and organization_id=p_organization_id
  for update;
  if document_row.id is null
     or document_row.content_sha256<>extraction_row.document_sha256
  then
    raise exception 'pandora_tax_extraction_document_binding_drift' using errcode='55000';
  end if;

  update public.tax_document_extractions
  set status=normalized_decision,
      reviewed_by=uid,
      reviewed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where id=extraction_row.id and organization_id=p_organization_id
  returning * into extraction_row;

  insert into public.tax_document_reviews(
    organization_id,document_id,extraction_id,decision,
    reviewer_user_id,review_notes,evidence_redacted
  ) values (
    p_organization_id,document_row.id,extraction_row.id,normalized_decision,
    uid,p_review_notes,coalesce(p_evidence_redacted,'{}'::jsonb)
  );

  if normalized_decision='verified' then
    update public.tax_document_extractions
    set status='superseded',updated_at=clock_timestamp()
    where organization_id=p_organization_id
      and document_id=document_row.id
      and id<>extraction_row.id
      and status='verified';

    update public.tax_documents
    set extraction_state='verified',
        extraction_confidence=extraction_row.overall_confidence,
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  else
    update public.tax_documents
    set extraction_state='review_required',
        updated_at=clock_timestamp()
    where id=document_row.id and organization_id=p_organization_id;
  end if;

  insert into public.tax_audit_events(
    organization_id,event_type,actor_user_id,actor_type,
    source_type,source_ref,event_payload_redacted
  ) values (
    p_organization_id,'tax_document_extraction_reviewed',uid,'user',
    'pandora_tax_review_document_extraction_v1',extraction_row.id::text,
    jsonb_build_object(
      'documentId',document_row.id,
      'extractionId',extraction_row.id,
      'decision',normalized_decision
    )
  );

  return jsonb_build_object(
    'schemaVersion','pandora.tax.review.v1',
    'extractionId',extraction_row.id,
    'documentId',document_row.id,
    'decision',normalized_decision,
    'reviewedBy',uid,
    'replayed',false
  );
end;
$$;

revoke all on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) from public,anon;
grant execute on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) to authenticated;

create or replace function public.pandora_tax_evidence_inbox_v1(
  p_organization_id uuid,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','auth'
as $$
declare
  uid uuid := auth.uid();
  bounded_limit integer := least(greatest(coalesce(p_limit,25),1),100);
  pending_count integer;
  review_count integer;
  verified_count integer;
  duplicate_source_count integer;
  recent_documents jsonb;
begin
  if uid is null then
    raise exception 'pandora_tax_sign_in_required' using errcode='42501';
  end if;
  if not public.pandora_tax_can_read_org_v1(p_organization_id) then
    raise exception 'pandora_tax_membership_required' using errcode='42501';
  end if;

  select
    count(*) filter (where extraction_state in ('pending','processing','failed'))::integer,
    count(*) filter (where extraction_state='review_required')::integer,
    count(*) filter (where extraction_state='verified')::integer
  into pending_count,review_count,verified_count
  from public.tax_documents
  where organization_id=p_organization_id;

  select count(*)::integer into duplicate_source_count
  from public.tax_document_links
  where organization_id=p_organization_id
    and link_type='duplicate_source';

  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc,d.id desc),'[]'::jsonb)
  into recent_documents
  from (
    select
      td.id,
      td.document_type,
      td.document_date,
      td.extraction_state,
      td.extraction_confidence,
      left(td.content_sha256,16) as content_sha256_prefix,
      td.created_at,
      (
        select count(*)::integer
        from public.tax_document_links l
        where l.organization_id=td.organization_id
          and l.document_id=td.id
          and l.linked_entity_type='source_object'
      ) as source_count
    from public.tax_documents td
    where td.organization_id=p_organization_id
    order by td.created_at desc,td.id desc
    limit bounded_limit
  ) d;

  return jsonb_build_object(
    'schemaVersion','pandora.tax.evidence-inbox.v1',
    'organizationId',p_organization_id,
    'generatedAt',clock_timestamp(),
    'summary',jsonb_build_object(
      'pendingOrFailed',pending_count,
      'needsReview',review_count,
      'verified',verified_count,
      'duplicateSources',duplicate_source_count
    ),
    'documents',recent_documents,
    'rawEvidenceIncluded',false
  );
end;
$$;

revoke all on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  from public,anon;
grant execute on function public.pandora_tax_evidence_inbox_v1(uuid,integer)
  to authenticated;

comment on table public.tax_evidence_hashes is
  'Tenant-scoped SHA-256 evidence registry. One content hash maps to one canonical tax document per organization.';
comment on table public.tax_document_extractions is
  'Provider/model/parser output. New extraction attempts are review_required and cannot self-verify.';
comment on function public.pandora_tax_register_evidence_v1(
  uuid,uuid,text,text,timestamptz,text,bigint,text,text,date,text,text,jsonb,uuid
) is
  'Service-role evidence registrar. Accepts metadata and an already-computed SHA-256 only; raw file bytes stay in authorized storage.';
comment on function public.pandora_tax_commit_document_extraction_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,numeric,text,jsonb
) is
  'Service-role extraction commit. Always produces review_required; model/provider output never becomes verified by itself.';
comment on function public.pandora_tax_review_document_extraction_v1(
  uuid,uuid,text,text,jsonb
) is
  'Owner/admin human review boundary for tax document extraction.';
