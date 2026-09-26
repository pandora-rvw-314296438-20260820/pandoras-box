-- Operations Room: provision a Vercel Cron secret without exposing it to clients or source.
create or replace function private.pandora_ops_provision_vercel_cron_secret_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions'
as $body$
declare
  v_vercel_token text;
  v_secret text;
  v_response extensions.http_response;
begin
  select decrypted_secret into strict v_vercel_token
  from vault.decrypted_secrets
  where name='vercel'
  limit 1;

  if nullif(trim(v_vercel_token),'') is null then
    raise exception 'OPS_VERCEL_PROVIDER_CREDENTIAL_UNAVAILABLE' using errcode='55000';
  end if;

  v_secret := rtrim(
    translate(encode(extensions.gen_random_bytes(48),'base64'),'+/','-_'),
    '='
  );

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    'https://api.vercel.com/v10/projects/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk/env?upsert=true&teamId=team_3yw1CN59ce4pj5SwyQGCAqN3'::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_vercel_token),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Operations-Cron-Provisioner/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_array(jsonb_build_object(
      'key','CRON_SECRET',
      'value',v_secret,
      'type','sensitive',
      'target',jsonb_build_array('production'),
      'comment','Pandora Operations native scheduler cron wake v1'
    ))::text::varchar
  )::extensions.http_request);

  if v_response.status not in (200,201) then
    raise exception 'OPS_VERCEL_CRON_SECRET_PROVISION_FAILED:%',v_response.status using errcode='55000';
  end if;

  v_secret := null;
  return jsonb_build_object(
    'provisioned',true,
    'provider','vercel',
    'projectId','prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
    'key','CRON_SECRET',
    'target','production',
    'httpStatus',v_response.status,
    'secretReturned',false
  );
end;
$body$;

revoke all on function private.pandora_ops_provision_vercel_cron_secret_v1() from public,anon,authenticated;
grant execute on function private.pandora_ops_provision_vercel_cron_secret_v1() to service_role;
