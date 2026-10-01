
do $patch$
declare
  v_def text;
  v_old text := $$replace(
            v_model_request #>> '{contents,0,parts,0,text}',
            'Bearer resource_metadata',
            'Protected-resource challenge metadata'
          )$$;
  v_new text := $$regexp_replace(
            replace(
              v_model_request #>> '{contents,0,parts,0,text}',
              'Bearer resource_metadata',
              'Protected-resource challenge metadata'
            ),
            'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}',
            'Bearer <redacted-test-token>',
            'g'
          )$$;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_def;
  if position(v_new in v_def)>0 then return; end if;
  if position(v_old in v_def)=0 then
    raise exception 'PANDORA_DIRECT_BEARER_SANITIZER_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch$;

