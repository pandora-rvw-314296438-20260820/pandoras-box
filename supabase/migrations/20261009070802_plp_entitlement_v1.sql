-- PLP Enterprise entitlement for any active member.
--
-- Returns only whether the organization's subscription is unlocked: state
-- 'active' AND provider-verified (source_kind='provider_verified' with
-- verified_at). This is the same rule the owner billing screen and the PLP
-- subscription gate use. No plan, price, provider reference or checkout data
-- is exposed, so staff (who cannot read /billing/paypal/status) can learn
-- whether the workspace is unlocked without seeing billing details.
--
-- Read-only; no table, policy or data changes. Replay-safe (create or
-- replace, no data dependency).

create or replace function public.pandora_plp_entitlement_v1(
  p_organization_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'ORGANIZATION_REQUIRED' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = uid
      and m.status = 'active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  return exists (
    select 1
    from public.pandora_customer_subscriptions s
    where s.organization_id = p_organization_id
      and s.state = 'active'
      and s.source_kind = 'provider_verified'
      and s.verified_at is not null
  );
end
$function$;

revoke all on function public.pandora_plp_entitlement_v1(uuid)
  from public, anon;
grant execute on function public.pandora_plp_entitlement_v1(uuid)
  to authenticated, service_role;

comment on function public.pandora_plp_entitlement_v1(uuid) is
  'PLP Enterprise unlocked flag for active members: subscription active and provider-verified. Returns a boolean only.';
