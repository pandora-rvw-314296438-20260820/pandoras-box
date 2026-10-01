-- Pandora Universal Core + Compatibility Activation v1
-- Completes the typed Universal Core framework and installs the universal
-- compatibility contracts without replacing incumbent domain runtimes.

-- ---------------------------------------------------------------------------
-- PHASE 1: remaining typed Universal Core nouns
-- ---------------------------------------------------------------------------

insert into public.enterprise_entity_type_registry(entity_kind,namespace,display_name,schema_version)
values
  ('location','core','Location','1.0.0'),
  ('money_account','core','Money Account','1.0.0'),
  ('transaction','core','Transaction','1.0.0'),
  ('product_service','core','Product / Service','1.0.0'),
  ('inventory_item','core','Inventory Item','1.0.0'),
  ('asset','core','Asset','1.0.0'),
  ('contract','core','Contract','1.0.0'),
  ('document','core','Document','1.0.0'),
  ('task','core','Task / Work Item','1.0.0'),
  ('event','core','Event','1.0.0'),
  ('device','core','Device','1.0.0'),
  ('identity_ref','core','Identity / Credential Ref','1.0.0'),
  ('policy','core','Policy','1.0.0')
on conflict (entity_kind) do nothing;

create table if not exists public.enterprise_event_type_registry (
  event_type text primary key
    check (event_type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  namespace text not null
    check (namespace ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  display_name text not null
    check (char_length(display_name) between 1 and 160),
  schema_version text not null
    check (schema_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  created_at timestamptz not null default clock_timestamp()
);

insert into public.enterprise_event_type_registry(event_type,namespace,display_name,schema_version)
values
  ('business.object_observed','business','Object observed','1.0.0'),
  ('business.state_changed','business','State changed','1.0.0'),
  ('integration.source_received','integration','Source received','1.0.0'),
  ('integration.reconciled','integration','Reconciled','1.0.0'),
  ('execution.verified','execution','Execution verified','1.0.0')
on conflict (event_type) do nothing;

create table if not exists public.enterprise_locations (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'location' check (entity_kind='location'),
  location_type text not null
    check (location_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  display_name text
    check (display_name is null or char_length(display_name) between 1 and 240),
  address_structured jsonb not null default '{}'::jsonb
    check (jsonb_typeof(address_structured)='object'),
  geo_point jsonb not null default '{}'::jsonb
    check (jsonb_typeof(geo_point)='object'),
  timezone text,
  operating_rules jsonb not null default '{}'::jsonb
    check (jsonb_typeof(operating_rules)='object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_locations_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade
);

create table if not exists public.enterprise_money_accounts (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'money_account' check (entity_kind='money_account'),
  owner_entity_id uuid,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  provider_key text
    check (provider_key is null or provider_key ~ '^[a-z][a-z0-9_.-]{0,127}$'),
  provider_reference_hash text
    check (provider_reference_hash is null or provider_reference_hash ~ '^[0-9a-f]{64}$'),
  account_state text not null default 'active'
    check (account_state in ('active','restricted','closed')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_money_accounts_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_money_accounts_owner_org_fkey
    foreign key(owner_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_transactions (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'transaction' check (entity_kind='transaction'),
  transaction_type text not null
    check (transaction_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  amount numeric(20,6) not null check (amount>=0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  from_entity_id uuid,
  to_entity_id uuid,
  transaction_state text not null
    check (transaction_state in ('pending','authorized','settled','failed','reversed','cancelled')),
  occurred_at timestamptz not null,
  settled_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_transactions_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_transactions_from_org_fkey
    foreign key(from_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_transactions_to_org_fkey
    foreign key(to_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (settled_at is null or settled_at>=occurred_at)
);

create table if not exists public.enterprise_products_services (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'product_service' check (entity_kind='product_service'),
  name text not null check (char_length(name) between 1 and 240),
  category text,
  unit text,
  pricing_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(pricing_refs)='array'),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_products_services_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade
);

create table if not exists public.enterprise_inventory_items (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'inventory_item' check (entity_kind='inventory_item'),
  product_entity_id uuid not null,
  location_entity_id uuid,
  unit text not null,
  physical_quantity numeric(20,6) not null default 0,
  reserved_quantity numeric(20,6) not null default 0,
  available_quantity numeric(20,6) not null default 0,
  valued_quantity numeric(20,6),
  observed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_inventory_items_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_inventory_items_product_org_fkey
    foreign key(product_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_inventory_items_location_org_fkey
    foreign key(location_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_assets (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'asset' check (entity_kind='asset'),
  asset_type text not null check (asset_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  owner_entity_id uuid,
  location_entity_id uuid,
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active','maintenance','retired','disposed')),
  provider_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(provider_refs)='array'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_assets_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_assets_owner_org_fkey
    foreign key(owner_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_assets_location_org_fkey
    foreign key(location_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_contracts (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'contract' check (entity_kind='contract'),
  contract_type text not null check (contract_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  effective_from timestamptz,
  effective_to timestamptz,
  document_entity_id uuid,
  obligations jsonb not null default '[]'::jsonb
    check (jsonb_typeof(obligations)='array'),
  provider_constraints jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provider_constraints)='object'),
  contract_state text not null default 'draft'
    check (contract_state in ('draft','active','expired','terminated')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_contracts_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_contracts_document_org_fkey
    foreign key(document_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (effective_to is null or effective_from is null or effective_to>=effective_from)
);

create table if not exists public.enterprise_documents (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'document' check (entity_kind='document'),
  document_type text not null check (document_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  owner_entity_id uuid,
  version_number integer not null default 1 check (version_number>=1),
  source_record_id uuid,
  parent_document_entity_id uuid,
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  retention_until timestamptz,
  media_type text,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_documents_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_documents_owner_org_fkey
    foreign key(owner_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_documents_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_documents_parent_org_fkey
    foreign key(parent_document_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_tasks (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'task' check (entity_kind='task'),
  task_type text not null check (task_type ~ '^[a-z][a-z0-9_]{0,63}$'),
  owner_entity_id uuid,
  due_at timestamptz,
  task_state text not null default 'open'
    check (task_state in ('open','in_progress','blocked','completed','cancelled')),
  evidence_required boolean not null default false,
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array'),
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_tasks_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_tasks_owner_org_fkey
    foreign key(owner_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (
    (task_state='completed' and completed_at is not null)
    or
    (task_state<>'completed' and completed_at is null)
  )
);

create table if not exists public.enterprise_events (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'event' check (entity_kind='event'),
  event_type text not null
    references public.enterprise_event_type_registry(event_type) on delete restrict,
  actor_entity_id uuid,
  object_entity_id uuid,
  occurred_at timestamptz not null,
  source_record_id uuid,
  source_event_key text,
  evidence_refs jsonb not null default '[]'::jsonb
    check (jsonb_typeof(evidence_refs)='array'),
  payload_metadata_redacted jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload_metadata_redacted)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  unique(organization_id,source_event_key),
  constraint enterprise_events_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_events_actor_org_fkey
    foreign key(actor_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_events_object_org_fkey
    foreign key(object_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  constraint enterprise_events_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict
);

create index if not exists enterprise_events_org_time_idx
  on public.enterprise_events(organization_id,occurred_at desc,event_type);

create table if not exists public.enterprise_devices (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'device' check (entity_kind='device'),
  owner_entity_id uuid,
  model text,
  device_identifier_hmac_sha256 text
    check (device_identifier_hmac_sha256 is null or device_identifier_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  capabilities jsonb not null default '[]'::jsonb
    check (jsonb_typeof(capabilities)='array'),
  trust_state text not null default 'unknown'
    check (trust_state in ('unknown','trusted','restricted','revoked')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_devices_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  constraint enterprise_devices_owner_org_fkey
    foreign key(owner_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_identity_refs (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'identity_ref' check (entity_kind='identity_ref'),
  provider_key text not null check (provider_key ~ '^[a-z][a-z0-9_.-]{0,127}$'),
  subject_ref_hmac_sha256 text not null check (subject_ref_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  scopes text[] not null default '{}'::text[],
  identity_state text not null default 'active'
    check (identity_state in ('active','expired','revoked')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  constraint enterprise_identity_refs_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade
);

create table if not exists public.enterprise_policies (
  entity_id uuid primary key,
  organization_id uuid not null,
  entity_kind text not null default 'policy' check (entity_kind='policy'),
  policy_key text not null check (policy_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  policy_version text not null check (policy_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  scope_contract jsonb not null default '{}'::jsonb
    check (jsonb_typeof(scope_contract)='object'),
  condition_contract jsonb not null default '{}'::jsonb
    check (jsonb_typeof(condition_contract)='object'),
  effect_contract jsonb not null default '{}'::jsonb
    check (jsonb_typeof(effect_contract)='object'),
  approver_role text,
  effective_from timestamptz not null default clock_timestamp(),
  effective_to timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique(entity_id,organization_id),
  unique(organization_id,policy_key,policy_version),
  constraint enterprise_policies_entity_org_kind_fkey
    foreign key(entity_id,organization_id,entity_kind)
    references public.enterprise_entities(id,organization_id,entity_kind)
    on delete cascade,
  check (effective_to is null or effective_to>=effective_from)
);

create or replace function private.pandora_reject_enterprise_event_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'enterprise_events_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists enterprise_events_append_only on public.enterprise_events;
create trigger enterprise_events_append_only
before update or delete on public.enterprise_events
for each row execute function private.pandora_reject_enterprise_event_mutation_v1();

-- ---------------------------------------------------------------------------
-- PHASE 2: compatibility / anti-corruption fabric
-- ---------------------------------------------------------------------------

create table if not exists public.enterprise_connector_contracts (
  connector_kind text not null
    check (connector_kind ~ '^[a-z][a-z0-9_]{1,63}$'),
  contract_version text not null
    check (contract_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  lifecycle_capabilities text[] not null,
  supports_write boolean not null default false,
  default_read_only boolean not null default true,
  database_write_policy text not null default 'not_applicable'
    check (database_write_policy in ('not_applicable','prohibited','vendor_supported_only')),
  outbound_first boolean not null default false,
  evidence_required boolean not null default true,
  retry_contract jsonb not null default '{}'::jsonb
    check (jsonb_typeof(retry_contract)='object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key(connector_kind,contract_version)
);

insert into public.enterprise_connector_contracts(
  connector_kind,contract_version,lifecycle_capabilities,supports_write,
  default_read_only,database_write_policy,outbound_first,evidence_required,retry_contract
) values
  ('rest_api','1.0.0',array['connect','health','read','write','event','disconnect'],true,true,'not_applicable',false,true,'{"bounded":true,"idempotencyForWrites":true}'::jsonb),
  ('webhook','1.0.0',array['connect','health','event','disconnect'],false,true,'not_applicable',false,true,'{"checkpointReplay":true}'::jsonb),
  ('file_exchange','1.0.0',array['connect','health','read','write','disconnect'],true,true,'not_applicable',false,true,'{"schemaValidation":true,"sourceHashRequired":true}'::jsonb),
  ('database_cdc','1.0.0',array['connect','health','read','event','disconnect'],false,true,'prohibited',false,true,'{"cdcReplay":true}'::jsonb),
  ('local_bridge','1.0.0',array['connect','health','read','write','event','disconnect'],true,true,'vendor_supported_only',true,true,'{"outboundFirst":true}'::jsonb),
  ('rpa_fallback','1.0.0',array['connect','health','write','disconnect'],true,true,'not_applicable',false,true,'{"boundedActions":true}'::jsonb),
  ('human_assisted','1.0.0',array['read','write'],true,true,'not_applicable',false,true,'{"actorEvidenceRequired":true}'::jsonb)
on conflict(connector_kind,contract_version) do nothing;

create table if not exists public.enterprise_mapping_specs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid not null,
  mapping_key text not null check (mapping_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  mapping_version text not null check (mapping_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  source_object_type text not null,
  target_type_key text not null,
  transform_contract jsonb not null check (jsonb_typeof(transform_contract)='object'),
  mapping_sha256 text not null check (mapping_sha256 ~ '^[0-9a-f]{64}$'),
  mapping_state text not null default 'draft'
    check (mapping_state in ('draft','approved','retired')),
  approved_at timestamptz,
  approved_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  unique(organization_id,mapping_key,mapping_version),
  constraint enterprise_mapping_specs_connection_org_fkey
    foreign key(source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict,
  check (
    (mapping_state='approved' and approved_at is not null and approved_by is not null)
    or mapping_state<>'approved'
  )
);

create table if not exists public.enterprise_sync_checkpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid not null,
  mapping_spec_id uuid not null,
  direction text not null check (direction in ('inbound','outbound','two_way')),
  checkpoint_hash text check (checkpoint_hash is null or checkpoint_hash ~ '^[0-9a-f]{64}$'),
  last_source_event_key text,
  last_applied_digest text check (last_applied_digest is null or last_applied_digest ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  unique(organization_id,source_connection_id,mapping_spec_id,direction),
  constraint enterprise_sync_checkpoints_connection_org_fkey
    foreign key(source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict,
  constraint enterprise_sync_checkpoints_mapping_org_fkey
    foreign key(mapping_spec_id,organization_id)
    references public.enterprise_mapping_specs(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_sync_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  mapping_spec_id uuid not null,
  direction text not null check (direction in ('inbound','outbound')),
  source_event_digest text not null check (source_event_digest ~ '^[0-9a-f]{64}$'),
  target_write_digest text check (target_write_digest is null or target_write_digest ~ '^[0-9a-f]{64}$'),
  idempotency_key text not null check (char_length(idempotency_key) between 16 and 160),
  outcome text not null check (outcome in ('accepted','applied','duplicate','failed','pending_verification','verified')),
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  created_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  unique(organization_id,mapping_spec_id,direction,source_event_digest),
  constraint enterprise_sync_receipts_mapping_org_fkey
    foreign key(mapping_spec_id,organization_id)
    references public.enterprise_mapping_specs(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_webhook_checkpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid not null,
  stream_key text not null,
  checkpoint_hash text check (checkpoint_hash is null or checkpoint_hash ~ '^[0-9a-f]{64}$'),
  last_delivery_hash text check (last_delivery_hash is null or last_delivery_hash ~ '^[0-9a-f]{64}$'),
  replay_from timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,source_connection_id,stream_key),
  unique(id,organization_id),
  constraint enterprise_webhook_checkpoints_connection_org_fkey
    foreign key(source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_file_exchange_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_connection_id uuid,
  direction text not null check (direction in ('inbound','outbound')),
  file_format text not null check (file_format in ('csv','xlsx','xml','json','edi','sftp')),
  schema_version text not null,
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  source_ref text,
  receipt_state text not null default 'accepted'
    check (receipt_state in ('accepted','quarantined','processed','failed')),
  error_code text,
  created_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  unique(organization_id,direction,content_sha256),
  constraint enterprise_file_exchange_receipts_connection_org_fkey
    foreign key(source_connection_id,organization_id)
    references public.enterprise_integration_connections(id,organization_id)
    on delete restrict
);

create table if not exists public.enterprise_local_bridge_nodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  node_key text not null check (node_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,159}$'),
  outbound_only boolean not null default true check (outbound_only),
  mutual_identity_ref_hmac_sha256 text not null
    check (mutual_identity_ref_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  node_state text not null default 'configured'
    check (node_state in ('configured','healthy','degraded','revoked')),
  last_health_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,node_key),
  unique(id,organization_id)
);

create table if not exists public.enterprise_rpa_action_sets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  action_set_key text not null check (action_set_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  allowed_actions text[] not null check (cardinality(allowed_actions)>0),
  action_state text not null default 'disabled'
    check (action_state in ('disabled','enabled','suspended')),
  evidence_required boolean not null default true check (evidence_required),
  max_actions_per_session integer not null default 10 check (max_actions_per_session between 1 and 100),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,action_set_key),
  unique(id,organization_id)
);

create table if not exists public.enterprise_human_work_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  task_entity_id uuid,
  work_key text not null check (work_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,159}$'),
  work_state text not null default 'open'
    check (work_state in ('open','in_progress','completed','cancelled')),
  actor_ref text,
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  resulting_state_ref text,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique(organization_id,work_key),
  unique(id,organization_id),
  constraint enterprise_human_work_items_task_org_fkey
    foreign key(task_entity_id,organization_id)
    references public.enterprise_entities(id,organization_id)
    on delete restrict,
  check (
    (work_state='completed' and completed_at is not null and jsonb_array_length(evidence_refs)>0)
    or work_state<>'completed'
  )
);

create index if not exists enterprise_mapping_specs_connection_idx
  on public.enterprise_mapping_specs(organization_id,source_connection_id,mapping_state);
create index if not exists enterprise_sync_receipts_mapping_idx
  on public.enterprise_sync_receipts(organization_id,mapping_spec_id,created_at desc);
create index if not exists enterprise_file_exchange_receipts_org_state_idx
  on public.enterprise_file_exchange_receipts(organization_id,receipt_state,created_at desc);

create or replace function private.pandora_reject_compatibility_receipt_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'compatibility_receipts_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists enterprise_sync_receipts_append_only on public.enterprise_sync_receipts;
create trigger enterprise_sync_receipts_append_only
before update or delete on public.enterprise_sync_receipts
for each row execute function private.pandora_reject_compatibility_receipt_mutation_v1();

create or replace function public.pandora_connector_write_ready_v1(
  p_organization_id uuid,
  p_connection_id uuid,
  p_mapping_spec_id uuid
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_connection public.enterprise_integration_connections%rowtype;
  v_mapping public.enterprise_mapping_specs%rowtype;
  v_has_write boolean:=false;
  v_ready boolean:=false;
  v_reasons text[]:='{}'::text[];
begin
  select * into v_connection
  from public.enterprise_integration_connections
  where organization_id=p_organization_id and id=p_connection_id;

  if not found then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('connection_not_found'));
  end if;

  select * into v_mapping
  from public.enterprise_mapping_specs
  where organization_id=p_organization_id
    and id=p_mapping_spec_id
    and source_connection_id=p_connection_id;

  if not found then
    v_reasons:=array_append(v_reasons,'mapping_not_found');
  elsif v_mapping.mapping_state<>'approved' or v_mapping.approved_at is null then
    v_reasons:=array_append(v_reasons,'mapping_not_approved');
  end if;

  select exists(
    select 1
    from jsonb_array_elements_text(v_connection.granted_scopes) s(scope)
    where s.scope='*' or s.scope='write' or s.scope like 'write:%'
  ) into v_has_write;

  if not v_has_write then
    v_reasons:=array_append(v_reasons,'write_scope_not_granted');
  end if;
  if v_connection.capability_state<>'healthy' then
    v_reasons:=array_append(v_reasons,'connection_not_healthy');
  end if;
  if v_connection.coexistence_mode='observe' then
    v_reasons:=array_append(v_reasons,'observe_mode_is_read_only');
  end if;
  if v_connection.revoked_at is not null then
    v_reasons:=array_append(v_reasons,'connection_revoked');
  end if;

  v_ready:=cardinality(v_reasons)=0;
  return jsonb_build_object(
    'ready',v_ready,
    'connectionId',p_connection_id,
    'mappingSpecId',p_mapping_spec_id,
    'coexistenceMode',v_connection.coexistence_mode,
    'reasons',to_jsonb(v_reasons)
  );
end;
$$;

create or replace function public.pandora_connector_runtime_v1(p_organization_id uuid)
returns jsonb
language sql
security invoker
stable
set search_path='pg_catalog','public'
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'connectionId',c.id,
      'sourceSystemKey',c.source_system_key,
      'displayName',c.display_name,
      'coexistenceMode',c.coexistence_mode,
      'state',c.capability_state,
      'grantedScopes',c.granted_scopes,
      'lastSyncedAt',c.last_synced_at,
      'mappingCount',(
        select count(*) from public.enterprise_mapping_specs m
        where m.organization_id=c.organization_id and m.source_connection_id=c.id
      )
    )
    order by c.source_system_key,c.connection_key
  ),'[]'::jsonb)
  from public.enterprise_integration_connections c
  where c.organization_id=p_organization_id;
$$;

-- ---------------------------------------------------------------------------
-- RLS / grants
-- ---------------------------------------------------------------------------

alter table public.enterprise_event_type_registry enable row level security;
alter table public.enterprise_connector_contracts enable row level security;

revoke all on table public.enterprise_event_type_registry,public.enterprise_connector_contracts
from public,anon,authenticated;
grant select on table public.enterprise_event_type_registry,public.enterprise_connector_contracts
to authenticated,service_role;
grant insert,update,delete on table public.enterprise_event_type_registry,public.enterprise_connector_contracts
to service_role;

drop policy if exists enterprise_event_type_registry_authenticated_read on public.enterprise_event_type_registry;
create policy enterprise_event_type_registry_authenticated_read
on public.enterprise_event_type_registry for select to authenticated using(true);
drop policy if exists enterprise_event_type_registry_service_all on public.enterprise_event_type_registry;
create policy enterprise_event_type_registry_service_all
on public.enterprise_event_type_registry for all to service_role using(true) with check(true);

drop policy if exists enterprise_connector_contracts_authenticated_read on public.enterprise_connector_contracts;
create policy enterprise_connector_contracts_authenticated_read
on public.enterprise_connector_contracts for select to authenticated using(true);
drop policy if exists enterprise_connector_contracts_service_all on public.enterprise_connector_contracts;
create policy enterprise_connector_contracts_service_all
on public.enterprise_connector_contracts for all to service_role using(true) with check(true);

do $$
declare
  v_table text;
  v_select_policy text;
  v_service_policy text;
begin
  foreach v_table in array array[
    'enterprise_locations',
    'enterprise_money_accounts',
    'enterprise_transactions',
    'enterprise_products_services',
    'enterprise_inventory_items',
    'enterprise_assets',
    'enterprise_contracts',
    'enterprise_documents',
    'enterprise_tasks',
    'enterprise_events',
    'enterprise_devices',
    'enterprise_identity_refs',
    'enterprise_policies',
    'enterprise_mapping_specs',
    'enterprise_sync_checkpoints',
    'enterprise_sync_receipts',
    'enterprise_webhook_checkpoints',
    'enterprise_file_exchange_receipts',
    'enterprise_local_bridge_nodes',
    'enterprise_rpa_action_sets',
    'enterprise_human_work_items'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated',v_table);
    execute format('grant select,insert,update,delete on table public.%I to service_role',v_table);

    v_select_policy:=v_table||'_member_select';
    v_service_policy:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_select_policy,v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.memberships m where m.organization_id=%I.organization_id and m.user_id=(select auth.uid()) and m.status=''active''))',
      v_select_policy,v_table,v_table
    );
    execute format('drop policy if exists %I on public.%I',v_service_policy,v_table);
    execute format(
      'create policy %I on public.%I for all to service_role using(true) with check(true)',
      v_service_policy,v_table
    );
  end loop;
end;
$$;

revoke update,delete on table public.enterprise_events,public.enterprise_sync_receipts from service_role;

revoke all on function public.pandora_connector_write_ready_v1(uuid,uuid,uuid) from public,anon;
revoke all on function public.pandora_connector_runtime_v1(uuid) from public,anon;
grant execute on function public.pandora_connector_write_ready_v1(uuid,uuid,uuid) to authenticated,service_role;
grant execute on function public.pandora_connector_runtime_v1(uuid) to authenticated,service_role;
