-- Pandora Universal Core registry RLS hardening v1.
-- Enables RLS on public registry tables while preserving authenticated read access.
-- Writes remain service_role-only under existing grants.

alter table public.enterprise_entity_type_registry enable row level security;
alter table public.enterprise_relationship_type_registry enable row level security;

drop policy if exists enterprise_entity_type_registry_authenticated_read
  on public.enterprise_entity_type_registry;
create policy enterprise_entity_type_registry_authenticated_read
  on public.enterprise_entity_type_registry
  for select
  to authenticated
  using (true);

drop policy if exists enterprise_relationship_type_registry_authenticated_read
  on public.enterprise_relationship_type_registry;
create policy enterprise_relationship_type_registry_authenticated_read
  on public.enterprise_relationship_type_registry
  for select
  to authenticated
  using (true);

