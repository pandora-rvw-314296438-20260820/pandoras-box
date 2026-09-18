-- Pandora native capability registry + provider readback v1
-- Active Chat uses Pandora-native capability/provider surfaces. Historical ProjectOS storage remains compatibility-only.

create or replace view public.pandora_provider_health with (security_invoker = true) as
select organization_id, project_id, provider, status, last_event_at, last_success_at, stale_after, details, updated_at
from public.projectos_integration_health;

revoke all on public.pandora_provider_health from public, anon;
grant select on public.pandora_provider_health to authenticated, service_role;
comment on view public.pandora_provider_health is 'Pandora-native provider health compatibility surface over historical integration-health storage. Active runtime must use this view rather than ProjectOS naming.';

CREATE OR REPLACE FUNCTION public.pandora_chat_capability_registry_v3(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_github boolean := false;
  v_supabase boolean := false;
  v_vercel boolean := false;
  v_posthog_query boolean := false;
  v_google jsonb := '{}'::jsonb;
  v_rows jsonb := '[]'::jsonb;
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

  select exists(
    select 1 from vault.decrypted_secrets
    where name='Github_supabase' and nullif(trim(decrypted_secret),'') is not null
  ) into v_github;

  select exists(
    select 1 from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','Supabase_access')
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_supabase;

  select exists(
    select 1 from vault.decrypted_secrets
    where name='vercel' and nullif(trim(decrypted_secret),'') is not null
  ) into v_vercel;

  select exists(
    select 1 from vault.decrypted_secrets
    where name in ('posthog_personal_api_key','POSTHOG_PERSONAL_API_KEY')
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_posthog_query;

  begin
    v_google := public.pandora_google_workspace_connection_v1(p_organization_id);
  exception when others then
    v_google := jsonb_build_object(
      'connected',false,'state','Problem','canUseNow',false
    );
  end;

  v_rows := jsonb_build_array(
    jsonb_build_object(
      'provider','github','label','GitHub',
      'connected',v_github,
      'state',case when v_github then 'Connected' else 'Needs authorization' end,
      'canUseNow',v_github,
      'authorization','Owner/admin reads and bounded provider actions execute through Pandora.',
      'capabilities',jsonb_build_array(
        jsonb_build_object('name','repository.read','mode','read','available',v_github),
        jsonb_build_object('name','pull_request.read','mode','read','available',v_github),
        jsonb_build_object('name','repository.change','mode','write','available',v_github,'execution','bounded_branch_and_pr')
      )
    ),
    jsonb_build_object(
      'provider','supabase','label','Supabase',
      'connected',v_supabase,
      'state',case when v_supabase then 'Connected' else 'Needs authorization' end,
      'canUseNow',v_supabase,
      'authorization','Owner/admin provider reads execute through Pandora. Consequential mutations require a bounded Pandora adapter.',
      'capabilities',jsonb_build_array(
        jsonb_build_object('name','project.read','mode','read','available',v_supabase),
        jsonb_build_object('name','database.write','mode','write','available',false,'reason','bounded_adapter_required')
      )
    ),
    jsonb_build_object(
      'provider','vercel','label','Vercel',
      'connected',v_vercel,
      'state',case when v_vercel then 'Connected' else 'Needs authorization' end,
      'canUseNow',v_vercel,
      'authorization','Owner/admin deployment reads execute through Pandora. Production mutation remains separately gated.',
      'capabilities',jsonb_build_array(
        jsonb_build_object('name','deployment.read','mode','read','available',v_vercel),
        jsonb_build_object('name','deployment.publish','mode','write','available',false,'reason','production_gate')
      )
    ),
    jsonb_build_object(
      'provider','posthog','label','PostHog',
      'connected',v_posthog_query,
      'state',case when v_posthog_query then 'Connected' else 'Needs authorization' end,
      'canUseNow',v_posthog_query,
      'authorization','A PostHog personal/query credential is required for live analytics queries.',
      'capabilities',jsonb_build_array(
        jsonb_build_object('name','analytics.query','mode','read','available',v_posthog_query)
      )
    ),
    jsonb_build_object(
      'provider','google_workspace','label','Google Workspace',
      'connected',coalesce((v_google->>'connected')::boolean,false),
      'state',coalesce(v_google->>'state','Needs authorization'),
      'canUseNow',coalesce((v_google->>'canUseNow')::boolean,false),
      'authorization','Google OAuth authorization is required before Drive or Sheets actions.',
      'capabilities',jsonb_build_array(
        jsonb_build_object('name','drive.read','mode','read','available',coalesce((v_google->>'canUseNow')::boolean,false)),
        jsonb_build_object('name','drive.write','mode','write','available',coalesce((v_google->>'canUseNow')::boolean,false)),
        jsonb_build_object('name','sheets.read','mode','read','available',coalesce((v_google->>'canUseNow')::boolean,false)),
        jsonb_build_object('name','sheets.write','mode','write','available',coalesce((v_google->>'canUseNow')::boolean,false))
      )
    )
  );

  return jsonb_build_object(
    'contractVersion','pandora-native-capability-registry-v3',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'projectRequired',false,
    'providers',v_rows
  );
end;
$function$;


revoke all on function public.pandora_chat_capability_registry_v3(uuid) from public,anon;
grant execute on function public.pandora_chat_capability_registry_v3(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.pandora_chat_capability_dispatch_native_v1(p_organization_id uuid, p_message text, p_thread_id uuid DEFAULT NULL::uuid, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'vault', 'auth', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_thread_id uuid := p_thread_id;
  v_provider text;
  v_repo text;
  v_pr_no integer;
  v_project_ref text;
  v_project_id text;
  v_team_id text;
  v_token text;
  v_env jsonb;
  v_http extensions.http_response;
  v_body jsonb;
  v_registry jsonb;
  v_google jsonb;
  v_reply text;
  v_result jsonb := '{}'::jsonb;
  v_intent text := 'inspect_provider';
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

  if v_norm ~ '\m(connection|connections|connector|connectors|capability|capabilities|connected|available tools|what can you do)\M' then
    v_provider := 'connections';
  elsif v_norm ~ '\m(github|repository|repo|pull request|pull requests|pr)\M' then
    v_provider := 'github';
  elsif v_norm ~ '\m(supabase|database|postgres|postgresql)\M' then
    v_provider := 'supabase';
  elsif v_norm ~ '\m(vercel|deployment|deployments)\M' then
    v_provider := 'vercel';
  elsif v_norm ~ '\m(posthog|analytics|product analytics)\M' then
    v_provider := 'posthog';
  elsif v_norm ~ '(google[[:space:]]+drive|google[[:space:]]+sheets?|google[[:space:]]+workspace|spreadsheet)' then
    v_provider := 'google';
  else
    return jsonb_build_object('handled',false);
  end if;

  if v_norm ~ '\m(delete|merge|publish|promote|rollback|drop|truncate|rotate|remove domain|production deploy|go live)\M' then
    return jsonb_build_object(
      'handled',false,
      'routing','pandora_native_intelligence',
      'reason','bounded_mutation_adapter_required'
    );
  end if;

  if v_provider='connections' then
    v_registry := public.pandora_chat_capability_registry_v3(p_organization_id);
    v_reply := 'I checked Pandora''s live capability registry. The connection state below is runtime evidence, not a model assumption.';
    v_result := jsonb_build_object(
      'provider','pandora_runtime',
      'verified',true,
      'registry',v_registry,
      'observedAt',now()
    );

  elsif v_provider='github' then
    v_repo := substring(v_message from '([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)');
    if v_repo is null and v_norm ~ '\m(pandora|box|mcpmaster|canonical)\M' then
      v_repo := 'pandora-rvw-314296438-20260820/pandoras-box';
    end if;

    if v_repo is null then
      v_reply := 'GitHub is connected, but I need the repository in owner/repo form for a provider read.';
      v_result := jsonb_build_object('provider','github','verified',false,'needsTarget',true,'observedAt',now());
    elsif not (
      v_repo in (
        'pandora-rvw-314296438-20260820/pandoras-box',
        'pandora-rvw-314296438-20260820/pandoras-box-memory',
        'pandora-rvw-314296438-20260820/plp'
      )
      or exists (
        select 1 from public.pandora_projects p
        where p.organization_id=p_organization_id
          and p.repository=v_repo
      )
    ) then
      raise exception 'pandora_chat_repository_not_allowlisted' using errcode='42501';
    else
      begin
        v_pr_no := nullif(substring(v_message from '#([0-9]{1,9})'),'')::integer;
      exception when others then
        v_pr_no := null;
      end;

      if v_pr_no is not null and v_norm ~ '\m(pr|pull request)\M' then
        v_env := private.pandora_integration_github_api_20260825(
          'GET',
          '/repos/'||v_repo||'/pulls/'||v_pr_no::text,
          null
        );
      else
        v_env := private.pandora_integration_github_api_20260825(
          'GET',
          '/repos/'||v_repo,
          null
        );
      end if;

      if coalesce((v_env->>'status')::integer,0) between 200 and 299 then
        v_body := coalesce(v_env->'body','{}'::jsonb);
        if v_pr_no is not null and v_norm ~ '\m(pr|pull request)\M' then
          v_reply := format(
            'GitHub verified PR #%s in %s: %s%s. Head %s targets %s.',
            v_pr_no,
            v_repo,
            coalesce(v_body->>'state','unknown'),
            case when coalesce((v_body->>'merged')::boolean,false) then ', merged' else '' end,
            coalesce(v_body #>> '{head,sha}','unknown'),
            coalesce(v_body #>> '{base,ref}','unknown')
          );
          v_result := jsonb_build_object(
            'provider','github','verified',true,'repository',v_repo,
            'pullRequest',v_pr_no,'state',v_body->>'state',
            'merged',coalesce((v_body->>'merged')::boolean,false),
            'headSha',v_body #>> '{head,sha}','base',v_body #>> '{base,ref}',
            'updatedAt',v_body->>'updated_at','observedAt',now()
          );
        else
          v_reply := format(
            'GitHub verified %s. Default branch %s; visibility %s; pushed %s.',
            coalesce(v_body->>'full_name',v_repo),
            coalesce(v_body->>'default_branch','unknown'),
            coalesce(v_body->>'visibility','unknown'),
            coalesce(v_body->>'pushed_at','unknown')
          );
          v_result := jsonb_build_object(
            'provider','github','verified',true,
            'repository',coalesce(v_body->>'full_name',v_repo),
            'defaultBranch',v_body->>'default_branch',
            'visibility',v_body->>'visibility',
            'pushedAt',v_body->>'pushed_at',
            'archived',coalesce((v_body->>'archived')::boolean,false),
            'observedAt',now()
          );
        end if;
      else
        v_reply := format(
          'GitHub is connected, but the provider read returned status %s. Pandora will not substitute a guess.',
          coalesce(v_env->>'status','unknown')
        );
        v_result := jsonb_build_object(
          'provider','github','verified',false,'repository',v_repo,
          'httpStatus',v_env->>'status','observedAt',now()
        );
      end if;
    end if;

  elsif v_provider='supabase' then
    v_project_ref := substring(lower(v_message) from '([a-z]{20})');
    if v_project_ref is null and v_norm ~ '\m(pandora|box|mcpmaster|canonical)\M' then
      v_project_ref := 'jcyqixttuebxqqfkjonq';
    end if;

    if v_project_ref is null and p_project_id is not null then
      select h.details->>'projectRef' into v_project_ref
      from public.pandora_provider_health h
      where h.organization_id=p_organization_id
        and h.project_id=p_project_id
        and h.provider='supabase'
      order by h.updated_at desc
      limit 1;
    end if;

    if v_project_ref is null then
      v_reply := 'Supabase is connected, but I need the project reference for a live Management API read.';
      v_result := jsonb_build_object('provider','supabase','verified',false,'needsTarget',true,'observedAt',now());
    elsif v_project_ref<>'jcyqixttuebxqqfkjonq'
      and not exists (
        select 1 from public.pandora_provider_health h
        where h.organization_id=p_organization_id
          and h.provider='supabase'
          and h.details->>'projectRef'=v_project_ref
      ) then
      raise exception 'pandora_chat_supabase_project_not_allowlisted' using errcode='42501';
    else
      select decrypted_secret into v_token
      from vault.decrypted_secrets
      where name in ('mcpmaster_supabase_account_1_pat','Supabase_access')
        and nullif(trim(decrypted_secret),'') is not null
      order by case when name='mcpmaster_supabase_account_1_pat' then 0 else 1 end
      limit 1;

      if nullif(trim(v_token),'') is null then
        v_reply := 'Supabase needs authorization before Pandora can perform a live provider read.';
        v_result := jsonb_build_object('provider','supabase','verified',false,'connected',false,'observedAt',now());
      else
        perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
        perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
        select * into v_http
        from extensions.http((
          'GET'::extensions.http_method,
          ('https://api.supabase.com/v1/projects/'||v_project_ref)::varchar,
          array[
            extensions.http_header('authorization','Bearer '||v_token),
            extensions.http_header('accept','application/json'),
            extensions.http_header('user-agent','Pandora-Native-Capability/1.0')
          ]::extensions.http_header[],
          null::varchar,null::varchar
        )::extensions.http_request);

        begin
          v_body := nullif(v_http.content,'')::jsonb;
        exception when others then
          v_body := null;
        end;

        if v_http.status between 200 and 299 and v_body is not null then
          v_reply := format(
            'Supabase verified %s (%s): %s in %s.',
            coalesce(v_body->>'name',v_project_ref),
            v_project_ref,
            coalesce(v_body->>'status','unknown'),
            coalesce(v_body->>'region','unknown region')
          );
          v_result := jsonb_build_object(
            'provider','supabase','verified',true,
            'projectRef',v_project_ref,'name',v_body->>'name',
            'status',v_body->>'status','region',v_body->>'region',
            'organizationId',v_body->>'organization_id','observedAt',now()
          );
        else
          v_reply := format(
            'Supabase is connected, but the live provider read returned status %s. Pandora will not substitute stale state.',
            v_http.status
          );
          v_result := jsonb_build_object(
            'provider','supabase','verified',false,'projectRef',v_project_ref,
            'httpStatus',v_http.status,'observedAt',now()
          );
        end if;
      end if;
    end if;

  elsif v_provider='vercel' then
    select config_value into v_team_id
    from public.pandora_runtime_provider_configs
    where provider='vercel' and config_key='team_id' and active=true
    limit 1;

    select config_value into v_project_id
    from public.pandora_runtime_provider_configs
    where provider='vercel' and config_key='mcpmaster_project_id' and active=true
    limit 1;

    if nullif(v_team_id,'') is null or nullif(v_project_id,'') is null then
      v_reply := 'Vercel runtime configuration is unavailable, so Pandora will not guess deployment state.';
      v_result := jsonb_build_object('provider','vercel','verified',false,'configured',false,'observedAt',now());
    else
      v_env := private.pandora_worker_f_vercel_api_20260829(
        'GET',
        '/v9/projects/'||v_project_id||'?teamId='||v_team_id,
        null
      );

      if coalesce((v_env->>'status')::integer,0) between 200 and 299 then
        v_body := coalesce(v_env->'body','{}'::jsonb);
        v_reply := format(
          'Vercel verified project %s (%s). Framework %s; updated %s.',
          coalesce(v_body->>'name','pandoras-box'),
          v_project_id,
          coalesce(v_body->>'framework','unknown'),
          coalesce(v_body->>'updatedAt',v_body->>'updated_at','unknown')
        );
        v_result := jsonb_build_object(
          'provider','vercel','verified',true,
          'projectId',v_project_id,'name',v_body->>'name',
          'framework',v_body->>'framework',
          'updatedAt',coalesce(v_body->>'updatedAt',v_body->>'updated_at'),
          'observedAt',now()
        );
      else
        v_reply := format(
          'Vercel is connected, but the live project read returned status %s.',
          coalesce(v_env->>'status','unknown')
        );
        v_result := jsonb_build_object(
          'provider','vercel','verified',false,'projectId',v_project_id,
          'httpStatus',v_env->>'status','observedAt',now()
        );
      end if;
    end if;

  elsif v_provider='google' then
    v_google := public.pandora_google_workspace_connection_v1(p_organization_id);
    if coalesce((v_google->>'connected')::boolean,false) then
      v_reply := format(
        'Google Workspace is connected%s and ready for the authorized Drive/Sheets scopes.',
        case when nullif(v_google #>> '{account,label}','') is null
          then '' else ' as '||(v_google #>> '{account,label}') end
      );
      v_result := jsonb_build_object(
        'provider','google_workspace','verified',true,
        'connected',true,'state',v_google->>'state',
        'account',v_google->'account','scopes',v_google->'scopes',
        'scopesVerified',v_google->'scopesVerified',
        'lastVerifiedAt',v_google->'lastVerifiedAt',
        'observedAt',now()
      );
    elsif v_norm ~ '\m(connect|authorize|authorization|sign in)\M' then
      v_google := public.pandora_google_workspace_oauth_prepare_v1(p_organization_id);
      v_reply := case
        when coalesce((v_google->>'ok')::boolean,false)
          then 'Google Workspace needs your authorization. Pandora prepared the secure OAuth handoff.'
        else 'Google Workspace authorization is not configured yet, so Pandora cannot create the OAuth handoff.'
      end;
      v_result := jsonb_build_object(
        'provider','google_workspace','verified',false,
        'connected',false,'authorization',v_google,'observedAt',now()
      );
    else
      v_reply := 'Google Workspace is not connected yet. Pandora will not claim Drive or Sheets access until OAuth is verified.';
      v_result := jsonb_build_object(
        'provider','google_workspace','verified',false,
        'connected',false,'state',coalesce(v_google->>'state','Needs authorization'),
        'observedAt',now()
      );
    end if;

  elsif v_provider='posthog' then
    select jsonb_build_object(
      'provider','posthog',
      'verified',false,
      'status',h.status,
      'lastVerifiedAt',h.last_success_at,
      'staleAfter',h.stale_after,
      'details',h.details,
      'observedAt',now()
    )
    into v_result
    from public.pandora_provider_health h
    where h.organization_id=p_organization_id
      and h.provider='posthog'
    order by h.updated_at desc
    limit 1;

    if v_result is null then
      v_result := jsonb_build_object(
        'provider','posthog','verified',false,'status','unknown','observedAt',now()
      );
    end if;

    if exists(
      select 1 from vault.decrypted_secrets
      where name in ('posthog_personal_api_key','POSTHOG_PERSONAL_API_KEY')
        and nullif(trim(decrypted_secret),'') is not null
    ) then
      v_reply := 'PostHog query authorization exists, but a live bounded analytics-query adapter is not active in this lane yet. Pandora will not invent analytics.';
    else
      v_reply := 'PostHog live query authorization is not configured. Existing telemetry health is stale evidence only, so Pandora will not present it as a live analytics result.';
    end if;
  end if;

  if v_thread_id is not null then
    perform 1
    from public.pandora_intelligence_threads t
    where t.id=v_thread_id
      and t.organization_id=p_organization_id
      and t.created_by=v_uid
      and t.status='active';
    if not found then
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
      'intent',v_intent,
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'handoff',null,
      'providerReadback',v_result
    ),
    'pandora_native_capability',
    'deterministic-provider-readback-v1'
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(),updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent',v_intent,
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'projectRequired',false,
    'handoff',null,
    'providerReadback',v_result
  );
end;
$function$;


revoke all on function public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.pandora_chat_universal_dispatch_v9(p_organization_id uuid, p_message text, p_thread_id uuid DEFAULT NULL::uuid, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_norm text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_direct_action boolean := false;
  v_plp_explicit boolean := false;
  v_box_explicit boolean := false;
  v_plp_context boolean := false;
  v_box_context boolean := false;
  v_capability jsonb;
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

  if v_norm='' or length(v_norm)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_direct_action := v_norm ~ '\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply|redesign|refactor|rewrite|finish|complete|make)\M';
  v_plp_explicit := v_norm ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M';
  v_box_explicit := v_norm ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo|this[[:space:]]+repo)\M';

  if p_thread_id is not null and (not v_plp_explicit or not v_box_explicit) then
    select
      coalesce(bool_or(lower(recent.content) ~ '\m(plp|pueblo[[:space:]]+la[[:space:]]+perla)\M'),false),
      coalesce(bool_or(lower(recent.content) ~ '\m(pandoras-box|pandora''?s[[:space:]-]+box|mcpmaster|ask[[:space:]]+pandora|pandora[[:space:]]+chat|activity[[:space:]]+theatre|build[[:space:]]+theatre|canonical[[:space:]]+repo)\M'),false)
    into v_plp_context,v_box_context
    from (
      select m.content
      from public.pandora_intelligence_messages m
      join public.pandora_intelligence_threads t on t.id=m.thread_id
      where m.thread_id=p_thread_id
        and m.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
      order by m.created_at desc
      limit 12
    ) recent;
  end if;

  if v_direct_action and (v_plp_explicit or (v_plp_context and not v_box_explicit)) then
    return private.pandora_direct_plp_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  if v_direct_action and (v_box_explicit or v_box_context) then
    return private.pandora_direct_box_code_edit_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  v_capability := public.pandora_chat_capability_dispatch_native_v1(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
  if coalesce((v_capability->>'handled')::boolean,false) then
    return v_capability;
  end if;

  return jsonb_build_object(
    'handled',false,
    'routing','pandora_native_intelligence',
    'projectId',p_project_id,
    'projectRequired',false,
    'requestMode','intelligence'
  );
end;
$function$;


revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) to authenticated;

do $contract$
declare v_router text; v_native text; v_registry text;
begin
  select pg_get_functiondef('public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)'::regprocedure) into v_router;
  select pg_get_functiondef('public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)'::regprocedure) into v_native;
  select pg_get_functiondef('public.pandora_chat_capability_registry_v3(uuid)'::regprocedure) into v_registry;
  if position('projectos' in lower(v_router))>0 or position('projectos' in lower(v_native))>0 or position('projectos' in lower(v_registry))>0 then
    raise exception 'pandora_native_capability_projectos_regression' using errcode='55000';
  end if;
  if position('pandora_chat_capability_dispatch_native_v1' in v_router)=0 or position('pandora_direct_box_code_edit_v1' in v_router)=0 then
    raise exception 'pandora_native_capability_route_missing' using errcode='55000';
  end if;
end
$contract$;
