-- Pandora Chat in-place execution v13
--
-- Universal Chat remains the owner surface for selected-project actions.
-- The dispatcher may authorize a real project_workspace_change handoff, but
-- the mobile client consumes that handoff in place. No screen transition is
-- implied by the routing contract.

create or replace function public.pandora_chat_universal_dispatch_v9(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $body$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_thread_id uuid := p_thread_id;
  v_project_mode text;
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
        select 1 from public.pandora_projects p
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

  return public.pandora_chat_universal_dispatch_v8(
    p_organization_id,p_message,p_thread_id,p_project_id
  );
end;
$body$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  to authenticated;

comment on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
is 'Universal Chat v13 execution UX: selected-project planning and audits remain read-only; explicit project actions emit one governed project_workspace_change handoff consumed in-place by Universal Chat, with no automatic screen transition; provider actions continue through v8.';

do $contract$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)'::regprocedure
  ) into v_definition;
  if position('handle this change here in chat' in v_definition) = 0 then
    raise exception 'pandora_chat_v13_in_place_reply_missing' using errcode='55000';
  end if;
  if position('workspace-change-v3-chat-in-place' in v_definition) = 0 then
    raise exception 'pandora_chat_v13_model_marker_missing' using errcode='55000';
  end if;
end
$contract$;
