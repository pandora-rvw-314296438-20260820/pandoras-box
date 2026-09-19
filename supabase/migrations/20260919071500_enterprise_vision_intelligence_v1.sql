
create or replace function private.pandora_vision_has_access_v1(
  p_organization_id uuid,
  p_manage boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status::text = 'active'
      and (
        not p_manage
        or m.role::text in ('owner','admin')
      )
  );
$$;

revoke all on function private.pandora_vision_has_access_v1(uuid,boolean) from public;
grant execute on function private.pandora_vision_has_access_v1(uuid,boolean) to authenticated;

create table if not exists public.enterprise_vision_cameras (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid null,
  camera_key text not null,
  display_name text not null,
  location_label text null,
  source_type text not null check (source_type in ('rtsp','onvif','nvr','upload','edge_agent','provider_embed')),
  source_ref text null,
  source_status text not null default 'disconnected'
    check (source_status in ('disconnected','connecting','live','degraded','offline')),
  analysis_enabled boolean not null default false,
  public_feed boolean not null default false,
  biometric_identification_enabled boolean not null default false,
  anonymous_tracking_enabled boolean not null default true,
  retention_hours integer not null default 72 check (retention_hours between 0 and 8760),
  analysis_interval_seconds integer not null default 10 check (analysis_interval_seconds between 1 and 3600),
  last_frame_at timestamptz null,
  last_analysis_at timestamptz null,
  source_observed_at timestamptz null,
  source_message text null,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, camera_key),
  check (
    source_ref is null
    or (
      source_ref !~* 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}'
      and source_ref !~* '://[^/@[:space:]]+:[^/@[:space:]]+@'
      and source_ref !~ 'sk-[A-Za-z0-9_-]{20,}'
      and source_ref !~ 'AIza[0-9A-Za-z_-]{20,}'
      and source_ref !~ 'github_pat_[A-Za-z0-9_]{20,}'
    )
  )
);

create table if not exists public.enterprise_vision_zones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  name text not null,
  zone_kind text not null default 'monitor'
    check (zone_kind in ('monitor','restricted','entry','exit','queue','loading','parking','custom')),
  polygon jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (camera_id,name),
  check (jsonb_typeof(polygon)='array')
);

create table if not exists public.enterprise_vision_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid null references public.enterprise_vision_cameras(id) on delete cascade,
  zone_id uuid null references public.enterprise_vision_zones(id) on delete set null,
  name text not null,
  event_types text[] not null default '{}',
  min_confidence numeric(5,4) not null default 0.65 check (min_confidence between 0 and 1),
  min_count integer null check (min_count is null or min_count >= 1),
  dwell_seconds integer null check (dwell_seconds is null or dwell_seconds >= 0),
  severity text not null default 'warning'
    check (severity in ('info','warning','critical')),
  schedule jsonb not null default '{}'::jsonb,
  notify_roles text[] not null default array['owner','admin']::text[],
  enabled boolean not null default true,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enterprise_vision_analysis_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  requested_by uuid null,
  source_kind text not null default 'frame_batch',
  frame_count integer not null default 1 check (frame_count between 1 and 8),
  status text not null default 'running'
    check (status in ('running','succeeded','failed','rejected')),
  provider text null,
  model text null,
  request_sha256 text null,
  response_sha256 text null,
  started_at timestamptz not null default now(),
  completed_at timestamptz null,
  error_code text null,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.enterprise_vision_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  run_id uuid null references public.enterprise_vision_analysis_runs(id) on delete set null,
  zone_id uuid null references public.enterprise_vision_zones(id) on delete set null,
  observed_at timestamptz not null,
  observation_type text not null,
  object_class text null,
  label text null,
  count_value integer null check (count_value is null or count_value >= 0),
  confidence numeric(5,4) null check (confidence is null or confidence between 0 and 1),
  track_key text null,
  description text null,
  attributes jsonb not null default '{}'::jsonb,
  human_state text not null default 'machine'
    check (human_state in ('machine','verified','rejected')),
  verified_by uuid null,
  verified_at timestamptz null,
  source_ref text null,
  created_at timestamptz not null default now()
);

create table if not exists public.enterprise_vision_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  run_id uuid null references public.enterprise_vision_analysis_runs(id) on delete set null,
  zone_id uuid null references public.enterprise_vision_zones(id) on delete set null,
  event_type text not null,
  severity text not null default 'info'
    check (severity in ('info','warning','critical')),
  title text not null,
  description text not null,
  confidence numeric(5,4) null check (confidence is null or confidence between 0 and 1),
  started_at timestamptz not null,
  ended_at timestamptz null,
  observation_ids uuid[] not null default '{}',
  human_state text not null default 'machine'
    check (human_state in ('machine','verified','rejected')),
  source_ref text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.enterprise_vision_alerts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  event_id uuid not null references public.enterprise_vision_events(id) on delete cascade,
  rule_id uuid null references public.enterprise_vision_rules(id) on delete set null,
  severity text not null check (severity in ('info','warning','critical')),
  title text not null,
  message text not null,
  status text not null default 'open'
    check (status in ('open','acknowledged','resolved','dismissed')),
  created_at timestamptz not null default now(),
  acknowledged_by uuid null,
  acknowledged_at timestamptz null,
  resolved_at timestamptz null,
  unique (event_id,rule_id)
);

create table if not exists public.enterprise_vision_clip_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  camera_id uuid not null references public.enterprise_vision_cameras(id) on delete cascade,
  event_id uuid null references public.enterprise_vision_events(id) on delete set null,
  requested_by uuid null default auth.uid(),
  start_at timestamptz not null,
  end_at timestamptz not null,
  reason text not null,
  status text not null default 'requested'
    check (status in ('requested','claimed','extracting','ready','failed','expired')),
  storage_bucket text null,
  storage_path text null,
  sha256 text null,
  media_type text null,
  duration_seconds numeric null,
  failure_code text null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  check (end_at > start_at)
);

create table if not exists public.enterprise_vision_incidents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  title text not null,
  summary text not null default '',
  severity text not null default 'warning'
    check (severity in ('info','warning','critical')),
  status text not null default 'open'
    check (status in ('open','reviewing','closed','dismissed')),
  started_at timestamptz not null,
  ended_at timestamptz null,
  event_ids uuid[] not null default '{}',
  clip_request_ids uuid[] not null default '{}',
  report jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists enterprise_vision_cameras_org_status_idx
  on public.enterprise_vision_cameras(organization_id,source_status,analysis_enabled);
create index if not exists enterprise_vision_observations_org_time_idx
  on public.enterprise_vision_observations(organization_id,observed_at desc);
create index if not exists enterprise_vision_observations_camera_time_idx
  on public.enterprise_vision_observations(camera_id,observed_at desc);
create index if not exists enterprise_vision_observations_track_idx
  on public.enterprise_vision_observations(organization_id,track_key,observed_at desc)
  where track_key is not null;
create index if not exists enterprise_vision_events_org_time_idx
  on public.enterprise_vision_events(organization_id,started_at desc);
create index if not exists enterprise_vision_events_camera_type_time_idx
  on public.enterprise_vision_events(camera_id,event_type,started_at desc);
create index if not exists enterprise_vision_alerts_org_status_time_idx
  on public.enterprise_vision_alerts(organization_id,status,created_at desc);
create index if not exists enterprise_vision_clip_requests_org_status_idx
  on public.enterprise_vision_clip_requests(organization_id,status,requested_at);
create index if not exists enterprise_vision_incidents_org_status_idx
  on public.enterprise_vision_incidents(organization_id,status,created_at desc);

alter table public.enterprise_vision_cameras enable row level security;
alter table public.enterprise_vision_zones enable row level security;
alter table public.enterprise_vision_rules enable row level security;
alter table public.enterprise_vision_analysis_runs enable row level security;
alter table public.enterprise_vision_observations enable row level security;
alter table public.enterprise_vision_events enable row level security;
alter table public.enterprise_vision_alerts enable row level security;
alter table public.enterprise_vision_clip_requests enable row level security;
alter table public.enterprise_vision_incidents enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'enterprise_vision_cameras','enterprise_vision_zones','enterprise_vision_rules',
    'enterprise_vision_analysis_runs','enterprise_vision_observations','enterprise_vision_events',
    'enterprise_vision_alerts','enterprise_vision_clip_requests','enterprise_vision_incidents'
  ]
  loop
    execute format('drop policy if exists %I_read on public.%I',t,t);
    execute format(
      'create policy %I_read on public.%I for select to authenticated using (private.pandora_vision_has_access_v1(organization_id,false))',
      t,t
    );
    execute format('drop policy if exists %I_manage on public.%I',t,t);
    execute format(
      'create policy %I_manage on public.%I for all to authenticated using (private.pandora_vision_has_access_v1(organization_id,true)) with check (private.pandora_vision_has_access_v1(organization_id,true))',
      t,t
    );
  end loop;
end $$;

create or replace function private.pandora_vision_apply_rules_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.enterprise_vision_alerts(
    organization_id,camera_id,event_id,rule_id,severity,title,message
  )
  select
    new.organization_id,
    new.camera_id,
    new.id,
    r.id,
    r.severity,
    r.name,
    new.title || ': ' || new.description
  from public.enterprise_vision_rules r
  where r.organization_id=new.organization_id
    and r.enabled=true
    and (r.camera_id is null or r.camera_id=new.camera_id)
    and (r.zone_id is null or r.zone_id=new.zone_id)
    and (cardinality(r.event_types)=0 or new.event_type=any(r.event_types))
    and coalesce(new.confidence,1) >= r.min_confidence
  on conflict (event_id,rule_id) do nothing;
  return new;
end;
$$;

drop trigger if exists enterprise_vision_events_apply_rules on public.enterprise_vision_events;
create trigger enterprise_vision_events_apply_rules
after insert on public.enterprise_vision_events
for each row execute function private.pandora_vision_apply_rules_v1();

create or replace function public.pandora_vision_overview_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not private.pandora_vision_has_access_v1(p_organization_id,false) then
    raise exception 'organization access required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'cameras',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'cameraKey',c.camera_key,'displayName',c.display_name,
        'locationLabel',c.location_label,'sourceType',c.source_type,
        'sourceStatus',c.source_status,'analysisEnabled',c.analysis_enabled,
        'publicFeed',c.public_feed,'biometricsEnabled',c.biometric_identification_enabled,
        'anonymousTrackingEnabled',c.anonymous_tracking_enabled,
        'lastFrameAt',c.last_frame_at,'lastAnalysisAt',c.last_analysis_at
      ) order by c.display_name)
      from public.enterprise_vision_cameras c
      where c.organization_id=p_organization_id
    ),'[]'::jsonb),
    'openAlerts',(
      select count(*) from public.enterprise_vision_alerts a
      where a.organization_id=p_organization_id and a.status='open'
    ),
    'events24h',(
      select count(*) from public.enterprise_vision_events e
      where e.organization_id=p_organization_id and e.started_at>=now()-interval '24 hours'
        and e.human_state<>'rejected'
    ),
    'incidentsOpen',(
      select count(*) from public.enterprise_vision_incidents i
      where i.organization_id=p_organization_id and i.status in ('open','reviewing')
    ),
    'latestEvents',coalesce((
      select jsonb_agg(x.payload)
      from (
        select jsonb_build_object(
          'id',e.id,'cameraId',e.camera_id,'eventType',e.event_type,
          'severity',e.severity,'title',e.title,'description',e.description,
          'confidence',e.confidence,'startedAt',e.started_at,'endedAt',e.ended_at,
          'humanState',e.human_state
        ) payload
        from public.enterprise_vision_events e
        where e.organization_id=p_organization_id and e.human_state<>'rejected'
        order by e.started_at desc
        limit 30
      ) x
    ),'[]'::jsonb),
    'latestAlerts',coalesce((
      select jsonb_agg(x.payload)
      from (
        select jsonb_build_object(
          'id',a.id,'eventId',a.event_id,'cameraId',a.camera_id,
          'severity',a.severity,'title',a.title,'message',a.message,
          'status',a.status,'createdAt',a.created_at
        ) payload
        from public.enterprise_vision_alerts a
        where a.organization_id=p_organization_id
        order by a.created_at desc
        limit 30
      ) x
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.pandora_vision_search_v1(
  p_organization_id uuid,
  p_query text default null,
  p_camera_id uuid default null,
  p_start_at timestamptz default now()-interval '24 hours',
  p_end_at timestamptz default now(),
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare v_query text:=nullif(trim(coalesce(p_query,'')),'');
begin
  if not private.pandora_vision_has_access_v1(p_organization_id,false) then
    raise exception 'organization access required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'events',coalesce((
      select jsonb_agg(x.payload)
      from (
        select jsonb_build_object(
          'id',e.id,'cameraId',e.camera_id,'eventType',e.event_type,
          'severity',e.severity,'title',e.title,'description',e.description,
          'confidence',e.confidence,'startedAt',e.started_at,'endedAt',e.ended_at,
          'humanState',e.human_state,'metadata',e.metadata
        ) payload
        from public.enterprise_vision_events e
        where e.organization_id=p_organization_id
          and (p_camera_id is null or e.camera_id=p_camera_id)
          and e.started_at between p_start_at and p_end_at
          and e.human_state<>'rejected'
          and (
            v_query is null
            or e.event_type ilike '%'||v_query||'%'
            or e.title ilike '%'||v_query||'%'
            or e.description ilike '%'||v_query||'%'
            or e.metadata::text ilike '%'||v_query||'%'
          )
        order by e.started_at desc
        limit least(greatest(coalesce(p_limit,100),1),250)
      ) x
    ),'[]'::jsonb),
    'observations',coalesce((
      select jsonb_agg(x.payload)
      from (
        select jsonb_build_object(
          'id',o.id,'cameraId',o.camera_id,'observationType',o.observation_type,
          'objectClass',o.object_class,'label',o.label,'count',o.count_value,
          'confidence',o.confidence,'trackKey',o.track_key,
          'description',o.description,'observedAt',o.observed_at,
          'humanState',o.human_state,'attributes',o.attributes
        ) payload
        from public.enterprise_vision_observations o
        where o.organization_id=p_organization_id
          and (p_camera_id is null or o.camera_id=p_camera_id)
          and o.observed_at between p_start_at and p_end_at
          and o.human_state<>'rejected'
          and (
            v_query is null
            or o.observation_type ilike '%'||v_query||'%'
            or coalesce(o.object_class,'') ilike '%'||v_query||'%'
            or coalesce(o.label,'') ilike '%'||v_query||'%'
            or coalesce(o.description,'') ilike '%'||v_query||'%'
            or o.attributes::text ilike '%'||v_query||'%'
          )
        order by o.observed_at desc
        limit least(greatest(coalesce(p_limit,100),1),250)
      ) x
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.pandora_vision_request_clip_v1(
  p_organization_id uuid,
  p_camera_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_reason text,
  p_event_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare v_id uuid;
begin
  if not private.pandora_vision_has_access_v1(p_organization_id,true) then
    raise exception 'manage access required' using errcode='42501';
  end if;
  if p_end_at<=p_start_at or p_end_at-p_start_at>interval '2 hours' then
    raise exception 'invalid clip window' using errcode='22023';
  end if;
  insert into public.enterprise_vision_clip_requests(
    organization_id,camera_id,event_id,start_at,end_at,reason,requested_by
  ) values (
    p_organization_id,p_camera_id,p_event_id,p_start_at,p_end_at,
    left(trim(p_reason),1000),auth.uid()
  ) returning id into v_id;
  return jsonb_build_object('id',v_id,'status','requested');
end;
$$;

create or replace function public.pandora_vision_verify_observation_v1(
  p_organization_id uuid,
  p_observation_id uuid,
  p_state text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare v_row public.enterprise_vision_observations;
begin
  if not private.pandora_vision_has_access_v1(p_organization_id,true) then
    raise exception 'manage access required' using errcode='42501';
  end if;
  if p_state not in ('verified','rejected') then
    raise exception 'invalid verification state' using errcode='22023';
  end if;
  update public.enterprise_vision_observations
  set human_state=p_state,verified_by=auth.uid(),verified_at=now()
  where id=p_observation_id and organization_id=p_organization_id
  returning * into v_row;
  if v_row.id is null then raise exception 'observation not found' using errcode='P0002'; end if;
  return jsonb_build_object('id',v_row.id,'state',v_row.human_state,'verifiedAt',v_row.verified_at);
end;
$$;

create or replace function public.pandora_vision_ack_alert_v1(
  p_organization_id uuid,
  p_alert_id uuid,
  p_status text default 'acknowledged'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare v_row public.enterprise_vision_alerts;
begin
  if not private.pandora_vision_has_access_v1(p_organization_id,true) then
    raise exception 'manage access required' using errcode='42501';
  end if;
  if p_status not in ('acknowledged','resolved','dismissed') then
    raise exception 'invalid alert status' using errcode='22023';
  end if;
  update public.enterprise_vision_alerts
  set status=p_status,
      acknowledged_by=coalesce(acknowledged_by,auth.uid()),
      acknowledged_at=coalesce(acknowledged_at,now()),
      resolved_at=case when p_status='resolved' then now() else resolved_at end
  where id=p_alert_id and organization_id=p_organization_id
  returning * into v_row;
  if v_row.id is null then raise exception 'alert not found' using errcode='P0002'; end if;
  return jsonb_build_object('id',v_row.id,'status',v_row.status);
end;
$$;

grant select on public.enterprise_vision_cameras,
  public.enterprise_vision_zones,
  public.enterprise_vision_rules,
  public.enterprise_vision_analysis_runs,
  public.enterprise_vision_observations,
  public.enterprise_vision_events,
  public.enterprise_vision_alerts,
  public.enterprise_vision_clip_requests,
  public.enterprise_vision_incidents to authenticated;

grant insert,update,delete on public.enterprise_vision_cameras,
  public.enterprise_vision_zones,
  public.enterprise_vision_rules,
  public.enterprise_vision_clip_requests,
  public.enterprise_vision_incidents to authenticated;

grant execute on function public.pandora_vision_overview_v1(uuid) to authenticated;
grant execute on function public.pandora_vision_search_v1(uuid,text,uuid,timestamptz,timestamptz,integer) to authenticated;
grant execute on function public.pandora_vision_request_clip_v1(uuid,uuid,timestamptz,timestamptz,text,uuid) to authenticated;
grant execute on function public.pandora_vision_verify_observation_v1(uuid,uuid,text) to authenticated;
grant execute on function public.pandora_vision_ack_alert_v1(uuid,uuid,text) to authenticated;

comment on table public.enterprise_vision_cameras is
'Authorized enterprise camera registry. Public third-party feeds must keep analysis_enabled=false.';
comment on column public.enterprise_vision_cameras.biometric_identification_enabled is
'Explicit per-camera gate; defaults false. Never infer identity merely from appearance.';
comment on table public.enterprise_vision_observations is
'Machine observations remain machine state until a human verifies or rejects them.';
