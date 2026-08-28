
-- Worker D Vercel Sandbox provider boundary.
-- The Vercel credential remains only in Supabase Vault secret `vercel` and is never returned.

insert into public.pandora_runtime_provider_configs(provider, config_key, config_value, active)
values ('vercel', 'worker_d_sandbox_project_id', 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk', true)
on conflict (provider, config_key) do update
set config_value=excluded.config_value, active=excluded.active, updated_at=now();

create or replace function private.pandora_worker_d_vercel_sandbox_api_20260829(
  p_method text,
  p_path text,
  p_body jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
declare
  v_token text;
  v_team_id text;
  v_project_id text;
  v_method extensions.http_method;
  v_response extensions.http_response;
  v_body jsonb;
  v_url text;
  v_base text;
  v_env_key text;
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST','DELETE') then
    raise exception 'unsupported Worker D Vercel Sandbox method' using errcode='22023';
  end if;
  if p_path is null or p_path like '%..%' or p_path ~ E'[\r\n]' or length(p_path)>1200 then
    raise exception 'invalid Worker D Vercel Sandbox path' using errcode='22023';
  end if;
  if p_body is not null and octet_length(p_body::text)>262144 then
    raise exception 'Worker D Vercel Sandbox body too large' using errcode='22023';
  end if;

  select config_value into strict v_team_id from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true;
  select config_value into strict v_project_id from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='worker_d_sandbox_project_id' and active=true;

  if not (p_path ~ ('[?&]teamId='||v_team_id||'(&|$)')) then
    raise exception 'Worker D Vercel Sandbox request is not team scoped' using errcode='22023';
  end if;
  v_base:=split_part(p_path,'?',1);

  if not (
    (upper(p_method)='POST' and v_base='/v2/sandboxes')
    or (upper(p_method) in ('GET','DELETE') and v_base ~ '^/v2/sandboxes/pandora-d-[a-f0-9]{1,32}$')
    or (upper(p_method)='POST' and v_base ~ '^/v2/sandboxes/sessions/sbx_[A-Za-z0-9]+/cmd$')
    or (upper(p_method)='GET' and v_base ~ '^/v2/sandboxes/sessions/sbx_[A-Za-z0-9]+/cmd/cmd_[A-Za-z0-9]+$')
    or (upper(p_method)='POST' and v_base ~ '^/v2/sandboxes/sessions/sbx_[A-Za-z0-9]+/cmd/cmd_[A-Za-z0-9]+/kill$')
    or (upper(p_method)='POST' and v_base ~ '^/v2/sandboxes/sessions/sbx_[A-Za-z0-9]+/stop$')
  ) then
    raise exception 'Vercel Sandbox path outside Worker D lane' using errcode='22023';
  end if;

  if upper(p_method)='POST' and v_base='/v2/sandboxes' then
    if p_body is null
       or p_body->>'projectId'<>v_project_id
       or p_body->>'runtime'<>'node24'
       or coalesce((p_body->>'persistent')::boolean,true)
       or jsonb_typeof(coalesce(p_body->'env','{}'::jsonb))<>'object'
       or coalesce(jsonb_object_length(coalesce(p_body->'env','{}'::jsonb)),0)<>0
       or jsonb_typeof(coalesce(p_body->'ports','[]'::jsonb))<>'array'
       or jsonb_array_length(coalesce(p_body->'ports','[]'::jsonb))<>0
       or coalesce(p_body->'networkPolicy'->>'mode','') not in ('deny-all','custom') then
      raise exception 'unsafe Worker D Vercel Sandbox create request' using errcode='22023';
    end if;
    if p_body->'networkPolicy'->>'mode'='custom' and (
      jsonb_typeof(coalesce(p_body->'networkPolicy'->'allowedDomains','[]'::jsonb))<>'array'
      or jsonb_array_length(coalesce(p_body->'networkPolicy'->'allowedDomains','[]'::jsonb))>64
      or jsonb_array_length(coalesce(p_body->'networkPolicy'->'allowedCIDRs','[]'::jsonb))<>0
    ) then
      raise exception 'unsafe Worker D Vercel Sandbox network policy' using errcode='22023';
    end if;
  end if;

  if upper(p_method)='POST' and v_base ~ '/cmd$' then
    if p_body is null
       or coalesce((p_body->>'sudo')::boolean,true)
       or coalesce((p_body->>'wait')::boolean,true)
       or coalesce((p_body->>'logs')::boolean,true)
       or coalesce(p_body->>'command','') ~* '^(sh|bash|zsh|cmd|cmd\.exe|powershell|powershell\.exe|pwsh)$'
       or jsonb_typeof(coalesce(p_body->'args','[]'::jsonb))<>'array'
       or jsonb_array_length(coalesce(p_body->'args','[]'::jsonb))>128
       or jsonb_typeof(coalesce(p_body->'env','{}'::jsonb))<>'object' then
      raise exception 'unsafe Worker D Vercel Sandbox command' using errcode='22023';
    end if;
    for v_env_key in select jsonb_object_keys(coalesce(p_body->'env','{}'::jsonb)) loop
      if v_env_key ~* '(^|_)(TOKEN|SECRET|PASSWORD|API_KEY|PRIVATE_KEY|AUTHORIZATION|COOKIE)($|_)' then
        raise exception 'credential-shaped environment field rejected' using errcode='22023';
      end if;
    end loop;
  end if;

  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='vercel' limit 1;
  if nullif(trim(v_token),'') is null then raise exception 'Vercel provider credential unavailable' using errcode='55000'; end if;

  v_method:=upper(p_method)::extensions.http_method;
  v_url:='https://api.vercel.com'||p_path;
  select * into v_response from extensions.http((
    v_method,v_url::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-D-Sandbox/1.0')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);

  begin v_body:=nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body:=case when nullif(v_response.content,'') is null then null else jsonb_build_object('raw',left(v_response.content,5000)) end;
  end;
  return jsonb_build_object('status',v_response.status,'contentType',v_response.content_type,'body',v_body);
end;
$$;

revoke all on function private.pandora_worker_d_vercel_sandbox_api_20260829(text,text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_worker_d_vercel_sandbox_api_20260829(text,text,jsonb) to service_role;

create or replace function public.pandora_worker_d_vercel_sandbox_request_20260829(
  p_method text,p_path text,p_body jsonb default null
)
returns jsonb
language sql
security definer
set search_path=''
as $$ select private.pandora_worker_d_vercel_sandbox_api_20260829(p_method,p_path,p_body); $$;
revoke all on function public.pandora_worker_d_vercel_sandbox_request_20260829(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_worker_d_vercel_sandbox_request_20260829(text,text,jsonb) to service_role;
