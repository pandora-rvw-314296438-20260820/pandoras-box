create or replace function private.pandora_verify_supabase_project_connection_20260906(
  p_installation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid;
  v_project_ref text;
  v_expected_name text;
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
  v_checked_at timestamptz := timezone('utc'::text, now());
begin
  if current_user not in ('postgres','service_role')
     and coalesce(auth.jwt() ->> 'role','') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  select c.organization_id,
         nullif(c.configuration ->> 'project_ref',''),
         nullif(c.configuration ->> 'project_name',''),
         s.decrypted_secret
    into strict v_org_id, v_project_ref, v_expected_name, v_token
  from public.connector_installations c
  join public.credential_refs cr
    on cr.installation_id = c.id
   and cr.organization_id = c.organization_id
   and cr.rotation_state = 'current'::public.rotation_status
  join vault.decrypted_secrets s
    on cr.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$'
   and s.id = replace(cr.secret_ref,'vault://','')::uuid
  where c.id = p_installation_id
    and c.provider = 'supabase'
    and c.status = 'active'::public.connector_status;

  if v_project_ref !~ '^[a-z]{20}$' then
    raise exception 'invalid Supabase project ref' using errcode='22023';
  end if;
  if nullif(trim(v_token),'') is null then
    raise exception 'Supabase provider credential unavailable' using errcode='55000';
  end if;

  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/' || v_project_ref)::varchar,
    array[
      extensions.http_header('authorization','Bearer ' || v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Supabase-Connection-Check/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := '{}'::jsonb;
  end;

  if v_response.status <> 200 then
    raise exception 'Supabase project verification failed' using errcode='55000';
  end if;
  if coalesce(v_body->>'ref','') <> v_project_ref then
    raise exception 'Supabase project identity mismatch' using errcode='55000';
  end if;
  if v_expected_name is not null and coalesce(v_body->>'name','') <> v_expected_name then
    raise exception 'Supabase project name mismatch' using errcode='55000';
  end if;
  if coalesce(v_body->>'status','') <> 'ACTIVE_HEALTHY' then
    raise exception 'Supabase project is not healthy' using errcode='55000';
  end if;

  update public.connector_installations
     set last_health_check_at = v_checked_at,
         updated_at = v_checked_at
   where id = p_installation_id
     and organization_id = v_org_id;

  return jsonb_build_object(
    'ok', true,
    'provider', 'supabase',
    'projectRef', v_project_ref,
    'projectName', v_body->>'name',
    'status', v_body->>'status',
    'checkedAt', v_checked_at
  );
end;
$$;

revoke all on function private.pandora_verify_supabase_project_connection_20260906(uuid)
  from public, anon, authenticated;
grant execute on function private.pandora_verify_supabase_project_connection_20260906(uuid)
  to service_role;

do $$
declare
  v_secret_id uuid;
  v_rows integer;
begin
  select id into strict v_secret_id
  from vault.secrets
  where name='Supabase_access'
  limit 1;

  update public.connector_installations
     set external_account_id = 'supabase-project:jcyqixttuebxqqfkjonq',
         display_name = 'Supabase Account — Pandoras-box',
         status = 'active'::public.connector_status,
         scopes = array['projects:read','projects:write']::text[],
         configuration = jsonb_build_object(
           'account_id','pandoras-box',
           'auth_mode','pat',
           'secret_name','Supabase_access',
           'credential_state','vault_configured',
           'management_api_origin','https://api.supabase.com/v1',
           'allow_mutations',true,
           'project_ref','jcyqixttuebxqqfkjonq',
           'project_name','pandoras-box',
           'allowed_project_refs',jsonb_build_array('jcyqixttuebxqqfkjonq')
         ),
         last_health_check_at = null,
         updated_at = timezone('utc'::text, now())
   where id = 'd3ea6e4a-a631-4599-86b0-cdf2e396eea1'
     and provider='supabase';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'pandoras-box Supabase connector row missing';
  end if;

  update public.connector_installations
     set external_account_id = 'supabase-project:ivmvufhcsezyhczzondn',
         display_name = 'Supabase Account — pandoras-box-memory',
         status = 'active'::public.connector_status,
         scopes = array['projects:read','projects:write']::text[],
         configuration = jsonb_build_object(
           'account_id','pandoras-box-memory',
           'auth_mode','pat',
           'secret_name','Supabase_access',
           'credential_state','vault_configured',
           'management_api_origin','https://api.supabase.com/v1',
           'allow_mutations',true,
           'project_ref','ivmvufhcsezyhczzondn',
           'project_name','pandoras-box-memory',
           'allowed_project_refs',jsonb_build_array('ivmvufhcsezyhczzondn')
         ),
         last_health_check_at = null,
         updated_at = timezone('utc'::text, now())
   where id = '51489801-4e6e-49d8-aeac-abc1d749a1ab'
     and provider='supabase';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'pandoras-box-memory Supabase connector row missing';
  end if;

  update public.credential_refs
     set secret_ref = 'vault://' || v_secret_id::text,
         rotation_state = 'current'::public.rotation_status,
         updated_at = timezone('utc'::text, now())
   where installation_id in (
     'd3ea6e4a-a631-4599-86b0-cdf2e396eea1',
     '51489801-4e6e-49d8-aeac-abc1d749a1ab'
   );

  get diagnostics v_rows = row_count;
  if v_rows <> 2 then
    raise exception 'expected two Supabase credential refs, updated %', v_rows;
  end if;
end
$$;
