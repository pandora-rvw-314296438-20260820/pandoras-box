-- P0: enforce explicit Publish separation, exact GitHub ref readback, and verified-only release promotion.
-- Generated from the live production function definitions after provider-verified incident analysis.

CREATE OR REPLACE FUNCTION private.projectos_reconcile_control_plane()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_token text;
  v_response extensions.http_response;
  v_now timestamptz := clock_timestamp();
  v_registry record;
  v_expectation record;
  v_check text;
  v_branches jsonb;
  v_runs jsonb;
  v_branch jsonb;
  v_run jsonb;
  v_observed_sha text;
  v_ref_state text;
  v_repo_url text;
  v_run_url text;
  v_run_path text;
  v_run_conclusion text;
  v_main_protected boolean;
  v_root_status integer := 0;
  v_health_status integer := 0;
  v_api_health_status integer := 0;
  v_health_state text;
  v_results jsonb := '[]'::jsonb;
  v_stamp text := to_char(v_now at time zone 'UTC', 'YYYYMMDDHH24MISSUS');
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'Github_supabase'
  limit 1;

  if nullif(trim(coalesce(v_token, '')), '') is null then
    raise exception 'canonical GitHub provider credential is unavailable' using errcode = '55000';
  end if;

  for v_registry in
    select registry.*,
           project.project_key,
           policy.required_ci_checks,
           policy.provider_observation_max_age
    from private.project_canonical_registry registry
    join public.projectos_projects project on project.id = registry.project_id
    left join private.project_release_policies policy on policy.project_id = registry.project_id
    where registry.canonical_provider = 'github'
      and registry.source_state in ('active','recovered','degraded')
  loop
    begin
      v_repo_url := 'https://github.com/' || v_registry.canonical_repository;

      select * into v_response
      from extensions.http((
        'GET'::extensions.http_method,
        ('https://api.github.com/repos/' || v_registry.canonical_repository || '/branches?per_page=100')::varchar,
        array[
          extensions.http_header('authorization', 'Bearer ' || v_token),
          extensions.http_header('accept', 'application/vnd.github+json'),
          extensions.http_header('x-github-api-version', '2022-11-28'),
          extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.0')
        ]::extensions.http_header[],
        null::varchar,
        null::varchar
      )::extensions.http_request);

      if v_response.status <> 200 then
        raise exception 'GitHub branch readback failed with status %', v_response.status;
      end if;
      v_branches := v_response.content::jsonb;

      for v_expectation in
        select *
        from private.project_source_ref_expectations expectation
        where expectation.project_id = v_registry.project_id
          and expectation.provider = v_registry.canonical_provider
          and expectation.repository = v_registry.canonical_repository
          and expectation.active
      loop
        v_branch := null;
        select * into v_response
        from extensions.http((
          'GET'::extensions.http_method,
          ('https://api.github.com/repos/' || v_registry.canonical_repository || '/git/ref/' ||
            regexp_replace(v_expectation.ref_name, '^refs/', ''))::varchar,
          array[
            extensions.http_header('authorization', 'Bearer ' || v_token),
            extensions.http_header('accept', 'application/vnd.github+json'),
            extensions.http_header('x-github-api-version', '2022-11-28'),
            extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.1')
          ]::extensions.http_header[],
          null::varchar,
          null::varchar
        )::extensions.http_request);

        if v_response.status = 200 then
          v_branch := v_response.content::jsonb;
          v_observed_sha := nullif(lower(coalesce(v_branch->'object'->>'sha', '')), '');
        elsif v_response.status = 404 then
          v_observed_sha := null;
        else
          raise exception 'GitHub exact ref readback failed for % with status %',
            v_expectation.ref_name, v_response.status;
        end if;
        v_ref_state := case
          when v_observed_sha is null then 'missing'
          when v_observed_sha = v_expectation.expected_object_id then 'matched'
          else 'mismatched'
        end;

        perform public.projectos_record_provider_observation(
          v_registry.organization_id,
          v_registry.project_key,
          jsonb_build_object(
            'observationKey', format(
              'auto:%s:source_ref:%s:%s',
              v_registry.project_key,
              regexp_replace(v_expectation.ref_name, '^refs/heads/', ''),
              v_stamp
            ),
            'provider', v_registry.canonical_provider,
            'observationKind', 'source_ref',
            'repository', v_registry.canonical_repository,
            'resourceId', v_expectation.ref_name,
            'refName', v_expectation.ref_name,
            'expectedObjectId', v_expectation.expected_object_id,
            'observedObjectId', v_observed_sha,
            'state', v_ref_state,
            'sourceUrl', v_repo_url || '/tree/' || regexp_replace(v_expectation.ref_name, '^refs/heads/', ''),
            'payloadRedacted', jsonb_build_object(
              'protected', coalesce((v_branch->>'protected')::boolean, false),
              'automatedReadback', true
            ),
            'observedAt', v_now
          )
        );
      end loop;

      select coalesce((item->>'protected')::boolean, false)
      into v_main_protected
      from jsonb_array_elements(v_branches) item
      where item->>'name' = regexp_replace(v_registry.canonical_ref, '^refs/heads/', '')
      limit 1;

      perform public.projectos_record_provider_observation(
        v_registry.organization_id,
        v_registry.project_key,
        jsonb_build_object(
          'observationKey', format('auto:%s:branch_protection:%s', v_registry.project_key, v_stamp),
          'provider', v_registry.canonical_provider,
          'observationKind', 'branch_protection',
          'repository', v_registry.canonical_repository,
          'resourceId', v_registry.canonical_ref,
          'expectedObjectId', v_registry.canonical_sha,
          'observedObjectId', v_registry.canonical_sha,
          'state', case when coalesce(v_main_protected, false) then 'verified' else 'waived' end,
          'sourceUrl', v_repo_url || '/settings/branches',
          'payloadRedacted', jsonb_build_object(
            'protected', coalesce(v_main_protected, false),
            'waiverActive', not coalesce(v_main_protected, false),
            'automatedReadback', true
          ),
          'observedAt', v_now
        )
      );

      select * into v_response
      from extensions.http((
        'GET'::extensions.http_method,
        ('https://api.github.com/repos/' || v_registry.canonical_repository || '/actions/runs?branch=' || regexp_replace(v_registry.canonical_ref, '^refs/heads/', '') || '&per_page=100')::varchar,
        array[
          extensions.http_header('authorization', 'Bearer ' || v_token),
          extensions.http_header('accept', 'application/vnd.github+json'),
          extensions.http_header('x-github-api-version', '2022-11-28'),
          extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.0')
        ]::extensions.http_header[],
        null::varchar,
        null::varchar
      )::extensions.http_request);

      if v_response.status <> 200 then
        raise exception 'GitHub Actions readback failed with status %', v_response.status;
      end if;
      v_runs := v_response.content::jsonb;

      foreach v_check in array coalesce(v_registry.required_ci_checks, '{}'::text[])
      loop
        v_run := null;
        select item into v_run
        from jsonb_array_elements(coalesce(v_runs->'workflow_runs', '[]'::jsonb)) item
        where item->>'head_sha' = v_registry.canonical_sha
          and (
            (v_check = 'pandora-mobile-integration' and item->>'path' = '.github/workflows/pandora-mobile-integration.yml')
            or (v_check = 'projectos-security' and item->>'path' = '.github/workflows/projectos-security.yml')
            or item->>'name' = v_check
          )
        order by (item->>'created_at')::timestamptz desc
        limit 1;

        v_run_url := nullif(v_run->>'html_url', '');
        v_run_path := nullif(v_run->>'path', '');
        v_run_conclusion := nullif(v_run->>'conclusion', '');
        v_observed_sha := nullif(lower(coalesce(v_run->>'head_sha', '')), '');

        perform public.projectos_record_provider_observation(
          v_registry.organization_id,
          v_registry.project_key,
          jsonb_build_object(
            'observationKey', format('auto:%s:ci:%s:%s', v_registry.project_key, v_check, v_stamp),
            'provider', v_registry.canonical_provider,
            'observationKind', 'ci_check',
            'repository', v_registry.canonical_repository,
            'resourceId', v_check,
            'expectedObjectId', v_registry.canonical_sha,
            'observedObjectId', v_observed_sha,
            'state', case
              when v_run is null then 'missing'
              when v_run_conclusion = 'success' then 'passed'
              else 'failed'
            end,
            'sourceUrl', coalesce(v_run_url, v_repo_url || '/actions'),
            'payloadRedacted', jsonb_build_object(
              'runId', v_run->'id',
              'workflowPath', v_run_path,
              'status', v_run->>'status',
              'conclusion', v_run_conclusion,
              'automatedReadback', true
            ),
            'observedAt', v_now
          )
        );
      end loop;

      if nullif(trim(coalesce(v_registry.production_url, '')), '') is not null
         and v_registry.deployed_sha is not null then
        begin
          select * into v_response
          from extensions.http((
            'GET'::extensions.http_method,
            rtrim(v_registry.production_url, '/')::varchar,
            array[extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.0')]::extensions.http_header[],
            null::varchar,
            null::varchar
          )::extensions.http_request);
          v_root_status := v_response.status;
        exception when others then
          v_root_status := 0;
        end;

        begin
          select * into v_response
          from extensions.http((
            'GET'::extensions.http_method,
            (rtrim(v_registry.production_url, '/') || '/health')::varchar,
            array[extensions.http_header('accept', 'application/json'), extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.0')]::extensions.http_header[],
            null::varchar,
            null::varchar
          )::extensions.http_request);
          v_health_status := v_response.status;
        exception when others then
          v_health_status := 0;
        end;

        begin
          select * into v_response
          from extensions.http((
            'GET'::extensions.http_method,
            (rtrim(v_registry.production_url, '/') || '/api/health')::varchar,
            array[extensions.http_header('accept', 'application/json'), extensions.http_header('user-agent', 'Pandora-Canonical-Control-Plane/1.0')]::extensions.http_header[],
            null::varchar,
            null::varchar
          )::extensions.http_request);
          v_api_health_status := v_response.status;
        exception when others then
          v_api_health_status := 0;
        end;

        v_health_state := case
          when v_root_status between 200 and 399
           and v_health_status between 200 and 399
           and v_api_health_status between 200 and 399
          then 'healthy'
          else 'failed'
        end;

        perform public.projectos_record_provider_observation(
          v_registry.organization_id,
          v_registry.project_key,
          jsonb_build_object(
            'observationKey', format('auto:%s:production_health:%s', v_registry.project_key, v_stamp),
            'provider', 'vercel',
            'observationKind', 'production_health',
            'resourceId', regexp_replace(v_registry.production_url, '^https?://', ''),
            'expectedObjectId', v_registry.deployed_sha,
            'observedObjectId', v_registry.deployed_sha,
            'state', v_health_state,
            'sourceUrl', v_registry.production_url,
            'payloadRedacted', jsonb_build_object(
              'root', v_root_status,
              'health', v_health_status,
              'apiHealth', v_api_health_status,
              'automatedReadback', true
            ),
            'observedAt', v_now
          )
        );
      end if;

      update private.project_canonical_registry
      set last_provider_readback_at = v_now,
          config = config || jsonb_build_object(
            'lastAutomatedReconciliationAt', v_now,
            'lastAutomatedReconciliationState', 'completed'
          )
      where project_id = v_registry.project_id;

      perform public.record_audit_event(
        v_registry.organization_id,
        'projectos.control_plane_reconciled',
        'system'::public.audit_actor_type,
        jsonb_build_object(
          'projectKey', v_registry.project_key,
          'canonicalRepository', v_registry.canonical_repository,
          'canonicalSha', v_registry.canonical_sha,
          'productionHealthState', v_health_state,
          'observedAt', v_now
        ),
        null,
        null,
        null
      );

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'projectKey', v_registry.project_key,
        'state', 'completed',
        'observedAt', v_now,
        'productionHealth', v_health_state
      ));
    exception when others then
      update private.project_canonical_registry
      set config = config || jsonb_build_object(
        'lastAutomatedReconciliationAt', v_now,
        'lastAutomatedReconciliationState', 'failed',
        'lastAutomatedReconciliationError', left(sqlerrm, 500)
      )
      where project_id = v_registry.project_id;

      perform public.record_audit_event(
        v_registry.organization_id,
        'projectos.control_plane_reconciliation_failed',
        'system'::public.audit_actor_type,
        jsonb_build_object(
          'projectKey', v_registry.project_key,
          'error', left(sqlerrm, 500),
          'observedAt', v_now
        ),
        null,
        null,
        null
      );

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'projectKey', v_registry.project_key,
        'state', 'failed',
        'error', left(sqlerrm, 500),
        'observedAt', v_now
      ));
    end;
  end loop;

  return jsonb_build_object(
    'reconciledAt', v_now,
    'results', v_results
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.projectos_record_release_receipt_base_v1(p_organization_id uuid, p_project_key text, p_receipt jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_project public.projectos_projects%rowtype;
  v_payload jsonb := coalesce(p_receipt, '{}'::jsonb);
  v_source_sha text;
  v_automation_sha text;
  v_receipt_hash text;
  v_result private.project_release_receipts%rowtype;
  v_inserted boolean := false;
begin
  perform private.projectos_control_plane_assert_service();
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'receipt payload must be an object' using errcode = '22023';
  end if;

  select * into v_project
  from public.projectos_projects
  where organization_id = p_organization_id and project_key = p_project_key;
  if v_project.id is null then
    raise exception 'project not found' using errcode = 'P0002';
  end if;

  v_source_sha := nullif(lower(trim(v_payload->>'sourceSha')), '');
  v_automation_sha := nullif(lower(trim(v_payload->>'automationSha')), '');

  if nullif(trim(v_payload->>'sourceRepository'), '') is null
     or nullif(trim(v_payload->>'sourceRef'), '') is null
     or v_source_sha is null
     or nullif(trim(v_payload->>'provider'), '') is null
     or nullif(trim(v_payload->>'deploymentId'), '') is null
     or nullif(trim(v_payload->>'environment'), '') is null
     or nullif(trim(v_payload->>'status'), '') is null
     or not (v_payload ? 'observedAt') then
    raise exception 'release receipt identity, source, provider, status, and observedAt are required' using errcode = '22023';
  end if;
  if v_source_sha !~ '^[0-9a-f]{40}([0-9a-f]{24})?$'
     or (v_automation_sha is not null and v_automation_sha !~ '^[0-9a-f]{40}([0-9a-f]{24})?$') then
    raise exception 'invalid release source SHA' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(v_payload->'healthReadback', '{}'::jsonb)) <> 'object' then
    raise exception 'healthReadback must be an object' using errcode = '22023';
  end if;

  v_receipt_hash := coalesce(
    nullif(lower(trim(v_payload->>'receiptHash')), ''),
    encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'projectKey', p_project_key,
            'sourceRepository', v_payload->>'sourceRepository',
            'sourceRef', v_payload->>'sourceRef',
            'sourceSha', v_source_sha,
            'automationSha', v_automation_sha,
            'provider', v_payload->>'provider',
            'deploymentId', v_payload->>'deploymentId',
            'deploymentUrl', v_payload->>'deploymentUrl',
            'environment', v_payload->>'environment',
            'artifactManifestDigest', v_payload->>'artifactManifestDigest',
            'databaseFingerprint', v_payload->>'databaseFingerprint',
            'edgeFunctionFingerprint', v_payload->>'edgeFunctionFingerprint',
            'status', v_payload->>'status',
            'healthReadback', coalesce(v_payload->'healthReadback', '{}'::jsonb),
            'previousDeploymentId', v_payload->>'previousDeploymentId',
            'rollbackDeploymentId', v_payload->>'rollbackDeploymentId',
            'observedAt', (v_payload->>'observedAt')::timestamptz
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  );

  if v_receipt_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid receipt hash' using errcode = '22023';
  end if;

  insert into private.project_release_receipts(
    organization_id, project_id, source_repository, source_ref, source_sha,
    automation_sha, provider, deployment_id, deployment_url, environment,
    artifact_manifest_digest, database_fingerprint, edge_function_fingerprint,
    status, health_readback, previous_deployment_id, rollback_deployment_id,
    receipt_hash, observed_at
  ) values (
    p_organization_id,
    v_project.id,
    trim(v_payload->>'sourceRepository'),
    trim(v_payload->>'sourceRef'),
    v_source_sha,
    v_automation_sha,
    trim(v_payload->>'provider'),
    trim(v_payload->>'deploymentId'),
    nullif(trim(v_payload->>'deploymentUrl'), ''),
    trim(v_payload->>'environment'),
    nullif(lower(trim(v_payload->>'artifactManifestDigest')), ''),
    nullif(lower(trim(v_payload->>'databaseFingerprint')), ''),
    nullif(lower(trim(v_payload->>'edgeFunctionFingerprint')), ''),
    trim(v_payload->>'status'),
    coalesce(v_payload->'healthReadback', '{}'::jsonb),
    nullif(trim(v_payload->>'previousDeploymentId'), ''),
    nullif(trim(v_payload->>'rollbackDeploymentId'), ''),
    v_receipt_hash,
    (v_payload->>'observedAt')::timestamptz
  )
  on conflict (project_id, provider, deployment_id) do nothing
  returning * into v_result;

  if v_result.id is null then
    select * into v_result
    from private.project_release_receipts
    where project_id = v_project.id
      and provider = trim(v_payload->>'provider')
      and deployment_id = trim(v_payload->>'deploymentId');
  else
    v_inserted := true;
  end if;

  if v_inserted and v_result.environment = 'production' and v_result.status in ('ready','verified') then
    update private.project_canonical_registry registry
    set deployed_sha = v_result.source_sha,
        last_known_good_sha = case when v_result.status = 'verified' then v_result.source_sha else registry.last_known_good_sha end,
        production_url = coalesce(v_result.deployment_url, registry.production_url),
        release_state = case
          when v_result.status = 'verified'
           and registry.canonical_sha = v_result.source_sha then 'released'
          when v_result.status = 'ready'
           and registry.canonical_sha = v_result.source_sha then 'ready'
          else 'deployed_unmerged'
        end,
        last_provider_readback_at = greatest(coalesce(registry.last_provider_readback_at, '-infinity'::timestamptz), v_result.observed_at)
    where registry.project_id = v_project.id;
  end if;

  if v_inserted then
    perform public.record_audit_event(
      p_organization_id,
      'projectos.release_receipt_recorded',
      'provider'::public.audit_actor_type,
      jsonb_build_object(
        'projectKey', p_project_key,
        'provider', v_result.provider,
        'deploymentId', v_result.deployment_id,
        'environment', v_result.environment,
        'sourceSha', v_result.source_sha,
        'automationSha', v_result.automation_sha,
        'status', v_result.status,
        'receiptHash', v_result.receipt_hash
      ),
      null,
      null,
      null
    );
  end if;

  return to_jsonb(v_result) || jsonb_build_object('idempotentReplay', not v_inserted);
end;
$function$



update private.project_canonical_registry registry
set release_state = 'ready',
    updated_at = clock_timestamp()
where registry.release_state = 'released'
  and registry.canonical_sha = registry.deployed_sha
  and exists (
    select 1
    from private.project_release_receipts receipt
    where receipt.project_id = registry.project_id
      and receipt.environment = 'production'
      and receipt.source_sha = registry.deployed_sha
      and receipt.status = 'ready'
  )
  and not exists (
    select 1
    from private.project_release_receipts receipt
    where receipt.project_id = registry.project_id
      and receipt.environment = 'production'
      and receipt.source_sha = registry.deployed_sha
      and receipt.status = 'verified'
  );
