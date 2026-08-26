-- Read-only canonical release receipt projection. Source files describe the
-- contract; only service-role reads of provider/reviewer evidence can satisfy it.

create table private.canonical_supabase_release_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  repository text not null check (repository = 'pandora-rvw-314296438-20260820/pandoras-box'),
  project_ref text not null check (project_ref = 'jcyqixttuebxqqfkjonq'),
  source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$'),
  source_tree_sha text not null check (source_tree_sha ~ '^[0-9a-f]{40}$'),
  source_chain_sha256 text not null check (source_chain_sha256 ~ '^[0-9a-f]{64}$'),
  source_artifact_sha256 text not null check (source_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  source_artifact_external_id text not null check (source_artifact_external_id ~ '^[1-9][0-9]{0,19}$'),
  source_artifact_url text not null,
  expected_version_chain_sha256 text not null check (expected_version_chain_sha256 ~ '^[0-9a-f]{64}$'),
  captured_applied_versions text[] not null check (cardinality(captured_applied_versions) > 0),
  captured_version_chain_sha256 text not null check (captured_version_chain_sha256 ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default clock_timestamp(),
  unique (organization_id, repository, source_sha),
  check (
    source_artifact_url = 'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/'
      || source_artifact_external_id
  ),
  check (captured_version_chain_sha256 = expected_version_chain_sha256)
);

create table private.canonical_vercel_rehearsal_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  repository text not null check (repository = 'pandora-rvw-314296438-20260820/pandoras-box'),
  project_id text not null check (project_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'),
  team_id text not null check (team_id = 'team_IcdJUnzLi5wUN1GD8ALHyjF7'),
  phase text not null check (phase in ('rollback_transition', 'rollback_restoration')),
  candidate_deployment_id text not null check (candidate_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  candidate_source_sha text not null check (candidate_source_sha ~ '^[0-9a-f]{40}$'),
  rollback_deployment_id text not null check (rollback_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  rollback_source_sha text not null check (rollback_source_sha ~ '^[0-9a-f]{40}$'),
  transition_from_deployment_id text not null check (transition_from_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  transition_to_deployment_id text not null check (transition_to_deployment_id ~ '^dpl_[A-Za-z0-9]+$'),
  external_id text not null check (external_id ~ '^dpl_[A-Za-z0-9]+$'),
  vercel_api_source_url text not null,
  alias_api_source_url text not null check (
    alias_api_source_url = 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app'
      || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
  ),
  alias_pre_response_sha256 text not null check (alias_pre_response_sha256 ~ '^[0-9a-f]{64}$'),
  alias_pre_observed_at timestamptz not null,
  alias_post_response_sha256 text not null check (alias_post_response_sha256 ~ '^[0-9a-f]{64}$'),
  alias_post_observed_at timestamptz not null,
  route_probe_contract text not null check (route_probe_contract = 'canonical_routes_v1'),
  route_probe_sha256 text not null check (route_probe_sha256 ~ '^[0-9a-f]{64}$'),
  route_probe_observed_at timestamptz not null,
  observed_at timestamptz not null default clock_timestamp(),
  unique (organization_id, repository, candidate_source_sha, phase),
  check (candidate_deployment_id <> rollback_deployment_id),
  check (candidate_source_sha <> rollback_source_sha),
  check (
    alias_pre_observed_at < route_probe_observed_at
    and route_probe_observed_at < alias_post_observed_at
    and alias_post_observed_at <= observed_at
  ),
  check (
    vercel_api_source_url = 'https://api.vercel.com/v13/deployments/'
      || external_id
      || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
  ),
  check (
    (phase = 'rollback_transition'
      and transition_from_deployment_id = candidate_deployment_id
      and transition_to_deployment_id = rollback_deployment_id
      and external_id = rollback_deployment_id)
    or
    (phase = 'rollback_restoration'
      and transition_from_deployment_id = rollback_deployment_id
      and transition_to_deployment_id = candidate_deployment_id
      and external_id = candidate_deployment_id)
  )
);

create or replace function private.reject_canonical_release_receipt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'canonical release receipts are immutable' using errcode = '55000';
end;
$$;

create trigger canonical_supabase_release_receipts_immutable
before update or delete on private.canonical_supabase_release_receipts
for each row execute function private.reject_canonical_release_receipt_mutation();

create trigger canonical_vercel_rehearsal_receipts_immutable
before update or delete on private.canonical_vercel_rehearsal_receipts
for each row execute function private.reject_canonical_release_receipt_mutation();

create or replace function public.capture_canonical_supabase_release_receipt(
  p_organization_id uuid,
  p_repository text,
  p_source_sha text,
  p_source_tree_sha text,
  p_source_chain_sha256 text,
  p_source_artifact_sha256 text,
  p_source_artifact_external_id text,
  p_source_artifact_url text,
  p_expected_version_chain_sha256 text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  applied_versions text[];
  applied_version_chain_sha256 text;
  receipt private.canonical_supabase_release_receipts%rowtype;
begin
  perform private.assert_control_service_role();

  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_source_sha !~ '^[0-9a-f]{40}$'
     or p_source_tree_sha !~ '^[0-9a-f]{40}$'
     or p_source_chain_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_artifact_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_artifact_external_id !~ '^[1-9][0-9]{0,19}$'
     or p_source_artifact_url <> 'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/'
       || p_source_artifact_external_id
     or p_expected_version_chain_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid canonical Supabase receipt identity';
  end if;

  if exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version !~ '^[0-9]{14}$'
  ) then
    raise exception 'invalid live Supabase migration version';
  end if;

  select coalesce(array_agg(migration.version order by migration.version), '{}'::text[]),
         encode(extensions.digest(
           coalesce(string_agg(migration.version || E'\n', '' order by migration.version), ''),
           'sha256'
         ), 'hex')
    into applied_versions, applied_version_chain_sha256
  from supabase_migrations.schema_migrations migration;

  if cardinality(applied_versions) = 0
     or applied_version_chain_sha256 <> p_expected_version_chain_sha256 then
    raise exception 'live Supabase migration history does not match source artifact';
  end if;

  insert into private.canonical_supabase_release_receipts (
    organization_id,
    repository,
    project_ref,
    source_sha,
    source_tree_sha,
    source_chain_sha256,
    source_artifact_sha256,
    source_artifact_external_id,
    source_artifact_url,
    expected_version_chain_sha256,
    captured_applied_versions,
    captured_version_chain_sha256
  ) values (
    p_organization_id,
    p_repository,
    'jcyqixttuebxqqfkjonq',
    p_source_sha,
    p_source_tree_sha,
    p_source_chain_sha256,
    p_source_artifact_sha256,
    p_source_artifact_external_id,
    p_source_artifact_url,
    p_expected_version_chain_sha256,
    applied_versions,
    applied_version_chain_sha256
  ) returning * into receipt;

  return jsonb_build_object(
    'providerDatabaseReceiptId', receipt.id,
    'projectRef', receipt.project_ref,
    'sourceSha', receipt.source_sha,
    'sourceTreeSha', receipt.source_tree_sha,
    'sourceArtifactDatabaseReceipt', jsonb_build_object(
      'databaseCaptured', true,
      'externalId', receipt.source_artifact_external_id,
      'sourceUrl', receipt.source_artifact_url,
      'artifactSha256', receipt.source_artifact_sha256,
      'sourceChainSha256', receipt.source_chain_sha256
    ),
    'capturedVersionChainSha256', receipt.captured_version_chain_sha256,
    'capturedAt', receipt.captured_at,
    'exactAppliedBytesProven', false
  );
end;
$$;

create or replace function public.capture_canonical_vercel_rehearsal_receipt(
  p_organization_id uuid,
  p_repository text,
  p_candidate_source_sha text,
  p_phase text,
  p_candidate_deployment_id text,
  p_rollback_deployment_id text,
  p_rollback_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  transition_receipt private.canonical_vercel_rehearsal_receipts%rowtype;
  receipt private.canonical_vercel_rehearsal_receipts%rowtype;
  target_deployment_id text;
  transition_from text;
  transition_to text;
  target_source_sha text;
  vercel_token text;
  vercel_team_id text;
  alias_response extensions.http_response;
  alias_payload jsonb;
  alias_post_response extensions.http_response;
  alias_post_payload jsonb;
  alias_source_url text := 'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app'
    || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7';
  alias_pre_response_sha256 text;
  alias_pre_observed_at timestamptz;
  alias_post_response_sha256 text;
  alias_post_observed_at timestamptz;
  health_response extensions.http_response;
  mcp_get_response extensions.http_response;
  mcp_post_response extensions.http_response;
  metadata_response extensions.http_response;
  health_payload jsonb;
  metadata_payload jsonb;
  route_probe_sha256 text;
  route_probe_observed_at timestamptz;
begin
  perform private.assert_control_service_role();

  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_candidate_source_sha !~ '^[0-9a-f]{40}$'
     or p_rollback_source_sha !~ '^[0-9a-f]{40}$'
     or p_candidate_source_sha = p_rollback_source_sha
     or p_candidate_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_rollback_deployment_id !~ '^dpl_[A-Za-z0-9]+$'
     or p_candidate_deployment_id = p_rollback_deployment_id
     or p_phase not in ('rollback_transition', 'rollback_restoration') then
    raise exception 'invalid canonical Vercel rehearsal receipt';
  end if;

  if p_phase = 'rollback_restoration' then
    select existing.* into transition_receipt
    from private.canonical_vercel_rehearsal_receipts existing
    where existing.organization_id = p_organization_id
      and existing.repository = p_repository
      and existing.phase = 'rollback_transition'
      and existing.candidate_source_sha = p_candidate_source_sha
      and existing.candidate_deployment_id = p_candidate_deployment_id
      and existing.rollback_deployment_id = p_rollback_deployment_id
      and existing.rollback_source_sha = p_rollback_source_sha
    order by existing.observed_at desc, existing.id desc
    limit 1;

    if transition_receipt.id is null then
      raise exception 'rollback transition receipt must precede restoration';
    end if;
    target_deployment_id := p_candidate_deployment_id;
    target_source_sha := p_candidate_source_sha;
    transition_from := p_rollback_deployment_id;
    transition_to := p_candidate_deployment_id;
  else
    target_deployment_id := p_rollback_deployment_id;
    target_source_sha := p_rollback_source_sha;
    transition_from := p_candidate_deployment_id;
    transition_to := p_rollback_deployment_id;
  end if;

  select secret.decrypted_secret,
         installation.configuration ->> 'team_id'
    into vercel_token, vercel_team_id
  from public.connector_installations installation
  join public.credential_refs credential
    on credential.installation_id = installation.id
   and credential.organization_id = installation.organization_id
  join vault.decrypted_secrets secret
    on credential.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$'
   and secret.id = replace(credential.secret_ref, 'vault://', '')::uuid
  where installation.organization_id = p_organization_id
    and installation.provider = 'vercel'
    and installation.status in ('pending'::public.connector_status, 'active'::public.connector_status)
    and installation.configuration -> 'project_repo_allowlist'
        ->> 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk' = p_repository
    and credential.rotation_state = 'current'::public.rotation_status
  order by installation.updated_at desc
  limit 1;

  if vercel_token is null
     or vercel_team_id <> 'team_IcdJUnzLi5wUN1GD8ALHyjF7' then
    raise exception 'canonical Vercel provider credential unavailable';
  end if;

  perform set_config('http.curlopt_connecttimeout_ms', '2000', true);
  perform set_config('http.curlopt_timeout_ms', '4000', true);

  select * into alias_response
  from extensions.http((
    'GET'::extensions.http_method,
    alias_source_url::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || vercel_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if alias_response.status = 200
     and lower(coalesce(alias_response.content_type, '')) like 'application/json%'
     and octet_length(coalesce(alias_response.content, '')) between 2 and 262144
     and left(ltrim(alias_response.content), 1) = '{' then
    begin
      alias_payload := alias_response.content::jsonb;
      if jsonb_typeof(alias_payload) <> 'object' then
        alias_payload := null;
      end if;
    exception when others then
      alias_payload := null;
    end;
  end if;

  if alias_payload is null
     or alias_payload ->> 'id' <> target_deployment_id
     or alias_payload ->> 'projectId' <> 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
     or alias_payload ->> 'readyState' <> 'READY'
     or alias_payload ->> 'target' <> 'production'
     or not (coalesce(alias_payload -> 'alias', '[]'::jsonb) ? 'mcpmaster.vercel.app')
     or alias_payload #>> '{meta,githubCommitSha}' <> target_source_sha
     or lower(coalesce(
       alias_payload #>> '{meta,githubCommitOrg}',
       alias_payload #>> '{meta,githubOrg}'
     )) <> 'banataosystems'
     or lower(coalesce(
       alias_payload #>> '{meta,githubCommitRepo}',
       alias_payload #>> '{meta,githubRepo}'
     )) <> 'pandoras-box' then
    raise exception 'live Vercel alias does not match rehearsal phase';
  end if;

  alias_pre_observed_at := clock_timestamp();
  alias_pre_response_sha256 := encode(extensions.digest(alias_response.content, 'sha256'), 'hex');

  select * into health_response
  from extensions.http((
    'GET'::extensions.http_method,
    'https://mcpmaster.vercel.app/health'::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  select * into mcp_get_response
  from extensions.http((
    'GET'::extensions.http_method,
    'https://mcpmaster.vercel.app/mcp'::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  select * into mcp_post_response
  from extensions.http((
    'POST'::extensions.http_method,
    'https://mcpmaster.vercel.app/mcp'::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    '{}'::varchar
  )::extensions.http_request);

  select * into metadata_response
  from extensions.http((
    'GET'::extensions.http_method,
    'https://mcpmaster.vercel.app/.well-known/oauth-protected-resource/mcp'::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if health_response.status = 200
     and metadata_response.status = 200
     and lower(coalesce(health_response.content_type, '')) like 'application/json%'
     and lower(coalesce(metadata_response.content_type, '')) like 'application/json%'
     and octet_length(coalesce(health_response.content, '')) between 2 and 65536
     and octet_length(coalesce(metadata_response.content, '')) between 2 and 65536
     and left(ltrim(health_response.content), 1) = '{'
     and left(ltrim(metadata_response.content), 1) = '{' then
    begin
      health_payload := health_response.content::jsonb;
      metadata_payload := metadata_response.content::jsonb;
      if jsonb_typeof(health_payload) <> 'object'
         or jsonb_typeof(metadata_payload) <> 'object' then
        health_payload := null;
        metadata_payload := null;
      end if;
    exception when others then
      health_payload := null;
      metadata_payload := null;
    end;
  end if;

  if health_payload is null
     or metadata_payload is null
     or health_payload ->> 'status' <> 'healthy'
     or mcp_get_response.status <> 401
     or mcp_post_response.status <> 401
     or octet_length(coalesce(mcp_get_response.content, '')) > 65536
     or octet_length(coalesce(mcp_post_response.content, '')) > 65536
     or not exists (
       select 1
       from unnest(mcp_get_response.headers) response_header
       where lower((response_header).field) = 'www-authenticate'
         and (response_header).value ~* '^Bearer(?: |$)'
     )
     or not exists (
       select 1
       from unnest(mcp_post_response.headers) response_header
       where lower((response_header).field) = 'www-authenticate'
         and (response_header).value ~* '^Bearer(?: |$)'
     )
     or metadata_payload ->> 'resource' <> 'https://mcpmaster.vercel.app/mcp'
     or (case
       when jsonb_typeof(metadata_payload -> 'authorization_servers') = 'array'
         then jsonb_array_length(metadata_payload -> 'authorization_servers') = 0
       else true
     end)
     or not (coalesce(metadata_payload -> 'bearer_methods_supported', '[]'::jsonb) ? 'header') then
    raise exception 'canonical route probe contract failed';
  end if;

  route_probe_observed_at := clock_timestamp();
  route_probe_sha256 := encode(extensions.digest(
    'GET /health ' || health_response.status::text || E'\n'
      || 'GET /mcp ' || mcp_get_response.status::text || E'\n'
      || 'POST /mcp ' || mcp_post_response.status::text || E'\n'
      || 'GET /.well-known/oauth-protected-resource/mcp '
      || metadata_response.status::text || E'\n'
      || encode(extensions.digest(health_response.content, 'sha256'), 'hex') || E'\n'
      || encode(extensions.digest(metadata_response.content, 'sha256'), 'hex') || E'\n',
    'sha256'
  ), 'hex');

  select * into alias_post_response
  from extensions.http((
    'GET'::extensions.http_method,
    alias_source_url::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || vercel_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'Pandoras-Box-Canonical-Rehearsal-Capture')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if alias_post_response.status = 200
     and lower(coalesce(alias_post_response.content_type, '')) like 'application/json%'
     and octet_length(coalesce(alias_post_response.content, '')) between 2 and 262144
     and left(ltrim(alias_post_response.content), 1) = '{' then
    begin
      alias_post_payload := alias_post_response.content::jsonb;
      if jsonb_typeof(alias_post_payload) <> 'object' then
        alias_post_payload := null;
      end if;
    exception when others then
      alias_post_payload := null;
    end;
  end if;

  if alias_post_payload is null
     or alias_post_payload ->> 'id' <> target_deployment_id
     or alias_post_payload ->> 'projectId' <> 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
     or alias_post_payload ->> 'readyState' <> 'READY'
     or alias_post_payload ->> 'target' <> 'production'
     or not (coalesce(alias_post_payload -> 'alias', '[]'::jsonb) ? 'mcpmaster.vercel.app')
     or alias_post_payload #>> '{meta,githubCommitSha}' <> target_source_sha
     or lower(coalesce(
       alias_post_payload #>> '{meta,githubCommitOrg}',
       alias_post_payload #>> '{meta,githubOrg}'
     )) <> 'banataosystems'
     or lower(coalesce(
       alias_post_payload #>> '{meta,githubCommitRepo}',
       alias_post_payload #>> '{meta,githubRepo}'
     )) <> 'pandoras-box' then
    raise exception 'live Vercel alias changed during route probes';
  end if;

  alias_post_observed_at := clock_timestamp();
  alias_post_response_sha256 := encode(
    extensions.digest(alias_post_response.content, 'sha256'),
    'hex'
  );

  insert into private.canonical_vercel_rehearsal_receipts (
    organization_id,
    repository,
    project_id,
    team_id,
    phase,
    candidate_deployment_id,
    candidate_source_sha,
    rollback_deployment_id,
    rollback_source_sha,
    transition_from_deployment_id,
    transition_to_deployment_id,
    external_id,
    vercel_api_source_url,
    alias_api_source_url,
    alias_pre_response_sha256,
    alias_pre_observed_at,
    alias_post_response_sha256,
    alias_post_observed_at,
    route_probe_contract,
    route_probe_sha256,
    route_probe_observed_at
  ) values (
    p_organization_id,
    p_repository,
    'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
    'team_IcdJUnzLi5wUN1GD8ALHyjF7',
    p_phase,
    p_candidate_deployment_id,
    p_candidate_source_sha,
    p_rollback_deployment_id,
    p_rollback_source_sha,
    transition_from,
    transition_to,
    target_deployment_id,
    'https://api.vercel.com/v13/deployments/' || target_deployment_id
      || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
    alias_source_url,
    alias_pre_response_sha256,
    alias_pre_observed_at,
    alias_post_response_sha256,
    alias_post_observed_at,
    'canonical_routes_v1',
    route_probe_sha256,
    route_probe_observed_at
  ) returning * into receipt;

  if transition_receipt.id is not null
     and receipt.observed_at <= transition_receipt.observed_at then
    raise exception 'rollback restoration receipt must follow transition';
  end if;

  return jsonb_build_object(
    'receiptId', receipt.id,
    'phase', receipt.phase,
    'externalId', receipt.external_id,
    'vercelApiSourceUrl', receipt.vercel_api_source_url,
    'aliasApiSourceUrl', receipt.alias_api_source_url,
    'aliasPreResponseSha256', receipt.alias_pre_response_sha256,
    'aliasPreObservedAt', receipt.alias_pre_observed_at,
    'aliasPostResponseSha256', receipt.alias_post_response_sha256,
    'aliasPostObservedAt', receipt.alias_post_observed_at,
    'routeProbeContract', receipt.route_probe_contract,
    'routeProbeSha256', receipt.route_probe_sha256,
    'routeProbeObservedAt', receipt.route_probe_observed_at,
    'observedAt', receipt.observed_at
  );
end;
$$;

revoke all on table private.canonical_supabase_release_receipts from public, anon, authenticated, service_role;
revoke all on table private.canonical_vercel_rehearsal_receipts from public, anon, authenticated, service_role;
revoke all on function private.reject_canonical_release_receipt_mutation() from public, anon, authenticated;
revoke all on function public.capture_canonical_supabase_release_receipt(uuid,text,text,text,text,text,text,text,text)
  from public, anon, authenticated;
revoke all on function public.capture_canonical_vercel_rehearsal_receipt(uuid,text,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.capture_canonical_supabase_release_receipt(uuid,text,text,text,text,text,text,text,text)
  to service_role;
grant execute on function public.capture_canonical_vercel_rehearsal_receipt(uuid,text,text,text,text,text,text)
  to service_role;

create or replace function public.get_canonical_release_status(
  p_organization_id uuid,
  p_repository text,
  p_source_sha text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  production public.projectos_evidence%rowtype;
  rollback_transition private.canonical_vercel_rehearsal_receipts%rowtype;
  rollback_restoration private.canonical_vercel_rehearsal_receipts%rowtype;
  migration_manifest private.canonical_supabase_release_receipts%rowtype;
  wifi public.projectos_evidence%rowtype;
  mobile_data public.projectos_evidence%rowtype;
  vercel_token text;
  vercel_team_id text;
  production_response extensions.http_response;
  rollback_response extensions.http_response;
  production_payload jsonb;
  rollback_payload jsonb;
  vercel_receipt jsonb := null;
  supabase_receipt jsonb := jsonb_build_object(
    'databaseReceiptReadback', false,
    'databaseReceiptMatchesSource', false,
    'exactAppliedBytesProven', false,
    'providerReadback', false,
    'verificationState', 'database_source_receipt_missing'
  );
  android_receipt jsonb := null;
begin
  perform private.assert_control_service_role();

  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_source_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'invalid canonical release identity';
  end if;

  select evidence.* into production
  from public.projectos_evidence evidence
  where evidence.organization_id = p_organization_id
    and evidence.repository = p_repository
    and evidence.head_sha = p_source_sha
    and evidence.evidence_type = 'canonical_vercel_production'
    and evidence.provider = 'vercel'
    and evidence.status in ('passing', 'complete')
    and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
    and evidence.invalidated_at is null
    and evidence.payload_redacted ->> 'gitRepository' = p_repository
    and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
    and evidence.payload_redacted ->> 'deploymentId' ~ '^dpl_[A-Za-z0-9]+$'
    and evidence.external_id = evidence.payload_redacted ->> 'deploymentId'
    and evidence.source_url = 'https://api.vercel.com/v13/deployments/'
      || evidence.external_id
      || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
    and evidence.payload_redacted ->> 'productionVerifiedDeploymentId'
        = evidence.payload_redacted ->> 'deploymentId'
    and evidence.payload_redacted -> 'routeProbesPassed' = 'true'::jsonb
    and evidence.observed_at <= statement_timestamp()
  order by evidence.observed_at desc, evidence.id desc
  limit 1;

  if production.id is not null then
    select receipt.* into rollback_transition
    from private.canonical_vercel_rehearsal_receipts receipt
    where receipt.organization_id = p_organization_id
      and receipt.repository = p_repository
      and receipt.project_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
      and receipt.team_id = 'team_IcdJUnzLi5wUN1GD8ALHyjF7'
      and receipt.phase = 'rollback_transition'
      and receipt.candidate_source_sha = p_source_sha
      and receipt.candidate_deployment_id
          = production.payload_redacted ->> 'deploymentId'
      and receipt.rollback_deployment_id <> receipt.candidate_deployment_id
      and receipt.rollback_source_sha <> p_source_sha
      and receipt.external_id = receipt.rollback_deployment_id
      and receipt.vercel_api_source_url = 'https://api.vercel.com/v13/deployments/'
        || receipt.external_id
        || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
      and receipt.alias_api_source_url =
        'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app'
        || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
      and receipt.alias_pre_response_sha256 ~ '^[0-9a-f]{64}$'
      and receipt.alias_post_response_sha256 ~ '^[0-9a-f]{64}$'
      and receipt.alias_pre_observed_at < receipt.route_probe_observed_at
      and receipt.route_probe_observed_at < receipt.alias_post_observed_at
      and receipt.route_probe_contract = 'canonical_routes_v1'
      and receipt.route_probe_sha256 ~ '^[0-9a-f]{64}$'
      and receipt.route_probe_observed_at <= receipt.observed_at
      and receipt.observed_at > production.observed_at
      and receipt.observed_at <= statement_timestamp()
    order by receipt.observed_at desc, receipt.id desc
    limit 1;

    if rollback_transition.id is not null then
      select receipt.* into rollback_restoration
      from private.canonical_vercel_rehearsal_receipts receipt
      where receipt.organization_id = p_organization_id
        and receipt.repository = p_repository
        and receipt.project_id = rollback_transition.project_id
        and receipt.team_id = rollback_transition.team_id
        and receipt.phase = 'rollback_restoration'
        and receipt.candidate_source_sha = p_source_sha
        and receipt.rollback_source_sha = rollback_transition.rollback_source_sha
        and receipt.candidate_deployment_id = rollback_transition.candidate_deployment_id
        and receipt.rollback_deployment_id = rollback_transition.rollback_deployment_id
        and receipt.external_id = receipt.candidate_deployment_id
        and receipt.vercel_api_source_url = 'https://api.vercel.com/v13/deployments/'
          || receipt.external_id
          || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7'
        and receipt.alias_api_source_url = rollback_transition.alias_api_source_url
        and receipt.alias_pre_response_sha256 ~ '^[0-9a-f]{64}$'
        and receipt.alias_post_response_sha256 ~ '^[0-9a-f]{64}$'
        and receipt.alias_pre_observed_at < receipt.route_probe_observed_at
        and receipt.route_probe_observed_at < receipt.alias_post_observed_at
        and receipt.route_probe_contract = 'canonical_routes_v1'
        and receipt.route_probe_sha256 ~ '^[0-9a-f]{64}$'
        and receipt.route_probe_observed_at <= receipt.observed_at
        and receipt.observed_at > rollback_transition.observed_at
        and receipt.observed_at <= statement_timestamp()
      order by receipt.observed_at desc, receipt.id desc
      limit 1;
    end if;
  end if;

  if production.id is not null
     and rollback_transition.id is not null
     and rollback_restoration.id is not null
     and production.observed_at < rollback_transition.observed_at
     and rollback_transition.observed_at < rollback_restoration.observed_at then
    select secret.decrypted_secret,
           installation.configuration ->> 'team_id'
      into vercel_token, vercel_team_id
    from public.connector_installations installation
    join public.credential_refs credential
      on credential.installation_id = installation.id
     and credential.organization_id = installation.organization_id
    join vault.decrypted_secrets secret
      on credential.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$'
     and secret.id = replace(credential.secret_ref, 'vault://', '')::uuid
    where installation.organization_id = p_organization_id
      and installation.provider = 'vercel'
      and installation.status in ('pending'::public.connector_status, 'active'::public.connector_status)
      and installation.configuration -> 'project_repo_allowlist'
          ->> 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk' = p_repository
      and credential.rotation_state = 'current'::public.rotation_status
    order by installation.updated_at desc
    limit 1;

    if vercel_token is not null
       and vercel_team_id = 'team_IcdJUnzLi5wUN1GD8ALHyjF7' then
      perform set_config('http.curlopt_connecttimeout_ms', '2000', true);
      perform set_config('http.curlopt_timeout_ms', '6000', true);

      select * into production_response
      from extensions.http((
        'GET'::extensions.http_method,
        ('https://api.vercel.com/v13/deployments/mcpmaster.vercel.app'
          || '?teamId=' || vercel_team_id)::varchar,
        array[
          ('Accept', 'application/json')::extensions.http_header,
          ('Authorization', 'Bearer ' || vercel_token)::extensions.http_header,
          ('Content-Type', 'application/json')::extensions.http_header,
          ('User-Agent', 'Pandoras-Box-Canonical-Status')::extensions.http_header
        ]::extensions.http_header[],
        'application/json'::varchar,
        null::varchar
      )::extensions.http_request);

      select * into rollback_response
      from extensions.http((
        'GET'::extensions.http_method,
        ('https://api.vercel.com/v13/deployments/'
          || rollback_transition.rollback_deployment_id
          || '?teamId=' || vercel_team_id)::varchar,
        array[
          ('Accept', 'application/json')::extensions.http_header,
          ('Authorization', 'Bearer ' || vercel_token)::extensions.http_header,
          ('Content-Type', 'application/json')::extensions.http_header,
          ('User-Agent', 'Pandoras-Box-Canonical-Status')::extensions.http_header
        ]::extensions.http_header[],
        'application/json'::varchar,
        null::varchar
      )::extensions.http_request);

      if production_response.status = 200
         and rollback_response.status = 200
         and lower(coalesce(production_response.content_type, '')) like 'application/json%'
         and lower(coalesce(rollback_response.content_type, '')) like 'application/json%'
         and octet_length(coalesce(production_response.content, '')) between 2 and 262144
         and octet_length(coalesce(rollback_response.content, '')) between 2 and 262144
         and left(ltrim(production_response.content), 1) = '{'
         and left(ltrim(rollback_response.content), 1) = '{' then
        begin
          production_payload := production_response.content::jsonb;
          rollback_payload := rollback_response.content::jsonb;
          if jsonb_typeof(production_payload) <> 'object'
             or jsonb_typeof(rollback_payload) <> 'object' then
            production_payload := null;
            rollback_payload := null;
          end if;
        exception when others then
          production_payload := null;
          rollback_payload := null;
        end;
      end if;
    end if;

    if production_payload ->> 'id' = production.payload_redacted ->> 'deploymentId'
       and production_payload ->> 'projectId' = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
       and production_payload ->> 'readyState' = 'READY'
       and production_payload ->> 'target' = 'production'
       and coalesce(production_payload -> 'alias', '[]'::jsonb) ? 'mcpmaster.vercel.app'
       and production_payload #>> '{meta,githubCommitSha}' = p_source_sha
       and lower(coalesce(
         production_payload #>> '{meta,githubCommitOrg}',
         production_payload #>> '{meta,githubOrg}'
       )) = 'banataosystems'
       and lower(coalesce(
         production_payload #>> '{meta,githubCommitRepo}',
         production_payload #>> '{meta,githubRepo}'
       )) = 'pandoras-box'
       and rollback_payload ->> 'id' = rollback_transition.rollback_deployment_id
       and rollback_payload ->> 'projectId' = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
       and rollback_payload ->> 'readyState' = 'READY'
       and rollback_payload #>> '{meta,githubCommitSha}'
           = rollback_transition.rollback_source_sha
       and rollback_payload #>> '{meta,githubCommitSha}' <> p_source_sha
       and lower(coalesce(
         rollback_payload #>> '{meta,githubCommitOrg}',
         rollback_payload #>> '{meta,githubOrg}'
       )) = 'banataosystems'
       and lower(coalesce(
         rollback_payload #>> '{meta,githubCommitRepo}',
         rollback_payload #>> '{meta,githubRepo}'
       )) = 'pandoras-box'
       and not (coalesce(rollback_payload -> 'alias', '[]'::jsonb) ? 'mcpmaster.vercel.app') then
      vercel_receipt := jsonb_build_object(
        'providerReadback', true,
        'projectId', 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
        'productionEvidenceId', production.id,
        'productionEvidenceExternalId', production.external_id,
        'productionEvidenceSourceUrl', production.source_url,
        'productionObservedAt', production.observed_at,
        'rollbackTransitionEvidenceId', rollback_transition.id,
        'rollbackTransitionExternalId', rollback_transition.external_id,
        'rollbackTransitionSourceUrl', rollback_transition.vercel_api_source_url,
        'rollbackTransitionAliasSourceUrl', rollback_transition.alias_api_source_url,
        'rollbackTransitionAliasPreResponseSha256', rollback_transition.alias_pre_response_sha256,
        'rollbackTransitionAliasPreObservedAt', rollback_transition.alias_pre_observed_at,
        'rollbackTransitionAliasPostResponseSha256', rollback_transition.alias_post_response_sha256,
        'rollbackTransitionAliasPostObservedAt', rollback_transition.alias_post_observed_at,
        'rollbackTransitionRouteProbeContract', rollback_transition.route_probe_contract,
        'rollbackTransitionRouteProbeSha256', rollback_transition.route_probe_sha256,
        'rollbackTransitionRouteProbeObservedAt', rollback_transition.route_probe_observed_at,
        'rollbackTransitionObservedAt', rollback_transition.observed_at,
        'rollbackRestorationEvidenceId', rollback_restoration.id,
        'rollbackRestorationExternalId', rollback_restoration.external_id,
        'rollbackRestorationSourceUrl', rollback_restoration.vercel_api_source_url,
        'rollbackRestorationAliasSourceUrl', rollback_restoration.alias_api_source_url,
        'rollbackRestorationAliasPreResponseSha256', rollback_restoration.alias_pre_response_sha256,
        'rollbackRestorationAliasPreObservedAt', rollback_restoration.alias_pre_observed_at,
        'rollbackRestorationAliasPostResponseSha256', rollback_restoration.alias_post_response_sha256,
        'rollbackRestorationAliasPostObservedAt', rollback_restoration.alias_post_observed_at,
        'rollbackRestorationRouteProbeContract', rollback_restoration.route_probe_contract,
        'rollbackRestorationRouteProbeSha256', rollback_restoration.route_probe_sha256,
        'rollbackRestorationRouteProbeObservedAt', rollback_restoration.route_probe_observed_at,
        'rollbackRestorationObservedAt', rollback_restoration.observed_at,
        'gitRepository', p_repository,
        'sourceSha', p_source_sha,
        'deploymentId', production.payload_redacted ->> 'deploymentId',
        'productionAlias', 'mcpmaster.vercel.app',
        'productionAliasSourceUrl',
          'https://api.vercel.com/v13/deployments/mcpmaster.vercel.app'
          || '?teamId=team_IcdJUnzLi5wUN1GD8ALHyjF7',
        'productionAliasLiveRead', true,
        'productionTarget', 'production',
        'productionVerified', true,
        'productionVerifiedDeploymentId', production.payload_redacted ->> 'deploymentId',
        'rollbackDeploymentId', rollback_transition.rollback_deployment_id,
        'rollbackSourceSha', rollback_transition.rollback_source_sha,
        'rollbackVerified', true,
        'rollbackVerifiedCandidateDeploymentId', production.payload_redacted ->> 'deploymentId',
        'rollbackRestoredDeploymentId', production.payload_redacted ->> 'deploymentId'
      );
    end if;
  end if;

  select receipt.* into migration_manifest
  from private.canonical_supabase_release_receipts receipt
  where receipt.organization_id = p_organization_id
    and receipt.repository = p_repository
    and receipt.project_ref = 'jcyqixttuebxqqfkjonq'
    and receipt.source_sha = p_source_sha
    and receipt.source_chain_sha256 ~ '^[0-9a-f]{64}$'
    and receipt.source_artifact_sha256 ~ '^[0-9a-f]{64}$'
    and receipt.source_artifact_url =
      'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/'
      || receipt.source_artifact_external_id
    and receipt.captured_version_chain_sha256 = receipt.expected_version_chain_sha256
    and receipt.captured_at <= statement_timestamp()
  order by receipt.captured_at desc, receipt.id desc
  limit 1;

  if migration_manifest.id is not null then
    supabase_receipt := jsonb_build_object(
      'providerDatabaseReceipt', jsonb_build_object(
        'databaseReadback', true,
        'receiptId', migration_manifest.id,
        'capturedAt', migration_manifest.captured_at,
        'capturedAppliedVersions', migration_manifest.captured_applied_versions,
        'capturedVersionChainSha256', migration_manifest.captured_version_chain_sha256
      ),
      'sourceArtifactDatabaseReceipt', jsonb_build_object(
        'databaseCaptured', true,
        'externalId', migration_manifest.source_artifact_external_id,
        'sourceUrl', migration_manifest.source_artifact_url,
        'artifactSha256', migration_manifest.source_artifact_sha256,
        'sourceSha', migration_manifest.source_sha,
        'sourceTreeSha', migration_manifest.source_tree_sha,
        'sourceChainSha256', migration_manifest.source_chain_sha256,
        'expectedVersionChainSha256', migration_manifest.expected_version_chain_sha256
      ),
      'projectRef', migration_manifest.project_ref,
      'exactAppliedBytesProven', false,
      'providerReadback', false,
      'verificationState', 'source_artifact_bound_to_captured_live_versions'
    );
  end if;

  if vercel_receipt is not null
     and rollback_restoration.id is not null then
    select evidence.* into wifi
    from public.projectos_evidence evidence
    where evidence.organization_id = p_organization_id
      and evidence.repository = p_repository
      and evidence.head_sha = p_source_sha
      and evidence.evidence_type = 'canonical_physical_android_wifi'
      and evidence.provider = 'physical_android_observer'
      and evidence.status in ('passing', 'complete')
      and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
      and evidence.invalidated_at is null
      and evidence.payload_redacted ->> 'network' = 'wifi'
      and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
      and evidence.payload_redacted ->> 'sourceTreeSha' ~ '^[0-9a-f]{40}$'
      and evidence.payload_redacted ->> 'productionOrigin' = 'https://mcpmaster.vercel.app'
      and evidence.payload_redacted ->> 'deploymentId'
          = production.payload_redacted ->> 'deploymentId'
      and evidence.payload_redacted ->> 'artifactSha256' ~ '^[0-9a-f]{64}$'
      and jsonb_typeof(evidence.payload_redacted -> 'ciArtifact') = 'object'
      and (evidence.payload_redacted -> 'ciArtifact')
          - array[
            'externalId',
            'sourceUrl',
            'name',
            'digestSha256',
            'apkSha256',
            'sourceSha',
            'sourceTreeSha'
          ]::text[] = '{}'::jsonb
      and evidence.payload_redacted #>> '{ciArtifact,externalId}' ~ '^[1-9][0-9]{0,19}$'
      and evidence.payload_redacted #>> '{ciArtifact,sourceUrl}' =
        'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/'
        || evidence.payload_redacted #>> '{ciArtifact,externalId}'
      and evidence.payload_redacted #>> '{ciArtifact,name}' =
        'pandora-mobile-android-validation-' || p_source_sha
      and evidence.payload_redacted #>> '{ciArtifact,digestSha256}' ~ '^[0-9a-f]{64}$'
      and evidence.payload_redacted #>> '{ciArtifact,apkSha256}' =
        evidence.payload_redacted ->> 'artifactSha256'
      and evidence.payload_redacted #>> '{ciArtifact,sourceSha}' = p_source_sha
      and evidence.payload_redacted #>> '{ciArtifact,sourceTreeSha}' =
        evidence.payload_redacted ->> 'sourceTreeSha'
      and evidence.payload_redacted ->> 'deviceIdHash' ~ '^[0-9a-f]{64}$'
      and evidence.payload_redacted ->> 'packageName' = 'com.banataosystems.pandora_mobile'
      and evidence.payload_redacted -> 'completedSteps' = jsonb_build_array(
        'owner_authenticate',
        'submit_owner_command',
        'observe_durable_dispatch',
        'observe_worker_01_claim',
        'observe_exact_provider_result',
        'observe_proof_in_owner_read'
      )
      and evidence.payload_redacted -> 'verified' = 'true'::jsonb
      and evidence.observed_at > rollback_restoration.alias_post_observed_at
      and evidence.observed_at <= statement_timestamp()
    order by evidence.observed_at desc, evidence.id desc
    limit 1;

    if wifi.id is not null then
      select evidence.* into mobile_data
      from public.projectos_evidence evidence
      where evidence.organization_id = p_organization_id
        and evidence.repository = p_repository
        and evidence.head_sha = p_source_sha
        and evidence.evidence_type = 'canonical_physical_android_mobile_data'
        and evidence.provider = 'physical_android_observer'
        and evidence.status in ('passing', 'complete')
        and lower(coalesce(evidence.verdict, '')) in ('pass', 'passed', 'success', 'verified')
        and evidence.invalidated_at is null
        and evidence.payload_redacted ->> 'network' = 'mobile_data'
        and evidence.payload_redacted ->> 'sourceSha' = p_source_sha
        and evidence.payload_redacted ->> 'productionOrigin' = 'https://mcpmaster.vercel.app'
        and evidence.payload_redacted ->> 'sourceTreeSha'
            = wifi.payload_redacted ->> 'sourceTreeSha'
        and evidence.payload_redacted ->> 'deploymentId'
            = production.payload_redacted ->> 'deploymentId'
        and evidence.payload_redacted ->> 'artifactSha256'
            = wifi.payload_redacted ->> 'artifactSha256'
        and evidence.payload_redacted -> 'ciArtifact'
            = wifi.payload_redacted -> 'ciArtifact'
        and evidence.payload_redacted ->> 'deviceIdHash'
            = wifi.payload_redacted ->> 'deviceIdHash'
        and evidence.payload_redacted ->> 'packageName' = 'com.banataosystems.pandora_mobile'
        and evidence.payload_redacted -> 'completedSteps' = jsonb_build_array(
          'owner_authenticate',
          'submit_owner_command',
          'observe_durable_dispatch',
          'observe_worker_01_claim',
          'observe_exact_provider_result',
          'observe_proof_in_owner_read'
        )
        and evidence.payload_redacted -> 'verified' = 'true'::jsonb
        and evidence.observed_at > rollback_restoration.alias_post_observed_at
        and evidence.observed_at <= statement_timestamp()
      order by evidence.observed_at desc, evidence.id desc
      limit 1;
    end if;
  end if;

  if production.id is not null and wifi.id is not null and mobile_data.id is not null then
    android_receipt := jsonb_build_object(
      'authority', 'PHYSICAL_ANDROID_OBSERVER',
      'providerReadback', true,
      'sourceSha', p_source_sha,
      'sourceTreeSha', wifi.payload_redacted ->> 'sourceTreeSha',
      'deploymentId', production.payload_redacted ->> 'deploymentId',
      'artifactSha256', wifi.payload_redacted ->> 'artifactSha256',
      'productionOrigin', 'https://mcpmaster.vercel.app',
      'ciArtifactDatabaseReceipt', jsonb_build_object(
        'databaseCaptured', true,
        'externalId', wifi.payload_redacted #>> '{ciArtifact,externalId}',
        'sourceUrl', wifi.payload_redacted #>> '{ciArtifact,sourceUrl}',
        'artifactName', wifi.payload_redacted #>> '{ciArtifact,name}',
        'artifactSha256', wifi.payload_redacted #>> '{ciArtifact,digestSha256}',
        'apkSha256', wifi.payload_redacted #>> '{ciArtifact,apkSha256}',
        'sourceSha', wifi.payload_redacted #>> '{ciArtifact,sourceSha}',
        'sourceTreeSha', wifi.payload_redacted #>> '{ciArtifact,sourceTreeSha}',
        'productionOrigin', 'https://mcpmaster.vercel.app',
        'wifiEvidenceId', wifi.id,
        'mobileDataEvidenceId', mobile_data.id,
        'capturedAt', greatest(wifi.observed_at, mobile_data.observed_at)
      ),
      'deviceIdHash', wifi.payload_redacted ->> 'deviceIdHash',
      'packageName', 'com.banataosystems.pandora_mobile',
      'wifi', jsonb_build_object(
        'network', 'wifi',
        'verified', true,
        'receiptId', wifi.id,
        'observedAt', wifi.observed_at,
        'artifactSha256', wifi.payload_redacted ->> 'artifactSha256'
      ),
      'mobileData', jsonb_build_object(
        'network', 'mobile_data',
        'verified', true,
        'receiptId', mobile_data.id,
        'observedAt', mobile_data.observed_at,
        'artifactSha256', mobile_data.payload_redacted ->> 'artifactSha256'
      )
    );
  end if;

  return jsonb_build_object(
    'vercel', vercel_receipt,
    'supabase', supabase_receipt,
    'android', android_receipt
  );
end;
$$;

revoke all on function public.get_canonical_release_status(uuid, text, text) from public, anon, authenticated;
grant execute on function public.get_canonical_release_status(uuid, text, text) to service_role;
