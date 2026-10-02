
do $patch$
declare
  v_def text;
  v_anchor text := $$jsonb_build_object('role','user','content',v_model_request #>> '{contents,0,parts,0,text}')$$;
  v_replacement text := $$jsonb_build_object(
          'role','user',
          'content',replace(
            v_model_request #>> '{contents,0,parts,0,text}',
            'Bearer resource_metadata',
            'Protected-resource challenge metadata'
          )
        )$$;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_def;
  if position(v_replacement in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def)=0 then
    raise exception 'PANDORA_DIRECT_KIMI_SANITIZER_ANCHOR_MISSING';
  end if;
  v_def := replace(v_def,v_anchor,v_replacement);
  execute v_def;
end;
$patch$;
;
