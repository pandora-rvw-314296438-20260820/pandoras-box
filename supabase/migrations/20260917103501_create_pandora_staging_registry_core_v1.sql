create schema if not exists pandora_staging;
revoke all on schema pandora_staging from public, anon, authenticated;
grant usage on schema pandora_staging to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pandora-staging','pandora-staging',false,104857600,array['application/octet-stream','application/json','text/plain','application/gzip','application/x-gzip','application/zip']::text[])
on conflict (id) do update
set public=false, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types, updated_at=now();

create table if not exists pandora_staging.pandora_projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  project_key text not null unique check (project_key ~ '^[a-z0-9][a-z0-9._-]{1,79}$'),
  canonical_repository text not null unique check (canonical_repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists pandora_staging.pandora_snapshots (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references pandora_staging.pandora_projects(id) on delete restrict,
  state text not null default 'staged' check (state in ('staged','building','verified','rejected','published')),
  object_prefix text not null unique,
  source_bundle_sha256 text not null check (source_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  source_bundle_bytes bigint not null check (source_bundle_bytes between 1 and 26214400),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_bytes bigint not null check (manifest_bytes between 1 and 1048576),
  checksums_sha256 text not null check (checksums_sha256 ~ '^[0-9a-f]{64}$'),
  checksums_bytes bigint not null check (checksums_bytes between 1 and 1048576),
  build_evidence_sha256 text not null check (build_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  build_evidence_bytes bigint not null check (build_evidence_bytes between 1 and 5242880),
  test_results_sha256 text not null check (test_results_sha256 ~ '^[0-9a-f]{64}$'),
  test_results_bytes bigint not null check (test_results_bytes between 1 and 67108864),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_by text not null check (length(created_by) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sealed_at timestamptz,
  verified_at timestamptz,
  published_at timestamptz,
  github_branch text,
  github_commit_sha text check (github_commit_sha is null or github_commit_sha ~ '^[0-9a-f]{40}$'),
  github_pr_number integer check (github_pr_number is null or github_pr_number>0),
  promotion_readback jsonb check (promotion_readback is null or jsonb_typeof(promotion_readback)='object'),
  unique(project_id,source_bundle_sha256,manifest_sha256,checksums_sha256,build_evidence_sha256,test_results_sha256)
);

create index if not exists pandora_snapshots_project_state_idx on pandora_staging.pandora_snapshots(project_id,state,created_at desc);
create index if not exists pandora_snapshots_created_at_idx on pandora_staging.pandora_snapshots(created_at desc);

create table if not exists pandora_staging.pandora_snapshot_events (
  id bigint generated always as identity primary key,
  snapshot_id uuid not null references pandora_staging.pandora_snapshots(id) on delete restrict,
  sequence integer not null check (sequence>0),
  event_type text not null check (event_type ~ '^snapshot\.[a-z0-9_.-]{2,80}$'),
  from_state text check (from_state is null or from_state in ('staged','building','verified','rejected','published')),
  to_state text check (to_state is null or to_state in ('staged','building','verified','rejected','published')),
  actor text not null check (length(actor) between 1 and 200),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  previous_event_hash text check (previous_event_hash is null or previous_event_hash ~ '^[0-9a-f]{64}$'),
  event_hash text not null check (event_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(snapshot_id,sequence), unique(event_hash)
);
create index if not exists pandora_snapshot_events_snapshot_idx on pandora_staging.pandora_snapshot_events(snapshot_id,sequence);

alter table pandora_staging.pandora_projects enable row level security;
alter table pandora_staging.pandora_snapshots enable row level security;
alter table pandora_staging.pandora_snapshot_events enable row level security;
revoke all on all tables in schema pandora_staging from public, anon, authenticated;
revoke all on all sequences in schema pandora_staging from public, anon, authenticated;

create or replace function pandora_staging.reject_snapshot_direct_mutation() returns trigger language plpgsql set search_path=pg_catalog,pandora_staging as $$
begin
  if tg_op='DELETE' then raise exception 'pandora_staging_snapshot_delete_forbidden' using errcode='42501'; end if;
  if coalesce(current_setting('pandora_staging.allow_snapshot_mutation',true),'')<>'on' then raise exception 'pandora_staging_snapshot_direct_update_forbidden' using errcode='42501'; end if;
  return new;
end; $$;

create or replace function pandora_staging.reject_event_mutation() returns trigger language plpgsql set search_path=pg_catalog,pandora_staging as $$
begin raise exception 'pandora_staging_event_immutable' using errcode='42501'; end; $$;

drop trigger if exists pandora_snapshots_guard on pandora_staging.pandora_snapshots;
create trigger pandora_snapshots_guard before update or delete on pandora_staging.pandora_snapshots for each row execute function pandora_staging.reject_snapshot_direct_mutation();
drop trigger if exists pandora_snapshot_events_immutable on pandora_staging.pandora_snapshot_events;
create trigger pandora_snapshot_events_immutable before update or delete on pandora_staging.pandora_snapshot_events for each row execute function pandora_staging.reject_event_mutation();

create or replace function pandora_staging.append_event(p_snapshot_id uuid,p_event_type text,p_from_state text,p_to_state text,p_actor text,p_evidence jsonb default '{}'::jsonb)
returns pandora_staging.pandora_snapshot_events language plpgsql set search_path=pg_catalog,pandora_staging,extensions as $$
declare v_sequence integer; v_previous_hash text; v_created_at timestamptz:=clock_timestamp(); v_hash text; v_row pandora_staging.pandora_snapshot_events;
begin
  if p_event_type !~ '^snapshot\.[a-z0-9_.-]{2,80}$' or nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_event_invalid' using errcode='22023'; end if;
  select e.sequence,e.event_hash into v_sequence,v_previous_hash from pandora_staging.pandora_snapshot_events e where e.snapshot_id=p_snapshot_id order by e.sequence desc limit 1;
  v_sequence:=coalesce(v_sequence,0)+1;
  v_hash:=encode(extensions.digest(jsonb_build_object('snapshotId',p_snapshot_id,'sequence',v_sequence,'eventType',p_event_type,'fromState',p_from_state,'toState',p_to_state,'actor',p_actor,'evidence',coalesce(p_evidence,'{}'::jsonb),'previousEventHash',v_previous_hash,'createdAt',to_char(v_created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'sha256'),'hex');
  insert into pandora_staging.pandora_snapshot_events(snapshot_id,sequence,event_type,from_state,to_state,actor,evidence,previous_event_hash,event_hash,created_at)
  values(p_snapshot_id,v_sequence,p_event_type,p_from_state,p_to_state,p_actor,coalesce(p_evidence,'{}'::jsonb),v_previous_hash,v_hash,v_created_at) returning * into v_row;
  return v_row;
end; $$;

insert into pandora_staging.pandora_projects(organization_id,project_key,canonical_repository)
values('2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,'pandoras-box','pandora-rvw-314296438-20260820/pandoras-box')
on conflict(project_key) do nothing;

comment on schema pandora_staging is 'Private pre-GitHub source staging registry.';
comment on table pandora_staging.pandora_snapshots is 'Immutable-content snapshot registry; published means promoted to canonical GitHub, not deployed.';
comment on table pandora_staging.pandora_snapshot_events is 'Append-only hash-chained staging lifecycle evidence.';
