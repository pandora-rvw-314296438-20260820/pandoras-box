
create table if not exists public.pandora_plp_site_studio_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  created_by uuid not null,
  request_text text not null,
  model_provider text not null default 'gemini',
  model_name text not null,
  base_sha text not null check (base_sha ~ '^[0-9a-f]{40}$'),
  branch_name text not null,
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  pull_request_number integer not null check (pull_request_number > 0),
  pull_request_url text,
  changed_files jsonb not null default '[]'::jsonb,
  preview_deployment_id text,
  preview_url text,
  preview_state text not null default 'INITIALIZING',
  publish_state text not null default 'candidate',
  merged_sha text check (merged_sha is null or merged_sha ~ '^[0-9a-f]{40}$'),
  production_deployment_id text,
  production_url text,
  provider_evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  constraint pandora_plp_site_studio_preview_state_ck
    check (preview_state in ('INITIALIZING','BUILDING','READY','ERROR','CANCELED','QUEUED','UNKNOWN')),
  constraint pandora_plp_site_studio_publish_state_ck
    check (publish_state in ('candidate','preview_ready','publishing','live','superseded','preview_error','production_error'))
);

create index if not exists pandora_plp_site_studio_candidates_project_created_idx
  on public.pandora_plp_site_studio_candidates(project_id, created_at desc);

alter table public.pandora_plp_site_studio_candidates enable row level security;
revoke all on public.pandora_plp_site_studio_candidates from anon, authenticated;

create or replace function private.pandora_plp_site_studio_assert_owner_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_repository text;
begin
  if v_uid is null then
    raise exception 'plp_site_studio_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id = p_organization_id
    and m.user_id = v_uid
    and m.status = 'active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'plp_site_studio_owner_required' using errcode='42501';
  end if;

  select p.repository into v_repository
  from public.pandora_projects p
  where p.id = p_project_id
    and p.organization_id = p_organization_id
  limit 1;

  if lower(coalesce(v_repository,'')) <> 'pandora-rvw-314296438-20260820/plp' then
    raise exception 'plp_site_studio_project_mismatch' using errcode='22023';
  end if;

  return v_uid;
end;
$function$;

revoke all on function private.pandora_plp_site_studio_assert_owner_v1(uuid,uuid)
  from public, anon, authenticated;

create or replace function private.pandora_plp_site_studio_safe_vercel_url_v1(p_value text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $function$
declare
  v_value text := trim(coalesce(p_value,''));
begin
  if v_value = '' then return null; end if;
  if v_value ~ '^[A-Za-z0-9.-]+[.]vercel[.]app(/.*)?$' then
    v_value := 'https://' || v_value;
  end if;
  if v_value !~ '^https://[A-Za-z0-9.-]+[.]vercel[.]app(/.*)?$' then
    return null;
  end if;
  return v_value;
end;
$function$;

revoke all on function private.pandora_plp_site_studio_safe_vercel_url_v1(text)
  from public, anon, authenticated;

create or replace function public.pandora_plp_site_studio_status_v1(
  p_organization_id uuid,
  p_project_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, extensions, pg_temp
as $function$
declare
  v_uid uuid;
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/plp';
  v_team constant text := 'team_3yw1CN59ce4pj5SwyQGCAqN3';
  v_vercel_project constant text := 'pandora-plp-boracay-73b1afe9';
  v_git jsonb;
  v_project_env jsonb;
  v_main_sha text;
  v_current_url text;
  v_prod_state text := 'UNKNOWN';
  v_prod_sha text;
  v_candidate public.pandora_plp_site_studio_candidates%rowtype;
  v_has_candidate boolean := false;
  v_preview_env jsonb;
  v_pr_env jsonb;
  v_branch_env jsonb;
  v_preview_state text;
  v_preview_url text;
  v_preview_sha text;
  v_branch_sha text;
  v_pr_state text;
  v_pr_head_sha text;
  v_pr_base text;
  v_publishable boolean := false;
  v_production_env jsonb;
  v_production_state text;
  v_production_sha text;
begin
  v_uid := private.pandora_plp_site_studio_assert_owner_v1(p_organization_id,p_project_id);

  v_git := private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/git/ref/heads/main',null
  );
  if coalesce((v_git->>'status')::integer,0) <> 200 then
    raise exception 'plp_site_studio_github_status_failed';
  end if;
  v_main_sha := v_git->'body'->'object'->>'sha';
  if v_main_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'plp_site_studio_github_head_invalid';
  end if;

  v_project_env := private.pandora_worker_f_vercel_api_20260829(
    'GET',
    '/v9/projects/'||v_vercel_project||'?teamId='||v_team,
    null
  );
  if coalesce((v_project_env->>'status')::integer,0) = 200 then
    v_prod_state := upper(coalesce(v_project_env#>>'{body,targets,production,readyState}','UNKNOWN'));
    v_prod_sha := v_project_env#>>'{body,targets,production,meta,githubCommitSha}';
    if v_prod_state = 'READY' and v_prod_sha = v_main_sha then
      v_current_url := private.pandora_plp_site_studio_safe_vercel_url_v1(
        coalesce(
          (v_project_env#>'{body,targets,production,alias}')->>0,
          v_project_env#>>'{body,targets,production,url}'
        )
      );
    end if;
  end if;

  select * into v_candidate
  from public.pandora_plp_site_studio_candidates
  where organization_id = p_organization_id
    and project_id = p_project_id
    and publish_state <> 'superseded'
  order by created_at desc
  limit 1;
  v_has_candidate := found;

  if v_has_candidate then
    if nullif(v_candidate.preview_deployment_id,'') is not null then
      v_preview_env := private.pandora_worker_f_vercel_api_20260829(
        'GET',
        '/v13/deployments/'||v_candidate.preview_deployment_id||'?teamId='||v_team,
        null
      );
      if coalesce((v_preview_env->>'status')::integer,0) = 200 then
        v_preview_state := upper(coalesce(v_preview_env#>>'{body,readyState}','UNKNOWN'));
        if v_preview_state not in ('INITIALIZING','BUILDING','READY','ERROR','CANCELED','QUEUED') then
          v_preview_state := 'UNKNOWN';
        end if;
        v_preview_url := private.pandora_plp_site_studio_safe_vercel_url_v1(
          v_preview_env#>>'{body,url}'
        );
        v_preview_sha := v_preview_env#>>'{body,meta,githubCommitSha}';

        update public.pandora_plp_site_studio_candidates
        set preview_state = v_preview_state,
            preview_url = coalesce(v_preview_url,preview_url),
            publish_state = case
              when v_preview_state = 'READY'
                and v_preview_sha = commit_sha
                and publish_state = 'candidate'
                then 'preview_ready'
              when v_preview_state in ('ERROR','CANCELED')
                and publish_state in ('candidate','preview_ready')
                then 'preview_error'
              else publish_state
            end,
            provider_evidence = provider_evidence || jsonb_build_object(
              'previewReadback',jsonb_build_object(
                'deploymentId',preview_deployment_id,
                'readyState',v_preview_state,
                'sourceSha',v_preview_sha,
                'verifiedAt',now()
              )
            ),
            updated_at = now()
        where id = v_candidate.id
        returning * into v_candidate;
      end if;
    end if;

    v_branch_env := private.pandora_integration_github_api_20260825(
      'GET',v_prefix||'/git/ref/heads/'||v_candidate.branch_name,null
    );
    if coalesce((v_branch_env->>'status')::integer,0) = 200 then
      v_branch_sha := v_branch_env->'body'->'object'->>'sha';
    end if;

    v_pr_env := private.pandora_integration_github_api_20260825(
      'GET',v_prefix||'/pulls/'||v_candidate.pull_request_number::text,null
    );
    if coalesce((v_pr_env->>'status')::integer,0) = 200 then
      v_pr_state := lower(coalesce(v_pr_env->'body'->>'state',''));
      v_pr_head_sha := v_pr_env#>>'{body,head,sha}';
      v_pr_base := v_pr_env#>>'{body,base,ref}';
    end if;

    if v_candidate.publish_state = 'publishing'
       and nullif(v_candidate.production_deployment_id,'') is not null then
      v_production_env := private.pandora_worker_f_vercel_api_20260829(
        'GET',
        '/v13/deployments/'||v_candidate.production_deployment_id||'?teamId='||v_team,
        null
      );
      if coalesce((v_production_env->>'status')::integer,0) = 200 then
        v_production_state := upper(coalesce(v_production_env#>>'{body,readyState}','UNKNOWN'));
        v_production_sha := v_production_env#>>'{body,meta,githubCommitSha}';

        if v_production_state = 'READY'
           and v_candidate.merged_sha is not null
           and v_production_sha = v_candidate.merged_sha
           and v_main_sha = v_candidate.merged_sha then
          update public.pandora_plp_site_studio_candidates
          set publish_state='live',
              production_url=coalesce(
                private.pandora_plp_site_studio_safe_vercel_url_v1(
                  v_production_env#>>'{body,url}'
                ),
                production_url
              ),
              published_at=coalesce(published_at,now()),
              provider_evidence=provider_evidence || jsonb_build_object(
                'productionReadback',jsonb_build_object(
                  'deploymentId',production_deployment_id,
                  'readyState',v_production_state,
                  'sourceSha',v_production_sha,
                  'verifiedAt',now()
                )
              ),
              updated_at=now()
          where id=v_candidate.id
          returning * into v_candidate;
        elsif v_production_state in ('ERROR','CANCELED') then
          update public.pandora_plp_site_studio_candidates
          set publish_state='production_error',updated_at=now()
          where id=v_candidate.id
          returning * into v_candidate;
        end if;
      end if;
    end if;

    v_publishable :=
      v_candidate.publish_state = 'preview_ready'
      and v_candidate.preview_state = 'READY'
      and v_preview_sha = v_candidate.commit_sha
      and v_branch_sha = v_candidate.commit_sha
      and v_pr_state = 'open'
      and v_pr_head_sha = v_candidate.commit_sha
      and v_pr_base = 'main'
      and v_main_sha = v_candidate.base_sha;
  end if;

  return jsonb_build_object(
    'kind','pandora.plp-site-studio.v1',
    'projectId',p_project_id,
    'repository','pandora-rvw-314296438-20260820/plp',
    'current',jsonb_build_object(
      'mainSha',v_main_sha,
      'url',v_current_url,
      'productionState',v_prod_state,
      'productionSha',v_prod_sha,
      'exact',v_prod_state='READY' and v_prod_sha=v_main_sha and v_current_url is not null
    ),
    'candidate',case when v_has_candidate then jsonb_build_object(
      'id',v_candidate.id,
      'request',v_candidate.request_text,
      'modelProvider',v_candidate.model_provider,
      'modelName',v_candidate.model_name,
      'baseSha',v_candidate.base_sha,
      'branch',v_candidate.branch_name,
      'commitSha',v_candidate.commit_sha,
      'pullRequestNumber',v_candidate.pull_request_number,
      'pullRequestUrl',v_candidate.pull_request_url,
      'changedFiles',v_candidate.changed_files,
      'previewDeploymentId',v_candidate.preview_deployment_id,
      'previewUrl',v_candidate.preview_url,
      'previewState',v_candidate.preview_state,
      'publishState',v_candidate.publish_state,
      'mergedSha',v_candidate.merged_sha,
      'productionDeploymentId',v_candidate.production_deployment_id,
      'productionUrl',v_candidate.production_url,
      'publishable',v_publishable,
      'createdAt',v_candidate.created_at,
      'updatedAt',v_candidate.updated_at,
      'publishedAt',v_candidate.published_at
    ) else null end,
    'observedAt',now()
  );
end;
$function$;

revoke all on function public.pandora_plp_site_studio_status_v1(uuid,uuid)
  from public, anon;
grant execute on function public.pandora_plp_site_studio_status_v1(uuid,uuid)
  to authenticated;

