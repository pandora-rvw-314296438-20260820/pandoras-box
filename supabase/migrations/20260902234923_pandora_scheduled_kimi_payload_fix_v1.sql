create or replace function private.pandora_scheduled_model_worker_tick_v1(p_limit integer default 4)
returns integer
language plpgsql
security definer
set search_path = 'pg_catalog','private','public'
as $function$
declare
  r record;
  v_envelope jsonb;
  v_text text;
  v_status integer;
  v_done integer := 0;
  v_error text;
begin
  if p_limit < 1 or p_limit > 8 then
    raise exception 'invalid worker tick limit' using errcode='22023';
  end if;
  for r in
    select id, provider, task_label, prompt, attempt_count
    from private.pandora_scheduled_model_worker_jobs
    where status='queued' and attempt_count < 3
    order by created_at
    for update skip locked
    limit p_limit
  loop
    update private.pandora_scheduled_model_worker_jobs
      set status='running', started_at=clock_timestamp(), attempt_count=attempt_count+1, error_code=null
      where id=r.id;
    begin
      v_envelope := null; v_text := null; v_status := 0;
      if r.provider='kimi' then
        v_envelope := public.pandora_kimi_chat_request_v1(
          'kimi-k3',
          jsonb_build_object(
            'messages', jsonb_build_array(
              jsonb_build_object('role','system','content','You are Kimi, an implementation worker for Pandora. Return concise technical work product only. Never request or reveal secrets.'),
              jsonb_build_object('role','user','content',r.prompt)
            ),
            'max_completion_tokens',4096,
            'stream',false
          )
        );
        v_status := coalesce((v_envelope->>'status')::integer,0);
        if coalesce((v_envelope->>'ok')::boolean,false) and v_status between 200 and 299 then
          v_text := v_envelope #>> '{body,choices,0,message,content}';
        else
          v_error := coalesce(v_envelope #>> '{error,kind}','KIMI_PROVIDER_FAILED');
          raise exception '%', v_error;
        end if;
      else
        v_envelope := public.pandora_worker_b_gemini_request_20260829(
          'gemini-3.5-flash-lite',
          jsonb_build_object(
            'systemInstruction',jsonb_build_object('parts',jsonb_build_array(jsonb_build_object('text','You are Gemini, an implementation worker for Pandora. Return concise technical work product only. Never request or reveal secrets.'))),
            'contents',jsonb_build_array(jsonb_build_object('role','user','parts',jsonb_build_array(jsonb_build_object('text',r.prompt)))),
            'generationConfig',jsonb_build_object('temperature',0.1,'maxOutputTokens',4096)
          )
        );
        v_status := coalesce((v_envelope->>'status')::integer,0);
        if v_status between 200 and 299 then
          v_text := v_envelope #>> '{body,candidates,0,content,parts,0,text}';
        else
          raise exception 'GEMINI_PROVIDER_FAILED';
        end if;
      end if;
      v_text := trim(coalesce(v_text,''));
      if not private.pandora_scheduled_model_worker_output_safe_v1(v_text) then
        raise exception 'MODEL_OUTPUT_REJECTED';
      end if;
      update private.pandora_scheduled_model_worker_jobs
        set status='succeeded', response_text=v_text, error_code=null, completed_at=clock_timestamp()
        where id=r.id;
      v_done := v_done + 1;
    exception when others then
      v_error := left(regexp_replace(coalesce(sqlerrm,'MODEL_WORKER_FAILED'),'[^A-Za-z0-9_.:-]+','_','g'),120);
      update private.pandora_scheduled_model_worker_jobs
        set status=case when attempt_count >= 3 then 'failed' else 'queued' end,
            response_text=null,
            error_code=v_error,
            completed_at=case when attempt_count >= 3 then clock_timestamp() else null end
        where id=r.id;
    end;
  end loop;
  return v_done;
end;
$function$;

revoke all on function private.pandora_scheduled_model_worker_tick_v1(integer) from public, anon, authenticated;
grant execute on function private.pandora_scheduled_model_worker_tick_v1(integer) to service_role;