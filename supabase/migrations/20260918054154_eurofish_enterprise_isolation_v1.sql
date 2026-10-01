
create schema if not exists eurofish;

revoke all on schema eurofish from public;
revoke all on schema eurofish from anon;
revoke all on schema eurofish from authenticated;

create table if not exists eurofish.business_profile (
  id uuid primary key default gen_random_uuid(),
  business_key text not null unique default 'enterprise-eurofish',
  display_name text not null,
  legal_name text not null,
  timezone text not null default 'Asia/Manila',
  currency text not null default 'PHP',
  address_text text,
  profile_status text not null default 'verified_public_profile',
  source_observed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.business_facts (
  id uuid primary key default gen_random_uuid(),
  fact_key text not null unique,
  label text not null,
  fact_value jsonb not null default '{}'::jsonb,
  truth_status text not null check (truth_status in ('verified','verified_historical','company_claim','external_intelligence','requires_current_verification','rejected')),
  source_kind text not null,
  source_name text not null,
  source_url text,
  observed_at timestamptz,
  verified_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.source_connections (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  display_name text not null,
  source_type text not null,
  status text not null check (status in ('verified','connected','manual','stale','not_connected','error')),
  last_success_at timestamptz,
  last_attempt_at timestamptz,
  customer_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.access_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','operator','viewer')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.customers (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  status text not null default 'active',
  contact jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  data_status text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.suppliers (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  country text,
  commodity_scope text[] not null default '{}'::text[],
  status text not null default 'candidate',
  provenance_status text not null default 'manual',
  external_confidence numeric(5,4),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (external_confidence is null or (external_confidence >= 0 and external_confidence <= 1))
);

create table if not exists eurofish.evidence_items (
  id uuid primary key default gen_random_uuid(),
  object_type text not null,
  object_id uuid,
  evidence_type text not null,
  title text not null,
  source_kind text not null,
  source_name text,
  source_url text,
  source_observed_at timestamptz,
  verification_status text not null default 'unverified',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists eurofish.shipments (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  lane_type text not null check (lane_type in ('milkfish_fry','flowers','other_aquatics','mixed')),
  status text not null default 'planned',
  supplier_id uuid references eurofish.suppliers(id),
  origin_country text,
  origin_location text,
  eta timestamptz,
  actual_arrival_at timestamptz,
  clearance_status text not null default 'not_started',
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.shipment_milestones (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references eurofish.shipments(id) on delete cascade,
  milestone_type text not null,
  status text not null default 'planned',
  expected_at timestamptz,
  actual_at timestamptz,
  evidence_id uuid references eurofish.evidence_items(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists eurofish.biological_lots (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid references eurofish.shipments(id),
  lot_code text not null unique,
  species text not null default 'Milkfish',
  grade text,
  expected_heads bigint,
  received_heads bigint,
  mortality_heads bigint,
  conditioned_heads bigint,
  reserved_heads bigint,
  dispatched_heads bigint,
  location text,
  condition_status text,
  data_status text not null default 'manual',
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (coalesce(expected_heads,0) >= 0 and coalesce(received_heads,0) >= 0 and coalesce(mortality_heads,0) >= 0 and coalesce(conditioned_heads,0) >= 0 and coalesce(reserved_heads,0) >= 0 and coalesce(dispatched_heads,0) >= 0)
);

create table if not exists eurofish.flower_lots (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid references eurofish.shipments(id),
  lot_code text not null unique,
  variety text,
  origin_country text,
  received_stems bigint,
  rejected_stems bigint,
  reserved_stems bigint,
  dispatched_stems bigint,
  condition_status text,
  cold_chain_status text,
  data_status text not null default 'manual',
  received_at timestamptz,
  sell_first_by timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (coalesce(received_stems,0) >= 0 and coalesce(rejected_stems,0) >= 0 and coalesce(reserved_stems,0) >= 0 and coalesce(dispatched_stems,0) >= 0)
);

create table if not exists eurofish.quotes (
  id uuid primary key default gen_random_uuid(),
  quote_number text not null unique,
  customer_id uuid references eurofish.customers(id),
  status text not null default 'draft',
  currency text not null default 'PHP',
  total_amount numeric(18,2),
  valid_until timestamptz,
  requested_delivery_at timestamptz,
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  quote_id uuid references eurofish.quotes(id),
  customer_id uuid references eurofish.customers(id),
  status text not null default 'confirmed',
  currency text not null default 'PHP',
  total_amount numeric(18,2),
  committed_delivery_at timestamptz,
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.allocations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references eurofish.orders(id) on delete cascade,
  object_type text not null check (object_type in ('biological_lot','flower_lot')),
  object_id uuid not null,
  quantity numeric(18,2) not null check (quantity >= 0),
  status text not null default 'reserved',
  created_at timestamptz not null default now()
);

create table if not exists eurofish.deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references eurofish.orders(id),
  reference text unique,
  status text not null default 'planned',
  planned_at timestamptz,
  delivered_at timestamptz,
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.receivables (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references eurofish.customers(id),
  order_id uuid references eurofish.orders(id),
  invoice_number text unique,
  currency text not null default 'PHP',
  amount numeric(18,2),
  due_at timestamptz,
  paid_at timestamptz,
  status text not null default 'unbilled',
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.compliance_cases (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid references eurofish.shipments(id),
  regulator text not null,
  case_type text not null,
  status text not null default 'required',
  valid_from timestamptz,
  valid_until timestamptz,
  blocking boolean not null default false,
  data_status text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists eurofish.business_events (
  id uuid primary key default gen_random_uuid(),
  object_type text not null,
  object_id uuid,
  event_type text not null,
  event_at timestamptz not null default now(),
  actor_ref text,
  source_kind text not null default 'pandora',
  source_ref text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists eurofish.memory_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  memory_namespace text not null default 'enterprise:eurofish',
  project_key text not null default 'enterprise-eurofish',
  event_type text not null,
  object_type text not null,
  object_id uuid,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','published','failed','superseded')),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  error_code text
);

create index if not exists eurofish_shipments_status_eta_idx on eurofish.shipments(status, eta);
create index if not exists eurofish_shipments_supplier_idx on eurofish.shipments(supplier_id);
create index if not exists eurofish_milestones_shipment_idx on eurofish.shipment_milestones(shipment_id, expected_at);
create index if not exists eurofish_biolots_shipment_idx on eurofish.biological_lots(shipment_id);
create index if not exists eurofish_flowerlots_sellfirst_idx on eurofish.flower_lots(sell_first_by);
create index if not exists eurofish_orders_customer_status_idx on eurofish.orders(customer_id, status);
create index if not exists eurofish_allocations_order_idx on eurofish.allocations(order_id);
create index if not exists eurofish_receivables_due_status_idx on eurofish.receivables(status, due_at);
create index if not exists eurofish_compliance_shipment_status_idx on eurofish.compliance_cases(shipment_id, status);
create index if not exists eurofish_events_object_idx on eurofish.business_events(object_type, object_id, event_at desc);
create index if not exists eurofish_outbox_status_idx on eurofish.memory_outbox(status, created_at);

do $$
declare t text;
begin
  foreach t in array array[
    'business_profile','business_facts','source_connections','access_memberships','customers','suppliers',
    'evidence_items','shipments','shipment_milestones','biological_lots','flower_lots','quotes','orders',
    'allocations','deliveries','receivables','compliance_cases','business_events','memory_outbox'
  ]
  loop
    execute format('alter table eurofish.%I enable row level security', t);
    execute format('revoke all on table eurofish.%I from anon, authenticated', t);
  end loop;
end $$;

insert into eurofish.business_profile (
  business_key,display_name,legal_name,timezone,currency,address_text,profile_status,source_observed_at
) values (
  'enterprise-eurofish','1064 Euro-Fish Trading','1064 Euro-Fish Trading','Asia/Manila','PHP',
  '302, Ilang-Ilang St., Lakeview Subd., Putatan, Muntinlupa City',
  'verified_public_profile','2026-05-15T00:00:00+08:00'
)
on conflict (business_key) do update set
  display_name=excluded.display_name,
  legal_name=excluded.legal_name,
  timezone=excluded.timezone,
  currency=excluded.currency,
  address_text=excluded.address_text,
  profile_status=excluded.profile_status,
  source_observed_at=excluded.source_observed_at,
  updated_at=now();

insert into eurofish.business_facts
(fact_key,label,fact_value,truth_status,source_kind,source_name,source_url,observed_at,verified_at,notes)
values
(
 'bfar_commercial_importer_2026_05_15',
 'BFAR commercial importer',
 jsonb_build_object('region','NCR','purpose','Commercial','address','302, Ilang-Ilang St., Lakeview Subd., Putatan, Muntinlupa City'),
 'verified','government','BFAR',
 'https://www.bfar.da.gov.ph/wp-content/uploads/2026/05/List-of-Accredited-Importers-under-FAOs-195-221-and-233-as-of-May-15-2026.pdf',
 '2026-05-15T00:00:00+08:00',now(),
 'Official BFAR importer list. List position is not treated as a performance ranking.'
),
(
 'milkfish_fry_importer_2020',
 'Accredited live milkfish fry importer in 2020',
 jsonb_build_object('commodity','Live Milkfish Fry'),
 'verified_historical','government','Philippine Milkfish Industry Roadmap 2021-2040',
 'https://pcaf.da.gov.ph/wp-content/uploads/2022/06/Philippine-Milkfish-Industry-Roadmap-2021-2040.pdf',
 '2020-12-31T00:00:00+08:00',now(),
 'Historical accreditation evidence; not a claim about present shipment volume or survival outcomes.'
),
(
 'npqsd_importer_record_2022_2025',
 'NPQSD importer record',
 jsonb_build_object('scope',jsonb_build_array('Ornamental Plants','Orchids','Fresh Cut Flowers','Aquatic Plants','Rose Cut Flower','Quicksand rose','Toffee rose','Red protea','Pink protea'),'listed_expiry','2025-05-18'),
 'requires_current_verification','government','NPQSD',
 'https://npqsd.bpi-npqsd.com.ph/list-of-licensed-importers/',
 '2022-04-05T00:00:00+08:00',now(),
 'The public record verifies historical licensing scope but does not prove current 2026 renewal.'
)
on conflict (fact_key) do update set
 label=excluded.label,fact_value=excluded.fact_value,truth_status=excluded.truth_status,source_kind=excluded.source_kind,
 source_name=excluded.source_name,source_url=excluded.source_url,observed_at=excluded.observed_at,verified_at=excluded.verified_at,
 notes=excluded.notes,updated_at=now();

insert into eurofish.source_connections(source_key,display_name,source_type,status,last_success_at,customer_message)
values
 ('website_profile','Euro-Fish public business profile','public_profile','connected',now(),'Public profile available; operational values are not sourced from the website.'),
 ('bfar_registry','BFAR public registry','government_registry','verified',now(),'Current public accreditation evidence verified against the May 15, 2026 BFAR list.'),
 ('npqsd_registry','BPI / NPQSD public importer registry','government_registry','stale',null,'Historical importer record found; current renewal evidence still required.'),
 ('orders_quotes','Orders & quotes','business_system','not_connected',null,'Connect the authoritative commercial source before showing live quotes or orders.'),
 ('shipments','Shipments & logistics','business_system','not_connected',null,'Connect the authoritative logistics source before showing live arrivals or delays.'),
 ('inventory','Inventory & availability','business_system','not_connected',null,'Connect receiving/inventory events before showing physical, reserved, or ATP quantities.'),
 ('customers','Customers','business_system','not_connected',null,'Connect the authoritative customer source before showing customer activity.'),
 ('finance','Finance & receivables','business_system','not_connected',null,'Connect the accounting/collections source before showing money values.'),
 ('compliance_documents','Compliance documents','document_system','not_connected',null,'Connect current permits and shipment evidence before claiming operational compliance.')
on conflict (source_key) do update set
 display_name=excluded.display_name,source_type=excluded.source_type,status=excluded.status,last_success_at=excluded.last_success_at,
 customer_message=excluded.customer_message,updated_at=now();

create or replace function eurofish.queue_memory_event_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog,eurofish
as $$
begin
  insert into eurofish.memory_outbox(event_key,event_type,object_type,object_id,payload)
  values (
    'business_event:' || new.id::text,
    new.event_type,
    new.object_type,
    new.object_id,
    jsonb_build_object(
      'business_event_id',new.id,
      'event_at',new.event_at,
      'actor_ref',new.actor_ref,
      'source_kind',new.source_kind,
      'source_ref',new.source_ref,
      'details',new.details
    )
  )
  on conflict (event_key) do nothing;
  return new;
end $$;

drop trigger if exists eurofish_business_event_memory_outbox on eurofish.business_events;
create trigger eurofish_business_event_memory_outbox
after insert on eurofish.business_events
for each row execute function eurofish.queue_memory_event_v1();

create or replace function public.pandora_eurofish_workspace_v1(p_surface text default 'overview')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,eurofish
as $$
declare
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_profile jsonb;
  v_facts jsonb;
  v_sources jsonb;
begin
  if v_surface not in ('overview','commercial','import_operations','aquaculture','floriculture','customers','suppliers','compliance','finance','evidence','integrations','admin') then
    v_surface := 'overview';
  end if;

  select jsonb_build_object(
    'businessKey',business_key,
    'displayName',display_name,
    'legalName',legal_name,
    'timezone',timezone,
    'currency',currency,
    'address',address_text,
    'status',profile_status,
    'observedAt',source_observed_at
  ) into v_profile
  from eurofish.business_profile
  where business_key='enterprise-eurofish'
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',fact_key,'label',label,'value',fact_value,'truthStatus',truth_status,
    'sourceKind',source_kind,'sourceName',source_name,'sourceUrl',source_url,
    'observedAt',observed_at,'verifiedAt',verified_at,'notes',notes
  ) order by fact_key),'[]'::jsonb)
  into v_facts
  from eurofish.business_facts;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',source_key,'name',display_name,'type',source_type,'status',status,
    'lastSuccessAt',last_success_at,'lastAttemptAt',last_attempt_at,'message',customer_message
  ) order by source_key),'[]'::jsonb)
  into v_sources
  from eurofish.source_connections;

  return jsonb_build_object(
    'projectKey','enterprise-eurofish',
    'memoryNamespace','enterprise:eurofish',
    'surface',v_surface,
    'profile',coalesce(v_profile,'{}'::jsonb),
    'facts',v_facts,
    'sources',v_sources,
    'dataTruth',jsonb_build_object(
      'live','source + sync time',
      'verified','evidence-backed',
      'manual','entered with provenance',
      'stale','last known state is old',
      'notConnected','no authoritative operational source',
      'externalIntelligence','never silently merged into internal truth'
    ),
    'operatingModel',jsonb_build_array(
      'Demand','Quote','Commitment','Supplier','Purchase','Permit','Booking','Flight','Arrival','Inspection',
      'Clearance','Release','Receiving','Condition/Survival','Allocation','Delivery','Invoice','Collection','Outcome'
    ),
    'generatedAt',now()
  );
end $$;

revoke all on function public.pandora_eurofish_workspace_v1(text) from public;
grant execute on function public.pandora_eurofish_workspace_v1(text) to anon, authenticated;

create or replace function public.pandora_eurofish_private_workspace_v1(p_surface text default 'overview')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,eurofish
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select role into v_role
  from eurofish.access_memberships
  where user_id=v_uid and active=true;

  if v_role is null then
    raise exception 'eurofish access denied' using errcode='42501';
  end if;

  if v_surface not in ('overview','commercial','import_operations','aquaculture','floriculture','customers','suppliers','compliance','finance','evidence','integrations','admin') then
    v_surface := 'overview';
  end if;

  v_result := jsonb_build_object(
    'projectKey','enterprise-eurofish',
    'memoryNamespace','enterprise:eurofish',
    'surface',v_surface,
    'actorRole',v_role,
    'counts',jsonb_build_object(
      'customers',(select count(*) from eurofish.customers),
      'suppliers',(select count(*) from eurofish.suppliers),
      'shipments',(select count(*) from eurofish.shipments),
      'biologicalLots',(select count(*) from eurofish.biological_lots),
      'flowerLots',(select count(*) from eurofish.flower_lots),
      'quotes',(select count(*) from eurofish.quotes),
      'orders',(select count(*) from eurofish.orders),
      'receivables',(select count(*) from eurofish.receivables),
      'complianceCases',(select count(*) from eurofish.compliance_cases)
    ),
    'generatedAt',now()
  );

  return v_result;
end $$;

revoke all on function public.pandora_eurofish_private_workspace_v1(text) from public;
grant execute on function public.pandora_eurofish_private_workspace_v1(text) to authenticated;

