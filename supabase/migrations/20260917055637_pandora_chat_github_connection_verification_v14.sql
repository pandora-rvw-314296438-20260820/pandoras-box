create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null::uuid,
  p_project_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'vault', 'auth', 'extensions', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_thread_id uuid := p_thread_id;
  v_project_mode text;
  v_reply text;
  v_prior_assistant text;
  v_confirmation boolean := false;
  v_github_connection_intent boolean := false;
  v_repository text;
  v_provider jsonb;
  v_provider_body jsonb := '{}'::jsonb;
  v_provider_status integer := 0;
  v_verified_at timestamptz;
  v_project_name text;
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

  if v_thread_id is not null then
    if not exists (
      select 1
      from public.pandora_intelligence_threads t
      where t.id=v_thread_id
        and t.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
    ) then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;

    select m.content into v_prior_assistant
    from public.pandora_intelligence_messages m
    where m.thread_id=v_thread_id
      and m.organization_id=p_organization_id
      and m.author_role='assistant'
    order by m.created_at desc
    limit 1;
  end if;

  v_confirmation := lower(regexp_replace(v_message,'[[:space:]]+',' ','g')) ~
    '^(yes|yes please|do it|please do|go ahead|go ahead please|proceed|continue|sure|okay|ok)[.! ]*$';

  v_github_connection_intent :=
    (
      v_message ~* E'\\mgithub\\M'
      and v_message ~* '(connect|connection|authoriz|access|sign[ -]?in|verify|check|test|link)'
    )
    or (
      v_confirmation
      and coalesce(v_prior_assistant,'') ~* E'\\mgithub\\M'
      and coalesce(v_prior_assistant,'') ~* '(connect|connection|authoriz|access|sign[ -]?in|verify|check|test|link)'
    );

  if v_github_connection_intent then
    if p_project_id is not null then
      select p.repository,p.name
      into v_repository,v_project_name
      from public.projectos_projects p
      where p.id=p_project_id
        and p.organization_id=p_organization_id
        and p.status <> 'archived'
      limit 1;
      if v_repository is null then
        raise exception 'pandora_chat_project_not_found' using errcode='22023';
      end if;
    else
      select p.repository,p.name
      into v_repository,v_project_name
      from public.projectos_projects p
      where p.organization_id=p_organization_id
        and p.status <> 'archived'
        and p.config->>'enterpriseDefault'='true'
        and coalesce(p.repository,'') <> ''
      order by p.updated_at desc
      limit 1;
    end if;

    if v_repository is null or v_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then
      v_repository := 'pandora-rvw-314296438-20260820/pandoras-box';
      v_project_name := 'Pandora';
    end if;

    begin
      v_provider := private.pandora_integration_github_api_20260825(
        'GET',
        '/repos/' || v_repository,
        null::jsonb
      );
      if coalesce(v_provider->>'status','') ~ '^[0-9]{3}$' then
        v_provider_status := (v_provider->>'status')::integer;
      end if;
      v_provider_body := coalesce(v_provider->'body','{}'::jsonb);
    exception when others then
      v_provider_status := 0;
      v_provider_body := '{}'::jsonb;
    end;

    if v_thread_id is null then
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

    if v_provider_status=200
       and lower(coalesce(v_provider_body->>'full_name',''))=lower(v_repository) then
      v_verified_at := now();
      update public.connector_installations
      set status='active',
          last_health_check_at=v_verified_at,
          updated_at=v_verified_at
      where organization_id=p_organization_id
        and lower(provider)='github';

      v_reply := format(
        'GitHub is already connected. I just verified live access to %s. No new GitHub sign-in or authorization flow is needed.',
        v_repository
      );

      insert into public.pandora_intelligence_messages(
        thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
      ) values(
        v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
        jsonb_build_object(
          'intent','github_connection_verified',
          'confidence',1,
          'needsClarification',false,
          'clarifyingQuestion',null,
          'projectRequired',false,
          'handoff',null,
          'providerReadback',jsonb_build_object(
            'provider','github',
            'verified',true,
            'repository',v_repository,
            'defaultBranch',v_provider_body->>'default_branch',
            'private',coalesce((v_provider_body->>'private')::boolean,false),
            'verifiedAt',v_verified_at
          )
        ),
        'pandora_capability_runtime','github-connection-readback-v1'
      );

      update public.pandora_intelligence_threads
      set last_message_at=now(),updated_at=now()
      where id=v_thread_id;

      return jsonb_build_object(
        'handled',true,
        'threadId',v_thread_id,
        'reply',v_reply,
        'intent','github_connection_verified',
        'confidence',1,
        'needsClarification',false,
        'clarifyingQuestion',null,
        'projectRequired',false,
        'handoff',null,
        'providerReadback',jsonb_build_object(
          'provider','github',
          'verified',true,
          'repository',v_repository,
          'defaultBranch',v_provider_body->>'default_branch',
          'verifiedAt',v_verified_at
        )
      );
    end if;

    v_reply := format(
      'GitHub is configured, but I could not verify live provider access to %s right now. I did not start a new authorization flow or claim the connection is healthy.',
      v_repository
    );

    insert into public.pandora_intelligence_messages(
      thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
    ) values(
      v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
      jsonb_build_object(
        'intent','github_connection_unverified',
        'confidence',1,
        'needsClarification',false,
        'clarifyingQuestion',null,
        'projectRequired',false,
        'handoff',null,
        'providerReadback',jsonb_build_object(
          'provider','github','verified',false,'repository',v_repository,'status',v_provider_status
        )
      ),
      'pandora_capability_runtime','github-connection-readback-v1'
    );

    update public.pandora_intelligence_threads
    set last_message_at=now(),updated_at=now()
    where id=v_thread_id;

    return jsonb_build_object(
      'handled',true,
      'threadId',v_thread_id,
      'reply',v_reply,
      'intent','github_connection_unverified',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'projectRequired',false,
      'handoff',null,
      'providerReadback',jsonb_build_object(
        'provider','github','verified',false,'repository',v_repository,'status',v_provider_status
      )
    );
  end if;

  if p_project_id is not null then
    v_project_mode := private.pandora_chat_project_request_mode_v1(v_message);

    if v_project_mode='repository_audit' then
      return jsonb_build_object(
        'handled',false,'routing','repository_audit_direct',
        'projectId',p_project_id,'projectRequired',false,
        'requestMode',v_project_mode
      );
    end if;

    if v_project_mode='project_intelligence' then
      return jsonb_build_object(
        'handled',false,'routing','project_intelligence_direct',
        'projectId',p_project_id,'projectRequired',false,
        'requestMode',v_project_mode
      );
    end if;

    if v_project_mode='workspace_action' then
      if not exists (
        select 1 from public.projectos_projects p
        where p.id=p_project_id
          and p.organization_id=p_organization_id
          and p.status <> 'archived'
      ) then
        raise exception 'pandora_chat_project_not_found' using errcode='22023';
      end if;

      if v_thread_id is null then
        insert into public.pandora_intelligence_threads(
          organization_id,project_id,created_by,title,status,last_message_at
        ) values(
          p_organization_id,p_project_id,v_uid,
          left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
          'active',now()
        ) returning id into v_thread_id;
      end if;

      v_reply := 'I''ll handle this change here in chat. I won''t open another screen. I''ll report only after the real build starts or needs you.';

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
          'requestMode',v_project_mode,
          'handoff',jsonb_build_object(
            'required',true,'request',v_message,'projectId',p_project_id,
            'source','project_workspace_change'
          )
        ),
        'pandora_project_workspace_router','workspace-change-v3-chat-in-place'
      );

      update public.pandora_intelligence_threads
      set last_message_at=now(),updated_at=now(),project_id=p_project_id
      where id=v_thread_id;

      return jsonb_build_object(
        'handled',true,'threadId',v_thread_id,'reply',v_reply,
        'intent','project_workspace_change','confidence',1,
        'needsClarification',false,'clarifyingQuestion',null,'projectRequired',false,
        'requestMode',v_project_mode,
        'handoff',jsonb_build_object(
          'required',true,'request',v_message,'projectId',p_project_id,
          'source','project_workspace_change'
        )
      );
    end if;
  end if;

  return jsonb_build_object(
    'handled',false,
    'routing','pandora_native_intelligence',
    'projectId',p_project_id,
    'projectRequired',false,
    'requestMode',coalesce(v_project_mode,'intelligence')
  );
end;
$function$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid) to authenticated;;
