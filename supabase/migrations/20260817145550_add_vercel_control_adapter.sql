-- Governed Vercel provider adapter for canonical Git binding repair.
-- Secrets remain in Supabase Vault and are resolved only inside SECURITY DEFINER RPCs.
-- Mutations are fail-closed to an exact project -> repository allowlist and attempt
-- compensating rollback when provider readback does not prove the requested state.

do $$
declare
  v_organization_id uuid;
  v_installed_by uuid;
  v_secret_id uuid;
  v_installation_id uuid;
begin
  select installation.organization_id, installation.installed_by
    into v_organization_id, v_installed_by
  from public.connector_installations installation
  where installation.provider = 'github'
    and installation.configuration ->> 'account_id' = 'github-primary'
  order by installation.updated_at desc
  limit 1;

  if v_organization_id is null or v_installed_by is null then
    raise exception 'canonical MCPMaster organization context unavailable' using errcode = 'P0002';
  end if;

  select secret.id
    into v_secret_id
  from vault.secrets secret
  where secret.name = 'vercel'
  order by secret.updated_at desc
  limit 1;

  if v_secret_id is null then
    raise exception 'Vercel Vault credential reference unavailable' using errcode = 'P0002';
  end if;

  insert into public.connector_installations (
    organization_id,
    provider,
    external_account_id,
    display_name,
    status,
    scopes,
    configuration,
    installed_by
  ) values (
    v_organization_id,
    'vercel',
    'vercel-team:team_IcdJUnzLi5wUN1GD8ALHyjF7',
    'Vercel Account — canonical Banatao Systems projects',
    'pending'::public.connector_status,
    array['projects:read','projects:write','git:read','git:write'],
    jsonb_build_object(
      'auth_mode', 'pat',
      'account_id', 'vercel-primary',
      'api_origin', 'https://api.vercel.com',
      'team_id', 'team_IcdJUnzLi5wUN1GD8ALHyjF7',
      'team_slug', 'mbanatao-dc676069',
      'secret_name', 'vercel',
      'credential_state', 'vault_configured',
      'allow_mutations', true,
      'project_repo_allowlist', jsonb_build_object(
        'prj_brg3BJDcHfSftHH84NhnFtDJAnDO', 'banataosystems/pandoras-box-memory',
        'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk', 'pandora-rvw-314296438-20260820/pandoras-box'
      )
    ),
    v_installed_by
  )
  on conflict (organization_id, provider, external_account_id)
  do update set
    display_name = excluded.display_name,
    status = 'pending'::public.connector_status,
    scopes = excluded.scopes,
    configuration = excluded.configuration,
    installed_by = excluded.installed_by,
    updated_at = timezone('utc'::text, now())
  returning id into v_installation_id;

  insert into public.credential_refs (
    organization_id,
    installation_id,
    secret_ref,
    key_version,
    rotation_state
  ) values (
    v_organization_id,
    v_installation_id,
    'vault://' || v_secret_id::text,
    1,
    'current'::public.rotation_status
  )
  on conflict (installation_id)
  do update set
    secret_ref = excluded.secret_ref,
    key_version = case
      when public.credential_refs.secret_ref = excluded.secret_ref
        then public.credential_refs.key_version
      else public.credential_refs.key_version + 1
    end,
    rotation_state = 'current'::public.rotation_status,
    updated_at = timezone('utc'::text, now());
end
$$;

create or replace function public.get_vercel_project_link(
  p_organization_id uuid,
  p_installation_id uuid,
  p_project_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_team_id text;
  v_allowed_repo text;
  v_response extensions.http_response;
  v_payload jsonb;
begin
  if current_user not in ('postgres', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  select secret.decrypted_secret,
         installation.configuration ->> 'team_id',
         installation.configuration -> 'project_repo_allowlist' ->> p_project_id
    into v_token, v_team_id, v_allowed_repo
  from public.connector_installations installation
  join public.credential_refs credential
    on credential.installation_id = installation.id
   and credential.organization_id = installation.organization_id
  join vault.decrypted_secrets secret
    on credential.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$'
   and secret.id = replace(credential.secret_ref, 'vault://', '')::uuid
  where installation.organization_id = p_organization_id
    and installation.id = p_installation_id
    and installation.provider = 'vercel'
    and installation.status in ('pending'::public.connector_status, 'active'::public.connector_status)
    and credential.rotation_state = 'current'::public.rotation_status;

  if v_token is null or v_team_id is null then
    raise exception 'Vercel credential unavailable' using errcode = 'P0002';
  end if;

  if v_allowed_repo is null then
    raise exception 'Vercel project is not allowlisted' using errcode = '42501';
  end if;

  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.vercel.com/v9/projects/' || p_project_id || '?teamId=' || v_team_id)::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if v_response.status <> 200 then
    return jsonb_build_object(
      'ok', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'status', v_response.status,
      'error', 'project_readback_failed'
    );
  end if;

  v_payload := v_response.content::jsonb;

  return jsonb_build_object(
    'ok', true,
    'provider', 'vercel',
    'projectId', p_project_id,
    'projectName', v_payload ->> 'name',
    'allowedRepository', v_allowed_repo,
    'link', case
      when v_payload -> 'link' is null or v_payload -> 'link' = 'null'::jsonb then null
      else jsonb_build_object(
        'type', v_payload #>> '{link,type}',
        'org', v_payload #>> '{link,org}',
        'repo', v_payload #>> '{link,repo}',
        'productionBranch', v_payload #>> '{link,productionBranch}'
      )
    end
  );
end;
$$;

revoke all on function public.get_vercel_project_link(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.get_vercel_project_link(uuid, uuid, text) to service_role;

create or replace function public.set_vercel_git_binding(
  p_organization_id uuid,
  p_installation_id uuid,
  p_project_id text,
  p_repo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_team_id text;
  v_allowed_repo text;
  v_url varchar;
  v_before extensions.http_response;
  v_disconnect extensions.http_response;
  v_connect extensions.http_response;
  v_after extensions.http_response;
  v_rollback_disconnect extensions.http_response;
  v_rollback_connect extensions.http_response;
  v_rollback_readback extensions.http_response;
  v_before_payload jsonb;
  v_after_payload jsonb;
  v_rollback_payload jsonb;
  v_before_type text;
  v_before_org text;
  v_before_repo text;
  v_after_type text;
  v_after_org text;
  v_after_repo text;
  v_rollback_verified boolean := false;
  v_had_link boolean := false;
begin
  if current_user not in ('postgres', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  select secret.decrypted_secret,
         installation.configuration ->> 'team_id',
         installation.configuration -> 'project_repo_allowlist' ->> p_project_id
    into v_token, v_team_id, v_allowed_repo
  from public.connector_installations installation
  join public.credential_refs credential
    on credential.installation_id = installation.id
   and credential.organization_id = installation.organization_id
  join vault.decrypted_secrets secret
    on credential.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$'
   and secret.id = replace(credential.secret_ref, 'vault://', '')::uuid
  where installation.organization_id = p_organization_id
    and installation.id = p_installation_id
    and installation.provider = 'vercel'
    and installation.status in ('pending'::public.connector_status, 'active'::public.connector_status)
    and installation.configuration ->> 'allow_mutations' = 'true'
    and credential.rotation_state = 'current'::public.rotation_status;

  if v_token is null or v_team_id is null then
    raise exception 'Vercel credential unavailable' using errcode = 'P0002';
  end if;

  if v_allowed_repo is null or v_allowed_repo <> p_repo then
    raise exception 'Vercel project/repository pair is not allowlisted' using errcode = '42501';
  end if;

  if p_repo !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
    raise exception 'invalid repository path' using errcode = '22023';
  end if;

  v_url := ('https://api.vercel.com/v9/projects/' || p_project_id || '/link?teamId=' || v_team_id)::varchar;

  select * into v_before
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.vercel.com/v9/projects/' || p_project_id || '?teamId=' || v_team_id)::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if v_before.status <> 200 then
    return jsonb_build_object(
      'ok', false,
      'changed', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'status', v_before.status,
      'error', 'pre_mutation_readback_failed'
    );
  end if;

  v_before_payload := v_before.content::jsonb;
  v_before_type := v_before_payload #>> '{link,type}';
  v_before_org := v_before_payload #>> '{link,org}';
  v_before_repo := v_before_payload #>> '{link,repo}';
  v_had_link := v_before_type is not null and v_before_type <> '';

  if v_before_type = 'github'
     and v_before_org || '/' || v_before_repo = p_repo then
    update public.connector_installations
       set status = 'active'::public.connector_status,
           last_health_check_at = timezone('utc'::text, now()),
           updated_at = timezone('utc'::text, now())
     where id = p_installation_id and organization_id = p_organization_id;

    return jsonb_build_object(
      'ok', true,
      'changed', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'repository', p_repo,
      'readbackVerified', true,
      'previousLink', jsonb_build_object('type',v_before_type,'org',v_before_org,'repo',v_before_repo)
    );
  end if;

  if v_had_link and v_before_type <> 'github' then
    return jsonb_build_object(
      'ok', false,
      'changed', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'error', 'unsupported_existing_git_provider',
      'existingProvider', v_before_type
    );
  end if;

  if v_had_link then
    select * into v_disconnect
    from extensions.http((
      'DELETE'::extensions.http_method,
      v_url,
      array[
        ('Accept', 'application/json')::extensions.http_header,
        ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
        ('Content-Type', 'application/json')::extensions.http_header,
        ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
      ]::extensions.http_header[],
      'application/json'::varchar,
      null::varchar
    )::extensions.http_request);

    if v_disconnect.status < 200 or v_disconnect.status >= 300 then
      return jsonb_build_object(
        'ok', false,
        'changed', false,
        'provider', 'vercel',
        'projectId', p_project_id,
        'status', v_disconnect.status,
        'error', 'disconnect_failed'
      );
    end if;
  end if;

  select * into v_connect
  from extensions.http((
    'POST'::extensions.http_method,
    v_url,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_object('type','github','repo',p_repo)::text::varchar
  )::extensions.http_request);

  if v_connect.status < 200 or v_connect.status >= 300 then
    if v_had_link and v_before_type = 'github' and v_before_org is not null and v_before_repo is not null then
      select * into v_rollback_connect
      from extensions.http((
        'POST'::extensions.http_method,
        v_url,
        array[
          ('Accept', 'application/json')::extensions.http_header,
          ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
          ('Content-Type', 'application/json')::extensions.http_header,
          ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
        ]::extensions.http_header[],
        'application/json'::varchar,
        jsonb_build_object('type','github','repo',v_before_org || '/' || v_before_repo)::text::varchar
      )::extensions.http_request);
      v_rollback_verified := v_rollback_connect.status between 200 and 299;
    else
      v_rollback_verified := true;
    end if;

    return jsonb_build_object(
      'ok', false,
      'changed', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'status', v_connect.status,
      'error', 'connect_failed',
      'rollbackAttempted', v_had_link,
      'rollbackVerified', v_rollback_verified
    );
  end if;

  select * into v_after
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.vercel.com/v9/projects/' || p_project_id || '?teamId=' || v_team_id)::varchar,
    array[
      ('Accept', 'application/json')::extensions.http_header,
      ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
      ('Content-Type', 'application/json')::extensions.http_header,
      ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
    ]::extensions.http_header[],
    'application/json'::varchar,
    null::varchar
  )::extensions.http_request);

  if v_after.status = 200 then
    v_after_payload := v_after.content::jsonb;
    v_after_type := v_after_payload #>> '{link,type}';
    v_after_org := v_after_payload #>> '{link,org}';
    v_after_repo := v_after_payload #>> '{link,repo}';
  end if;

  if v_after.status <> 200
     or v_after_type <> 'github'
     or coalesce(v_after_org,'') || '/' || coalesce(v_after_repo,'') <> p_repo then
    select * into v_rollback_disconnect
    from extensions.http((
      'DELETE'::extensions.http_method,
      v_url,
      array[
        ('Accept', 'application/json')::extensions.http_header,
        ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
        ('Content-Type', 'application/json')::extensions.http_header,
        ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
      ]::extensions.http_header[],
      'application/json'::varchar,
      null::varchar
    )::extensions.http_request);

    if v_had_link and v_before_type = 'github' and v_before_org is not null and v_before_repo is not null then
      select * into v_rollback_connect
      from extensions.http((
        'POST'::extensions.http_method,
        v_url,
        array[
          ('Accept', 'application/json')::extensions.http_header,
          ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
          ('Content-Type', 'application/json')::extensions.http_header,
          ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
        ]::extensions.http_header[],
        'application/json'::varchar,
        jsonb_build_object('type','github','repo',v_before_org || '/' || v_before_repo)::text::varchar
      )::extensions.http_request);
    end if;

    select * into v_rollback_readback
    from extensions.http((
      'GET'::extensions.http_method,
      ('https://api.vercel.com/v9/projects/' || p_project_id || '?teamId=' || v_team_id)::varchar,
      array[
        ('Accept', 'application/json')::extensions.http_header,
        ('Authorization', 'Bearer ' || v_token)::extensions.http_header,
        ('Content-Type', 'application/json')::extensions.http_header,
        ('User-Agent', 'MCPMaster-Control-Plane')::extensions.http_header
      ]::extensions.http_header[],
      'application/json'::varchar,
      null::varchar
    )::extensions.http_request);

    if v_rollback_readback.status = 200 then
      v_rollback_payload := v_rollback_readback.content::jsonb;
      if v_had_link then
        v_rollback_verified := (v_rollback_payload #>> '{link,type}') = v_before_type
          and (v_rollback_payload #>> '{link,org}') = v_before_org
          and (v_rollback_payload #>> '{link,repo}') = v_before_repo;
      else
        v_rollback_verified := v_rollback_payload -> 'link' is null
          or v_rollback_payload -> 'link' = 'null'::jsonb;
      end if;
    end if;

    return jsonb_build_object(
      'ok', false,
      'changed', false,
      'provider', 'vercel',
      'projectId', p_project_id,
      'error', 'post_mutation_readback_mismatch',
      'rollbackAttempted', true,
      'rollbackVerified', v_rollback_verified
    );
  end if;

  update public.connector_installations
     set status = 'active'::public.connector_status,
         last_health_check_at = timezone('utc'::text, now()),
         updated_at = timezone('utc'::text, now())
   where id = p_installation_id and organization_id = p_organization_id;

  return jsonb_build_object(
    'ok', true,
    'changed', true,
    'provider', 'vercel',
    'projectId', p_project_id,
    'repository', p_repo,
    'readbackVerified', true,
    'previousLink', case
      when v_had_link then jsonb_build_object('type',v_before_type,'org',v_before_org,'repo',v_before_repo)
      else null
    end,
    'currentLink', jsonb_build_object('type',v_after_type,'org',v_after_org,'repo',v_after_repo,'productionBranch',v_after_payload #>> '{link,productionBranch}')
  );
end;
$$;

revoke all on function public.set_vercel_git_binding(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.set_vercel_git_binding(uuid, uuid, text, text) to service_role;
