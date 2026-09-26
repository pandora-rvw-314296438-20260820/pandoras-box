-- PLP Activity page read models.
-- Provides a bounded resort activity feed and a paginated Pandora audit feed.
create or replace function public.plp_recent_business_activity_v1(
  p_limit integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  items jsonb := '[]'::jsonb;
  has_mock boolean := false;
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

  with unified as (
    select
      'business:' || e.id::text as id,
      case
        when lower(coalesce(e.category,'')) in
          ('guest','guests','booking','bookings','arrival','arrivals','departure','departures','concierge','hospitality')
          then 'guests'
        when lower(coalesce(e.category,'')) in
          ('operations','team','staff','maintenance','housekeeping')
          then 'team'
        else 'all'
      end as audience,
      coalesce(nullif(trim(e.category),''),'activity') as category,
      e.title,
      e.summary,
      coalesce(nullif(trim(e.source_label),''),'PLP runtime') as source_label,
      e.occurred_at,
      lower(coalesce(e.source_label,'')) like '%mock%'
        or lower(coalesce(e.source_label,'')) like '%qa%' as is_mock
    from public.enterprise_business_activity e
    where e.organization_id=prop.organization_id
      and e.property_id=prop.id

    union all

    select
      'task:' || t.id::text as id,
      'team'::text as audience,
      coalesce(nullif(trim(t.category),''), nullif(trim(t.kind),''), 'team') as category,
      t.title,
      coalesce(nullif(trim(t.note),''), 'PLP staff task updated.') as summary,
      coalesce(nullif(trim(t.source),''),'PLP runtime') as source_label,
      coalesce(t.completed_at,t.updated_at,t.created_at) as occurred_at,
      lower(coalesce(t.source,'')) like 'qa_%'
        or lower(coalesce(t.actor,'')) like '%qa%' as is_mock
    from plp_runtime.plp_staff_tasks t

    union all

    select
      'booking:' || b.id::text as id,
      'guests'::text as audience,
      'booking'::text as category,
      case upper(coalesce(b.status,''))
        when 'CONFIRMED' then 'Booking confirmed'
        when 'CHECKED_IN' then 'Guest checked in'
        when 'IN_HOUSE' then 'Guest in house'
        when 'CHECKED_OUT' then 'Guest checked out'
        when 'CANCELLED' then 'Booking cancelled'
        when 'CANCELED' then 'Booking cancelled'
        else 'Booking updated'
      end as title,
      concat_ws(
        ' · ',
        nullif(trim(g.full_name),''),
        nullif(trim(b.accommodation_name),''),
        nullif(trim(b.booking_reference),'')
      ) as summary,
      coalesce(nullif(trim(b.source),''),'PLP runtime') as source_label,
      coalesce(b.confirmed_at,b.cancelled_at,b.updated_at,b.created_at) as occurred_at,
      lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
        or lower(coalesce(b.source,'')) like 'qa_%' as is_mock
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
  ),
  page as (
    select *
    from unified
    where occurred_at is not null
    order by occurred_at desc, id desc
    limit lim
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'audience',p.audience,
          'category',p.category,
          'title',p.title,
          'summary',p.summary,
          'sourceLabel',p.source_label,
          'occurredAt',p.occurred_at,
          'isMock',p.is_mock
        )
        order by p.occurred_at desc, p.id desc
      ),
      '[]'::jsonb
    ),
    coalesce(bool_or(p.is_mock),false)
  into items, has_mock
  from page p;

  return jsonb_build_object(
    'schemaVersion','plp.business-activity.v1',
    'items',items,
    'containsMockData',has_mock
  );
end
$$;

revoke all on function public.plp_recent_business_activity_v1(integer) from public, anon;
grant execute on function public.plp_recent_business_activity_v1(integer) to authenticated, service_role;

create or replace function public.plp_pandora_activity_logs_v1(
  p_before_id bigint default null,
  p_limit integer default 60,
  p_query text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit,60),1),100);
  q text := nullif(trim(coalesce(p_query,'')),'');
  items jsonb := '[]'::jsonb;
  has_more boolean := false;
  next_before_id bigint := null;
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

  with matched as (
    select
      a.id,
      a.event_type,
      a.actor_type,
      coalesce(
        nullif(trim(p.display_name),''),
        case lower(coalesce(a.actor_type,''))
          when 'system' then 'Pandora'
          when 'provider' then 'Provider'
          when 'user' then 'PLP user'
          else initcap(replace(coalesce(a.actor_type,'Pandora'),'_',' '))
        end
      ) as actor_label,
      a.resource_type,
      a.resource_id,
      a.request_id,
      a.created_at,
      case
        when lower(coalesce(a.event_type,'')) like '%fail%'
          or lower(coalesce(a.event_type,'')) like '%error%' then 'failed'
        when lower(coalesce(a.event_type,'')) like '%insert%'
          or lower(coalesce(a.event_type,'')) like '%update%'
          or lower(coalesce(a.event_type,'')) like '%completed%'
          or lower(coalesce(a.event_type,'')) like '%verified%' then 'completed'
        else 'recorded'
      end as status
    from public.audit_events a
    left join public.profiles p on p.id=a.actor_user_id
    where a.organization_id=prop.organization_id
      and lower(coalesce(a.event_type,'')) like 'pandora%'
      and (p_before_id is null or a.id < p_before_id)
      and (
        q is null
        or a.event_type ilike '%' || q || '%'
        or coalesce(a.actor_type,'') ilike '%' || q || '%'
        or coalesce(p.display_name,'') ilike '%' || q || '%'
        or coalesce(a.resource_type,'') ilike '%' || q || '%'
        or coalesce(a.resource_id,'') ilike '%' || q || '%'
        or coalesce(a.request_id,'') ilike '%' || q || '%'
      )
    order by a.id desc
    limit lim + 1
  ),
  page as (
    select *
    from matched
    order by id desc
    limit lim
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'eventType',p.event_type,
          'actorType',p.actor_type,
          'actorLabel',p.actor_label,
          'resourceType',p.resource_type,
          'resourceId',p.resource_id,
          'requestId',p.request_id,
          'status',p.status,
          'occurredAt',p.created_at
        )
        order by p.id desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > lim from matched),
    case
      when (select count(*) > lim from matched) then min(p.id)
      else null
    end
  into items, has_more, next_before_id
  from page p;

  return jsonb_build_object(
    'schemaVersion','plp.pandora-activity-logs.v1',
    'items',items,
    'hasMore',coalesce(has_more,false),
    'nextBeforeId',next_before_id
  );
end
$$;

revoke all on function public.plp_pandora_activity_logs_v1(bigint,integer,text) from public, anon;
grant execute on function public.plp_pandora_activity_logs_v1(bigint,integer,text) to authenticated, service_role;
