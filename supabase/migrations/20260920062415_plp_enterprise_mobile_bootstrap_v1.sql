
create or replace function public.plp_enterprise_mobile_bootstrap_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  profile public.profiles%rowtype;
  ctx jsonb;
  snap jsonb;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc, p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select * into profile from public.profiles p where p.id=uid;

  select to_jsonb(c) into ctx
  from plp_runtime.plp_ai_business_context c
  limit 1;

  select to_jsonb(s) into snap
  from public.enterprise_hospitality_snapshots s
  where s.organization_id=prop.organization_id
    and s.property_id=prop.id
  order by s.as_of desc, s.created_at desc, s.id desc
  limit 1;

  return jsonb_build_object(
    'schemaVersion','plp.enterprise.mobile-bootstrap.v1',
    'generatedAt',clock_timestamp(),
    'organization',jsonb_build_object(
      'id',prop.organization_id,
      'propertyId',prop.id,
      'propertySlug',prop.slug,
      'propertyName',prop.display_name,
      'businessIdentity','Luxury Resort',
      'timezone',prop.timezone,
      'currency',prop.currency
    ),
    'user',jsonb_build_object(
      'id',uid,
      'displayName',coalesce(nullif(trim(profile.display_name),''),'PLP administrator'),
      'role',member.role::text,
      'timezone',coalesce(profile.timezone,prop.timezone)
    ),
    'today',coalesce(ctx,'{}'::jsonb),
    'sourceHealth',jsonb_build_object(
      'state',prop.source_status,
      'observedAt',prop.source_observed_at,
      'message',prop.source_message
    ),
    'latestHospitalitySnapshot',snap,
    'localAiContext',jsonb_build_object(
      'scope','plp-boracay-authorized-snapshot',
      'authoritativeAsOf',coalesce(ctx->>'generated_at',prop.source_observed_at::text),
      'payload',coalesce(ctx,'{}'::jsonb)
    )
  );
end;
$$;

revoke all on function public.plp_enterprise_mobile_bootstrap_v1() from public, anon;
grant execute on function public.plp_enterprise_mobile_bootstrap_v1() to authenticated;
