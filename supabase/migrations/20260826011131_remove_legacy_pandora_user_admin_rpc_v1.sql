-- Removes the transitional client-callable mutation after the Edge Function
-- has switched to the service-role-only broker.

drop function if exists public.pandora_add_organization_member(
  uuid,
  uuid,
  public.member_role
);
