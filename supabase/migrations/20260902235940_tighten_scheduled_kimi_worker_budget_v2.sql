do $$
declare
  v_def text;
begin
  select pg_get_functiondef('private.pandora_scheduled_model_worker_tick_v1(integer)'::regprocedure)
    into v_def;
  v_def := replace(v_def, '''max_completion_tokens'',4096', '''max_completion_tokens'',1024');
  v_def := replace(v_def, '''stream'',false', '''reasoning_effort'',''low'',''stream'',false');
  if position('''max_completion_tokens'',1024' in v_def) = 0 or position('''reasoning_effort'',''low''' in v_def) = 0 then
    raise exception 'scheduled Kimi worker budget patch did not bind';
  end if;
  execute v_def;
end $$;