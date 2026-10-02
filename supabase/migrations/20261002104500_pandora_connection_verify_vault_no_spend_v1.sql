create or replace function public.pandora_connection_verify_vault_no_spend_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','vault','extensions','auth','pg_temp'
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_provider text := lower(trim(coalesce(p_provider_key,'')));
  v_state text := 'error';
  v_source text := 'vault_no_spend_provider_readback';
  v_missing text;
  v_evidence jsonb := '{}'::jsonb;
  v_secret text;
  v_project text;
  v_model text;
  v_response extensions.http_response;
  v_response_2 extensions.http_response;
  v_json jsonb;
  v_json_2 jsonb;
  v_model_present boolean := false;
  v_connection private.pandora_meta_connections%rowtype;
  v_google private.pandora_google_workspace_connections%rowtype;
  v_granted text[];
  v_required text[];
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if not exists (
    select 1
    from public.memberships m
    where m.organization_id=p_organization_id
      and m.user_id=p_actor_user_id
      and m.status='active'
      and m.role in ('owner','admin')
  ) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if v_provider not in ('posthog','openai','gemini','kimi','meta','google_workspace') then
    raise exception 'pandora_connection_provider_not_supported' using errcode='22023';
  end if;

  if v_provider = 'google_workspace' then
    select * into v_google
    from private.pandora_google_workspace_connections
    where organization_id=p_organization_id
      and user_id=p_actor_user_id
    limit 1;

    if v_google.organization_id is null then
      v_state := 'not_connected';
      v_source := 'connection_inventory';
      v_missing := 'No organization-scoped Google Workspace OAuth connection is recorded.';
      v_evidence := jsonb_build_object('connectionPresent',false);
    else
      v_required := private.pandora_google_workspace_required_scopes_v1();
      if v_google.status='connected'
         and v_google.last_verified_at >= v_now-interval '15 minutes'
         and v_required <@ coalesce(v_google.scopes,array[]::text[])
         and coalesce(v_google.scopes,array[]::text[]) <@ v_required then
        v_state := 'verified';
        v_source := 'google_workspace_connection_record';
        v_missing := null;
      else
        v_state := 'partial';
        v_source := 'google_workspace_connection_record';
        v_missing := 'Google Workspace authorization exists but requires a fresh provider verification.';
      end if;
      v_evidence := jsonb_build_object(
        'connectionPresent',true,
        'scopesExact',v_required <@ coalesce(v_google.scopes,array[]::text[])
          and coalesce(v_google.scopes,array[]::text[]) <@ v_required,
        'lastVerifiedAt',v_google.last_verified_at,
        'credentialReturned',false
      );
    end if;

  elsif v_provider = 'meta' then
    select * into v_connection
    from private.pandora_meta_connections
    where organization_id=p_organization_id
    limit 1;

    if v_connection.organization_id is null or v_connection.user_token_secret_id is null then
      v_state := 'not_connected';
      v_missing := 'No organization-scoped Meta authorization is recorded.';
      v_evidence := jsonb_build_object('connectionPresent',false);
    else
      select decrypted_secret into v_secret
      from vault.decrypted_secrets
      where id=v_connection.user_token_secret_id
      limit 1;

      if nullif(v_secret,'') is null then
        v_state := 'error';
        v_missing := 'The Meta credential reference exists but the Vault value is unavailable.';
        v_evidence := jsonb_build_object('credentialAvailable',false);
      else
        select * into v_response
        from extensions.http((
          'GET'::extensions.http_method,
          'https://graph.facebook.com/v26.0/me?fields=id'::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
        select * into v_response_2
        from extensions.http((
          'GET'::extensions.http_method,
          'https://graph.facebook.com/v26.0/me/permissions?limit=100'::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
        v_secret := null;
        begin
          v_json := nullif(v_response.content,'')::jsonb;
          v_json_2 := nullif(v_response_2.content,'')::jsonb;
        exception when others then
          v_json := '{}'::jsonb;
          v_json_2 := '{}'::jsonb;
        end;
        select coalesce(array_agg(x->>'permission'),array[]::text[])
        into v_granted
        from jsonb_array_elements(coalesce(v_json_2->'data','[]'::jsonb)) x
        where x->>'status'='granted';
        v_required := private.pandora_meta_required_scopes_v1();

        if v_response.status=200
           and v_response_2.status=200
           and v_json->>'id'=v_connection.provider_user_id
           and v_required <@ v_granted
           and v_connection.token_expires_at is not null
           and v_connection.token_expires_at>v_now then
          v_state := 'verified';
          v_missing := null;
          update private.pandora_meta_connections
          set last_verified_at=v_now,last_http_status=200,last_error=null,updated_at=v_now
          where organization_id=p_organization_id;
          update public.connector_installations
          set last_health_check_at=v_now,updated_at=v_now
          where organization_id=p_organization_id
            and provider='meta'
            and status='active';
        else
          v_state := 'error';
          v_missing := 'Meta provider identity, permissions, or token freshness could not be verified.';
        end if;
        v_evidence := jsonb_build_object(
          'identityHttp',v_response.status,
          'permissionsHttp',v_response_2.status,
          'identityVerified',v_json->>'id'=v_connection.provider_user_id,
          'requiredScopesPresent',v_required <@ v_granted,
          'tokenCurrent',v_connection.token_expires_at is not null and v_connection.token_expires_at>v_now,
          'credentialReturned',false
        );
      end if;
    end if;

  elsif v_provider = 'posthog' then
    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name='pandora_posthog_project_token'
    limit 1;
    select decrypted_secret into v_project
    from vault.decrypted_secrets
    where name='Posthog_projectid'
    limit 1;

    if nullif(v_secret,'') is null or nullif(v_project,'') is null then
      v_state := 'not_connected';
      v_missing := 'A PostHog project-read credential and project ID are required.';
      v_evidence := jsonb_build_object('credentialAvailable',false,'credentialReturned',false);
    else
      select * into v_response
      from extensions.http((
        'GET'::extensions.http_method,
        ('https://us.posthog.com/api/projects/'||v_project||'/')::varchar,
        array[
          extensions.http_header('authorization','Bearer '||v_secret),
          extensions.http_header('accept','application/json')
        ]::extensions.http_header[],
        null::varchar,null::varchar
      )::extensions.http_request);
      if v_response.status <> 200 then
        select * into v_response_2
        from extensions.http((
          'GET'::extensions.http_method,
          ('https://eu.posthog.com/api/projects/'||v_project||'/')::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
      end if;
      v_secret := null;
      if v_response.status=200 or coalesce(v_response_2.status,0)=200 then
        v_state := 'verified';
        v_missing := null;
      else
        v_state := 'error';
        v_missing := 'Stored PostHog credential is not authorized for project-read API access; a personal API key with project read access is required.';
      end if;
      v_evidence := jsonb_build_object(
        'usHttp',v_response.status,
        'euHttp',case when v_response.status=200 then null else v_response_2.status end,
        'projectReadVerified',v_response.status=200 or coalesce(v_response_2.status,0)=200,
        'credentialReturned',false
      );
    end if;

  else
    if v_provider='openai' then
      select decrypted_secret into v_secret from vault.decrypted_secrets where name='openai_key' limit 1;
      select config_value into v_model from public.pandora_runtime_provider_configs
       where provider='openai' and config_key='default_model' and active=true limit 1;
      if nullif(v_secret,'') is not null then
        select * into v_response
        from extensions.http((
          'GET'::extensions.http_method,
          'https://api.openai.com/v1/models'::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
      end if;
    elsif v_provider='gemini' then
      select decrypted_secret into v_secret from vault.decrypted_secrets where name='gemini_api_key' limit 1;
      select config_value into v_model from public.pandora_runtime_provider_configs
       where provider='gemini' and config_key='default_model' and active=true limit 1;
      if nullif(v_secret,'') is not null then
        select * into v_response
        from extensions.http((
          'GET'::extensions.http_method,
          'https://generativelanguage.googleapis.com/v1beta/models'::varchar,
          array[
            extensions.http_header('x-goog-api-key',v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
      end if;
    else
      select decrypted_secret into v_secret from vault.decrypted_secrets where name='moonshot_api_key' limit 1;
      select config_value into v_model from public.pandora_runtime_provider_configs
       where provider='kimi' and config_key='default_model' and active=true limit 1;
      if nullif(v_secret,'') is not null then
        select * into v_response
        from extensions.http((
          'GET'::extensions.http_method,
          'https://api.moonshot.ai/v1/models'::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_secret),
            extensions.http_header('accept','application/json')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);
      end if;
    end if;
    v_secret := null;

    if v_response.status is null then
      v_state := 'not_connected';
      v_missing := 'No provider credential is available in the tenant Vault.';
      v_evidence := jsonb_build_object('credentialAvailable',false,'credentialReturned',false);
    else
      begin
        v_json := nullif(v_response.content,'')::jsonb;
      exception when others then
        v_json := '{}'::jsonb;
      end;
      if v_provider='gemini' then
        select exists(
          select 1 from jsonb_array_elements(coalesce(v_json->'models','[]'::jsonb)) x
          where x->>'name'='models/'||v_model
        ) into v_model_present;
      else
        select exists(
          select 1 from jsonb_array_elements(coalesce(v_json->'data','[]'::jsonb)) x
          where x->>'id'=v_model
        ) into v_model_present;
      end if;

      if v_response.status=200 and v_model_present then
        v_state := 'partial';
        v_missing := 'Configured model is readable, but the broker-required test inference was not run under the no-spend rule.';
      else
        v_state := 'error';
        v_missing := 'Provider credential or configured model could not be verified.';
      end if;
      v_evidence := jsonb_build_object(
        'modelsListHttp',v_response.status,
        'configuredModelPresent',v_model_present,
        'testInference','not_run_no_spend',
        'credentialReturned',false
      );
    end if;
  end if;

  insert into public.pandora_connection_verification_observations_v1(
    organization_id,provider_key,state,observed_at,stale_after,source,missing_reason,evidence_redacted,updated_at
  ) values(
    p_organization_id,v_provider,v_state,v_now,
    case when v_state='not_connected' then null else v_now+interval '15 minutes' end,
    v_source,v_missing,v_evidence,v_now
  )
  on conflict(organization_id,provider_key) do update set
    state=excluded.state,
    observed_at=excluded.observed_at,
    stale_after=excluded.stale_after,
    source=excluded.source,
    missing_reason=excluded.missing_reason,
    evidence_redacted=excluded.evidence_redacted,
    updated_at=excluded.updated_at;

  return jsonb_build_object(
    'ok',true,
    'provider',v_provider,
    'state',v_state,
    'missingReason',v_missing,
    'observedAt',v_now,
    'evidence',v_evidence,
    'credentialReturned',false
  );
end;
$function$;

revoke all on function public.pandora_connection_verify_vault_no_spend_v1(uuid,text,uuid) from public;
grant execute on function public.pandora_connection_verify_vault_no_spend_v1(uuid,text,uuid) to service_role;
