-- Pandora Chat capability loop v1
-- Runtime/provider truth is read at execution time. Models remain proposal-only;
-- mutating provider requests are admitted into ProjectOS rather than executed here.

create or replace function public.pandora_chat_capability_registry_v1(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_github_credential boolean := false;
  v_supabase_credential boolean := false;
  v_posthog_query_credential boolean := false;
  v_rows jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode = '42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id = p_organization_id
    and m.user_id = v_uid
    and m.status = 'active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode = '42501';
  end if;

  select exists(
    select 1 from vault.decrypted_secrets
    where name = 'Github_supabase'
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_github_credential;

  select exists(
    select 1 from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','Supabase_access')
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_supabase_credential;

  select exists(
    select 1 from vault.decrypted_secrets
    where name in ('posthog_personal_api_key','POSTHOG_PERSONAL_API_KEY')
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_posthog_query_credential;

  with latest as (
    select distinct on (h.provider)
      h.provider,
      h.status,
      h.last_success_at,
      h.stale_after,
      h.updated_at
    from public.projectos_integration_health h
    where h.organization_id = p_organization_id
      and h.provider in ('github','supabase','vercel','posthog')
    order by h.provider, h.updated_at desc nulls last
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'provider', p.provider,
    'connected', p.connected,
    'status', p.status,
    'lastVerifiedAt', p.last_verified_at,
    'temporarilyUnavailable', p.temporarily_unavailable,
    'authorization', p.authorization,
    'capabilities', p.capabilities
  ) order by p.ord), '[]'::jsonb)
  into v_rows
  from (
    select 1 ord, 'github'::text provider,
      v_github_credential connected,
      case
        when not v_github_credential then 'needs_connection'
        when l.stale_after is not null and l.stale_after <= now() then 'stale'
        else coalesce(l.status,'unknown')
      end status,
      l.last_success_at last_verified_at,
      (not v_github_credential or l.status = 'down') temporarily_unavailable,
      'ProjectOS governs writes; reads use provider truth.'::text authorization,
      jsonb_build_array(
        jsonb_build_object('name','repository.read','mode','read','available',v_github_credential),
        jsonb_build_object('name','pull_request.read','mode','read','available',v_github_credential),
        jsonb_build_object('name','repository.write','mode','write','available',v_github_credential,'approval','projectos')
      ) capabilities
    from (select 1) x
    left join latest l on l.provider='github'

    union all

    select 2, 'supabase',
      v_supabase_credential,
      case
        when not v_supabase_credential then 'needs_connection'
        when l.stale_after is not null and l.stale_after <= now() then 'stale'
        else coalesce(l.status,'unknown')
      end,
      l.last_success_at,
      (not v_supabase_credential or l.status = 'down'),
      'ProjectOS governs writes; project reads use the Supabase Management API.',
      jsonb_build_array(
        jsonb_build_object('name','project.read','mode','read','available',v_supabase_credential),
        jsonb_build_object('name','project.write','mode','write','available',v_supabase_credential,'approval','projectos')
      )
    from (select 1) x
    left join latest l on l.provider='supabase'

    union all

    select 3, 'posthog',
      v_posthog_query_credential,
      case
        when not v_posthog_query_credential then 'needs_authorization'
        when l.stale_after is not null and l.stale_after <= now() then 'stale'
        else coalesce(l.status,'unknown')
      end,
      l.last_success_at,
      not v_posthog_query_credential,
      'A governed PostHog query credential is required. Ingest tokens are never treated as query authority.',
      jsonb_build_array(
        jsonb_build_object('name','analytics.query','mode','read','available',v_posthog_query_credential),
        jsonb_build_object('name','analytics.manage','mode','write','available',false,'approval','projectos')
      )
    from (select 1) x
    left join latest l on l.provider='posthog'

    union all
    select 4, 'google_drive', false, 'needs_authorization', null::timestamptz, true,
      'Google Workspace authorization is required.',
      jsonb_build_array(jsonb_build_object('name','files.read','mode','read','available',false),
                        jsonb_build_object('name','files.write','mode','write','available',false,'approval','projectos'))

    union all
    select 5, 'google_sheets', false, 'needs_authorization', null::timestamptz, true,
      'Google Workspace authorization is required.',
      jsonb_build_array(jsonb_build_object('name','sheets.read','mode','read','available',false),
                        jsonb_build_object('name','sheets.write','mode','write','available',false,'approval','projectos'))
  ) p;

  return jsonb_build_object(
    'contractVersion','pandora-chat-capability-registry-v1',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'providers',v_rows
  );
end;
$$;

revoke all on function public.pandora_chat_capability_registry_v1(uuid) from public, anon;
grant execute on function public.pandora_chat_capability_registry_v1(uuid) to authenticated;

create or replace function public.pandora_chat_capability_dispatch_v1(
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
  v_member_role text;
  v_message text := trim(coalesce(p_message,''));
  v_provider text;
  v_mutating boolean := false;
  v_thread_id uuid := p_thread_id;
  v_project public.projectos_projects%rowtype;
  v_repo text;
  v_project_ref text;
  v_token text;
  v_http extensions.http_response;
  v_body jsonb;
  v_reply text;
  v_intent text := 'inspect_project';
  v_registry jsonb;
  v_intake jsonb;
  v_evidence jsonb := '{}'::jsonb;
  v_pr_no integer;
  v_idempotency text;
  v_is_connection_query boolean;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode = '42501';
  end if;

  select m.role into v_member_role
  from public.memberships m
  where m.organization_id = p_organization_id
    and m.user_id = v_uid
    and m.status = 'active'
  limit 1;

  if v_member_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode = '42501';
  end if;

  if v_message = '' or length(v_message) > 8000 then
    raise exception 'pandora_chat_invalid_message' using errcode = '22023';
  end if;

  if p_project_id is not null then
    select * into v_project
    from public.projectos_projects
    where organization_id = p_organization_id
      and id = p_project_id
    limit 1;
    if not found then
      raise exception 'pandora_chat_project_not_found' using errcode = '22023';
    end if;
  end if;

  v_is_connection_query := v_message ~* '\m(connection|connections|connector|connectors|capability|capabilities|connected|available tools)\M';

  if v_message ~* '\m(github|repository|repo|pull request|pull requests)\M' then
    v_provider := 'github';
  elsif v_message ~* '\m(supabase|database|postgres|postgresql)\M' then
    v_provider := 'supabase';
  elsif v_message ~* '\m(posthog|analytics|product analytics)\M' then
    v_provider := 'posthog';
  elsif v_message ~* '(google[[:space:]]+drive|google[[:space:]]+sheets?|spreadsheet)' then
    v_provider := 'google';
  elsif v_is_connection_query then
    v_provider := 'connections';
  else
    return jsonb_build_object('handled',false);
  end if;

  v_registry := public.pandora_chat_capability_registry_v1(p_organization_id);

  if v_provider = 'connections' then
    v_reply := 'I checked Pandora''s runtime capability registry. Connection state is based on current control-plane evidence, not model assumptions.';
    v_evidence := v_registry;
  elsif v_provider = 'posthog' then
    if exists(
      select 1 from vault.decrypted_secrets
      where name in ('posthog_personal_api_key','POSTHOG_PERSONAL_API_KEY')
        and nullif(trim(decrypted_secret),'') is not null
    ) then
      v_reply := 'PostHog is authorized, but Pandora does not yet expose a bounded live-query adapter in this capability lane. I will not invent analytics results.';
    else
      v_reply := 'PostHog live queries need authorization. Pandora has ingest/telemetry material, but no governed PostHog query credential is configured, so I will not pretend I can query it.';
    end if;
    v_evidence := jsonb_build_object('provider','posthog','registry',v_registry,'observedAt',now());
  elsif v_provider = 'google' then
    v_reply := 'Google Drive and Google Sheets need authorization before Pandora can read or change them. No Google Workspace capability is currently connected in the runtime registry.';
    v_evidence := jsonb_build_object('provider','google_workspace','registry',v_registry,'observedAt',now());
  else
    v_mutating := v_message ~* '\m(fix|change|update|deploy|publish|delete|create|write|merge|apply|configure|reconnect|install|remove|pause|restore|repair)\M';

    if v_mutating then
      v_idempotency := encode(
        extensions.digest(
          p_organization_id::text || ':' || coalesce(p_project_id::text,'') || ':' || lower(v_provider) || ':' || v_message,
          'sha256'
        ),
        'hex'
      );

      v_intake := public.projectos_accept_intake(
        p_organization_id,
        v_uid,
        v_message,
        case when p_project_id is not null then v_project.project_key else null end,
        case when p_project_id is not null then v_project.name else null end,
        case when p_project_id is not null then v_project.repository else null end,
        'work',
        'pandora_chat',
        v_idempotency
      );

      v_intent := case
        when v_message ~* '\m(deploy|publish|go live)\M' then 'publish'
        when v_message ~* '\m(build|create)\M' then 'build'
        else 'change_project'
      end;

      v_reply := format(
        'I sent this %s action to ProjectOS for governed execution. Pandora has not marked it complete; provider readback and verification are still required. If approval is needed, it will appear in Needs You.',
        initcap(v_provider)
      );
      v_evidence := jsonb_build_object(
        'provider',v_provider,
        'authority','projectos',
        'intakeId',v_intake #>> '{intake,id}',
        'projectId',v_intake #>> '{project,id}',
        'status',v_intake #>> '{intake,status}',
        'observedAt',now()
      );
    elsif v_provider = 'github' then
      if p_project_id is not null then v_repo := nullif(v_project.repository,''); end if;
      if v_repo is null then
        v_repo := substring(v_message from '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
      end if;
      if v_repo is null and v_message ~* '\mpandora' then
        v_repo := 'pandora-rvw-314296438-20260820/pandoras-box';
      end if;

      if v_repo is null then
        v_reply := 'GitHub is available, but I need the repository name in owner/repo form before I can read provider state.';
        v_evidence := jsonb_build_object('provider','github','registry',v_registry,'observedAt',now());
      else
        if not (
          v_repo in ('pandora-rvw-314296438-20260820/pandoras-box','pandora-rvw-314296438-20260820/pandoras-box-memory')
          or exists (
            select 1 from public.projectos_projects p
            where p.organization_id = p_organization_id
              and p.repository = v_repo
          )
        ) then
          raise exception 'pandora_chat_repository_not_allowlisted' using errcode = '42501';
        end if;

        select decrypted_secret into v_token
        from vault.decrypted_secrets
        where name='Github_supabase'
        limit 1;
        if nullif(trim(v_token),'') is null then
          v_reply := 'GitHub needs connection before Pandora can read provider state.';
          v_evidence := jsonb_build_object('provider','github','connected',false,'observedAt',now());
        else
          begin
            v_pr_no := nullif(substring(v_message from '#([0-9]{1,9})'),'')::integer;
          exception when others then
            v_pr_no := null;
          end;

          perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
          perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');

          select * into v_http from extensions.http((
            'GET'::extensions.http_method,
            ('https://api.github.com/repos/' || v_repo ||
              case when v_pr_no is not null and v_message ~* '\m(pr|pull request)\M'
                then '/pulls/' || v_pr_no::text else '' end)::varchar,
            array[
              extensions.http_header('authorization','Bearer ' || v_token),
              extensions.http_header('accept','application/vnd.github+json'),
              extensions.http_header('x-github-api-version','2022-11-28'),
              extensions.http_header('user-agent','Pandora-Chat-Capability/1.0')
            ]::extensions.http_header[],
            null::varchar,
            null::varchar
          )::extensions.http_request);

          begin
            v_body := nullif(v_http.content,'')::jsonb;
          exception when others then
            v_body := null;
          end;

          if v_http.status < 200 or v_http.status >= 300 or v_body is null then
            v_reply := format('GitHub is connected, but the provider read failed with status %s. Pandora will not substitute a guess.',v_http.status);
            v_evidence := jsonb_build_object('provider','github','repository',v_repo,'httpStatus',v_http.status,'observedAt',now());
          elsif v_pr_no is not null and v_message ~* '\m(pr|pull request)\M' then
            v_reply := format(
              'GitHub provider readback: PR #%s in %s is %s%s. Head %s targets %s. Last updated %s.',
              v_pr_no,
              v_repo,
              coalesce(v_body->>'state','unknown'),
              case when coalesce((v_body->>'merged')::boolean,false) then ' and merged' else '' end,
              coalesce(v_body #>> '{head,sha}','unknown'),
              coalesce(v_body #>> '{base,ref}','unknown'),
              coalesce(v_body->>'updated_at','unknown')
            );
            v_evidence := jsonb_build_object(
              'provider','github',
              'repository',v_repo,
              'pullRequest',v_pr_no,
              'state',v_body->>'state',
              'merged',coalesce((v_body->>'merged')::boolean,false),
              'headSha',v_body #>> '{head,sha}',
              'base',v_body #>> '{base,ref}',
              'updatedAt',v_body->>'updated_at',
              'httpStatus',v_http.status,
              'observedAt',now()
            );
          else
            v_reply := format(
              'GitHub provider readback: %s is available. Default branch %s; pushed %s; open issues %s; visibility %s%s.',
              coalesce(v_body->>'full_name',v_repo),
              coalesce(v_body->>'default_branch','unknown'),
              coalesce(v_body->>'pushed_at','unknown'),
              coalesce(v_body->>'open_issues_count','unknown'),
              coalesce(v_body->>'visibility','unknown'),
              case when coalesce((v_body->>'archived')::boolean,false) then '; archived' else '' end
            );
            v_evidence := jsonb_build_object(
              'provider','github',
              'repository',coalesce(v_body->>'full_name',v_repo),
              'defaultBranch',v_body->>'default_branch',
              'pushedAt',v_body->>'pushed_at',
              'openIssues',v_body->'open_issues_count',
              'visibility',v_body->>'visibility',
              'archived',coalesce((v_body->>'archived')::boolean,false),
              'httpStatus',v_http.status,
              'observedAt',now()
            );
          end if;
        end if;
      end if;
    elsif v_provider = 'supabase' then
      v_project_ref := substring(lower(v_message) from '([a-z]{20})');
      if v_project_ref is null and p_project_id is not null then
        select h.details->>'projectRef' into v_project_ref
        from public.projectos_integration_health h
        where h.organization_id=p_organization_id
          and h.project_id=p_project_id
          and h.provider='supabase'
        order by h.updated_at desc
        limit 1;
      end if;
      if v_project_ref is null and v_message ~* '\mpandora' then
        select h.details->>'projectRef' into v_project_ref
        from public.projectos_integration_health h
        where h.organization_id=p_organization_id
          and h.provider='supabase'
          and h.details->>'projectRef'='jcyqixttuebxqqfkjonq'
        order by h.updated_at desc
        limit 1;
      end if;

      if v_project_ref is null then
        v_reply := 'Supabase is available, but I need the project reference before I can perform a live Management API read.';
        v_evidence := jsonb_build_object('provider','supabase','registry',v_registry,'observedAt',now());
      elsif not exists (
        select 1 from public.projectos_integration_health h
        where h.organization_id=p_organization_id
          and h.provider='supabase'
          and h.details->>'projectRef'=v_project_ref
      ) and v_project_ref <> 'jcyqixttuebxqqfkjonq' then
        raise exception 'pandora_chat_supabase_project_not_allowlisted' using errcode='42501';
      else
        select decrypted_secret into v_token
        from vault.decrypted_secrets
        where name in ('mcpmaster_supabase_account_1_pat','Supabase_access')
          and nullif(trim(decrypted_secret),'') is not null
        order by case when name='mcpmaster_supabase_account_1_pat' then 0 else 1 end
        limit 1;

        if nullif(trim(v_token),'') is null then
          v_reply := 'Supabase needs connection before Pandora can perform a live provider read.';
          v_evidence := jsonb_build_object('provider','supabase','connected',false,'observedAt',now());
        else
          perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
          perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');

          select * into v_http from extensions.http((
            'GET'::extensions.http_method,
            ('https://api.supabase.com/v1/projects/' || v_project_ref)::varchar,
            array[
              extensions.http_header('authorization','Bearer ' || v_token),
              extensions.http_header('accept','application/json'),
              extensions.http_header('user-agent','Pandora-Chat-Capability/1.0')
            ]::extensions.http_header[],
            null::varchar,
            null::varchar
          )::extensions.http_request);

          begin
            v_body := nullif(v_http.content,'')::jsonb;
          exception when others then
            v_body := null;
          end;

          if v_http.status < 200 or v_http.status >= 300 or v_body is null then
            v_reply := format('Supabase is connected, but the live provider read failed with status %s. Pandora will not substitute stale state.',v_http.status);
            v_evidence := jsonb_build_object('provider','supabase','projectRef',v_project_ref,'httpStatus',v_http.status,'observedAt',now());
          else
            v_reply := format(
              'Supabase provider readback: %s (%s) is %s in %s.',
              coalesce(v_body->>'name',v_project_ref),
              v_project_ref,
              coalesce(v_body->>'status','unknown'),
              coalesce(v_body->>'region','unknown region')
            );
            v_evidence := jsonb_build_object(
              'provider','supabase',
              'projectRef',v_project_ref,
              'name',v_body->>'name',
              'status',v_body->>'status',
              'region',v_body->>'region',
              'organizationId',v_body->>'organization_id',
              'httpStatus',v_http.status,
              'observedAt',now()
            );
          end if;
        end if;
      end if;
    end if;
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
    ) values (
      p_organization_id,p_project_id,v_uid,left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),'active',now()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values (
    v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values (
    v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent',v_intent,
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'capabilityResult',v_evidence,
      'authority',case when v_mutating then 'projectos' else 'provider_readback' end
    ),
    'pandora_capability_gateway',
    'deterministic-v1'
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(), updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent',v_intent,
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'handoff',null,
    'capabilityResult',v_evidence
  );
end;
$$;

revoke all on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_capability_registry_v1(uuid)
is 'Owner/admin runtime capability registry for Pandora Chat. Provider availability is derived from current credentials and ProjectOS integration health; no model can invent capabilities.';

comment on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid)
is 'Deterministic Pandora Chat capability gateway: executes bounded provider reads with exact provider readback and routes provider mutations into ProjectOS intake. Models never become execution authority.';
