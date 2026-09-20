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
as $$
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
    'nextBeforeSequence',next_before_sequence
  );
end
$$;

revoke all on function public.plp_pandora_activity_logs_v2(timestamptz,uuid,bigint,integer,text)
  from public, anon;
grant execute on function public.plp_pandora_activity_logs_v2(timestamptz,uuid,bigint,integer,text)
  to authenticated, service_role;
