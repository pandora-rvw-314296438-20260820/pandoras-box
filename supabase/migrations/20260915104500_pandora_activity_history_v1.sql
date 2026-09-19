-- M2-008: searchable Activity History over the canonical Activity Theatre ledger.
-- History is a read projection only. It does not copy, rewrite, or invent events.

create index if not exists pandora_activity_events_org_admitted_idx
  on public.pandora_activity_events(organization_id, admitted_at desc, job_id, sequence desc);

create index if not exists pandora_activity_jobs_org_requester_created_idx
  on public.pandora_activity_jobs(organization_id, requested_by, created_at desc, id);

create or replace function public.pandora_activity_history_search_v1(
  p_organization_id uuid,
  p_query text default null,
  p_states text[] default null,
  p_domains text[] default null,
  p_source_types text[] default null,
  p_requested_by uuid default null,
  p_job_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_before_admitted_at timestamptz default null,
  p_before_job_id uuid default null,
  p_before_sequence bigint default null,
  p_limit integer default 100
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_uid uuid := auth.uid();
  v_query text := lower(trim(coalesce(p_query,'')));
  v_effective_requested_by uuid;
  v_items jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_at timestamptz;
  v_next_job uuid;
  v_next_sequence bigint;
begin
  if v_uid is null then
    raise exception 'pandora_activity_sign_in_required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=v_uid
      and m.status='active'
  ) then
    raise exception 'pandora_activity_membership_required' using errcode='42501';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'pandora_activity_history_limit_invalid' using errcode='22023';
  end if;
  if length(v_query) > 200 then
    raise exception 'pandora_activity_history_query_invalid' using errcode='22023';
  end if;
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'pandora_activity_history_range_invalid' using errcode='22023';
  end if;
  if (p_before_admitted_at is null)::integer
     + (p_before_job_id is null)::integer
     + (p_before_sequence is null)::integer not in (0,3) then
    raise exception 'pandora_activity_history_cursor_invalid' using errcode='22023';
  end if;
  if p_before_sequence is not null and p_before_sequence < 1 then
    raise exception 'pandora_activity_history_cursor_invalid' using errcode='22023';
  end if;

  if p_states is not null and exists (
    select 1 from unnest(p_states) s
    where lower(trim(s)) not in (
      'understanding','planning','acting','checking','needs_you','retrying','fallback',
      'verifying','paused','resuming','result','failed','cancelled'
    )
  ) then
    raise exception 'pandora_activity_history_state_invalid' using errcode='22023';
  end if;
  if p_source_types is not null and exists (
    select 1 from unnest(p_source_types) s
    where lower(trim(s)) not in ('runtime','device','provider','projectos','model','tool')
  ) then
    raise exception 'pandora_activity_history_source_invalid' using errcode='22023';
  end if;
  if p_domains is not null and exists (
    select 1 from unnest(p_domains) d
    where length(trim(d)) < 1 or length(trim(d)) > 100
  ) then
    raise exception 'pandora_activity_history_domain_invalid' using errcode='22023';
  end if;

  -- Preserve the exact requester visibility boundary used by live replay:
  -- an active member may read only jobs they originally requested. Organization
  -- roles do not widen Activity History visibility.
  if p_requested_by is not null and p_requested_by <> v_uid then
    raise exception 'pandora_activity_history_person_forbidden' using errcode='42501';
  end if;
  v_effective_requested_by := v_uid;

  with eligible as (
    select
      e.job_id,
      e.sequence,
      e.admitted_at,
      e.event,
      j.requested_by,
      j.thread_id,
      j.project_id,
      coalesce(pr.display_name,'') as requested_by_name,
      o.name as organization_name
    from public.pandora_activity_events e
    join public.pandora_activity_jobs j
      on j.id=e.job_id and j.organization_id=e.organization_id
    join public.organizations o on o.id=e.organization_id
    left join public.profiles pr on pr.id=j.requested_by
    where e.organization_id=p_organization_id
      and e.expires_at > now()
      and (v_effective_requested_by is null or j.requested_by=v_effective_requested_by)
      and (p_job_id is null or e.job_id=p_job_id)
      and (p_from is null or e.admitted_at >= p_from)
      and (p_to is null or e.admitted_at <= p_to)
      and (
        p_states is null
        or e.state = any(select lower(trim(value)) from unnest(p_states) value)
      )
      and (
        p_domains is null
        or lower(coalesce(e.event->>'domain','')) = any(select lower(trim(value)) from unnest(p_domains) value)
      )
      and (
        p_source_types is null
        or lower(coalesce(e.event#>>'{provenance,sourceType}','')) = any(select lower(trim(value)) from unnest(p_source_types) value)
      )
      and (
        v_query=''
        or strpos(lower(e.message),v_query)>0
        or strpos(lower(e.state),v_query)>0
        or strpos(lower(e.event_id),v_query)>0
        or strpos(lower(e.job_id::text),v_query)>0
        or strpos(lower(coalesce(e.event->>'domain','')),v_query)>0
        or strpos(lower(coalesce(e.event->>'capability','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{provenance,sourceType}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{provenance,sourceId}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{outcome,summary}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{blocker,reason}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{blocker,requiredAction}','')),v_query)>0
        or strpos(lower(coalesce(pr.display_name,'')),v_query)>0
        or strpos(lower(o.name),v_query)>0
      )
      and (
        p_before_admitted_at is null
        or (e.admitted_at,e.job_id,e.sequence) < (p_before_admitted_at,p_before_job_id,p_before_sequence)
      )
    order by e.admitted_at desc,e.job_id desc,e.sequence desc
    limit p_limit + 1
  ), page as (
    select * from eligible
    order by admitted_at desc,job_id desc,sequence desc
    limit p_limit
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'organizationId',p_organization_id,
        'organizationName',organization_name,
        'requestedBy',requested_by,
        'requestedByName',nullif(requested_by_name,''),
        'threadId',thread_id,
        'projectId',project_id,
        'event',event
      ) order by admitted_at desc,job_id desc,sequence desc
    ),'[]'::jsonb)
  into v_items
  from page;

  with eligible as (
    select e.job_id,e.sequence,e.admitted_at
    from public.pandora_activity_events e
    join public.pandora_activity_jobs j
      on j.id=e.job_id and j.organization_id=e.organization_id
    left join public.profiles pr on pr.id=j.requested_by
    join public.organizations o on o.id=e.organization_id
    where e.organization_id=p_organization_id
      and e.expires_at > now()
      and (v_effective_requested_by is null or j.requested_by=v_effective_requested_by)
      and (p_job_id is null or e.job_id=p_job_id)
      and (p_from is null or e.admitted_at >= p_from)
      and (p_to is null or e.admitted_at <= p_to)
      and (p_states is null or e.state = any(select lower(trim(value)) from unnest(p_states) value))
      and (p_domains is null or lower(coalesce(e.event->>'domain','')) = any(select lower(trim(value)) from unnest(p_domains) value))
      and (p_source_types is null or lower(coalesce(e.event#>>'{provenance,sourceType}','')) = any(select lower(trim(value)) from unnest(p_source_types) value))
      and (
        v_query=''
        or strpos(lower(e.message),v_query)>0
        or strpos(lower(e.state),v_query)>0
        or strpos(lower(e.event_id),v_query)>0
        or strpos(lower(e.job_id::text),v_query)>0
        or strpos(lower(coalesce(e.event->>'domain','')),v_query)>0
        or strpos(lower(coalesce(e.event->>'capability','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{provenance,sourceType}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{provenance,sourceId}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{outcome,summary}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{blocker,reason}','')),v_query)>0
        or strpos(lower(coalesce(e.event#>>'{blocker,requiredAction}','')),v_query)>0
        or strpos(lower(coalesce(pr.display_name,'')),v_query)>0
        or strpos(lower(o.name),v_query)>0
      )
      and (p_before_admitted_at is null or (e.admitted_at,e.job_id,e.sequence) < (p_before_admitted_at,p_before_job_id,p_before_sequence))
    order by e.admitted_at desc,e.job_id desc,e.sequence desc
    limit p_limit + 1
  )
  select count(*) > p_limit into v_has_more from eligible;

  if jsonb_array_length(v_items)>0 then
    select e.admitted_at,e.job_id,e.sequence
    into v_next_at,v_next_job,v_next_sequence
    from public.pandora_activity_events e
    where e.job_id=(v_items->-1->'event'->>'jobId')::uuid
      and e.sequence=(v_items->-1->'event'->>'sequence')::bigint;
  end if;

  return jsonb_build_object(
    'projectionVersion',1,
    'items',v_items,
    'hasMore',v_has_more,
    'nextCursor',case when v_has_more then jsonb_build_object(
      'admittedAt',v_next_at,
      'jobId',v_next_job,
      'sequence',v_next_sequence
    ) else null end,
    'retentionBoundary','canonical_event_retention'
  );
end;
$body$;

revoke all on function public.pandora_activity_history_search_v1(
  uuid,text,text[],text[],text[],uuid,uuid,timestamptz,timestamptz,timestamptz,uuid,bigint,integer
) from public,anon;
grant execute on function public.pandora_activity_history_search_v1(
  uuid,text,text[],text[],text[],uuid,uuid,timestamptz,timestamptz,timestamptz,uuid,bigint,integer
) to authenticated;
