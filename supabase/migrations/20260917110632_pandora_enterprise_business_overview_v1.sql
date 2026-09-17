-- Enterprise business overview boundary for customer-safe operational data.
-- Additive only: engineering/provider telemetry remains outside this model.

create table if not exists public.pandora_enterprise_business_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_key text not null,
  source text not null default 'business_operations',
  observed_at timestamptz not null,
  metrics jsonb not null default '{}'::jsonb,
  alerts jsonb not null default '[]'::jsonb,
  handled jsonb not null default '[]'::jsonb,
  insights jsonb not null default '[]'::jsonb,
  received_at timestamptz not null default timezone('utc', now()),
  constraint pandora_enterprise_business_snapshots_metrics_object check (jsonb_typeof(metrics) = 'object'),
  constraint pandora_enterprise_business_snapshots_alerts_array check (jsonb_typeof(alerts) = 'array'),
  constraint pandora_enterprise_business_snapshots_handled_array check (jsonb_typeof(handled) = 'array'),
  constraint pandora_enterprise_business_snapshots_insights_array check (jsonb_typeof(insights) = 'array')
);
create index if not exists idx_pandora_enterprise_business_snapshots_latest
  on public.pandora_enterprise_business_snapshots (organization_id, project_key, observed_at desc);
alter table public.pandora_enterprise_business_snapshots enable row level security;
drop policy if exists enterprise_business_snapshots_member_read on public.pandora_enterprise_business_snapshots;
create policy enterprise_business_snapshots_member_read
  on public.pandora_enterprise_business_snapshots
  for select to authenticated using (private.is_org_member(organization_id));
revoke insert, update, delete on public.pandora_enterprise_business_snapshots from anon, authenticated;
grant select on public.pandora_enterprise_business_snapshots to authenticated;

create or replace function public.pandora_enterprise_business_overview_v1(
  target_organization_id uuid,
  target_project_key text default 'plp-boracay'
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  project_record record;
  snapshot_record record;
  profile jsonb := '{}'::jsonb;
  operations jsonb := '{}'::jsonb;
  metrics_payload jsonb := '{}'::jsonb;
  alerts_payload jsonb := '[]'::jsonb;
  handled_payload jsonb := '[]'::jsonb;
  insights_payload jsonb := '[]'::jsonb;
  connection_state text := 'not_connected';
  display_name text := 'Pueblo La Perla Boracay';
begin
  if not private.is_org_member(target_organization_id) then
    raise exception 'organization membership required' using errcode = '42501';
  end if;
  select p.project_key, p.name, p.config, p.updated_at
    into project_record
  from public.projectos_projects p
  where p.organization_id = target_organization_id
    and p.status <> 'archived'
    and (
      p.project_key = target_project_key
      or lower(coalesce(p.project_key, '')) like '%plp%'
      or lower(coalesce(p.name, '')) like '%pueblo%'
      or lower(coalesce(p.name, '')) like '%boracay%'
    )
  order by case when p.project_key = target_project_key then 0 else 1 end,
           p.updated_at desc
  limit 1;

  if project_record.project_key is null then
    return jsonb_build_object(
      'displayName', display_name,
      'connectionState', 'unavailable',
      'metrics', metrics_payload,
      'alerts', alerts_payload,
      'handled', handled_payload,
      'insights', insights_payload
    );
  end if;

  profile := coalesce(project_record.config -> 'enterpriseProfile', '{}'::jsonb);
  display_name := coalesce(nullif(profile ->> 'displayName', ''), nullif(project_record.name, ''), display_name);

  select s.*
    into snapshot_record
  from public.pandora_enterprise_business_snapshots s
  where s.organization_id = target_organization_id
    and s.project_key = project_record.project_key
  order by s.observed_at desc, s.received_at desc
  limit 1;

  if snapshot_record.id is not null then
    metrics_payload := coalesce(snapshot_record.metrics, '{}'::jsonb);
    alerts_payload := coalesce(snapshot_record.alerts, '[]'::jsonb);
    handled_payload := coalesce(snapshot_record.handled, '[]'::jsonb);
    insights_payload := coalesce(snapshot_record.insights, '[]'::jsonb);
    connection_state := case
      when snapshot_record.observed_at >= timezone('utc', now()) - interval '15 minutes'
        then 'live'
      else 'stale'
    end;
    return jsonb_build_object(
      'projectKey', project_record.project_key,
      'displayName', display_name,
      'connectionState', connection_state,
      'metrics', metrics_payload,
      'alerts', alerts_payload,
      'handled', handled_payload,
      'insights', insights_payload,
      'observedAt', snapshot_record.observed_at,
      'source', snapshot_record.source
    );
  end if;

  operations := case
    when jsonb_typeof(profile -> 'hotelOperations') = 'object'
      then profile -> 'hotelOperations'
    when jsonb_typeof(project_record.config -> 'hotelOperations') = 'object'
      then project_record.config -> 'hotelOperations'
    else '{}'::jsonb
  end;

  if operations <> '{}'::jsonb then
    connection_state := 'configured';
    metrics_payload := case
      when jsonb_typeof(operations -> 'metrics') = 'object'
        then operations -> 'metrics'
      else operations - 'alerts' - 'attention' - 'handled' - 'handledActions' - 'insights' - 'observedAt' - 'updatedAt'
    end;
    alerts_payload := case
      when jsonb_typeof(operations -> 'alerts') = 'array' then operations -> 'alerts'
      when jsonb_typeof(operations -> 'attention') = 'array' then operations -> 'attention'
      else '[]'::jsonb
    end;
    handled_payload := case
      when jsonb_typeof(operations -> 'handled') = 'array' then operations -> 'handled'
      when jsonb_typeof(operations -> 'handledActions') = 'array' then operations -> 'handledActions'
      else '[]'::jsonb
    end;
    insights_payload := case
      when jsonb_typeof(operations -> 'insights') = 'array' then operations -> 'insights'
      else '[]'::jsonb
    end;
  end if;

  return jsonb_build_object(
    'projectKey', project_record.project_key,
    'displayName', display_name,
    'connectionState', connection_state,
    'metrics', metrics_payload,
    'alerts', alerts_payload,
    'handled', handled_payload,
    'insights', insights_payload,
    'observedAt', coalesce(operations ->> 'observedAt', operations ->> 'updatedAt'),
    'source', case when operations <> '{}'::jsonb then 'PLP operations' else null end
  );
end;
$$;

revoke all on function public.pandora_enterprise_business_overview_v1(uuid, text) from public, anon;
grant execute on function public.pandora_enterprise_business_overview_v1(uuid, text) to authenticated;

create or replace function public.pandora_enterprise_business_snapshot_ingest_v1(
  target_organization_id uuid,
  target_project_key text,
  source_name text,
  source_observed_at timestamptz,
  snapshot_payload jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_id uuid;
begin
  if (select auth.role()) <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if coalesce(target_project_key, '') = '' then
    raise exception 'project key required' using errcode = '22023';
  end if;

  insert into public.pandora_enterprise_business_snapshots (
    organization_id, project_key, source, observed_at,
    metrics, alerts, handled, insights
  ) values (
    target_organization_id,
    target_project_key,
    coalesce(nullif(source_name, ''), 'business_operations'),
    coalesce(source_observed_at, timezone('utc', now())),
    case when jsonb_typeof(snapshot_payload -> 'metrics') = 'object' then snapshot_payload -> 'metrics' else '{}'::jsonb end,
    case when jsonb_typeof(snapshot_payload -> 'alerts') = 'array' then snapshot_payload -> 'alerts' else '[]'::jsonb end,
    case when jsonb_typeof(snapshot_payload -> 'handled') = 'array' then snapshot_payload -> 'handled' else '[]'::jsonb end,
    case when jsonb_typeof(snapshot_payload -> 'insights') = 'array' then snapshot_payload -> 'insights' else '[]'::jsonb end
  ) returning id into inserted_id;

  return inserted_id;
end;
$$;

revoke all on function public.pandora_enterprise_business_snapshot_ingest_v1(uuid, text, text, timestamptz, jsonb)
  from public, anon, authenticated;
grant execute on function public.pandora_enterprise_business_snapshot_ingest_v1(uuid, text, text, timestamptz, jsonb)
  to service_role;

comment on table public.pandora_enterprise_business_snapshots is
  'Customer-safe Enterprise business snapshots. Engineering and provider telemetry must not be stored here.';
comment on function public.pandora_enterprise_business_overview_v1(uuid, text) is
  'Returns only customer-facing Enterprise business state with explicit freshness; excludes engineering telemetry.';
