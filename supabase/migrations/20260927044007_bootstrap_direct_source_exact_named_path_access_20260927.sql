
do $patch$
declare
  v_def text;
  v_anchor text := $$      and lower(e->>'path') ~ '^(supabase/functions/|packages/|apps/pandora-mobile/|src/|test/)'$$;
  v_replacement text := $$      and (
        lower(e->>'path') ~ '^(supabase/functions/|packages/|apps/pandora-mobile/|src/|test/)'
        or position(lower(e->>'path') in lower(v_message)) > 0
      )$$;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_def;
  if position(v_replacement in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def)=0 then
    raise exception 'PANDORA_DIRECT_EXACT_PATH_ALLOWLIST_ANCHOR_MISSING';
  end if;
  v_def := replace(v_def,v_anchor,v_replacement);
  execute v_def;
end;
$patch$;
;
