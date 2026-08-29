-- Worker F Vercel webhook and reconciliation ingress.
-- Provider access and webhook signing secrets remain in Supabase Vault and are never returned.

create index if not exists pandora_runtime_provider_events_project_received_idx
  on public.pandora_runtime_provider_events(project_id, received_at desc)
  where project_id is not null;
create index if not exists pandora_runtime_provider_events_provider_resource_idx
  on public.pandora_runtime_provider_events(provider, provider_resource_id, received_at desc)
  where provider_resource_id is not null;
create index if not exists pandora_runtime_provider_events_status_received_idx
  on public.pandora_runtime_provider_events(status, received_at)
  where status in ('received','failed');

create or replace function private.pandora_worker_f_constant_time_sha1_equal_20260829(
  p_expected bytea,
  p_signature text
)
returns boolean
language plpgsql
immutable
strict
set search_path='pg_catalog'
as $$
declare
  v_provided bytea;
  v_diff integer := 0;
  i integer;
begin
  if octet_length(p_expected) <> 20 or p_signature !~ '^[0-9A-Fa-f]{40}$' then
    return false;
  end if;
  begin
    v_provided := decode(lower(p_signature), 'hex');
  exception when others then
    return false;
  end;
  if octet_length(v_provided) <> 20 then return false; end if;
  for i in 0..19 loop
    v_diff := v_diff | (get_byte(p_expected, i) # get_byte(v_provided, i));
  end loop;
  return v_diff = 0;
end;
$$;

create or replace function private.pandora_worker_f_ingest_vercel_webhook_20260829(
  p_raw_body text,
  p_signature text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
declare
  v_secret text;
  v_expected bytea;
  v_payload jsonb;
  v_payload_data jsonb := '{}'::jsonb;
  v_payload_sha text;
  v_event_id text;
  v_event_type text;
  v_provider_project_id text;
  v_provider_resource_id text;
  v_region text;
  v_target text;
  v_ready_state text;
  v_occurred_at timestamptz;
  v_org uuid;
  v_project uuid;
  v_mapping_count integer := 0;
  v_supported boolean := false;
  v_status text := 'received';
  v_inserted_id uuid;
  v_existing_sha text;
  v_existing_status text;
begin
  if p_raw_body is null or octet_length(p_raw_body) < 2 or octet_length(p_raw_body) > 524288 then
    return jsonb_build_object('accepted', false, 'reason', 'body_invalid');
  end if;
  if p_signature is null or p_signature !~ '^[0-9A-Fa-f]{40}$' then
    return jsonb_build_object('accepted', false, 'reason', 'signature_invalid');
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name='pandora_vercel_runtime_webhook_signing'
  limit 1;
  if nullif(v_secret,'') is null then
    raise exception 'Vercel webhook signing secret unavailable' using errcode='55000';
  end if;

  v_expected := extensions.hmac(convert_to(p_raw_body,'utf8'), convert_to(v_secret,'utf8'), 'sha1');
  if not private.pandora_worker_f_constant_time_sha1_equal_20260829(v_expected, p_signature) then
    return jsonb_build_object('accepted', false, 'reason', 'signature_invalid');
  end if;

  v_payload_sha := encode(extensions.digest(convert_to(p_raw_body,'utf8'),'sha256'),'hex');
  begin
    v_payload := p_raw_body::jsonb;
  exception when others then
    v_event_id := 'invalid:'||substr(v_payload_sha,1,32);
    insert into public.pandora_runtime_provider_events(
      provider,provider_event_id,event_type,payload_sha256,safe_summary,status
    ) values (
      'vercel',v_event_id,'invalid_json',v_payload_sha,jsonb_build_object('reason','invalid_json'),'rejected'
    ) on conflict(provider,provider_event_id) do nothing;
    return jsonb_build_object('accepted', true, 'eventId', v_event_id, 'status', 'rejected');
  end;

  if jsonb_typeof(v_payload) <> 'object' then
    v_event_id := 'invalid:'||substr(v_payload_sha,1,32);
    insert into public.pandora_runtime_provider_events(provider,provider_event_id,event_type,payload_sha256,safe_summary,status)
    values('vercel',v_event_id,'invalid_payload',v_payload_sha,jsonb_build_object('reason','payload_not_object'),'rejected')
    on conflict(provider,provider_event_id) do nothing;
    return jsonb_build_object('accepted', true, 'eventId', v_event_id, 'status', 'rejected');
  end if;

  v_event_id := nullif(left(coalesce(v_payload->>'id',''),200),'');
  v_event_type := nullif(left(coalesce(v_payload->>'type',''),160),'');
  if v_event_id is null or v_event_type is null then
    v_event_id := coalesce(v_event_id,'invalid:'||substr(v_payload_sha,1,32));
    insert into public.pandora_runtime_provider_events(provider,provider_event_id,event_type,payload_sha256,safe_summary,status)
    values('vercel',v_event_id,coalesce(v_event_type,'invalid_event'),v_payload_sha,jsonb_build_object('reason','event_identity_missing'),'rejected')
    on conflict(provider,provider_event_id) do nothing;
    return jsonb_build_object('accepted', true, 'eventId', v_event_id, 'status', 'rejected');
  end if;

  if jsonb_typeof(v_payload->'payload')='object' then v_payload_data := v_payload->'payload'; end if;
  v_provider_project_id := nullif(left(coalesce(
    v_payload_data->'project'->>'id',
    v_payload_data->>'projectId',
    v_payload_data->'deployment'->>'projectId',
    v_payload_data->'deployment'->'project'->>'id',
    ''),200),'');
  v_provider_resource_id := nullif(left(coalesce(
    v_payload_data->'deployment'->>'id',
    v_payload_data->>'deploymentId',
    v_payload_data->'deployment'->>'uid',
    ''),200),'');
  v_region := nullif(left(coalesce(v_payload->>'region',''),80),'');
  v_target := nullif(left(coalesce(v_payload_data->'deployment'->>'target',v_payload_data->>'target',''),80),'');
  v_ready_state := nullif(left(coalesce(v_payload_data->'deployment'->>'readyState',v_payload_data->>'readyState',''),80),'');

  begin
    if (v_payload->>'createdAt') ~ '^\d{10,16}$' then
      v_occurred_at := to_timestamp((v_payload->>'createdAt')::numeric / 1000.0);
    end if;
  exception when others then
    v_occurred_at := null;
  end;

  v_supported := v_event_type in ('deployment.created','deployment.ready','deployment.error','deployment.promoted');

  if v_provider_project_id is not null then
    select count(*) into v_mapping_count
    from (
      select distinct organization_id,project_id
      from public.pandora_runtime_environments
      where provider='vercel' and provider_project_id=v_provider_project_id
    ) mapped;
    if v_mapping_count=1 then
      select organization_id,project_id into v_org,v_project
      from public.pandora_runtime_environments
      where provider='vercel' and provider_project_id=v_provider_project_id
      order by updated_at desc
      limit 1;
    end if;
  end if;

  if not v_supported or v_mapping_count<>1 then v_status := 'ignored'; end if;

  insert into public.pandora_runtime_provider_events(
    provider,provider_event_id,event_type,organization_id,project_id,provider_project_id,
    provider_resource_id,payload_sha256,safe_summary,provider_occurred_at,status
  ) values (
    'vercel',v_event_id,v_event_type,v_org,v_project,v_provider_project_id,v_provider_resource_id,v_payload_sha,
    jsonb_strip_nulls(jsonb_build_object(
      'region',v_region,
      'target',v_target,
      'readyState',v_ready_state,
      'mapped',v_mapping_count=1,
      'supported',v_supported
    )),
    v_occurred_at,v_status
  )
  on conflict(provider,provider_event_id) do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    select payload_sha256,status into v_existing_sha,v_existing_status
    from public.pandora_runtime_provider_events
    where provider='vercel' and provider_event_id=v_event_id;
    if v_existing_sha is distinct from v_payload_sha then
      update public.pandora_runtime_provider_events
      set status='rejected',
          safe_summary=safe_summary||jsonb_build_object('replayMismatch',true)
      where provider='vercel' and provider_event_id=v_event_id;
      return jsonb_build_object('accepted', true, 'eventId',v_event_id,'duplicate',true,'status','rejected');
    end if;
    return jsonb_build_object('accepted', true, 'eventId',v_event_id,'duplicate',true,'status',v_existing_status);
  end if;

  return jsonb_build_object('accepted', true, 'eventId',v_event_id,'duplicate',false,'status',v_status);
end;
$$;

revoke all on function private.pandora_worker_f_ingest_vercel_webhook_20260829(text,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_ingest_vercel_webhook_20260829(text,text) to service_role;

create or replace function public.pandora_worker_f_ingest_vercel_webhook_20260829(
  p_raw_body text,
  p_signature text
)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select private.pandora_worker_f_ingest_vercel_webhook_20260829(p_raw_body,p_signature);
$$;
revoke all on function public.pandora_worker_f_ingest_vercel_webhook_20260829(text,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_ingest_vercel_webhook_20260829(text,text) to service_role;

create or replace function private.pandora_worker_f_ensure_vercel_webhook_20260829(
  p_webhook_url text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
declare
  v_token text;
  v_team_id text;
  v_response extensions.http_response;
  v_body jsonb;
  v_existing jsonb;
  v_existing_id text;
  v_secret_id uuid;
  v_signing_secret text;
  v_webhook_id text;
  v_events jsonb := '["deployment.created","deployment.ready","deployment.error","deployment.promoted"]'::jsonb;
begin
  if p_webhook_url <> 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-vercel-runtime-webhook' then
    raise exception 'invalid Worker F webhook URL' using errcode='22023';
  end if;
  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true;
  select decrypted_secret into strict v_token
  from vault.decrypted_secrets where name='vercel' limit 1;
  if nullif(v_token,'') is null then raise exception 'Vercel provider credential unavailable' using errcode='55000'; end if;

  select * into v_response from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.vercel.com/v1/webhooks?teamId='||v_team_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('user-agent','Pandora-Worker-F-Webhook/1.0')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  if v_response.status<>200 then raise exception 'Vercel webhook list failed: %',v_response.status using errcode='55000'; end if;
  begin v_body:=coalesce(nullif(v_response.content,'')::jsonb,'[]'::jsonb); exception when others then raise exception 'Vercel webhook list returned invalid JSON' using errcode='55000'; end;
  if jsonb_typeof(v_body)<>'array' then raise exception 'Vercel webhook list shape invalid' using errcode='55000'; end if;
  select item into v_existing
  from jsonb_array_elements(v_body) item
  where item->>'url'=p_webhook_url
  order by coalesce((item->>'updatedAt')::bigint,0) desc
  limit 1;
  v_existing_id:=nullif(coalesce(v_existing->>'id',''),'');
  select id into v_secret_id from vault.secrets where name='pandora_vercel_runtime_webhook_signing' limit 1;

  if v_existing_id is not null and v_secret_id is not null then
    insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active)
    values ('vercel','runtime_webhook_id',v_existing_id,true),('vercel','runtime_webhook_url',p_webhook_url,true)
    on conflict(provider,config_key) do update set config_value=excluded.config_value,active=true,updated_at=now();
    return jsonb_build_object('configured',true,'reused',true,'webhookId',v_existing_id,'url',p_webhook_url,'events',v_events);
  end if;

  if v_existing_id is not null then
    select * into v_response from extensions.http((
      'DELETE'::extensions.http_method,
      ('https://api.vercel.com/v1/webhooks/'||v_existing_id||'?teamId='||v_team_id)::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('user-agent','Pandora-Worker-F-Webhook/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    if v_response.status not in (200,204) then raise exception 'Vercel stale webhook delete failed: %',v_response.status using errcode='55000'; end if;
  end if;

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    ('https://api.vercel.com/v1/webhooks?teamId='||v_team_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-F-Webhook/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_object('url',p_webhook_url,'events',v_events)::text::varchar
  )::extensions.http_request);
  if v_response.status not in (200,201) then raise exception 'Vercel webhook create failed: %',v_response.status using errcode='55000'; end if;
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then raise exception 'Vercel webhook create returned invalid JSON' using errcode='55000'; end;
  v_webhook_id:=nullif(coalesce(v_body->>'id',''),'');
  v_signing_secret:=nullif(coalesce(v_body->>'secret',''),'');
  if v_webhook_id is null or v_signing_secret is null then raise exception 'Vercel webhook response missing identity or signing secret' using errcode='55000'; end if;

  select id into v_secret_id from vault.secrets where name='pandora_vercel_runtime_webhook_signing' limit 1;
  if v_secret_id is null then
    perform vault.create_secret(v_signing_secret,'pandora_vercel_runtime_webhook_signing','Worker F Vercel webhook signing secret',null);
  else
    perform vault.update_secret(v_secret_id,v_signing_secret,'pandora_vercel_runtime_webhook_signing','Worker F Vercel webhook signing secret',null);
  end if;

  insert into public.pandora_runtime_provider_configs(provider,config_key,config_value,active)
  values ('vercel','runtime_webhook_id',v_webhook_id,true),('vercel','runtime_webhook_url',p_webhook_url,true)
  on conflict(provider,config_key) do update set config_value=excluded.config_value,active=true,updated_at=now();

  v_signing_secret:=null;
  v_token:=null;
  return jsonb_build_object('configured',true,'reused',false,'webhookId',v_webhook_id,'url',p_webhook_url,'events',v_events);
end;
$$;

revoke all on function private.pandora_worker_f_ensure_vercel_webhook_20260829(text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_ensure_vercel_webhook_20260829(text) to service_role;

create or replace function public.pandora_worker_f_ensure_vercel_webhook_20260829(p_webhook_url text)
returns jsonb
language sql
security definer
set search_path=''
as $$ select private.pandora_worker_f_ensure_vercel_webhook_20260829(p_webhook_url); $$;
revoke all on function public.pandora_worker_f_ensure_vercel_webhook_20260829(text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_ensure_vercel_webhook_20260829(text) to service_role;
