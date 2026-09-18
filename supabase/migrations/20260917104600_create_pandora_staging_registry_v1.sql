
create schema if not exists pandora_staging;
revoke all on schema pandora_staging from public, anon, authenticated;
grant usage on schema pandora_staging to service_role;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'pandora-staging','pandora-staging',false,104857600,
  array['application/octet-stream','application/json','text/plain','application/gzip','application/x-gzip','application/zip']::text[]
)
on conflict (id) do update
set public=false,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types,
    updated_at=now();

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
  build_evidence_sha256 text check (build_evidence_sha256 is null or build_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  build_evidence_bytes bigint check (build_evidence_bytes is null or build_evidence_bytes between 1 and 5242880),
  test_results_sha256 text check (test_results_sha256 is null or test_results_sha256 ~ '^[0-9a-f]{64}$'),
  test_results_bytes bigint check (test_results_bytes is null or test_results_bytes between 1 and 67108864),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_by text not null check (length(created_by) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sealed_at timestamptz,
  verified_at timestamptz,
  published_at timestamptz,
  github_branch text,
  github_commit_sha text check (github_commit_sha is null or github_commit_sha ~ '^[0-9a-f]{40}$'),
  github_pr_number integer check (github_pr_number is null or github_pr_number > 0),
  promotion_readback jsonb check (promotion_readback is null or jsonb_typeof(promotion_readback)='object'),
  constraint pandora_snapshots_build_evidence_pair_ck check ((build_evidence_sha256 is null)=(build_evidence_bytes is null)),
  constraint pandora_snapshots_test_results_pair_ck check ((test_results_sha256 is null)=(test_results_bytes is null))
);

create unique index if not exists pandora_snapshots_source_identity_uq
  on pandora_staging.pandora_snapshots(project_id,source_bundle_sha256,manifest_sha256,checksums_sha256);
create index if not exists pandora_snapshots_project_state_idx
  on pandora_staging.pandora_snapshots(project_id,state,created_at desc);
create index if not exists pandora_snapshots_created_at_idx
  on pandora_staging.pandora_snapshots(created_at desc);
create index if not exists pandora_projects_organization_idx
  on pandora_staging.pandora_projects(organization_id);

create table if not exists pandora_staging.pandora_snapshot_events (
  id bigint generated always as identity primary key,
  snapshot_id uuid not null references pandora_staging.pandora_snapshots(id) on delete restrict,
  sequence integer not null check (sequence > 0),
  event_type text not null check (event_type ~ '^snapshot\.[a-z0-9_.-]{2,80}$'),
  from_state text check (from_state is null or from_state in ('staged','building','verified','rejected','published')),
  to_state text check (to_state is null or to_state in ('staged','building','verified','rejected','published')),
  actor text not null check (length(actor) between 1 and 200),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  previous_event_hash text check (previous_event_hash is null or previous_event_hash ~ '^[0-9a-f]{64}$'),
  event_hash text not null check (event_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(snapshot_id,sequence),
  unique(event_hash)
);
create index if not exists pandora_snapshot_events_snapshot_idx
  on pandora_staging.pandora_snapshot_events(snapshot_id,sequence);

alter table pandora_staging.pandora_projects enable row level security;
alter table pandora_staging.pandora_snapshots enable row level security;
alter table pandora_staging.pandora_snapshot_events enable row level security;
revoke all on all tables in schema pandora_staging from public, anon, authenticated;
revoke all on all sequences in schema pandora_staging from public, anon, authenticated;

create or replace function pandora_staging.reject_snapshot_direct_mutation()
returns trigger language plpgsql set search_path=pg_catalog,pandora_staging as $$
begin
  if tg_op='DELETE' then raise exception 'pandora_staging_snapshot_delete_forbidden' using errcode='42501'; end if;
  if coalesce(current_setting('pandora_staging.allow_snapshot_mutation',true),'') <> 'on' then
    raise exception 'pandora_staging_snapshot_direct_update_forbidden' using errcode='42501';
  end if;
  return new;
end; $$;

create or replace function pandora_staging.reject_event_mutation()
returns trigger language plpgsql set search_path=pg_catalog,pandora_staging as $$
begin raise exception 'pandora_staging_event_immutable' using errcode='42501'; end; $$;

drop trigger if exists pandora_snapshots_guard on pandora_staging.pandora_snapshots;
create trigger pandora_snapshots_guard before update or delete on pandora_staging.pandora_snapshots
for each row execute function pandora_staging.reject_snapshot_direct_mutation();
drop trigger if exists pandora_snapshot_events_immutable on pandora_staging.pandora_snapshot_events;
create trigger pandora_snapshot_events_immutable before update or delete on pandora_staging.pandora_snapshot_events
for each row execute function pandora_staging.reject_event_mutation();

create or replace function pandora_staging.append_event(
  p_snapshot_id uuid,p_event_type text,p_from_state text,p_to_state text,p_actor text,p_evidence jsonb default '{}'::jsonb
) returns pandora_staging.pandora_snapshot_events
language plpgsql set search_path=pg_catalog,pandora_staging,extensions as $$
declare
  v_sequence integer; v_previous_hash text; v_created_at timestamptz:=clock_timestamp();
  v_hash text; v_row pandora_staging.pandora_snapshot_events;
begin
  if p_event_type !~ '^snapshot\.[a-z0-9_.-]{2,80}$' or nullif(trim(p_actor),'') is null
     or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then
    raise exception 'pandora_staging_event_invalid' using errcode='22023';
  end if;
  select e.sequence,e.event_hash into v_sequence,v_previous_hash
  from pandora_staging.pandora_snapshot_events e
  where e.snapshot_id=p_snapshot_id order by e.sequence desc limit 1;
  v_sequence:=coalesce(v_sequence,0)+1;
  v_hash:=encode(extensions.digest(
    jsonb_build_object(
      'snapshotId',p_snapshot_id,'sequence',v_sequence,'eventType',p_event_type,
      'fromState',p_from_state,'toState',p_to_state,'actor',p_actor,
      'evidence',coalesce(p_evidence,'{}'::jsonb),'previousEventHash',v_previous_hash,
      'createdAt',to_char(v_created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )::text,'sha256'),'hex');
  insert into pandora_staging.pandora_snapshot_events(
    snapshot_id,sequence,event_type,from_state,to_state,actor,evidence,previous_event_hash,event_hash,created_at
  ) values (
    p_snapshot_id,v_sequence,p_event_type,p_from_state,p_to_state,p_actor,
    coalesce(p_evidence,'{}'::jsonb),v_previous_hash,v_hash,v_created_at
  ) returning * into v_row;
  return v_row;
end; $$;

insert into pandora_staging.pandora_projects(organization_id,project_key,canonical_repository)
select id,'pandoras-box','pandora-rvw-314296438-20260820/pandoras-box'
from public.organizations
where slug='mcpmaster-staging'
on conflict(project_key) do nothing;

create or replace function public.pandora_staging_register_snapshot_v2(
  p_organization_id uuid,p_project_key text,p_source_bundle_sha256 text,p_source_bundle_bytes bigint,
  p_manifest_sha256 text,p_manifest_bytes bigint,p_checksums_sha256 text,p_checksums_bytes bigint,
  p_actor text,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_project pandora_staging.pandora_projects; v_snapshot pandora_staging.pandora_snapshots; v_created boolean:=false;
begin
  select * into v_project from pandora_staging.pandora_projects
  where organization_id=p_organization_id and project_key=p_project_key and active is true;
  if not found then raise exception 'pandora_staging_project_not_found' using errcode='P0002'; end if;
  if p_source_bundle_sha256 !~ '^[0-9a-f]{64}$' or p_manifest_sha256 !~ '^[0-9a-f]{64}$' or p_checksums_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_bundle_bytes not between 1 and 26214400 or p_manifest_bytes not between 1 and 1048576 or p_checksums_bytes not between 1 and 1048576
     or nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'pandora_staging_snapshot_invalid' using errcode='22023';
  end if;
  select * into v_snapshot from pandora_staging.pandora_snapshots
  where project_id=v_project.id and source_bundle_sha256=p_source_bundle_sha256
    and manifest_sha256=p_manifest_sha256 and checksums_sha256=p_checksums_sha256
  order by created_at desc limit 1;
  if not found then
    v_snapshot.id:=gen_random_uuid();
    insert into pandora_staging.pandora_snapshots(
      id,project_id,state,object_prefix,source_bundle_sha256,source_bundle_bytes,
      manifest_sha256,manifest_bytes,checksums_sha256,checksums_bytes,metadata,created_by
    ) values (
      v_snapshot.id,v_project.id,'staged',p_project_key||'/'||v_snapshot.id::text,
      p_source_bundle_sha256,p_source_bundle_bytes,p_manifest_sha256,p_manifest_bytes,
      p_checksums_sha256,p_checksums_bytes,coalesce(p_metadata,'{}'::jsonb),p_actor
    ) returning * into v_snapshot;
    v_created:=true;
    perform pandora_staging.append_event(v_snapshot.id,'snapshot.registered',null,'staged',p_actor,
      jsonb_build_object('projectKey',p_project_key,'repository',v_project.canonical_repository,
        'objectPrefix',v_snapshot.object_prefix,'sourceBundleSha256',p_source_bundle_sha256));
  end if;
  return jsonb_build_object('created',v_created,'snapshotId',v_snapshot.id,'state',v_snapshot.state,
    'sealedAt',v_snapshot.sealed_at,'objectPrefix',v_snapshot.object_prefix,'repository',v_project.canonical_repository,
    'objects',jsonb_build_object(
      'source.bundle',jsonb_build_object('path',v_snapshot.object_prefix||'/source.bundle','sha256',v_snapshot.source_bundle_sha256,'bytes',v_snapshot.source_bundle_bytes),
      'manifest.json',jsonb_build_object('path',v_snapshot.object_prefix||'/manifest.json','sha256',v_snapshot.manifest_sha256,'bytes',v_snapshot.manifest_bytes),
      'checksums.sha256',jsonb_build_object('path',v_snapshot.object_prefix||'/checksums.sha256','sha256',v_snapshot.checksums_sha256,'bytes',v_snapshot.checksums_bytes)));
end; $$;

create or replace function public.pandora_staging_get_snapshot_v1(p_snapshot_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public,pandora_staging as $$
select jsonb_build_object(
  'snapshotId',s.id,'projectId',s.project_id,'organizationId',p.organization_id,'projectKey',p.project_key,
  'repository',p.canonical_repository,'state',s.state,'objectPrefix',s.object_prefix,
  'sourceBundleSha256',s.source_bundle_sha256,'sourceBundleBytes',s.source_bundle_bytes,
  'manifestSha256',s.manifest_sha256,'manifestBytes',s.manifest_bytes,
  'checksumsSha256',s.checksums_sha256,'checksumsBytes',s.checksums_bytes,
  'buildEvidenceSha256',s.build_evidence_sha256,'buildEvidenceBytes',s.build_evidence_bytes,
  'testResultsSha256',s.test_results_sha256,'testResultsBytes',s.test_results_bytes,
  'metadata',s.metadata,'createdBy',s.created_by,'createdAt',s.created_at,'sealedAt',s.sealed_at,
  'verifiedAt',s.verified_at,'publishedAt',s.published_at,'githubBranch',s.github_branch,
  'githubCommitSha',s.github_commit_sha,'githubPrNumber',s.github_pr_number,'promotionReadback',s.promotion_readback
)
from pandora_staging.pandora_snapshots s
join pandora_staging.pandora_projects p on p.id=s.project_id
where s.id=p_snapshot_id;
$$;

create or replace function public.pandora_staging_seal_snapshot_v1(
  p_snapshot_id uuid,p_actor text,p_evidence jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> 'staged' then raise exception 'pandora_staging_snapshot_not_staged' using errcode='55000'; end if;
  if v_snapshot.sealed_at is not null then return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'alreadySealed',true); end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then raise exception 'pandora_staging_seal_invalid' using errcode='22023'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots set sealed_at=now(),updated_at=now() where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.sealed','staged','staged',p_actor,coalesce(p_evidence,'{}'::jsonb));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'alreadySealed',false);
end; $$;

create or replace function public.pandora_staging_transition_snapshot_v1(
  p_snapshot_id uuid,p_expected_state text,p_new_state text,p_actor text,p_evidence jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots; v_allowed boolean:=false;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> p_expected_state then raise exception 'pandora_staging_state_moved' using errcode='40001'; end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then raise exception 'pandora_staging_transition_invalid' using errcode='22023'; end if;
  v_allowed := (p_expected_state='staged' and p_new_state in ('building','rejected'))
    or (p_expected_state='building' and p_new_state in ('verified','rejected'))
    or (p_expected_state='verified' and p_new_state='rejected');
  if not v_allowed then raise exception 'pandora_staging_transition_not_allowed' using errcode='22023'; end if;
  if p_new_state='building' and v_snapshot.sealed_at is null then raise exception 'pandora_staging_snapshot_not_sealed' using errcode='55000'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots
  set state=p_new_state,verified_at=case when p_new_state='verified' then now() else verified_at end,updated_at=now()
  where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.'||p_new_state,p_expected_state,p_new_state,p_actor,coalesce(p_evidence,'{}'::jsonb));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'verifiedAt',v_snapshot.verified_at);
end; $$;

create or replace function public.pandora_staging_attach_evidence_v1(
  p_snapshot_id uuid,p_build_evidence_sha256 text,p_build_evidence_bytes bigint,
  p_test_results_sha256 text,p_test_results_bytes bigint,p_actor text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> 'building' then raise exception 'pandora_staging_snapshot_not_building' using errcode='55000'; end if;
  if p_build_evidence_sha256 !~ '^[0-9a-f]{64}$' or p_test_results_sha256 !~ '^[0-9a-f]{64}$'
     or p_build_evidence_bytes not between 1 and 5242880 or p_test_results_bytes not between 1 and 67108864
     or nullif(trim(p_actor),'') is null then raise exception 'pandora_staging_evidence_invalid' using errcode='22023'; end if;
  if v_snapshot.build_evidence_sha256 is not null or v_snapshot.test_results_sha256 is not null then
    if v_snapshot.build_evidence_sha256=p_build_evidence_sha256 and v_snapshot.build_evidence_bytes=p_build_evidence_bytes
       and v_snapshot.test_results_sha256=p_test_results_sha256 and v_snapshot.test_results_bytes=p_test_results_bytes then
      return jsonb_build_object('snapshotId',v_snapshot.id,'alreadyAttached',true,'objectPrefix',v_snapshot.object_prefix);
    end if;
    raise exception 'pandora_staging_evidence_already_attached' using errcode='55000';
  end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots
  set build_evidence_sha256=p_build_evidence_sha256,build_evidence_bytes=p_build_evidence_bytes,
      test_results_sha256=p_test_results_sha256,test_results_bytes=p_test_results_bytes,updated_at=now()
  where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.evidence_attached','building','building',p_actor,
    jsonb_build_object('buildEvidenceSha256',p_build_evidence_sha256,'testResultsSha256',p_test_results_sha256));
  return jsonb_build_object('snapshotId',v_snapshot.id,'alreadyAttached',false,'objectPrefix',v_snapshot.object_prefix,
    'objects',jsonb_build_object(
      'build-evidence.json',jsonb_build_object('path',v_snapshot.object_prefix||'/build-evidence.json','sha256',v_snapshot.build_evidence_sha256,'bytes',v_snapshot.build_evidence_bytes),
      'test-results.tar.gz',jsonb_build_object('path',v_snapshot.object_prefix||'/test-results.tar.gz','sha256',v_snapshot.test_results_sha256,'bytes',v_snapshot.test_results_bytes)));
end; $$;

create or replace function public.pandora_staging_record_github_promotion_v1(
  p_snapshot_id uuid,p_branch text,p_commit_sha text,p_pr_number integer,p_actor text,p_readback jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state='published' then
    if v_snapshot.github_branch=p_branch and v_snapshot.github_commit_sha=p_commit_sha and v_snapshot.github_pr_number=p_pr_number then
      return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'alreadyPublished',true,'branch',v_snapshot.github_branch,'commitSha',v_snapshot.github_commit_sha,'prNumber',v_snapshot.github_pr_number);
    end if;
    raise exception 'pandora_staging_snapshot_already_published' using errcode='55000';
  end if;
  if v_snapshot.state <> 'verified' then raise exception 'pandora_staging_snapshot_not_verified' using errcode='55000'; end if;
  if p_branch !~ '^pandora/staging-[a-z0-9-]{8,64}$' or p_commit_sha !~ '^[0-9a-f]{40}$'
     or p_pr_number is null or p_pr_number<=0 or nullif(trim(p_actor),'') is null
     or jsonb_typeof(coalesce(p_readback,'{}'::jsonb)) <> 'object' then raise exception 'pandora_staging_promotion_invalid' using errcode='22023'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots
  set state='published',published_at=now(),updated_at=now(),github_branch=p_branch,
      github_commit_sha=p_commit_sha,github_pr_number=p_pr_number,promotion_readback=coalesce(p_readback,'{}'::jsonb)
  where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.published','verified','published',p_actor,
    jsonb_build_object('branch',p_branch,'commitSha',p_commit_sha,'prNumber',p_pr_number,'readback',coalesce(p_readback,'{}'::jsonb)));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'alreadyPublished',false,
    'branch',v_snapshot.github_branch,'commitSha',v_snapshot.github_commit_sha,'prNumber',v_snapshot.github_pr_number);
end; $$;

create or replace function public.pandora_staging_github_fallback_request_v1(
  p_method text,p_path text,p_body jsonb default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare
  v_method text:=upper(trim(coalesce(p_method,'')));
  v_path text:=trim(coalesce(p_path,''));
  v_prefix constant text:='/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_body_text text:=coalesce(p_body::text,'');
begin
  if v_method not in ('GET','POST') or v_path like '%..%' or length(v_path)>1600 then
    raise exception 'pandora_staging_github_fallback_request_invalid' using errcode='22023';
  end if;
  if v_method='GET' then
    if not (
      v_path=v_prefix or v_path=v_prefix||'/git/ref/heads/main'
      or v_path ~ ('^'||v_prefix||'/git/ref/heads/pandora/staging-[a-z0-9-]{8,64}$')
      or v_path ~ ('^'||v_prefix||'/git/commits/[0-9a-f]{40}$')
      or v_path ~ ('^'||v_prefix||'/pulls/[1-9][0-9]*$')
      or v_path ~ ('^'||v_prefix||'/pulls\?state=open&head=[A-Za-z0-9_.-]+:pandora%2Fstaging-[a-z0-9-]{8,64}&base=main&per_page=10$')
    ) then raise exception 'pandora_staging_github_fallback_read_not_allowed' using errcode='22023'; end if;
  else
    if v_path not in (v_prefix||'/git/blobs',v_prefix||'/git/trees',v_prefix||'/git/commits',v_prefix||'/git/refs',v_prefix||'/pulls') then
      raise exception 'pandora_staging_github_fallback_write_not_allowed' using errcode='22023';
    end if;
    if octet_length(v_body_text)>14000000 then raise exception 'pandora_staging_github_fallback_body_too_large' using errcode='22023'; end if;
  end if;
  return private.pandora_integration_github_api_20260825(v_method,v_path,p_body);
end; $$;

revoke all on function public.pandora_staging_register_snapshot_v2(uuid,text,text,bigint,text,bigint,text,bigint,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_get_snapshot_v1(uuid) from public,anon,authenticated;
revoke all on function public.pandora_staging_seal_snapshot_v1(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_transition_snapshot_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_attach_evidence_v1(uuid,text,bigint,text,bigint,text) from public,anon,authenticated;
revoke all on function public.pandora_staging_record_github_promotion_v1(uuid,text,text,integer,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_github_fallback_request_v1(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_staging_register_snapshot_v2(uuid,text,text,bigint,text,bigint,text,bigint,text,jsonb) to service_role;
grant execute on function public.pandora_staging_get_snapshot_v1(uuid) to service_role;
grant execute on function public.pandora_staging_seal_snapshot_v1(uuid,text,jsonb) to service_role;
grant execute on function public.pandora_staging_transition_snapshot_v1(uuid,text,text,text,jsonb) to service_role;
grant execute on function public.pandora_staging_attach_evidence_v1(uuid,text,bigint,text,bigint,text) to service_role;
grant execute on function public.pandora_staging_record_github_promotion_v1(uuid,text,text,integer,text,jsonb) to service_role;
grant execute on function public.pandora_staging_github_fallback_request_v1(text,text,jsonb) to service_role;

comment on schema pandora_staging is 'Private pre-GitHub source staging registry.';
comment on table pandora_staging.pandora_snapshots is 'Immutable-content snapshot registry; published means promoted to canonical GitHub, not deployed.';
comment on table pandora_staging.pandora_snapshot_events is 'Append-only hash-chained staging lifecycle evidence.';
