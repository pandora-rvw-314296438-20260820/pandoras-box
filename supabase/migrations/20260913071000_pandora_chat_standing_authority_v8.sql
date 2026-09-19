-- Pandora Universal Chat standing-authority UX v8
-- Routine owner instructions continue automatically. ProjectOS/Tool Gateway are implementation details,
-- not owner-facing gates. Worker/tool credentials remain isolated from the model.

create or replace function public.pandora_chat_universal_dispatch_v8(
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
  v_message text := trim(coalesce(p_message,''));
  v_result jsonb;
  v_thread_id uuid := p_thread_id;
  v_intake_id uuid;
  v_intake_status text;
  v_intake_project_id uuid;
  v_reply text;
  v_previous_reply text;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;
  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  if v_thread_id is not null then
    if not exists(
      select 1
      from public.pandora_intelligence_threads t
      where t.id=v_thread_id
        and t.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
    ) then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;

    -- A status follow-up such as "has it been accepted?" must read the actual
    -- persisted execution state instead of falling back to a generic model refusal.
    if v_message ~* '\m(accepted|acceptance|status|progress|running|started|executing|done|complete|completed|blocked)\M' then
      select nullif(m.structured_response #>> '{handoff,intakeId}','')::uuid
      into v_intake_id
      from public.pandora_intelligence_messages m
      where m.thread_id=v_thread_id
        and m.organization_id=p_organization_id
        and m.author_role='assistant'
        and nullif(m.structured_response #>> '{handoff,intakeId}','') is not null
      order by m.created_at desc, m.id desc
      limit 1;

      if v_intake_id is not null then
        select i.status, i.project_id
        into v_intake_status, v_intake_project_id
        from public.projectos_intake_requests i
        where i.id=v_intake_id
          and i.organization_id=p_organization_id
        limit 1;

        if found then
          v_reply := case lower(coalesce(v_intake_status,''))
            when 'accepted' then 'Yes — the work request is accepted. Pandora will continue automatically from here.'
            when 'planned' then 'Yes — it is accepted and planned. Pandora will continue into execution automatically.'
            when 'executing' then 'Yes — it is executing now. Pandora will keep going unless something genuinely needs you.'
            when 'completed' then 'The execution step is complete. Pandora is verifying the requested outcome before calling it finished.'
            when 'blocked' then 'The execution is genuinely blocked. Pandora should surface the specific blocker in Needs You instead of asking you to submit the request again.'
            else format('The work is currently %s. Pandora will continue automatically unless a real blocker needs you.',coalesce(v_intake_status,'unknown'))
          end;

          insert into public.pandora_intelligence_messages(
            thread_id,organization_id,project_id,author_role,content,attachment_manifest
          ) values(
            v_thread_id,p_organization_id,coalesce(v_intake_project_id,p_project_id),'user',v_message,'[]'::jsonb
          );

          insert into public.pandora_intelligence_messages(
            thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
          ) values(
            v_thread_id,p_organization_id,coalesce(v_intake_project_id,p_project_id),'assistant',v_reply,
            jsonb_build_object(
              'intent','execution_status',
              'confidence',1,
              'needsClarification',false,
              'clarifyingQuestion',null,
              'projectRequired',false,
              'execution',jsonb_build_object(
                'intakeId',v_intake_id,
                'status',v_intake_status,
                'requestedOutcomeVerified',false
              )
            ),
            'pandora_execution_status','standing-authority-v1'
          );

          update public.pandora_intelligence_threads
          set last_message_at=now(),updated_at=now()
          where id=v_thread_id;

          return jsonb_build_object(
            'handled',true,
            'threadId',v_thread_id,
            'reply',v_reply,
            'intent','execution_status',
            'confidence',1,
            'needsClarification',false,
            'clarifyingQuestion',null,
            'projectRequired',false,
            'execution',jsonb_build_object(
              'intakeId',v_intake_id,
              'status',v_intake_status,
              'requestedOutcomeVerified',false
            )
          );
        end if;
      end if;
    end if;
  end if;

  -- Keep the existing deterministic capability resolver while the standing-authority
  -- Worker C lane is converging. The owner should see the task, not the internal admission plumbing.
  v_result := public.pandora_chat_universal_dispatch_v7(
    p_organization_id,p_message,p_thread_id,p_project_id
  );

  if coalesce((v_result->>'handled')::boolean,false)
     and coalesce(v_result->>'intent','') in ('repository_action','repository_analysis') then
    v_thread_id := nullif(v_result->>'threadId','')::uuid;
    v_previous_reply := coalesce(v_result->>'reply','');

    if coalesce((v_result #>> '{capabilityResult,ok}')::boolean,false) then
      v_reply := case v_result->>'intent'
        when 'repository_analysis' then 'I found the target and started handling the analysis. Pandora will keep working automatically in this chat and only stop if something genuinely needs you. I will report completion only after verified evidence.'
        else 'I found the target and started handling the request. Pandora will keep going automatically in this chat and only stop if something genuinely needs you. I will report completion only after verified provider evidence.'
      end;
    else
      v_reply := 'I found the target, but execution could not start because the runtime is unavailable. Nothing was changed. Pandora will retry or surface a real blocker rather than ask you to submit the request again.';
    end if;

    if v_thread_id is not null then
      update public.pandora_intelligence_messages m
      set content=v_reply
      where m.id=(
        select m2.id
        from public.pandora_intelligence_messages m2
        where m2.thread_id=v_thread_id
          and m2.organization_id=p_organization_id
          and m2.author_role='assistant'
          and m2.content=v_previous_reply
        order by m2.created_at desc,m2.id desc
        limit 1
      );
    end if;

    v_result := jsonb_set(v_result,'{reply}',to_jsonb(v_reply),true);
    v_result := jsonb_set(v_result,'{projectRequired}','false'::jsonb,true);
  end if;

  return v_result;
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid)
is 'Universal Chat v8: standing-authority owner UX, exact persisted execution-status follow-ups, no ProjectOS/Tool Gateway front-door language, and truthful completion claims.';
