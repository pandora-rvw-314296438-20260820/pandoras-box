create schema if not exists private;

create table if not exists private.pandora_scheduled_model_worker_jobs (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('kimi','gemini')),
  task_label text not null check (char_length(task_label) between 1 and 160),
  prompt text not null check (char_length(prompt) between 1 and 16000),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed')),
  response_text text,
  error_code text,
  attempt_count integer not null default 0 check (attempt_count between 0 and 3),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  constraint pandora_scheduled_model_worker_response_bound check (response_text is null or octet_length(response_text) <= 65536),
  constraint pandora_scheduled_model_worker_error_bound check (error_code is null or char_length(error_code) <= 120)
);

revoke all on private.pandora_scheduled_model_worker_jobs from public, anon, authenticated;
grant select, insert, update on private.pandora_scheduled_model_worker_jobs to service_role;

create index if not exists pandora_scheduled_model_worker_jobs_queue_idx
  on private.pandora_scheduled_model_worker_jobs(status, created_at)
  where status='queued';

create or replace function private.pandora_scheduled_model_worker_output_safe_v1(p_text text)
returns boolean
language sql
immutable
set search_path = 'pg_catalog'
as $function$
  select p_text is not null
    and octet_length(p_text) between 1 and 65536
    and p_text !~* '(MOONSHOT|KIMI|GEMINI|GOOGLE)[_-]?API[_-]?KEY[[:space:]]*[:=]'
    and p_text !~ 'AIza[0-9A-Za-z_-]{20,}'
    and p_text !~ 'sk-[A-Za-z0-9_-]{20,}'
    and p_text !~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
    and p_text !~ 'github_pat_[A-Za-z0-9_]{20,}'
    and p_text !~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    and p_text !~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@';
$function$;

revoke all on function private.pandora_scheduled_model_worker_output_safe_v1(text) from public, anon, authenticated;
grant execute on function private.pandora_scheduled_model_worker_output_safe_v1(text) to service_role;

create or replace function public.pandora_enqueue_scheduled_model_worker_v1(
  p_provider text,
  p_task_label text,
  p_prompt text
)
returns uuid
language plpgsql
security definer
set search_path = 'pg_catalog','private','public'
as $function$
declare
  v_id uuid;
  v_provider text := lower(trim(coalesce(p_provider,'')));
  v_task text := trim(coalesce(p_task_label,''));
  v_prompt text := trim(coalesce(p_prompt,''));
begin
  if v_provider not in ('kimi','gemini') then
    raise exception 'unsupported scheduled model worker provider' using errcode='22023';
  end if;
  if char_length(v_task) not between 1 and 160 then
    raise exception 'invalid scheduled worker task label' using errcode='22023';
  end if;
  if char_length(v_prompt) not between 1 and 16000 then
    raise exception 'invalid scheduled worker prompt' using errcode='22023';
  end if;
  if v_prompt ~* '(MOONSHOT|KIMI|GEMINI|GOOGLE)[_-]?API[_-]?KEY[[:space:]]*[:=]'
     or v_prompt ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_prompt ~ 'sk-[A-Za-z0-9_-]{20,}'
     or v_prompt ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_prompt ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_prompt ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
     or v_prompt ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
    raise exception 'credential material rejected from scheduled worker prompt' using errcode='22023';
  end if;
  insert into private.pandora_scheduled_model_worker_jobs(provider,task_label,prompt)
  values(v_provider,v_task,v_prompt)
  returning id into v_id;
  return v_id;
end;
$function$;

revoke all on function public.pandora_enqueue_scheduled_model_worker_v1(text,text,text) from public, anon, authenticated;
grant execute on function public.pandora_enqueue_scheduled_model_worker_v1(text,text,text) to service_role;

create or replace function public.pandora_scheduled_model_worker_result_v1(p_job_id uuid)
returns jsonb
language sql
security definer
set search_path = 'pg_catalog','private','public'
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'id',id,
    'provider',provider,
    'taskLabel',task_label,
    'status',status,
    'responseText',case when status='succeeded' then response_text else null end,
    'errorCode',error_code,
    'attemptCount',attempt_count,
    'createdAt',created_at,
    'startedAt',started_at,
    'completedAt',completed_at
  ))
  from private.pandora_scheduled_model_worker_jobs
  where id=p_job_id;
$function$;

revoke all on function public.pandora_scheduled_model_worker_result_v1(uuid) from public, anon, authenticated;
grant execute on function public.pandora_scheduled_model_worker_result_v1(uuid) to service_role;

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
      v_envelope := null;
      v_text := null;
      v_status := 0;
      if r.provider='kimi' then
        v_envelope := public.pandora_kimi_chat_request_v1(
          'kimi-k3',
          jsonb_build_object(
            'messages', jsonb_build_array(
              jsonb_build_object('role','system','content','You are Kimi, an implementation worker for Pandora. Return concise technical work product only. Never request or reveal secrets.'),
              jsonb_build_object('role','user','content',r.prompt)
            ),
            'temperature',0.1,
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

select cron.unschedule(jobid) from cron.job where jobname='pandora-scheduled-model-workers-v1';
select cron.schedule(
  'pandora-scheduled-model-workers-v1',
  '* * * * *',
  $cron$select private.pandora_scheduled_model_worker_tick_v1(4);$cron$
);