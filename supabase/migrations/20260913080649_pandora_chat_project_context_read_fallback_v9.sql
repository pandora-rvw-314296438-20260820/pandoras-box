do $migration$
declare
  v_src text;
  v_needle text := E'  -- Keep the existing deterministic capability resolver while the standing-authority\n  -- Worker C lane is converging. The owner should see the task, not the internal admission plumbing.\n';
  v_guard text := E'  -- Project-context reads are not repository operations merely because the selected\n  -- project has a repository binding. Keep project plan/scope/status questions in\n  -- the intelligence path unless the owner explicitly asks about repository/source.\n  if p_project_id is not null\n     and v_message ~* ''\\m(show|read|explain|summarize|summarise|describe|what|plan|roadmap|requirements|scope|status)\\M''\n     and v_message !~* ''\\m(github|repository|repo|code|source|branch|commit|pull|file|deploy|publish|build|fix|change|update|repair|edit|merge|run|test|implement|write|apply|configure|install|remove|restore)\\M'' then\n    return public.pandora_chat_universal_dispatch_v6(\n      p_organization_id,p_message,p_thread_id,p_project_id\n    );\n  end if;\n\n';
begin
  select pg_get_functiondef('public.pandora_chat_universal_dispatch_v8(uuid,text,uuid,uuid)'::regprocedure)
  into v_src;
  if position('Project-context reads are not repository operations' in v_src) > 0 then
    return;
  end if;
  if position(v_needle in v_src) = 0 then
    raise exception 'pandora_chat_v8_insertion_point_missing' using errcode='55000';
  end if;
  v_src := replace(v_src, v_needle, v_guard || v_needle);
  execute v_src;
end
$migration$;
