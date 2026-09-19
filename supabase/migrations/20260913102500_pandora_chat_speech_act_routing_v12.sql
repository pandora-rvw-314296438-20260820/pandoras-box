-- Pandora Chat speech-act routing v12
--
-- Permanent safety/UX invariant:
--   * intelligence/read/planning is the default;
--   * merely mentioning build/fix/deploy/publish/etc. never authorizes execution;
--   * selected-project workspace execution requires an explicit action speech act.
--
-- This repairs the physical-device regression where
-- "generate the ... step by step plan on how we are going to build this"
-- was treated as a build mutation because the sentence contained the token "build".

create or replace function private.pandora_chat_project_request_mode_v1(
  p_message text
) returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v text := lower(regexp_replace(trim(coalesce(p_message,'')), '[[:space:]]+', ' ', 'g'));
  v_planning_artifact boolean;
  v_planning_signal boolean;
  v_informational_read boolean;
  v_deep_audit boolean;
  v_sequence_workspace_action boolean;
  v_direct_workspace_action boolean;
begin
  if v = '' then
    return 'default';
  end if;

  v_planning_artifact :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(show|give|generate|draft|write|produce|make|create|build|outline)[[:space:]]+(me[[:space:]]+)?((a|an|the)[[:space:]]+)?((comprehensive|detailed|complete|full|entire|technical|implementation|development|project|build|deployment|migration|execution|action|step|by|step-by-step|end-to-end)[[:space:]]+){0,8}(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|steps)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(can|could|would|will)[[:space:]]+you[[:space:]]+(show|give|generate|draft|write|produce|make|create|build|outline)[[:space:]]+(me[[:space:]]+)?((a|an|the)[[:space:]]+)?((comprehensive|detailed|complete|full|entire|technical|implementation|development|project|build|deployment|migration|execution|action|step|by|step-by-step|end-to-end)[[:space:]]+){0,8}(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|steps)\\M';

  v_sequence_workspace_action :=
    v ~ E'\\m(then|after[[:space:]]+that)\\M[[:space:]]+(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply)\\M'
    or v ~ E'\\mand\\M[[:space:]]+(then[[:space:]]+)?(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply)\\M[[:space:]]+(it|this|that|them|the[[:space:]])'
    or v ~ E'[.!?][[:space:]]*(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply)\\M';

  v_informational_read :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(update|brief|fill)[[:space:]]+me[[:space:]]+(on|about)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(what|how)[[:space:]]+(is|are|was|were|has|have|did|does)[[:space:]]+.*\\m(status|progress|state)\\M';

  v_direct_workspace_action :=
    v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(please[[:space:]]+)?(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*((can|could|would|will)[[:space:]]+you|i[[:space:]]+(want|need)[[:space:]]+you[[:space:]]+to|let''s|go[[:space:]]+ahead([[:space:]]+and)?)[[:space:]]+(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|apply)\\M';

  v_deep_audit :=
    (v ~ E'\\m(audit|analy[sz]e)\\M' and v ~ E'\\m(entire|full|whole|repository|repo|project|codebase|source|code)\\M')
    or (v ~ E'\\m(inspect|review|scan)\\M' and v ~ E'\\m(entire|full|whole|repository|repo|project|codebase|source|all)\\M');

  v_planning_signal :=
    v ~ E'\\m(plan|roadmap|strategy|approach|architecture|specification|spec|design|blueprint|checklist|step-by-step|steps)\\M'
    or v ~ E'\\m(how[[:space:]]+(are|should|would|could|can)[[:space:]]+(we|i|you)|what[[:space:]]+should[[:space:]]+(we|i|you)|what[[:space:]]+would[[:space:]]+it[[:space:]]+take|best[[:space:]]+way[[:space:]]+to)\\M'
    or v ~ E'^((okay|ok|great|alright|yes|yep|sure)[[:space:],.!-]+)*(can|could|would|should)[[:space:]]+(we|i)[[:space:]]+'
    or (v ~ E'\\m(explain|describe|outline|summari[sz]e)\\M' and v ~ E'\\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|deploy|publish|merge|migration|project|system|app|website)\\M')
    or (v ~ E'^(what|how|why|which|where|when)\\M' and v ~ E'\\m(build|fix|change|update|repair|edit|implement|create|configure|improve|upgrade|add|remove|restore|deploy|publish|merge|project|system|app|website|status|progress|state)\\M');

  if v_sequence_workspace_action then return 'workspace_action'; end if;
  if v_planning_artifact then return 'project_intelligence'; end if;
  if v_informational_read then return 'project_intelligence'; end if;
  if v_direct_workspace_action then return 'workspace_action'; end if;
  if v_deep_audit then return 'repository_audit'; end if;
  if v_planning_signal then return 'project_intelligence'; end if;
  return 'default';
end;
$$;

revoke all on function private.pandora_chat_project_request_mode_v1(text)
  from public, anon, authenticated;

comment on function private.pandora_chat_project_request_mode_v1(text)
is 'Fail-closed speech-act classifier for selected-project chat. Intelligence is the default; workspace execution requires an explicit imperative/request, not incidental action vocabulary.';

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
          'requestMode',v_project_mode,
          'handoff',jsonb_build_object(
            'required',true,'request',v_message,'projectId',p_project_id,
            'source','project_workspace_change'
          )
        ),
        'pandora_project_workspace_router','workspace-change-v2'
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
$$;

revoke all on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  from public,anon;
grant execute on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
  to authenticated;

comment on function public.pandora_chat_universal_dispatch_v9(uuid,text,uuid,uuid)
is 'Universal Chat v9 speech-act routing: selected-project planning/reads stay in intelligence, repository audits receive verified source, explicit workspace imperatives enter the real build runtime, and incidental action words never trigger mutation.';

do $speech_act_contract$
declare
  v_case record;
  v_actual text;
begin
  for v_case in
    select * from (values
      ('Okay great generate the comprehensive detailed step by step plan on how we are going to build this','project_intelligence'),
      ('Show me the entire detailed plan for this project','project_intelligence'),
      ('Build me a step-by-step plan for this project','project_intelligence'),
      ('Can you create a detailed implementation plan for this?','project_intelligence'),
      ('I want a plan for how to build this','project_intelligence'),
      ('Create an implementation roadmap to deploy this','project_intelligence'),
      ('How are we going to build this?','project_intelligence'),
      ('How should we deploy this?','project_intelligence'),
      ('Can we build this?','project_intelligence'),
      ('Explain how to fix this','project_intelligence'),
      ('Update me on the project status','project_intelligence'),
      ('What is the status of this project?','project_intelligence'),
      ('Build it','workspace_action'),
      ('Okay great, build it','workspace_action'),
      ('Please fix this','workspace_action'),
      ('Can you build it now?','workspace_action'),
      ('I need you to implement this','workspace_action'),
      ('Implement the plan','workspace_action'),
      ('Build the app according to the plan','workspace_action'),
      ('Create the booking flow','workspace_action'),
      ('Update the checkout screen','workspace_action'),
      ('Review the entire repo and then fix it','workspace_action'),
      ('Create a plan and then build it','workspace_action'),
      ('Audit the entire repository','repository_audit'),
      ('Analyze the whole codebase and tell me what to fix','repository_audit'),
      ('Review the entire repo and give me a plan','repository_audit'),
      ('Deploy it now','default'),
      ('Publish this now','default')
    ) as t(message,expected)
  loop
    v_actual := private.pandora_chat_project_request_mode_v1(v_case.message);
    if v_actual is distinct from v_case.expected then
      raise exception 'pandora_chat_speech_act_contract_failed message=% expected=% actual=%',
        v_case.message,v_case.expected,v_actual using errcode='55000';
    end if;
  end loop;
end
$speech_act_contract$;
