-- Pandora chat execution truth v10
-- Admission is not execution. Owner-facing progress is derived only from persisted runtime state.

do $migration$
declare
  v_src text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef('public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid)'::regprocedure)
  into v_src;

  if position('there is no persisted evidence that execution has started' in v_src) = 0 then
    v_old := $old$    if v_message ~* '\m(accepted|acceptance|status|progress|running|started|executing|done|complete|completed|blocked)\M' then$old$;
    v_new := $new$    if length(v_message) <= 200
       and (
         v_message ~* '\m(accepted|acceptance|status|progress|running|started|executing|done|complete|completed|blocked|eta)\M'
         or v_message ~* '\m(minute|minutes|hour|hours|taking|slow|still|yet|happening|background)\M'
         or v_message ~* '\mhow long\M'
         or v_message ~* '\myou said\M'
         or v_message ~* '\mthousand years\M'
         or v_message ~* '^\s*(and|so)\s*\?\s*$'
       ) then$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_status_followup_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            when 'accepted' then 'Yes — the work request is accepted. Pandora will continue automatically from here.'$old$;
    v_new := $new$            when 'accepted' then 'The request is accepted, but there is no persisted evidence that execution has started. It is not done, and no ETA is verified.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_accepted_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            when 'planned' then 'Yes — it is accepted and planned. Pandora will continue into execution automatically.'$old$;
    v_new := $new$            when 'planned' then 'The request is planned, but there is no persisted evidence that a worker has started executing it. It is not done, and no ETA is verified.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_planned_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            when 'executing' then 'Yes — it is executing now. Pandora will keep going unless something genuinely needs you.'$old$;
    v_new := $new$            when 'executing' then 'The request is executing now according to persisted ProjectOS state. Completion has not been verified yet.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_executing_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            when 'completed' then 'The execution step is complete. Pandora is verifying the requested outcome before calling it finished.'$old$;
    v_new := $new$            when 'completed' then 'ProjectOS records the execution step as completed. Pandora will only call the requested outcome verified when provider or evidence checks explicitly prove it.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_completed_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            when 'blocked' then 'The execution is genuinely blocked. Pandora should surface the specific blocker in Needs You instead of asking you to submit the request again.'$old$;
    v_new := $new$            when 'blocked' then 'The request is blocked in persisted ProjectOS state. It is not running; Pandora should surface the recorded blocker in Needs You.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_blocked_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$            else format('The work is currently %s. Pandora will continue automatically unless a real blocker needs you.',coalesce(v_intake_status,'unknown'))$old$;
    v_new := $new$            else format('Persisted ProjectOS status is %s. Pandora will not claim progress or an ETA beyond that recorded state.',coalesce(v_intake_status,'unknown'))$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_default_status_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$        when 'repository_analysis' then 'I found the target and started handling the analysis. Pandora will keep working automatically in this chat and only stop if something genuinely needs you. I will report completion only after verified evidence.'$old$;
    v_new := $new$        when 'repository_analysis' then 'I found the target and accepted the analysis request into ProjectOS. Acceptance is not execution. I will only report it as running after persisted execution evidence says a worker started, and I will only report completion after verified evidence.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_repository_analysis_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    v_old := $old$        else 'I found the target and started handling the request. Pandora will keep going automatically in this chat and only stop if something genuinely needs you. I will report completion only after verified provider evidence.'$old$;
    v_new := $new$        else 'I found the target and accepted the request into ProjectOS. Acceptance is not execution. I will only report it as running after persisted execution evidence says a worker started, and I will only report completion after verified provider evidence.'$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_repository_action_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);

    execute v_src;
  end if;

  -- The owner-selected "pandoras-box" project predates the verified canonical
  -- ProjectOS mcpmaster root and has no repository column value. Resolve that
  -- selected context to the verified canonical repository without mutating the
  -- project row or creating a second canonical source of truth.
  select pg_get_functiondef('private.pandora_resolve_repository_target_v2(uuid,text,uuid,uuid)'::regprocedure)
  into v_src;

  if position('explicit_project_canonical_fallback' in v_src) = 0 then
    v_old := $old$    if found then
      return jsonb_build_object(
        'state','resolved','resolved',true,'resolution','explicit_project_context',
        'repository',v_project.repository,'projectId',v_project.id,'projectKey',v_project.project_key,
        'projectName',v_project.name,'repositoryStatus','project_bound','projectRequired',false
      );
    end if;$old$;
    v_new := $new$    if found then
      return jsonb_build_object(
        'state','resolved','resolved',true,
        'resolution',case
          when nullif(trim(v_project.repository),'') is null and v_project.project_key='pandoras-box'
            then 'explicit_project_canonical_fallback'
          else 'explicit_project_context'
        end,
        'repository',case
          when nullif(trim(v_project.repository),'') is null and v_project.project_key='pandoras-box'
            then 'pandora-rvw-314296438-20260820/pandoras-box'
          else v_project.repository
        end,
        'projectId',v_project.id,
        'projectKey',v_project.project_key,
        'projectName',v_project.name,
        'repositoryStatus',case
          when nullif(trim(v_project.repository),'') is null and v_project.project_key='pandoras-box'
            then 'provider_verified'
          else 'project_bound'
        end,
        'projectRequired',false
      );
    end if;$new$;
    if position(v_old in v_src) = 0 then
      raise exception 'pandora_chat_v10_project_resolution_anchor_missing' using errcode='55000';
    end if;
    v_src := replace(v_src,v_old,v_new);
    execute v_src;
  end if;
end
$migration$;

comment on function public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid)
is 'Standing-authority universal chat. Admission/accepted state is never represented as execution; owner-facing progress comes from persisted ProjectOS state and verified evidence.';

comment on function private.pandora_resolve_repository_target_v2(uuid,text,uuid,uuid)
is 'Resolves repository context. The legacy owner-selected pandoras-box project key deterministically maps to the independently verified canonical Pandora repository when its repository column is empty.';
