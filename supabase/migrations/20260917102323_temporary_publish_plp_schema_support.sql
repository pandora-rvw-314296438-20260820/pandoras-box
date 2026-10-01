create or replace function private.publish_plp_schema_support_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_token text;
  v_owner text := 'pandora-rvw-314296438-20260820';
  v_repo text := 'plp';
  v_branch text := 'feature/plp-temp-backend-20260917';
  v_main extensions.http_response;
  v_ref extensions.http_response;
  v_file extensions.http_response;
  v_put extensions.http_response;
  v_pr extensions.http_response;
  v_main_sha text;
  v_blob_sha text;
  v_old text;
  v_new text;
  v_headers extensions.http_header[];
  v_payload jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if v_token is null then return jsonb_build_object('ok',false,'stage','github_credential'); end if;
  v_headers := array[
    extensions.http_header('Accept','application/vnd.github+json'),
    extensions.http_header('Authorization','Bearer '||v_token),
    extensions.http_header('X-GitHub-Api-Version','2022-11-28'),
    extensions.http_header('User-Agent','Pandora-PLP-TempBackend/1.0')
  ];
  select * into v_main from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/'||v_owner||'/'||v_repo||'/git/ref/heads/main')::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_main.status<>200 then return jsonb_build_object('ok',false,'stage','main_ref','status',v_main.status); end if;
  v_main_sha := (v_main.content::jsonb)#>>'{object,sha}';
  if v_main_sha <> 'ea78ebcc43d76d018006287252e0a0a1ab2ff7e7' then return jsonb_build_object('ok',false,'stage','stale_main','mainSha',v_main_sha); end if;

  select * into v_ref from extensions.http(('POST'::extensions.http_method,('https://api.github.com/repos/'||v_owner||'/'||v_repo||'/git/refs')::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('ref','refs/heads/'||v_branch,'sha',v_main_sha)::text::varchar)::extensions.http_request);
  if v_ref.status not in (201,422) then return jsonb_build_object('ok',false,'stage','create_ref','status',v_ref.status); end if;

  select * into v_file from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/'||v_owner||'/'||v_repo||'/contents/api/_supabase.js?ref='||v_branch)::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_file.status<>200 then return jsonb_build_object('ok',false,'stage','get_file','status',v_file.status); end if;
  v_blob_sha := (v_file.content::jsonb)->>'sha';
  v_old := convert_from(decode(replace((v_file.content::jsonb)->>'content',E'\n',''),'base64'),'UTF8');
  if position('const SUPABASE_SCHEMA = process.env.PLP_SUPABASE_SCHEMA' in v_old)>0 then
    v_new := v_old;
  else
    if position('const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;' in v_old)=0 then return jsonb_build_object('ok',false,'stage','patch_anchor_1'); end if;
    if position('Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,' in v_old)=0 then return jsonb_build_object('ok',false,'stage','patch_anchor_2'); end if;
    v_new := replace(v_old,
      'const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;',
      'const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;'||E'\n'||'const SUPABASE_SCHEMA = process.env.PLP_SUPABASE_SCHEMA || ''public'';');
    v_new := replace(v_new,
      'Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,'||E'\n      '||'''Content-Type'': ''application/json'',',
      'Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,'||E'\n      '||'''Accept-Profile'': SUPABASE_SCHEMA,'||E'\n      '||'''Content-Profile'': SUPABASE_SCHEMA,'||E'\n      '||'''Content-Type'': ''application/json'',');
  end if;

  select * into v_put from extensions.http(('PUT'::extensions.http_method,('https://api.github.com/repos/'||v_owner||'/'||v_repo||'/contents/api/_supabase.js')::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,
    jsonb_build_object('message','feat(plp): route temporary backend through isolated Supabase schema','content',replace(encode(convert_to(v_new,'UTF8'),'base64'),E'\n',''),'sha',v_blob_sha,'branch',v_branch)::text::varchar)::extensions.http_request);
  if v_put.status not in (200,201) then return jsonb_build_object('ok',false,'stage','update_file','status',v_put.status); end if;

  select * into v_pr from extensions.http(('POST'::extensions.http_method,('https://api.github.com/repos/'||v_owner||'/'||v_repo||'/pulls')::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,
    jsonb_build_object('title','feat(plp): use isolated temporary Supabase backend','head',v_branch,'base','main','body','Routes PLP REST reads/writes through PLP_SUPABASE_SCHEMA using Accept-Profile/Content-Profile. Temporary backend is isolated in pandoras-box Supabase plp_runtime; no Pandora Memory or ProjectOS data is exposed.')::text::varchar)::extensions.http_request);
  if v_pr.status not in (201,422) then return jsonb_build_object('ok',false,'stage','create_pr','status',v_pr.status); end if;
  v_token:=null;
  return jsonb_build_object('ok',true,'branch',v_branch,'baseSha',v_main_sha,'commitSha',(v_put.content::jsonb)#>>'{commit,sha}','prNumber',case when v_pr.status=201 then (v_pr.content::jsonb)->>'number' else null end,'prStatus',v_pr.status);
end $fn$;
revoke all on function private.publish_plp_schema_support_20260917() from public,anon,authenticated;
