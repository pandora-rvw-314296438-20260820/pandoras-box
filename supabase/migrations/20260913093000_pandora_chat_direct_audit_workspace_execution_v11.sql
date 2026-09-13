-- Pandora Chat direct repository audit + project workspace execution v11
-- Read-only project audits use verified repository source in the intelligence turn.
-- Routine selected-project changes hand off directly to the existing real project
-- workspace/build runtime. ProjectOS remains internal for other governed mutations.

create or replace function private.pandora_project_github_read_v1(
  p_organization_id uuid,
  p_repository text,
  p_suffix text default ''
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_repo text := trim(coalesce(p_repository,''));
  v_suffix text := coalesce(p_suffix,'');
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  if v_repo !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
    raise exception 'pandora_project_github_repository_invalid' using errcode='22023';
  end if;
  if v_suffix like '%..%' then
    raise exception 'pandora_project_github_path_invalid' using errcode='22023';
  end if;
  if not (
    v_suffix = ''
    or v_suffix ~ '^/git/trees/[0-9A-Za-z._-]{1,200}[?]recursive=1$'
    or v_suffix ~ '^/git/blobs/[0-9a-f]{40}$'
  ) then
    raise exception 'pandora_project_github_path_not_allowed' using errcode='22023';
  end if;

  if not exists (
    select 1
    from public.projectos_projects p
    where p.organization_id=p_organization_id
      and p.repository=v_repo
      and p.status <> 'archived'
  ) then
    raise exception 'pandora_project_github_repository_not_bound' using errcode='42501';
  end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='Github_supabase'
    and nullif(trim(decrypted_secret),'') is not null
  limit 1;
  if nullif(trim(v_token),'') is null then
    raise exception 'pandora_project_github_credential_unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');

  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.github.com/repos/'||v_repo||v_suffix)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/vnd.github+json'),
      extensions.http_header('x-github-api-version','2026-03-10'),
      extensions.http_header('user-agent','Pandora-Project-Read/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := null;
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$$;

revoke all on function private.pandora_project_github_read_v1(uuid,text,text)
  from public,anon,authenticated;
grant execute on function private.pandora_project_github_read_v1(uuid,text,text)
  to service_role;

comment on function private.pandora_project_github_read_v1(uuid,text,text)
is 'Vault-backed GET-only GitHub transport for repositories already bound to an active Pandora project. No credential or unrestricted provider path is exposed.';

create or replace function public.pandora_chat_repository_snapshot_v1(
  p_organization_id uuid,
  p_project_id uuid,
  p_max_bytes integer default 110000,
  p_max_files integer default 80
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_project public.projectos_projects%rowtype;
  v_repo_response jsonb;
  v_repo_body jsonb;
  v_tree_response jsonb;
  v_tree_body jsonb;
  v_blob_response jsonb;
  v_blob_body jsonb;
  v_default_branch text;
  v_head_sha text;
  v_files jsonb := '[]'::jsonb;
  v_inventory jsonb := '[]'::jsonb;
  v_total_files integer := 0;
  v_eligible_files integer := 0;
  v_included_files integer := 0;
  v_bytes integer := 0;
  v_limit_bytes integer := greatest(16000,least(coalesce(p_max_bytes,110000),120000));
  v_limit_files integer := greatest(1,least(coalesce(p_max_files,80),100));
  v_entry record;
  v_encoded text;
  v_text text;
  v_size integer;
  v_truncated boolean := false;
begin
  if v_uid is null then
    raise exception 'pandora_repository_snapshot_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then
    raise exception 'pandora_repository_snapshot_owner_required' using errcode='42501';
  end if;

  select * into v_project
  from public.projectos_projects p
  where p.organization_id=p_organization_id
    and p.id=p_project_id
    and p.status <> 'archived'
  limit 1;
  if v_project.id is null or nullif(trim(v_project.repository),'') is null then
    raise exception 'pandora_repository_snapshot_project_repository_required' using errcode='22023';
  end if;

  v_repo_response := private.pandora_project_github_read_v1(
    p_organization_id,v_project.repository,''
  );
  if coalesce((v_repo_response->>'status')::integer,0) not between 200 and 299
     or v_repo_response->'body' is null then
    return jsonb_build_object(
      'ok',false,'reason','repository_read_failed',
      'repository',v_project.repository,'httpStatus',coalesce((v_repo_response->>'status')::integer,0)
    );
  end if;
  v_repo_body := v_repo_response->'body';
  v_default_branch := nullif(v_repo_body->>'default_branch','');
  if v_default_branch is null or v_default_branch !~ '^[0-9A-Za-z._-]{1,200}$' then
    return jsonb_build_object(
      'ok',false,'reason','default_branch_unsupported','repository',v_project.repository
    );
  end if;

  v_tree_response := private.pandora_project_github_read_v1(
    p_organization_id,
    v_project.repository,
    '/git/trees/'||v_default_branch||'?recursive=1'
  );
  if coalesce((v_tree_response->>'status')::integer,0) not between 200 and 299
     or v_tree_response->'body' is null then
    return jsonb_build_object(
      'ok',false,'reason','repository_tree_failed',
      'repository',v_project.repository,'httpStatus',coalesce((v_tree_response->>'status')::integer,0)
    );
  end if;
  v_tree_body := v_tree_response->'body';
  v_head_sha := nullif(v_tree_body->>'sha','');
  if v_head_sha is null or v_head_sha !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object(
      'ok',false,'reason','repository_head_unverified','repository',v_project.repository
    );
  end if;

  select count(*) into v_total_files
  from jsonb_array_elements(coalesce(v_tree_body->'tree','[]'::jsonb)) e
  where e->>'type'='blob';

  for v_entry in
    select
      e->>'path' as path,
      e->>'sha' as sha,
      coalesce(nullif(e->>'size','')::integer,0) as size
    from jsonb_array_elements(coalesce(v_tree_body->'tree','[]'::jsonb)) e
    where e->>'type'='blob'
      and coalesce(nullif(e->>'size','')::integer,0) between 1 and 120000
      and e->>'sha' ~ '^[0-9a-f]{40}$'
      and e->>'path' !~* '(^|/)(\.env([^/]*|$)|\.npmrc$|\.pypirc$|id_rsa$|id_ed25519$|credentials?([^/]*|$)|secrets?([^/]*|$)|.*\.(pem|key|p12|pfx|jks|keystore))$'
      and (
        e->>'path' ~* '\.(dart|ts|tsx|js|jsx|mjs|cjs|json|html|htm|css|scss|sass|less|sql|md|mdx|yaml|yml|toml|xml|txt|py|go|rs|java|kt|kts|swift|c|cc|cpp|h|hpp|cs|php|rb|sh|bash|zsh|gradle|properties|graphql|gql|prisma|vue|svelte)$'
        or e->>'path' ~* '(^|/)(README|LICENSE|Dockerfile|Makefile|Procfile|Gemfile|Podfile)$'
      )
    order by
      case
        when e->>'path' ~* '(^|/)(README(\.[^/]*)?|package\.json|pubspec\.yaml|pubspec\.yml|deno\.json|vite\.config\.[^/]+|next\.config\.[^/]+|vercel\.json|Dockerfile|Makefile)$' then 0
        when e->>'path' ~* '(^|/)(src|lib|app|apps|api|server|supabase|test|tests)/' then 1
        else 2
      end,
      e->>'path'
  loop
    v_eligible_files := v_eligible_files + 1;
    if v_included_files >= v_limit_files then
      v_truncated := true;
      continue;
    end if;

    v_inventory := v_inventory || jsonb_build_array(
      jsonb_build_object('path',v_entry.path,'sha',v_entry.sha,'size',v_entry.size)
    );

    v_blob_response := private.pandora_project_github_read_v1(
      p_organization_id,
      v_project.repository,
      '/git/blobs/'||v_entry.sha
    );
    if coalesce((v_blob_response->>'status')::integer,0) not between 200 and 299
       or v_blob_response->'body' is null then
      v_truncated := true;
      continue;
    end if;
    v_blob_body := v_blob_response->'body';
    if coalesce(v_blob_body->>'encoding','') <> 'base64' then
      v_truncated := true;
      continue;
    end if;

    v_encoded := replace(replace(coalesce(v_blob_body->>'content',''),E'\n',''),E'\r','');
    begin
      v_text := convert_from(decode(v_encoded,'base64'),'UTF8');
    exception when others then
      v_truncated := true;
      continue;
    end;

    v_size := octet_length(v_text);
    if v_size < 1 then
      continue;
    end if;
    if v_bytes + v_size > v_limit_bytes then
      v_truncated := true;
      continue;
    end if;

    v_files := v_files || jsonb_build_array(
      jsonb_build_object(
        'path',v_entry.path,
        'sha',v_entry.sha,
        'size',v_size,
        'text',v_text
      )
    );
    v_included_files := v_included_files + 1;
    v_bytes := v_bytes + v_size;
  end loop;

  if coalesce((v_tree_body->>'truncated')::boolean,false) then
    v_truncated := true;
  end if;
  if v_included_files < v_eligible_files then
    v_truncated := true;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','pandora-repository-snapshot-v1',
    'projectId',v_project.id,
    'projectKey',v_project.project_key,
    'projectName',v_project.name,
    'repository',v_project.repository,
    'defaultBranch',v_default_branch,
    'headSha',v_head_sha,
    'allFileCount',v_total_files,
    'eligibleTextFileCount',v_eligible_files,
    'includedFileCount',v_included_files,
    'bytesIncluded',v_bytes,
    'truncated',v_truncated,
    'inventory',v_inventory,
    'files',v_files,
    'authority','project_bound_vault_backed_github_read',
    'observedAt',now()
  );
end;
$$;

revoke all on function public.pandora_chat_repository_snapshot_v1(uuid,uuid,integer,integer)
  from public,anon;
grant execute on function public.pandora_chat_repository_snapshot_v1(uuid,uuid,integer,integer)
  to authenticated;

comment on function public.pandora_chat_repository_snapshot_v1(uuid,uuid,integer,integer)
is 'Owner/admin bounded exact-head repository snapshot for a selected Pandora project. Sensitive filenames and binary blobs are excluded; credentials never leave Vault.';

create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_thread_id uuid := p_thread_id;
  v_deep_audit boolean;
  v_mutating boolean;
  v_workspace_change boolean;
  v_reply text;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;
  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;
  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_mutating := v_message ~* '\m(fix|change|update|repair|edit|merge|branch|commit|deploy|publish|build|continue|finish|run|implement|work|proceed|create|write|apply|configure|install|remove|restore|improve|upgrade|add)\M|go ahead|do it';
  v_deep_audit := (
      v_message ~* '\m(audit|analy[sz]e)\M'
      or (
        v_message ~* '\m(inspect|review|scan)\M'
        and v_message ~* '\m(entire|full|whole|repository|repo|project|codebase|source|all)\M'
      )
    )
    and not v_mutating;

  if p_project_id is not null and v_deep_audit then
    return jsonb_build_object(
      'handled',false,
      'routing','repository_audit_direct',
      'projectId',p_project_id,
      'projectRequired',false
    );
  end if;

  v_workspace_change := p_project_id is not null
    and (
      v_message ~* '\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore)\M'
      or v_message ~* '^\s*(build|fix|improve|upgrade|change|update)\s+(it|this|that)\s*[.!?]*\s*$'
    )
    and v_message !~* '\m(audit|analy[sz]e|inspect|review|scan)\M';

  if v_workspace_change then
    if not exists (
      select 1 from public.projectos_projects p
      where p.id=p_project_id
        and p.organization_id=p_organization_id
        and p.status <> 'archived'
    ) then
      raise exception 'pandora_chat_project_not_found' using errcode='22023';
    end if;

    if v_thread_id is not null then
      if not exists (
        select 1 from public.pandora_intelligence_threads t
        where t.id=v_thread_id
          and t.organization_id=p_organization_id
          and t.created_by=v_uid
          and t.status='active'
      ) then
        raise exception 'pandora_chat_thread_not_found' using errcode='22023';
      end if;
    else
      insert into public.pandora_intelligence_threads(
        organization_id,project_id,created_by,title,status,last_message_at
      ) values(
        p_organization_id,p_project_id,v_uid,
        left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
        'active',now()
      ) returning id into v_thread_id;
    end if;

    v_reply := 'Opening the project''s real change and build runtime for this request.';

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,attachment_manifest
    ) values(
      v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
    );

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values(
      v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','project_workspace_change','confidence',1,
        'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,
        'handoff',jsonb_build_object(
          'required',true,'request',v_message,'projectId',p_project_id,
          'source','project_workspace_change'
        )
      ),
      'pandora_project_workspace_router','workspace-change-v1'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now(),project_id=p_project_id
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,'threadId',v_thread_id,'reply',v_reply,
      'intent','project_workspace_change','confidence',1,
      'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,
      'handoff',jsonb_build_object(
        'required',true,'request',v_message,'projectId',p_project_id,
        'source','project_workspace_change'
      )
    );
  end if;

  return public.pandora_chat_universal_dispatch_v8(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  to authenticated;

comment on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
is 'Universal Chat v9: selected-project read-only audits execute in the deep intelligence turn with exact-head repository context; routine selected-project changes hand off once to the real workspace/build runtime; other governed provider actions preserve v8 behavior.';
