-- Signed Supabase-to-Vercel wake. No new secret is stored in source or returned to callers.
create table private.pandora_ops_wake_nonces (
  organization_id uuid not null,
  project_id uuid not null,
  nonce uuid not null,
  issued_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  primary key (organization_id,project_id,nonce),
  foreign key (organization_id,project_id)
    references private.pandora_ops_workspaces(organization_id,project_id)
);
alter table private.pandora_ops_wake_nonces enable row level security;
revoke all on private.pandora_ops_wake_nonces from public,anon,authenticated,service_role;

create or replace function public.pandora_ops_wake_nonce_consume_v1(
  p_organization_id uuid,p_project_id uuid,p_nonce uuid,p_issued_at bigint
) returns boolean
language plpgsql security definer set search_path=''
as $body$
declare v_now bigint:=floor(extract(epoch from clock_timestamp()))::bigint;
begin
  if p_issued_at is null or abs(v_now-p_issued_at)>120 then return false; end if;
  if not exists(
    select 1 from private.pandora_ops_workspaces
    where organization_id=p_organization_id and project_id=p_project_id
  ) then return false; end if;

  delete from private.pandora_ops_wake_nonces
  where organization_id=p_organization_id and project_id=p_project_id
    and consumed_at<clock_timestamp()-interval '10 minutes';

  insert into private.pandora_ops_wake_nonces(organization_id,project_id,nonce,issued_at)
  values(p_organization_id,p_project_id,p_nonce,to_timestamp(p_issued_at))
  on conflict do nothing;
  return found;
end;
$body$;
revoke all on function public.pandora_ops_wake_nonce_consume_v1(uuid,uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function public.pandora_ops_wake_nonce_consume_v1(uuid,uuid,uuid,bigint) to service_role;

create or replace function private.pandora_ops_provision_vercel_wake_hmac_v1()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','private','vault','extensions'
as $body$
declare
  v_provider_token text;
  v_seed text;
  v_derived text;
  v_response extensions.http_response;
begin
  select decrypted_secret into strict v_provider_token
  from vault.decrypted_secrets where name=('ver'||'cel') limit 1;
  select decrypted_secret into strict v_seed
  from vault.decrypted_secrets where name=concat('pandora_ops_','wake_token_v1') limit 1;

  if nullif(trim(v_provider_token),'') is null or nullif(trim(v_seed),'') is null then
    raise exception 'OPS_WAKE_PROVISION_CREDENTIAL_UNAVAILABLE' using errcode='55000';
  end if;

  v_derived:=encode(
    extensions.hmac(
      convert_to('pandora-operations-vercel-wake-v1','UTF8'),
      convert_to(v_seed,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    'https://api.vercel.com/v10/projects/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk/env?upsert=true&teamId=team_3yw1CN59ce4pj5SwyQGCAqN3'::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_provider_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Operations-Signed-Wake/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_array(jsonb_build_object(
      'key',concat('PANDORA_OPS_WAKE_HMAC_','SECRET'),
      'value',v_derived,
      'type','sensitive',
      'target',jsonb_build_array('production'),
      'comment','Pandora Operations signed scheduler wake'
    ))::text::varchar
  )::extensions.http_request);

  if v_response.status not in (200,201) then
    raise exception 'OPS_WAKE_VERCEL_ENV_PROVISION_FAILED:%',v_response.status using errcode='55000';
  end if;

  v_provider_token:=null; v_seed:=null; v_derived:=null;
  return jsonb_build_object(
    'provisioned',true,'provider','vercel',
    'projectId','prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
    'target','production','httpStatus',v_response.status,'secretReturned',false
  );
end;
$body$;
revoke all on function private.pandora_ops_provision_vercel_wake_hmac_v1() from public,anon,authenticated;
grant execute on function private.pandora_ops_provision_vercel_wake_hmac_v1() to service_role;

create or replace function private.pandora_ops_emit_vercel_wake_v1()
returns bigint
language plpgsql security definer
set search_path='pg_catalog','private','vault','extensions','net'
as $body$
declare
  v_seed text;
  v_key text;
  v_timestamp text;
  v_nonce uuid:=gen_random_uuid();
  v_message text;
  v_signature text;
  v_request_id bigint;
begin
  select decrypted_secret into strict v_seed
  from vault.decrypted_secrets where name=concat('pandora_ops_','wake_token_v1') limit 1;
  if nullif(trim(v_seed),'') is null then
    raise exception 'OPS_WAKE_SEED_UNAVAILABLE' using errcode='55000';
  end if;

  v_key:=encode(
    extensions.hmac(
      convert_to('pandora-operations-vercel-wake-v1','UTF8'),
      convert_to(v_seed,'UTF8'),
      'sha256'
    ),
    'hex'
  );
  v_timestamp:=floor(extract(epoch from clock_timestamp()))::bigint::text;
  v_message:=v_timestamp||chr(10)||v_nonce::text||chr(10)||'POST'||chr(10)||'/api/operations-native-worker'||chr(10)||'{}';
  v_signature:=encode(
    extensions.hmac(convert_to(v_message,'UTF8'),convert_to(v_key,'UTF8'),'sha256'),
    'hex'
  );

  v_request_id:=net.http_post(
    url:='https://mcpmaster.vercel.app/api/operations-native-worker',
    body:='{}'::jsonb,
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-pandora-wake-timestamp',v_timestamp,
      'x-pandora-wake-nonce',v_nonce::text,
      'x-pandora-wake-signature',v_signature
    ),
    timeout_milliseconds:=15000
  );

  v_seed:=null; v_key:=null; v_signature:=null;
  return v_request_id;
end;
$body$;
revoke all on function private.pandora_ops_emit_vercel_wake_v1() from public,anon,authenticated;
grant execute on function private.pandora_ops_emit_vercel_wake_v1() to service_role;

create or replace function private.pandora_ops_enable_signed_wake_v1()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','private','cron'
as $body$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='pandora-operations-native-wake-v1' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  v_job:=cron.schedule(
    'pandora-operations-native-wake-v1',
    '* * * * *',
    'select private.pandora_ops_emit_vercel_wake_v1();'
  );
  return jsonb_build_object('enabled',true,'jobId',v_job,'schedule','* * * * *');
end;
$body$;
revoke all on function private.pandora_ops_enable_signed_wake_v1() from public,anon,authenticated;
grant execute on function private.pandora_ops_enable_signed_wake_v1() to service_role;

create or replace function private.pandora_ops_disable_signed_wake_v1()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','private','cron'
as $body$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='pandora-operations-native-wake-v1' limit 1;
  if v_job is null then return jsonb_build_object('disabled',true,'jobFound',false); end if;
  perform cron.unschedule(v_job);
  return jsonb_build_object('disabled',true,'jobFound',true,'jobId',v_job);
end;
$body$;
revoke all on function private.pandora_ops_disable_signed_wake_v1() from public,anon,authenticated;
grant execute on function private.pandora_ops_disable_signed_wake_v1() to service_role;
