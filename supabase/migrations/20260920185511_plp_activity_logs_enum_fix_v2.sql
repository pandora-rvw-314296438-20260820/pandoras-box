-- Fix the audit actor/resource casts discovered by live provider verification.
-- audit_events.actor_type is an enum and resource_id is uuid; both must be
-- projected to text before COALESCE/ILIKE.
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
      a.actor_type::text as actor_type,
      coalesce(
        nullif(trim(p.display_name),''),
        case lower(coalesce(a.actor_type::text,''))
          when 'system' then 'Pandora'
          when 'provider' then 'Provider'
          when 'user' then 'PLP user'
          else initcap(replace(coalesce(a.actor_type::text,'Pandora'),'_',' '))
        end
      ) as actor_label,
      a.resource_type,
      a.resource_id::text as resource_id,
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
        or coalesce(a.actor_type::text,'') ilike '%' || q || '%'
        or coalesce(p.display_name,'') ilike '%' || q || '%'
        or coalesce(a.resource_type,'') ilike '%' || q || '%'
        or coalesce(a.resource_id::text,'') ilike '%' || q || '%'
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
