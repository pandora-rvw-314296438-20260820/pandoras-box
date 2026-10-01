
do $patch$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_def;

  v_old := E'  v_model_request jsonb;\n  v_model_env jsonb;\n  v_raw text;';
  v_new := E'  v_model_request jsonb;\n  v_model_env jsonb;\n  v_kimi_request jsonb;\n  v_model_used text := ''gemini-3.1-pro-preview'';\n  v_raw text;';
  if position(v_old in v_def)=0 then
    raise exception 'pandora_direct_box_provider_decl_anchor_missing' using errcode='55000';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := E'  v_model_env := public.pandora_worker_b_gemini_request_20260829(\n    ''gemini-3.1-pro-preview'',\n    v_model_request\n  );\n  if coalesce((v_model_env->>''status'')::integer,0) not between 200 and 299 then\n    raise exception ''pandora_direct_box_model_failed'';\n  end if;\n\n  v_raw := v_model_env->''body''->''candidates''->0->''content''->''parts''->0->>''text'';';
  v_new := E'  v_model_env := public.pandora_worker_b_gemini_request_20260829(\n    ''gemini-3.1-pro-preview'',\n    v_model_request\n  );\n\n  if coalesce((v_model_env->>''status'')::integer,0) between 200 and 299 then\n    v_raw := v_model_env->''body''->''candidates''->0->''content''->''parts''->0->>''text'';\n  else\n    v_model_used := ''kimi-k3'';\n    v_kimi_request := jsonb_build_object(\n      ''messages'',jsonb_build_array(\n        jsonb_build_object(''role'',''system'',''content'',v_model_request #>> ''{systemInstruction,parts,0,text}''),\n        jsonb_build_object(''role'',''user'',''content'',v_model_request #>> ''{contents,0,parts,0,text}'')\n      ),\n      ''response_format'',jsonb_build_object(''type'',''json_object''),\n      ''reasoning_effort'',''high'',\n      ''max_completion_tokens'',10000,\n      ''stream'',false\n    );\n    v_model_env := public.pandora_kimi_chat_request_v1(''kimi-k3'',v_kimi_request);\n    if coalesce((v_model_env->>''status'')::integer,0) not between 200 and 299\n       or coalesce((v_model_env->>''ok'')::boolean,false)<>true then\n      raise exception ''pandora_direct_box_model_failed'';\n    end if;\n    v_raw := v_model_env->''body''->''choices''->0->''message''->>''content'';\n  end if;';
  if position(v_old in v_def)=0 then
    raise exception 'pandora_direct_box_provider_block_anchor_missing' using errcode='55000';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := E'''pandora_direct_github'',''gemini-3.1-pro-preview''';
  v_new := E'''pandora_direct_github'',v_model_used';
  if position(v_old in v_def)=0 then
    raise exception 'pandora_direct_box_model_audit_anchor_missing' using errcode='55000';
  end if;
  v_def := replace(v_def,v_old,v_new);

  execute v_def;
end
$patch$;

revoke all on function private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)
  from public,anon,authenticated;

do $contract$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'private.pandora_direct_box_code_edit_v1(uuid,text,uuid,uuid)'::regprocedure
  ) into v_definition;
  if position('pandora_kimi_chat_request_v1' in v_definition)=0
     or position('v_model_used' in v_definition)=0 then
    raise exception 'pandora_direct_box_provider_fallback_missing' using errcode='55000';
  end if;
end
$contract$;

