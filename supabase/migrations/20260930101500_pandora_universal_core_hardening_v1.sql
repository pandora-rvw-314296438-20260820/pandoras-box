-- Pandora Universal Core hardening v1.
-- Follow-up to pandora_universal_core_foundation_v1.
-- Fixes public-registry RLS, RLS init-plan performance, and genuinely missing FK indexes.

alter table public.enterprise_entity_type_registry enable row level security;
alter table public.enterprise_relationship_type_registry enable row level security;

drop policy if exists enterprise_entity_type_registry_authenticated_read
  on public.enterprise_entity_type_registry;
create policy enterprise_entity_type_registry_authenticated_read
on public.enterprise_entity_type_registry
for select to authenticated
using (true);

drop policy if exists enterprise_entity_type_registry_service_all
  on public.enterprise_entity_type_registry;
create policy enterprise_entity_type_registry_service_all
on public.enterprise_entity_type_registry
for all to service_role
using (true)
with check (true);

drop policy if exists enterprise_relationship_type_registry_authenticated_read
  on public.enterprise_relationship_type_registry;
create policy enterprise_relationship_type_registry_authenticated_read
on public.enterprise_relationship_type_registry
for select to authenticated
using (true);

drop policy if exists enterprise_relationship_type_registry_service_all
  on public.enterprise_relationship_type_registry;
create policy enterprise_relationship_type_registry_service_all
on public.enterprise_relationship_type_registry
for all to service_role
using (true)
with check (true);

drop policy if exists enterprise_entities_member_select on public.enterprise_entities;
create policy enterprise_entities_member_select
on public.enterprise_entities for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_entities.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_people_member_select on public.enterprise_people;
create policy enterprise_people_member_select
on public.enterprise_people for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_people.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_integration_connections_member_select
  on public.enterprise_integration_connections;
create policy enterprise_integration_connections_member_select
on public.enterprise_integration_connections for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_integration_connections.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_source_records_member_select
  on public.enterprise_source_records;
create policy enterprise_source_records_member_select
on public.enterprise_source_records for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_source_records.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_identity_signals_member_select
  on public.enterprise_identity_signals;
create policy enterprise_identity_signals_member_select
on public.enterprise_identity_signals for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_identity_signals.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_entity_bindings_member_select
  on public.enterprise_entity_bindings;
create policy enterprise_entity_bindings_member_select
on public.enterprise_entity_bindings for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_entity_bindings.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_relationships_member_select
  on public.enterprise_relationships;
create policy enterprise_relationships_member_select
on public.enterprise_relationships for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_relationships.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_authority_policies_member_select
  on public.enterprise_authority_policies;
create policy enterprise_authority_policies_member_select
on public.enterprise_authority_policies for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_authority_policies.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_field_provenance_member_select
  on public.enterprise_field_provenance;
create policy enterprise_field_provenance_member_select
on public.enterprise_field_provenance for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_field_provenance.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

drop policy if exists enterprise_identity_resolutions_member_select
  on public.enterprise_identity_resolutions;
create policy enterprise_identity_resolutions_member_select
on public.enterprise_identity_resolutions for select to authenticated
using (exists(
  select 1 from public.memberships m
  where m.organization_id=enterprise_identity_resolutions.organization_id
    and m.user_id=(select auth.uid())
    and m.status='active'
));

-- Index only FK paths without an existing useful equality-prefix index.
create index if not exists enterprise_entities_entity_kind_fk_idx
  on public.enterprise_entities(entity_kind);

create index if not exists enterprise_identity_signals_source_org_fk_idx
  on public.enterprise_identity_signals(source_record_id,organization_id);

create index if not exists enterprise_entity_bindings_source_org_fk_idx
  on public.enterprise_entity_bindings(source_record_id,organization_id);

create index if not exists enterprise_relationships_binding_org_fk_idx
  on public.enterprise_relationships(source_binding_id,organization_id)
  where source_binding_id is not null;

create index if not exists enterprise_relationships_relation_type_fk_idx
  on public.enterprise_relationships(relation_type);

create index if not exists enterprise_authority_policies_connection_org_fk_idx
  on public.enterprise_authority_policies(source_connection_id,organization_id)
  where source_connection_id is not null;

create index if not exists enterprise_authority_policies_entity_kind_fk_idx
  on public.enterprise_authority_policies(entity_kind);

create index if not exists enterprise_field_provenance_source_org_fk_idx
  on public.enterprise_field_provenance(source_record_id,organization_id)
  where source_record_id is not null;

create index if not exists enterprise_field_provenance_connection_org_fk_idx
  on public.enterprise_field_provenance(source_connection_id,organization_id)
  where source_connection_id is not null;

create index if not exists enterprise_field_provenance_authority_org_fk_idx
  on public.enterprise_field_provenance(authority_policy_id,organization_id);

create index if not exists enterprise_field_provenance_supersedes_org_fk_idx
  on public.enterprise_field_provenance(supersedes_provenance_id,organization_id)
  where supersedes_provenance_id is not null;

create index if not exists enterprise_identity_resolutions_source_b_org_fk_idx
  on public.enterprise_identity_resolutions(source_record_b_id,organization_id);

create index if not exists enterprise_identity_resolutions_entity_org_fk_idx
  on public.enterprise_identity_resolutions(canonical_entity_id,organization_id)
  where canonical_entity_id is not null;
