do $$
declare
  v_def text;
  v_old text := '''repository_full_name'', ''projectId'', ''project_id'', ''projectRef'',';
  v_new text := '''repository_full_name'', ''projectKey'', ''project_key'', ''projectId'', ''project_id'', ''projectRef'',';
begin
  select pg_get_functiondef('private.projectos_legacy_node_context_json(jsonb)'::regprocedure) into v_def;
  if position(v_new in v_def) > 0 then
    return;
  end if;
  if position(v_old in v_def) = 0 then
    raise exception 'projectos legacy context validator source shape changed; refusing blind patch';
  end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end
$$;