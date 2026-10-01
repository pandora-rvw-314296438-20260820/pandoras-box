-- Pandora Industry Packs + Onboarding Activation v1
-- Industry packs extend the Universal Core rather than redefine it.

-- ---------------------------------------------------------------------------
-- Pack catalog and onboarding
-- ---------------------------------------------------------------------------

create table if not exists public.pandora_industry_packs (
  pack_key text not null
    check (pack_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  pack_version text not null
    check (pack_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  display_name text not null,
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','deprecated','retired')),
  description text not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(pack_key,pack_version)
);

insert into public.pandora_industry_packs(pack_key,pack_version,display_name,description)
values
  ('hospitality','1.0.0','Hospitality','Hotel and resort operational extensions.'),
  ('restaurant','1.0.0','Restaurant','Restaurant and food-service operational extensions.'),
  ('legal','1.0.0','Legal','Law-office matter, hearing, filing, and evidence extensions.'),
  ('trade','1.0.0','Import / Export','Import-export, shipment, customs, and trade-document extensions.'),
  ('retail','1.0.0','Retail','Store, sale, return, SKU, and stock-position extensions.'),
  ('custom','1.0.0','Custom Business','Namespaced custom extensions that cannot override Core semantics.')
on conflict(pack_key,pack_version) do nothing;

create table if not exists public.pandora_industry_pack_entities (
  pack_key text not null,
  pack_version text not null,
  entity_key text not null
    check (entity_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  core_projection text not null
    check (core_projection in ('person','location','money_account','transaction','product_service','inventory_item','asset','contract','document','task','event','device','identity_ref','policy','relationship','industry_entity')),
  entity_kind text,
  typed_table text not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(pack_key,pack_version,entity_key),
  constraint pandora_industry_pack_entities_pack_fkey
    foreign key(pack_key,pack_version)
    references public.pandora_industry_packs(pack_key,pack_version)
    on delete restrict,
  check (
    (core_projection='industry_entity' and entity_kind is not null)
    or
    (core_projection<>'industry_entity')
  )
);

create table if not exists public.pandora_industry_authority_defaults (
  pack_key text not null,
  pack_version text not null,
  entity_key text not null,
  field_path text not null default '*',
  authority_kind text not null
    check (authority_kind in ('source_of_record','pandora_derived','advisory','fallback_source')),
  source_role text not null,
  rationale text not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(pack_key,pack_version,entity_key,field_path,source_role),
  constraint pandora_industry_authority_defaults_entity_fkey
    foreign key(pack_key,pack_version,entity_key)
    references public.pandora_industry_pack_entities(pack_key,pack_version,entity_key)
    on delete restrict
);

create table if not exists public.pandora_industry_pack_mappings (
  id uuid primary key default gen_random_uuid(),
  pack_key text not null,
  pack_version text not null,
  mapping_key text not null
    check (mapping_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  source_system_role text not null,
  source_object_type text not null,
  target_entity_key text not null,
  mapping_contract jsonb not null check (jsonb_typeof(mapping_contract)='object'),
  mapping_version text not null
    check (mapping_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(pack_key,pack_version,mapping_key,mapping_version),
  constraint pandora_industry_pack_mappings_pack_fkey
    foreign key(pack_key,pack_version,target_entity_key)
    references public.pandora_industry_pack_entities(pack_key,pack_version,entity_key)
    on delete restrict
);

create table if not exists public.pandora_workspace_industry_packs (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  pack_key text not null,
  pack_version text not null,
  activation_state text not null default 'active'
    check (activation_state in ('active','suspended','retired')),
  activated_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,pack_key),
  constraint pandora_workspace_industry_packs_pack_fkey
    foreign key(pack_key,pack_version)
    references public.pandora_industry_packs(pack_key,pack_version)
    on delete restrict
);

create table if not exists public.pandora_existing_system_inventory (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  system_key text not null check (system_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  display_name text not null,
  system_type text not null,
  owner_ref text,
  access_path text not null
    check (access_path in ('native_connector','standard','api','webhook','database_read','cdc','file','sftp','local_bridge','rpa','human')),
  authority_scope jsonb not null default '[]'::jsonb check (jsonb_typeof(authority_scope)='array'),
  risk_level text not null default 'medium' check (risk_level in ('low','medium','high','regulated')),
  coexistence_mode text not null default 'observe'
    check (coexistence_mode in ('observe','synchronize','coordinate','replace')),
  connection_id uuid,
  inventory_state text not null default 'inventoried'
    check (inventory_state in ('inventoried','connected','verified','retired')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,system_key),
  unique(id,organization_id),
  constraint pandora_existing_system_inventory_connection_org_fkey
    foreign key(connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict
);

create table if not exists public.pandora_custom_entity_types (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  namespace text not null
    check (namespace ~ '^[a-z][a-z0-9_]{1,31}$' and namespace not in ('core','hospitality','restaurant','legal','trade','retail')),
  type_key text not null check (type_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  type_version text not null check (type_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  generated_entity_kind text generated always as ('custom_'||namespace||'_'||type_key) stored,
  definition_schema jsonb not null check (jsonb_typeof(definition_schema)='object'),
  lifecycle_state text not null default 'active' check (lifecycle_state in ('active','deprecated','retired')),
  created_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,namespace,type_key,type_version),
  unique(organization_id,generated_entity_kind,type_version)
);

-- ---------------------------------------------------------------------------
-- New industry entity kinds
-- ---------------------------------------------------------------------------

insert into public.enterprise_entity_type_registry(entity_kind,namespace,display_name,schema_version)
values
  ('hospitality_reservation','hospitality','Reservation','1.0.0'),
  ('hospitality_stay','hospitality','Stay','1.0.0'),
  ('hospitality_folio','hospitality','Folio','1.0.0'),
  ('restaurant_order','restaurant','Order','1.0.0'),
  ('restaurant_check','restaurant','Check','1.0.0'),
  ('restaurant_recipe','restaurant','Recipe','1.0.0'),
  ('legal_matter','legal','Matter','1.0.0'),
  ('legal_hearing','legal','Hearing','1.0.0'),
  ('legal_filing','legal','Filing','1.0.0'),
  ('trade_shipment','trade','Shipment','1.0.0'),
  ('trade_container','trade','Container','1.0.0'),
  ('trade_customs_entry','trade','Customs Entry','1.0.0'),
  ('retail_sale','retail','Sale','1.0.0'),
  ('retail_return','retail','Return','1.0.0')
on conflict(entity_kind) do nothing;

-- ---------------------------------------------------------------------------
-- Hospitality pack
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_hospitality_guest_profiles (
  person_entity_id uuid primary key,
  organization_id uuid not null,
  vip_state text not null default 'standard'
    check (vip_state in ('standard','vip','do_not_upgrade')),
  preference_summary jsonb not null default '{}'::jsonb check (jsonb_typeof(preference_summary)='object'),
  loyalty_ref_hmac_sha256 text
    check (loyalty_ref_hmac_sha256 is null or loyalty_ref_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(person_entity_id,organization_id),
  constraint enterprise_hospitality_guest_profiles_person_org_fkey
    foreign key(person_entity_id,organization_id)
    references public.enterprise_people(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_hospitality_rooms (
  location_entity_id uuid primary key,
  organization_id uuid not null,
  room_code text not null,
  room_class text,
  room_state text not null default 'available'
    check (room_state in ('available','occupied','dirty','inspection','maintenance','out_of_order')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(location_entity_id,organization_id),
  unique(organization_id,room_code),
  constraint enterprise_hospitality_rooms_location_org_fkey
    foreign key(location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_hospitality_reservations (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'hospitality_reservation' check (entity_kind='hospitality_reservation'),
  guest_person_entity_id uuid not null,
  room_location_entity_id uuid,
  reservation_state text not null
    check (reservation_state in ('inquiry','held','confirmed','cancelled','no_show','completed')),
  arrival_date date not null,
  departure_date date not null,
  source_record_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_hospitality_reservations_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_hospitality_reservations_guest_org_fkey
    foreign key(guest_person_entity_id,organization_id)
    references public.enterprise_people(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_hospitality_reservations_room_org_fkey
    foreign key(room_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_hospitality_reservations_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  check (departure_date>arrival_date)
);

create table if not exists public.enterprise_hospitality_stays (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'hospitality_stay' check (entity_kind='hospitality_stay'),
  reservation_entity_id uuid,
  guest_person_entity_id uuid not null,
  room_location_entity_id uuid,
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  stay_state text not null
    check (stay_state in ('expected','in_house','departed','cancelled')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_hospitality_stays_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_hospitality_stays_reservation_org_fkey
    foreign key(reservation_entity_id,organization_id)
    references public.enterprise_hospitality_reservations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_hospitality_stays_guest_org_fkey
    foreign key(guest_person_entity_id,organization_id)
    references public.enterprise_people(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_hospitality_stays_room_org_fkey
    foreign key(room_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  check (checked_out_at is null or checked_in_at is null or checked_out_at>=checked_in_at)
);

create table if not exists public.enterprise_hospitality_folios (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'hospitality_folio' check (entity_kind='hospitality_folio'),
  stay_entity_id uuid,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  folio_state text not null default 'open' check (folio_state in ('open','settled','void')),
  balance_amount numeric(20,6) not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_hospitality_folios_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_hospitality_folios_stay_org_fkey
    foreign key(stay_entity_id,organization_id)
    references public.enterprise_hospitality_stays(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_hospitality_housekeeping_jobs (
  task_entity_id uuid primary key,
  organization_id uuid not null,
  room_location_entity_id uuid not null,
  housekeeping_type text not null
    check (housekeeping_type in ('clean','turnover','inspection','turndown','linen','other')),
  created_at timestamptz not null default clock_timestamp(),
  unique(task_entity_id,organization_id),
  constraint enterprise_hospitality_housekeeping_jobs_task_org_fkey
    foreign key(task_entity_id,organization_id)
    references public.enterprise_tasks(entity_id,organization_id)
    on delete cascade,
  constraint enterprise_hospitality_housekeeping_jobs_room_org_fkey
    foreign key(room_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Restaurant pack
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_restaurant_menu_items (
  product_entity_id uuid primary key,
  organization_id uuid not null,
  menu_section text,
  kitchen_station text,
  sellable boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  unique(product_entity_id,organization_id),
  constraint enterprise_restaurant_menu_items_product_org_fkey
    foreign key(product_entity_id,organization_id)
    references public.enterprise_products_services(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_restaurant_tables (
  location_entity_id uuid primary key,
  organization_id uuid not null,
  table_code text not null,
  capacity integer not null check (capacity>0),
  table_state text not null default 'available'
    check (table_state in ('available','reserved','occupied','blocked')),
  unique(location_entity_id,organization_id),
  unique(organization_id,table_code),
  constraint enterprise_restaurant_tables_location_org_fkey
    foreign key(location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_restaurant_recipes (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'restaurant_recipe' check (entity_kind='restaurant_recipe'),
  menu_product_entity_id uuid not null,
  recipe_version text not null,
  yield_quantity numeric(20,6) not null check (yield_quantity>0),
  ingredient_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(ingredient_refs)='array'),
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_restaurant_recipes_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_restaurant_recipes_menu_org_fkey
    foreign key(menu_product_entity_id,organization_id)
    references public.enterprise_products_services(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_restaurant_orders (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'restaurant_order' check (entity_kind='restaurant_order'),
  table_location_entity_id uuid,
  guest_person_entity_id uuid,
  order_state text not null
    check (order_state in ('open','submitted','preparing','served','cancelled','closed')),
  opened_at timestamptz not null,
  closed_at timestamptz,
  source_record_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_restaurant_orders_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_restaurant_orders_table_org_fkey
    foreign key(table_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_restaurant_orders_guest_org_fkey
    foreign key(guest_person_entity_id,organization_id)
    references public.enterprise_people(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_restaurant_orders_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  check (closed_at is null or closed_at>=opened_at)
);

create table if not exists public.enterprise_restaurant_checks (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'restaurant_check' check (entity_kind='restaurant_check'),
  order_entity_id uuid not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_amount numeric(20,6) not null default 0 check (total_amount>=0),
  check_state text not null default 'open' check (check_state in ('open','presented','settled','void')),
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_restaurant_checks_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_restaurant_checks_order_org_fkey
    foreign key(order_entity_id,organization_id)
    references public.enterprise_restaurant_orders(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_restaurant_kitchen_tickets (
  task_entity_id uuid primary key,
  organization_id uuid not null,
  order_entity_id uuid not null,
  station text,
  ticket_state text not null default 'open'
    check (ticket_state in ('open','preparing','ready','served','cancelled')),
  unique(task_entity_id,organization_id),
  constraint enterprise_restaurant_kitchen_tickets_task_org_fkey
    foreign key(task_entity_id,organization_id)
    references public.enterprise_tasks(entity_id,organization_id)
    on delete cascade,
  constraint enterprise_restaurant_kitchen_tickets_order_org_fkey
    foreign key(order_entity_id,organization_id)
    references public.enterprise_restaurant_orders(entity_id,organization_id)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Legal pack
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_legal_matters (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'legal_matter' check (entity_kind='legal_matter'),
  matter_reference text not null,
  client_entity_id uuid,
  matter_state text not null default 'open'
    check (matter_state in ('open','pending','closed','archived')),
  privileged boolean not null default true,
  opened_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  unique(entity_id,organization_id),
  unique(organization_id,matter_reference),
  constraint enterprise_legal_matters_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_legal_matters_client_org_fkey
    foreign key(client_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_legal_hearings (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'legal_hearing' check (entity_kind='legal_hearing'),
  matter_entity_id uuid not null,
  venue_location_entity_id uuid,
  scheduled_at timestamptz not null,
  hearing_state text not null default 'scheduled'
    check (hearing_state in ('scheduled','continued','completed','cancelled')),
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_legal_hearings_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_legal_hearings_matter_org_fkey
    foreign key(matter_entity_id,organization_id)
    references public.enterprise_legal_matters(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_legal_hearings_venue_org_fkey
    foreign key(venue_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_legal_filings (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'legal_filing' check (entity_kind='legal_filing'),
  matter_entity_id uuid not null,
  document_entity_id uuid not null,
  filing_state text not null default 'prepared'
    check (filing_state in ('prepared','submitted','accepted','rejected','withdrawn')),
  submitted_at timestamptz,
  authority_reference text,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_legal_filings_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_legal_filings_matter_org_fkey
    foreign key(matter_entity_id,organization_id)
    references public.enterprise_legal_matters(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_legal_filings_document_org_fkey
    foreign key(document_entity_id,organization_id)
    references public.enterprise_documents(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_legal_evidence_items (
  document_entity_id uuid primary key,
  organization_id uuid not null,
  matter_entity_id uuid not null,
  original_content_sha256 text not null check (original_content_sha256 ~ '^[0-9a-f]{64}$'),
  chain_of_custody jsonb not null default '[]'::jsonb check (jsonb_typeof(chain_of_custody)='array'),
  evidence_state text not null default 'preserved'
    check (evidence_state in ('preserved','reviewed','admitted','excluded','returned')),
  unique(document_entity_id,organization_id),
  constraint enterprise_legal_evidence_items_document_org_fkey
    foreign key(document_entity_id,organization_id)
    references public.enterprise_documents(entity_id,organization_id)
    on delete cascade,
  constraint enterprise_legal_evidence_items_matter_org_fkey
    foreign key(matter_entity_id,organization_id)
    references public.enterprise_legal_matters(entity_id,organization_id)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Trade pack
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_trade_incoterms (
  code text primary key check (code ~ '^[A-Z]{3}$'),
  display_name text not null
);

insert into public.enterprise_trade_incoterms(code,display_name)
values
 ('EXW','Ex Works'),('FCA','Free Carrier'),('CPT','Carriage Paid To'),('CIP','Carriage and Insurance Paid To'),
 ('DAP','Delivered At Place'),('DPU','Delivered at Place Unloaded'),('DDP','Delivered Duty Paid'),
 ('FAS','Free Alongside Ship'),('FOB','Free On Board'),('CFR','Cost and Freight'),('CIF','Cost, Insurance and Freight')
on conflict(code) do nothing;

create table if not exists public.enterprise_trade_shipments (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'trade_shipment' check (entity_kind='trade_shipment'),
  shipment_reference text not null,
  incoterm_code text references public.enterprise_trade_incoterms(code),
  origin_location_entity_id uuid,
  destination_location_entity_id uuid,
  shipment_state text not null default 'planned'
    check (shipment_state in ('planned','booked','in_transit','customs','delivered','cancelled')),
  source_record_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  unique(organization_id,shipment_reference),
  constraint enterprise_trade_shipments_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_trade_shipments_origin_org_fkey
    foreign key(origin_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_trade_shipments_destination_org_fkey
    foreign key(destination_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_trade_shipments_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_trade_containers (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'trade_container' check (entity_kind='trade_container'),
  shipment_entity_id uuid not null,
  container_number text not null,
  seal_number text,
  container_state text not null default 'planned'
    check (container_state in ('planned','loaded','in_transit','unloaded','returned')),
  unique(entity_id,organization_id),
  unique(organization_id,container_number),
  constraint enterprise_trade_containers_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_trade_containers_shipment_org_fkey
    foreign key(shipment_entity_id,organization_id)
    references public.enterprise_trade_shipments(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_trade_customs_entries (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'trade_customs_entry' check (entity_kind='trade_customs_entry'),
  shipment_entity_id uuid not null,
  authority_name text not null,
  authority_reference text,
  official_status text not null,
  observed_at timestamptz not null,
  source_record_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_trade_customs_entries_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_trade_customs_entries_shipment_org_fkey
    foreign key(shipment_entity_id,organization_id)
    references public.enterprise_trade_shipments(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_trade_customs_entries_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_trade_bills_of_lading (
  document_entity_id uuid primary key,
  organization_id uuid not null,
  shipment_entity_id uuid not null,
  carrier_reference text,
  document_number text not null,
  unique(document_entity_id,organization_id),
  unique(organization_id,document_number),
  constraint enterprise_trade_bills_of_lading_document_org_fkey
    foreign key(document_entity_id,organization_id)
    references public.enterprise_documents(entity_id,organization_id)
    on delete cascade,
  constraint enterprise_trade_bills_of_lading_shipment_org_fkey
    foreign key(shipment_entity_id,organization_id)
    references public.enterprise_trade_shipments(entity_id,organization_id)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Retail pack
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_retail_skus (
  product_entity_id uuid primary key,
  organization_id uuid not null,
  sku_code text not null,
  barcode text,
  sellable boolean not null default true,
  unique(product_entity_id,organization_id),
  unique(organization_id,sku_code),
  constraint enterprise_retail_skus_product_org_fkey
    foreign key(product_entity_id,organization_id)
    references public.enterprise_products_services(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_retail_stores (
  location_entity_id uuid primary key,
  organization_id uuid not null,
  store_code text not null,
  active boolean not null default true,
  unique(location_entity_id,organization_id),
  unique(organization_id,store_code),
  constraint enterprise_retail_stores_location_org_fkey
    foreign key(location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete cascade
);

create table if not exists public.enterprise_retail_sales (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'retail_sale' check (entity_kind='retail_sale'),
  store_location_entity_id uuid not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_amount numeric(20,6) not null check (total_amount>=0),
  sale_state text not null default 'completed'
    check (sale_state in ('pending','completed','void','refunded')),
  sold_at timestamptz not null,
  source_record_id uuid,
  unique(entity_id,organization_id),
  constraint enterprise_retail_sales_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_retail_sales_store_org_fkey
    foreign key(store_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict,
  constraint enterprise_retail_sales_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_retail_returns (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'retail_return' check (entity_kind='retail_return'),
  sale_entity_id uuid not null,
  return_state text not null default 'requested'
    check (return_state in ('requested','approved','received','refunded','rejected')),
  reason_code text,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_retail_returns_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_retail_returns_sale_org_fkey
    foreign key(sale_entity_id,organization_id)
    references public.enterprise_retail_sales(entity_id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_retail_stock_positions (
  inventory_entity_id uuid primary key,
  organization_id uuid not null,
  store_location_entity_id uuid not null,
  stock_state text not null default 'available'
    check (stock_state in ('available','reserved','damaged','in_transit')),
  unique(inventory_entity_id,organization_id),
  constraint enterprise_retail_stock_positions_inventory_org_fkey
    foreign key(inventory_entity_id,organization_id)
    references public.enterprise_inventory_items(entity_id,organization_id)
    on delete cascade,
  constraint enterprise_retail_stock_positions_store_org_fkey
    foreign key(store_location_entity_id,organization_id)
    references public.enterprise_locations(entity_id,organization_id)
    on delete restrict
);

-- ---------------------------------------------------------------------------
-- Pack metadata seed
-- ---------------------------------------------------------------------------

insert into public.pandora_industry_pack_entities(pack_key,pack_version,entity_key,core_projection,entity_kind,typed_table)
values
  ('hospitality','1.0.0','guest','person',null,'public.enterprise_hospitality_guest_profiles'),
  ('hospitality','1.0.0','reservation','industry_entity','hospitality_reservation','public.enterprise_hospitality_reservations'),
  ('hospitality','1.0.0','stay','industry_entity','hospitality_stay','public.enterprise_hospitality_stays'),
  ('hospitality','1.0.0','room','location',null,'public.enterprise_hospitality_rooms'),
  ('hospitality','1.0.0','folio','industry_entity','hospitality_folio','public.enterprise_hospitality_folios'),
  ('hospitality','1.0.0','housekeeping_job','task',null,'public.enterprise_hospitality_housekeeping_jobs'),
  ('restaurant','1.0.0','order','industry_entity','restaurant_order','public.enterprise_restaurant_orders'),
  ('restaurant','1.0.0','check','industry_entity','restaurant_check','public.enterprise_restaurant_checks'),
  ('restaurant','1.0.0','menu_item','product_service',null,'public.enterprise_restaurant_menu_items'),
  ('restaurant','1.0.0','recipe','industry_entity','restaurant_recipe','public.enterprise_restaurant_recipes'),
  ('restaurant','1.0.0','table','location',null,'public.enterprise_restaurant_tables'),
  ('restaurant','1.0.0','kitchen_ticket','task',null,'public.enterprise_restaurant_kitchen_tickets'),
  ('legal','1.0.0','matter','industry_entity','legal_matter','public.enterprise_legal_matters'),
  ('legal','1.0.0','hearing','industry_entity','legal_hearing','public.enterprise_legal_hearings'),
  ('legal','1.0.0','filing','industry_entity','legal_filing','public.enterprise_legal_filings'),
  ('legal','1.0.0','evidence_item','document',null,'public.enterprise_legal_evidence_items'),
  ('trade','1.0.0','shipment','industry_entity','trade_shipment','public.enterprise_trade_shipments'),
  ('trade','1.0.0','container','industry_entity','trade_container','public.enterprise_trade_containers'),
  ('trade','1.0.0','customs_entry','industry_entity','trade_customs_entry','public.enterprise_trade_customs_entries'),
  ('trade','1.0.0','bill_of_lading','document',null,'public.enterprise_trade_bills_of_lading'),
  ('retail','1.0.0','sku','product_service',null,'public.enterprise_retail_skus'),
  ('retail','1.0.0','store','location',null,'public.enterprise_retail_stores'),
  ('retail','1.0.0','sale','industry_entity','retail_sale','public.enterprise_retail_sales'),
  ('retail','1.0.0','return','industry_entity','retail_return','public.enterprise_retail_returns'),
  ('retail','1.0.0','stock_position','inventory_item',null,'public.enterprise_retail_stock_positions')
on conflict(pack_key,pack_version,entity_key) do nothing;

insert into public.pandora_industry_authority_defaults(
  pack_key,pack_version,entity_key,field_path,authority_kind,source_role,rationale
) values
  ('hospitality','1.0.0','reservation','*','source_of_record','pms','Existing PMS may remain reservation authority.'),
  ('restaurant','1.0.0','order','*','source_of_record','pos','Existing POS may remain order authority.'),
  ('restaurant','1.0.0','check','*','source_of_record','pos','Existing POS may remain check authority.'),
  ('legal','1.0.0','evidence_item','*','source_of_record','document_system','Evidence originals and versions remain source authoritative.'),
  ('trade','1.0.0','customs_entry','official_status','source_of_record','customs_authority','Official customs status remains external authoritative.'),
  ('retail','1.0.0','sale','*','source_of_record','pos_or_commerce','POS or commerce system remains transaction authority.')
on conflict(pack_key,pack_version,entity_key,field_path,source_role) do nothing;

insert into public.pandora_industry_pack_mappings(
  pack_key,pack_version,mapping_key,source_system_role,source_object_type,target_entity_key,mapping_contract,mapping_version
) values
  ('hospitality','1.0.0','pms_guest','pms','guest','guest','{"sourceIdRequired":true,"preserveProviderId":true}'::jsonb,'1.0.0'),
  ('hospitality','1.0.0','pms_reservation','pms','reservation','reservation','{"sourceIdRequired":true,"preserveAuthority":true}'::jsonb,'1.0.0'),
  ('restaurant','1.0.0','pos_order','pos','order','order','{"sourceIdRequired":true,"preserveAuthority":true}'::jsonb,'1.0.0'),
  ('restaurant','1.0.0','pos_check','pos','check','check','{"sourceIdRequired":true,"preserveAuthority":true}'::jsonb,'1.0.0'),
  ('legal','1.0.0','dms_evidence','document_system','document','evidence_item','{"hashRequired":true,"versionRequired":true}'::jsonb,'1.0.0'),
  ('trade','1.0.0','logistics_shipment','logistics','shipment','shipment','{"sourceIdRequired":true,"preserveProviderId":true}'::jsonb,'1.0.0'),
  ('trade','1.0.0','customs_entry','customs_authority','customs_entry','customs_entry','{"sourceIdRequired":true,"externalAuthority":true}'::jsonb,'1.0.0'),
  ('retail','1.0.0','pos_sale','pos','sale','sale','{"sourceIdRequired":true,"preserveAuthority":true}'::jsonb,'1.0.0'),
  ('retail','1.0.0','erp_stock','erp','stock_position','stock_position','{"sourceIdRequired":true,"preserveAuthority":true}'::jsonb,'1.0.0')
on conflict(pack_key,pack_version,mapping_key,mapping_version) do nothing;

-- ---------------------------------------------------------------------------
-- Onboarding / activation readbacks
-- ---------------------------------------------------------------------------

create or replace function public.pandora_industry_pack_catalog_v1()
returns jsonb
language sql
security invoker
stable
set search_path='pg_catalog','public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'packKey',p.pack_key,
    'packVersion',p.pack_version,
    'displayName',p.display_name,
    'lifecycleState',p.lifecycle_state,
    'description',p.description,
    'entities',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'entityKey',e.entity_key,
        'coreProjection',e.core_projection,
        'entityKind',e.entity_kind,
        'typedTable',e.typed_table
      ) order by e.entity_key),'[]'::jsonb)
      from public.pandora_industry_pack_entities e
      where e.pack_key=p.pack_key and e.pack_version=p.pack_version
    )
  ) order by p.display_name),'[]'::jsonb)
  from public.pandora_industry_packs p
  where p.lifecycle_state<>'retired';
$$;

create or replace function public.pandora_workspace_onboarding_state_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_packs jsonb;
  v_systems jsonb;
  v_connections jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'packKey',w.pack_key,
    'packVersion',w.pack_version,
    'state',w.activation_state,
    'activatedAt',w.activated_at
  ) order by w.pack_key),'[]'::jsonb)
  into v_packs
  from public.pandora_workspace_industry_packs w
  where w.organization_id=p_organization_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'systemKey',s.system_key,
    'displayName',s.display_name,
    'systemType',s.system_type,
    'accessPath',s.access_path,
    'authorityScope',s.authority_scope,
    'riskLevel',s.risk_level,
    'coexistenceMode',s.coexistence_mode,
    'connectionId',s.connection_id,
    'state',s.inventory_state
  ) order by s.system_key),'[]'::jsonb)
  into v_systems
  from public.pandora_existing_system_inventory s
  where s.organization_id=p_organization_id;

  v_connections:=public.pandora_connector_runtime_v1(p_organization_id);

  return jsonb_build_object(
    'industryPacks',v_packs,
    'existingSystems',v_systems,
    'connections',v_connections
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS / grants
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
  v_read text;
  v_service text;
begin
  foreach v_table in array array[
    'pandora_industry_packs',
    'pandora_industry_pack_entities',
    'pandora_industry_authority_defaults',
    'pandora_industry_pack_mappings',
    'enterprise_trade_incoterms'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated,service_role',v_table);
    execute format('grant insert,update,delete on table public.%I to service_role',v_table);
    v_read:=v_table||'_authenticated_read';
    v_service:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_read,v_table);
    execute format('create policy %I on public.%I for select to authenticated using(true)',v_read,v_table);
    execute format('drop policy if exists %I on public.%I',v_service,v_table);
    execute format('create policy %I on public.%I for all to service_role using(true) with check(true)',v_service,v_table);
  end loop;

  foreach v_table in array array[
    'pandora_workspace_industry_packs',
    'pandora_existing_system_inventory',
    'pandora_custom_entity_types',
    'enterprise_hospitality_guest_profiles',
    'enterprise_hospitality_rooms',
    'enterprise_hospitality_reservations',
    'enterprise_hospitality_stays',
    'enterprise_hospitality_folios',
    'enterprise_hospitality_housekeeping_jobs',
    'enterprise_restaurant_menu_items',
    'enterprise_restaurant_tables',
    'enterprise_restaurant_recipes',
    'enterprise_restaurant_orders',
    'enterprise_restaurant_checks',
    'enterprise_restaurant_kitchen_tickets',
    'enterprise_legal_matters',
    'enterprise_legal_hearings',
    'enterprise_legal_filings',
    'enterprise_legal_evidence_items',
    'enterprise_trade_shipments',
    'enterprise_trade_containers',
    'enterprise_trade_customs_entries',
    'enterprise_trade_bills_of_lading',
    'enterprise_retail_skus',
    'enterprise_retail_stores',
    'enterprise_retail_sales',
    'enterprise_retail_returns',
    'enterprise_retail_stock_positions'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated',v_table);
    execute format('grant select,insert,update,delete on table public.%I to service_role',v_table);
    v_read:=v_table||'_member_select';
    v_service:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_read,v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.memberships m where m.organization_id=%I.organization_id and m.user_id=(select auth.uid()) and m.status=''active''))',
      v_read,v_table,v_table
    );
    execute format('drop policy if exists %I on public.%I',v_service,v_table);
    execute format('create policy %I on public.%I for all to service_role using(true) with check(true)',v_service,v_table);
  end loop;
end;
$$;

revoke all on function public.pandora_industry_pack_catalog_v1() from public,anon;
revoke all on function public.pandora_workspace_onboarding_state_v1(uuid) from public,anon;
grant execute on function public.pandora_industry_pack_catalog_v1() to authenticated,service_role;
grant execute on function public.pandora_workspace_onboarding_state_v1(uuid) to authenticated,service_role;

