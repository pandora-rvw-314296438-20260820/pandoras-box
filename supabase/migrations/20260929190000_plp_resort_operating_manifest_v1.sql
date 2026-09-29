-- PLP complete luxury-resort operating surface manifest.
-- Additive only: verified business data remains sourced from PLP bootstrap v1.
begin;

create or replace function public.plp_resort_operating_manifest_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_property public.enterprise_properties%rowtype;
  v_allowed boolean := false;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select *
  into v_property
  from public.enterprise_properties p
  where p.slug = 'plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if v_property.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select exists(
    select 1
    from public.memberships m
    where m.organization_id = v_property.organization_id
      and m.user_id = v_uid
      and m.status::text = 'active'
  )
  into v_allowed;

  if not v_allowed then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'plp.resort-operating-system.v1',
    'workspaceSlug', 'plp-boracay',
    'workspaceName', v_property.display_name,
    'assistantIdentity', 'MFR',
    'design', jsonb_build_object(
      'contentPages', 'light_ivory_editorial_luxury',
      'navigationPanel', 'pure_black',
      'logoPlacement', 'workspace_selector_only'
    ),
    'truthContract', jsonb_build_object(
      'activityTheatre', 'verified_events_only',
      'completionRequiresEvidence', true,
      'fabricatedMetricsAllowed', false,
      'sourceHealthRequired', true
    ),
    'groups', '[{"group":"Guest & Stay","modules":["Reservations","Front Desk","Arrivals & Departures","In-House Guests","Guest Profiles & CRM","Concierge","Guest Requests & Recovery","VIP & Preferences","Lost & Found"]},{"group":"Rooms & Property","modules":["Rooms","Housekeeping","Laundry & Linen","Maintenance","Engineering","Security & Incidents","Transport & Fleet","Beach, Pool & Facilities","Utilities"]},{"group":"Hospitality & Experiences","modules":["Food & Beverage","Restaurants & Bars","Room Service","Spa & Wellness","Experiences & Activities","Weddings & Events"]},{"group":"Commercial","modules":["Rates & Availability","Sales & CRM","Marketing & Campaigns","Distribution & Channels","Reviews & Reputation"]},{"group":"Finance & Supply","modules":["Finance & Billing","Procurement","Suppliers","Inventory & Stock","Cash & Payments","CapEx & Assets"]},{"group":"People & Governance","modules":["Scheduling & Attendance","Training & SOPs","Documents & Compliance","Permits & Expiry","Sustainability"]},{"group":"Intelligence & System","modules":["Reports & Forecasts","Automations","Integrations","Notifications","Audit & Provenance"]}]'::jsonb,
    'moduleCount', 45,
    'generatedAt', clock_timestamp()
  );
end;
$function$;

revoke all on function public.plp_resort_operating_manifest_v1()
  from public, anon;
grant execute on function public.plp_resort_operating_manifest_v1()
  to authenticated;

comment on function public.plp_resort_operating_manifest_v1() is
  'Authorized PLP resort operating-system manifest. Business facts remain sourced from the verified PLP bootstrap.';

commit;
