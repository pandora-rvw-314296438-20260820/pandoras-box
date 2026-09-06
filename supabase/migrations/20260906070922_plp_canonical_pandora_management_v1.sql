-- PLP canonical Pandora management onboarding v1.
-- Reconciles the legacy PLP project to the current canonical repository and
-- provisions a fresh Pandora-owned Vercel runtime through the existing
-- Vault-backed Worker F broker. No credential value is read or persisted here.

begin;

do $$
declare
  v_project_id constant uuid := '73b1afe9-91b5-4bf5-864c-22c071c4471a';
  v_old_repo constant text := 'banataosystems/plp-boracay';
  v_new_repo constant text := 'pandora-rvw-314296438-20260820/plp';
  v_zip_sha constant text := '989b19a932a6cba7d6923361e0c8578032952b26b27712980aaa611538820f11';
  v_tree_sha constant text := 'c6c38e6e310cd6192bbaa09baed00088407b2510d50d7688a87b1a0b9a683163';
  v_legacy_vercel_id constant text := 'prj_3AcjIhpG9806yDjogNObfHApGwlR';
  v_org_id uuid;
  v_project_name text;
  v_current_repo text;
  v_repo_resource_id uuid;
  v_vercel_resource_id uuid;
  v_vercel jsonb;
  v_vercel_project_id text;
  v_vercel_project_name text;
  v_default_domain text;
  v_allowed jsonb;
begin
  select organization_id,name,repository
    into v_org_id,v_project_name,v_current_repo
  from public.projectos_projects
  where id=v_project_id
  for update;

  if v_org_id is null then
    return;
  end if;
  if v_current_repo not in (v_old_repo,v_new_repo) then
    raise exception 'PLP_REPOSITORY_IDENTITY_UNEXPECTED' using errcode='23514';
  end if;

  select coalesce(jsonb_agg(to_jsonb(value) order by value),'[]'::jsonb)
    into v_allowed
  from (
    select distinct value
    from (
      select jsonb_array_elements_text(coalesce(configuration->'allowed_repositories','[]'::jsonb)) as value
      from public.connector_installations
      where id='ae8d520f-5b98-411e-81fc-f756a4439e6a'::uuid
      union all
      select v_new_repo
    ) s
    where lower(value) <> lower(v_old_repo)
  ) dedup;

  update public.connector_installations
     set configuration=jsonb_set(configuration,'{allowed_repositories}',v_allowed,true),
         updated_at=now()
   where id='ae8d520f-5b98-411e-81fc-f756a4439e6a'::uuid
     and provider='github'
     and status='active';
  if not found then
    raise exception 'PLP_GITHUB_CONNECTOR_NOT_ACTIVE' using errcode='55000';
  end if;

  update public.projectos_projects
     set repository=v_new_repo,
         config=coalesce(config,'{}'::jsonb)
           || jsonb_build_object(
                'canonical_main_sha',null,
                'production_release',false,
                'vercel_project_created',false,
                'vercel_git_binding_verified',false,
                'governance_source_provider_snapshot_current',false,
                'source_import_application_payload_imported',true
              )
           || jsonb_build_object(
                'sourceAuthority',jsonb_build_object(
                  'canonicalRepository',v_new_repo,
                  'canonicalBranch','main',
                  'previousRepositories',jsonb_build_array(v_old_repo),
                  'uploadedZipSha256',v_zip_sha,
                  'uploadedTreeSha256',v_tree_sha,
                  'managementController','pandoras-box',
                  'managementMode','pandora_control_plane',
                  'onboardedAt',now()
                )
              ),
         last_reconciled_at=now(),
         updated_at=now()
   where id=v_project_id;

  update public.projectos_project_resources
     set external_id=v_new_repo,
         external_name='PLP',
         canonical_url='https://github.com/'||v_new_repo,
         binding_state='degraded',
         configuration=coalesce(configuration,'{}'::jsonb)
           || jsonb_build_object(
                'account_id','github-primary',
                'default_branch','main',
                'allowlist_verified',false,
                'previous_external_id',v_old_repo,
                'onboarding_state','pending_provider_readback'
              ),
         verified_at=null,
         updated_at=now()
   where project_id=v_project_id
     and provider='github'
     and resource_type='repository'
     and external_id in (v_old_repo,v_new_repo)
  returning id into v_repo_resource_id;

  if v_repo_resource_id is null then
    insert into public.projectos_project_resources(
      organization_id,project_id,provider,resource_type,external_id,external_name,
      environment,canonical_url,binding_state,configuration,verified_at
    ) values (
      v_org_id,v_project_id,'github','repository',v_new_repo,'PLP','canonical',
      'https://github.com/'||v_new_repo,'degraded',
      jsonb_build_object('account_id','github-primary','default_branch','main','allowlist_verified',false,'onboarding_state','pending_provider_readback'),
      null
    ) returning id into v_repo_resource_id;
  end if;

  v_vercel := private.pandora_provision_customer_vercel_project_20260901(v_project_name,v_project_id);
  v_vercel_project_id := coalesce(v_vercel->>'id','');
  v_vercel_project_name := coalesce(v_vercel->>'name','');
  v_default_domain := coalesce(v_vercel->>'default_domain','');
  if v_vercel_project_id !~ '^prj_[A-Za-z0-9]+$' or v_vercel_project_name='' or v_default_domain='' then
    raise exception 'PLP_VERCEL_PROVISIONING_INVALID' using errcode='55000';
  end if;

  update public.connector_installations
     set configuration=jsonb_set(
           configuration #- array['project_repo_allowlist',v_legacy_vercel_id],
           array['project_repo_allowlist',v_vercel_project_id],
           to_jsonb(v_new_repo),true
         ),
         updated_at=now()
   where id='e3770044-9b8e-418d-814a-0934eff91219'::uuid
     and provider='vercel'
     and status='active';
  if not found then
    raise exception 'PLP_VERCEL_CONNECTOR_NOT_ACTIVE' using errcode='55000';
  end if;

  insert into public.projectos_project_resources(
    organization_id,project_id,provider,resource_type,external_id,external_name,
    environment,canonical_url,binding_state,configuration,verified_at
  ) values (
    v_org_id,v_project_id,'vercel','project',v_vercel_project_id,v_vercel_project_name,
    'production','https://'||v_default_domain,'verified',
    jsonb_build_object('account_id','vercel-primary','default_domain',v_default_domain,'repository',v_new_repo,'legacy_project_id',v_legacy_vercel_id),
    now()
  )
  on conflict(project_id,provider,resource_type,external_id) do update
    set external_name=excluded.external_name,
        canonical_url=excluded.canonical_url,
        binding_state='verified',
        configuration=excluded.configuration,
        verified_at=now(),
        updated_at=now()
  returning id into v_vercel_resource_id;

  insert into public.pandora_runtime_environments(
    organization_id,project_id,environment,provider,provider_project_id,status,verification_state,last_reconciled_at
  ) values
    (v_org_id,v_project_id,'preview','vercel',v_vercel_project_id,'ready','not_verified',now()),
    (v_org_id,v_project_id,'production','vercel',v_vercel_project_id,'ready','not_verified',now())
  on conflict(project_id,environment) do update
    set provider='vercel',provider_project_id=excluded.provider_project_id,status='ready',verification_state='not_verified',last_reconciled_at=now(),updated_at=now();

  insert into public.pandora_runtime_resources(
    organization_id,project_id,project_version_id,project_resource_id,resource_type,provider,
    environment,isolation_mode,external_ref,status,configuration_redacted,provisioned_at,verified_at
  ) values
    (v_org_id,v_project_id,null,v_vercel_resource_id,'web_runtime','vercel','preview','dedicated',v_vercel_project_id,'ready',jsonb_build_object('default_domain',v_default_domain,'repository',v_new_repo),now(),now()),
    (v_org_id,v_project_id,null,v_vercel_resource_id,'web_runtime','vercel','production','dedicated',v_vercel_project_id,'ready',jsonb_build_object('default_domain',v_default_domain,'repository',v_new_repo),now(),now())
  on conflict do nothing;

  update public.projectos_projects
     set config=jsonb_set(
           coalesce(config,'{}'::jsonb),
           '{customerJourney}',
           coalesce(config->'customerJourney','{}'::jsonb)
             || jsonb_build_object(
                  'createdFrom','imported_existing',
                  'githubRepository',v_new_repo,
                  'githubDefaultBranch','main',
                  'githubProvisioningState','pending_readback',
                  'vercelProjectId',v_vercel_project_id,
                  'vercelProjectName',v_vercel_project_name,
                  'vercelDefaultDomain',v_default_domain,
                  'vercelDefaultDomainStatus','reserved',
                  'runtimeStatus','ready',
                  'runtimeUpdatedAt',now(),
                  'productionVerificationState','not_verified'
                ),
           true
         )
         || jsonb_build_object('vercel_project_created',true),
         updated_at=now()
   where id=v_project_id;
end
$$;

commit;