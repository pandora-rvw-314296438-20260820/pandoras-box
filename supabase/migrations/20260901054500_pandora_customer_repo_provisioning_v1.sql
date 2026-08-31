
-- Pandora customer project GitHub repository provisioning v1.
-- New Simple Mode projects receive a private GitHub repository through the
-- Vault-backed Github_supabase credential. The generic integration transport
-- remains fixed to the canonical Pandora repositories.

create or replace function private.pandora_customer_repo_name_20260901(
  p_name text,
  p_project_id uuid
)
returns text
language plpgsql
immutable
set search_path = 'pg_catalog'
as $$
declare
  v_slug text;
begin
  v_slug := regexp_replace(lower(coalesce(p_name,'')), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  if v_slug = '' then
    v_slug := 'project';
  end if;
  v_slug := left(v_slug,72);
  return 'pandora-' || v_slug || '-' || left(replace(p_project_id::text,'-',''),8);
end;
$$;

create or replace function private.pandora_github_create_customer_repo_20260901(
  p_repo_name text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'vault', 'extensions', 'public'
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_lookup extensions.http_response;
  v_body jsonb;
  v_lookup_body jsonb;
  v_description text;
  v_owner constant text := 'pandora-rvw-314296438-20260820';
begin
  if p_repo_name is null
     or length(p_repo_name) > 100
     or p_repo_name !~ '^pandora-[a-z0-9][a-z0-9-]{0,80}-[0-9a-f]{8}$' then
    raise exception 'invalid Pandora repository name' using errcode='22023';
  end if;

  v_description := nullif(trim(coalesce(p_description,'')),'');
  if v_description is not null and length(v_description) > 256 then
    raise exception 'repository description is too long' using errcode='22023';
  end if;

  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='Github_supabase'
  limit 1;
  if nullif(trim(v_token),'') is null then
    raise exception 'GitHub provider credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    'https://api.github.com/user/repos'::varchar,
    array[
      extensions.http_header('authorization','Bearer ' || v_token),
      extensions.http_header('accept','application/vnd.github+json'),
      extensions.http_header('x-github-api-version','2022-11-28'),
      extensions.http_header('user-agent','Pandora-Customer-Repository-Provisioner/1.0'),
      extensions.http_header('content-type','application/json')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_strip_nulls(jsonb_build_object(
      'name',p_repo_name,
      'description',v_description,
      'private',true,
      'auto_init',false,
      'has_issues',true,
      'has_projects',true,
      'has_wiki',false,
      'delete_branch_on_merge',true
    ))::text::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := null;
  end;

  if v_response.status = 201 then
    if coalesce(v_body->'owner'->>'login','') <> v_owner
       or coalesce(v_body->>'name','') <> p_repo_name
       or coalesce((v_body->>'private')::boolean,false) is not true then
      raise exception 'GitHub returned an invalid repository identity' using errcode='55000';
    end if;
    return jsonb_build_object(
      'id',v_body->>'id',
      'name',v_body->>'name',
      'full_name',v_body->>'full_name',
      'html_url',v_body->>'html_url',
      'default_branch',coalesce(v_body->>'default_branch','main'),
      'private',true,
      'existing',false
    );
  end if;

  -- Idempotent recovery for a retry after GitHub accepted the create but the
  -- caller lost the response. Only the deterministic Pandora-owned name is read.
  if v_response.status = 422 then
    select * into v_lookup
    from extensions.http((
      'GET'::extensions.http_method,
      ('https://api.github.com/repos/' || v_owner || '/' || p_repo_name)::varchar,
      array[
        extensions.http_header('authorization','Bearer ' || v_token),
        extensions.http_header('accept','application/vnd.github+json'),
        extensions.http_header('x-github-api-version','2022-11-28'),
        extensions.http_header('user-agent','Pandora-Customer-Repository-Provisioner/1.0')
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
    begin
      v_lookup_body := nullif(v_lookup.content,'')::jsonb;
    exception when others then
      v_lookup_body := null;
    end;
    if v_lookup.status = 200
       and coalesce(v_lookup_body->'owner'->>'login','') = v_owner
       and coalesce(v_lookup_body->>'name','') = p_repo_name
       and coalesce((v_lookup_body->>'private')::boolean,false) is true then
      return jsonb_build_object(
        'id',v_lookup_body->>'id',
        'name',v_lookup_body->>'name',
        'full_name',v_lookup_body->>'full_name',
        'html_url',v_lookup_body->>'html_url',
        'default_branch',coalesce(v_lookup_body->>'default_branch','main'),
        'private',true,
        'existing',true
      );
    end if;
  end if;

  raise exception 'GitHub repository provisioning failed' using errcode='55000';
end;
$$;

create or replace function private.pandora_project_auto_repository_20260901()
returns trigger
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'public'
as $$
declare
  v_repo_name text;
  v_repo jsonb;
  v_full_name text;
  v_journey jsonb;
begin
  if nullif(trim(coalesce(new.repository,'')),'') is not null then
    return new;
  end if;
  if coalesce(new.config #>> '{customerJourney,createdFrom}','') <> 'simple_mode' then
    return new;
  end if;
  if new.id is null then
    raise exception 'project identity is required before repository provisioning' using errcode='55000';
  end if;

  v_repo_name := private.pandora_customer_repo_name_20260901(new.name,new.id);
  v_repo := private.pandora_github_create_customer_repo_20260901(
    v_repo_name,
    left('Pandora project: ' || coalesce(new.name,'Untitled project'),256)
  );
  v_full_name := coalesce(v_repo->>'full_name','');
  if v_full_name <> 'pandora-rvw-314296438-20260820/' || v_repo_name then
    raise exception 'GitHub repository identity mismatch' using errcode='55000';
  end if;

  new.repository := v_full_name;
  v_journey := coalesce(new.config->'customerJourney','{}'::jsonb) || jsonb_build_object(
    'githubRepositoryId',v_repo->>'id',
    'githubRepository',v_full_name,
    'githubRepositoryUrl',v_repo->>'html_url',
    'githubRepositoryPrivate',true,
    'githubDefaultBranch',coalesce(v_repo->>'default_branch','main'),
    'githubProvisionedAt',now(),
    'githubProvisioningState','ready'
  );
  new.config := jsonb_set(coalesce(new.config,'{}'::jsonb),'{customerJourney}',v_journey,true);
  return new;
end;
$$;

drop trigger if exists pandora_project_auto_repository_v1 on public.projectos_projects;
create trigger pandora_project_auto_repository_v1
before insert on public.projectos_projects
for each row
when (
  (new.repository is null or btrim(new.repository) = '')
  and coalesce(new.config #>> '{customerJourney,createdFrom}','') = 'simple_mode'
)
execute function private.pandora_project_auto_repository_20260901();

revoke all on function private.pandora_customer_repo_name_20260901(text,uuid) from public, anon, authenticated;
revoke all on function private.pandora_github_create_customer_repo_20260901(text,text) from public, anon, authenticated;
revoke all on function private.pandora_project_auto_repository_20260901() from public, anon, authenticated;
grant execute on function private.pandora_customer_repo_name_20260901(text,uuid) to service_role;
grant execute on function private.pandora_github_create_customer_repo_20260901(text,text) to service_role;
$fn$
$fn$;
