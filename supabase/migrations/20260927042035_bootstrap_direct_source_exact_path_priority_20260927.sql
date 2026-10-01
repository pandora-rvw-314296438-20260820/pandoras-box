
do $bootstrap$
declare
  v_def text;
  v_anchor text := $$      (case when lower(e->>'path')='supabase/functions/pandora-intelligence-chat/index.ts' then 140 else 0 end) +$$;
  v_replacement text := $$      (case when position(lower(e->>'path') in lower(v_message)) > 0 then 500 else 0 end) +
      (case when lower(e->>'path')='supabase/functions/pandora-intelligence-chat/index.ts' then 140 else 0 end) +$$;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_def;

  if position(v_replacement in v_def) > 0 then
    return;
  end if;

  if position(v_anchor in v_def) = 0 then
    raise exception 'PANDORA_DIRECT_SOURCE_SELECTOR_ANCHOR_MISSING';
  end if;

  v_def := replace(v_def, v_anchor, v_replacement);
  execute v_def;
end;
$bootstrap$;

