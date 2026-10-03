
create or replace function public.plp_recent_business_activity_v1(
  p_limit integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  items jsonb := '[]'::jsonb;
begin
  perform private.pandora_core_legacy_client_scope_v1(
    (select o.id
       from public.organizations o
       join public.pandora_enterprise_accounts a on a.organization_id=o.id
      where o.slug='plp-boracay')
  );

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
        or lower(coalesce(t.actor,'')) like '%qa%'
        or lower(coalesce(t.note,'')) like '%[mock qa]%'
        or lower(coalesce(t.note,'')) like '%synthetic%' as is_mock
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
        or lower(coalesce(b.source,'')) like 'qa_%'
        or upper(coalesce(b.booking_reference,'')) like 'MOCK-%' as is_mock
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
  ),
  page as (
    select *
    from unified
    where occurred_at is not null
      and not is_mock
    order by occurred_at desc, id desc
    limit lim
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',p.id,
        'audience',p.audience,
        'category',p.category,
        'title',p.title,
        'summary',p.summary,
        'sourceLabel',p.source_label,
        'occurredAt',p.occurred_at,
        'isMock',false
      )
      order by p.occurred_at desc, p.id desc
    ),
    '[]'::jsonb
  )
  into items
  from page p;

  return jsonb_build_object(
    'schemaVersion','plp.business-activity.v1',
    'items',items,
    'containsMockData',false,
    'testDataExcluded',true
  );
end
$function$;

revoke all on function public.plp_recent_business_activity_v1(integer)
  from public, anon;
grant execute on function public.plp_recent_business_activity_v1(integer)
  to authenticated, service_role;

create or replace function public.plp_pandora_activity_logs_v2(
  p_before_at timestamptz default null,
  p_before_job_id uuid default null,
  p_before_sequence bigint default null,
  p_limit integer default 60,
  p_query text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  lim integer := least(greatest(coalesce(p_limit,60),1),100);
  q text := nullif(trim(coalesce(p_query,'')),'');
  items jsonb := '[]'::jsonb;
  has_more boolean := false;
  next_before_at timestamptz := null;
  next_before_job_id uuid := null;
  next_before_sequence bigint := null;
begin
  perform private.pandora_core_legacy_client_scope_v1(
    (select o.id
       from public.organizations o
       join public.pandora_enterprise_accounts a on a.organization_id=o.id
      where o.slug='plp-boracay')
  );

  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  if p_before_at is not null
     and (p_before_job_id is null or p_before_sequence is null) then
    raise exception 'complete activity cursor required' using errcode='22023';
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

  if lower(member.role::text) not in ('owner','admin') then
    raise exception 'PLP owner or admin access required' using errcode='42501';
  end if;

  with matched as (
    select
      a.event_id,
      a.job_id,
      a.sequence,
      a.state,
      a.message,
      coalesce(nullif(a.event->>'domain',''),'pandora') as domain,
      coalesce(nullif(a.event->>'capability',''),'activity') as capability,
      coalesce(nullif(a.event#>>'{provenance,sourceType}',''),'runtime') as source_type,
      j.request_id,
      coalesce(
        nullif(trim(p.display_name),''),
        case when j.requested_by is null then 'Pandora' else 'PLP user' end
      ) as actor_label,
      a.occurred_at
    from public.pandora_activity_events a
    left join public.pandora_activity_jobs j
      on j.id=a.job_id
     and j.organization_id=a.organization_id
    left join public.profiles p
      on p.id=j.requested_by
    where a.organization_id=prop.organization_id
      and lower(coalesce(a.event->>'isTest','false')) not in ('true','1','yes')
      and lower(coalesce(a.event->>'synthetic','false')) not in ('true','1','yes')
      and lower(coalesce(a.event->>'mock','false')) not in ('true','1','yes')
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like '%mock%'
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like '%synthetic%'
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like 'qa_%'
      and lower(coalesce(a.message,'')) not like '%[mock qa]%'
      and lower(coalesce(a.message,'')) not like '%synthetic%'
      and (
        p_before_at is null
        or (a.occurred_at, a.job_id, a.sequence)
          < (p_before_at, p_before_job_id, p_before_sequence)
      )
      and (
        q is null
        or a.message ilike '%' || q || '%'
        or coalesce(a.state,'') ilike '%' || q || '%'
        or coalesce(a.event->>'domain','') ilike '%' || q || '%'
        or coalesce(a.event->>'capability','') ilike '%' || q || '%'
        or coalesce(a.event#>>'{provenance,sourceType}','') ilike '%' || q || '%'
        or coalesce(p.display_name,'') ilike '%' || q || '%'
        or coalesce(j.request_id,'') ilike '%' || q || '%'
        or a.job_id::text ilike '%' || q || '%'
      )
    order by a.occurred_at desc, a.job_id desc, a.sequence desc
    limit lim + 1
  ),
  page as (
    select *
    from matched
    order by occurred_at desc, job_id desc, sequence desc
    limit lim
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.event_id,
          'jobId',p.job_id,
          'sequence',p.sequence,
          'state',p.state,
          'status',p.state,
          'message',p.message,
          'domain',p.domain,
          'capability',p.capability,
          'sourceType',p.source_type,
          'requestId',p.request_id,
          'actorLabel',p.actor_label,
          'occurredAt',p.occurred_at
        )
        order by p.occurred_at desc, p.job_id desc, p.sequence desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > lim from matched),
    (select x.occurred_at from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1),
    (select x.job_id from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1),
    (select x.sequence from page x
      order by x.occurred_at asc,x.job_id asc,x.sequence asc limit 1)
  into
    items,has_more,next_before_at,next_before_job_id,next_before_sequence
  from page p;

  if not coalesce(has_more,false) then
    next_before_at := null;
    next_before_job_id := null;
    next_before_sequence := null;
  end if;

  return jsonb_build_object(
    'schemaVersion','plp.pandora-activity-logs.v2',
    'items',items,
    'hasMore',coalesce(has_more,false),
    'nextBeforeAt',next_before_at,
    'nextBeforeJobId',next_before_job_id,
    'nextBeforeSequence',next_before_sequence,
    'testDataExcluded',true
  );
end
$function$;

revoke all on function public.plp_pandora_activity_logs_v2(timestamptz,uuid,bigint,integer,text)
  from public, anon;
grant execute on function public.plp_pandora_activity_logs_v2(timestamptz,uuid,bigint,integer,text)
  to authenticated, service_role;
