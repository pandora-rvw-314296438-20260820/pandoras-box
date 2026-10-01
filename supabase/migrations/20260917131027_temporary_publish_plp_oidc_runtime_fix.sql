create or replace function private.publish_plp_oidc_runtime_fix_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_token text; v_headers extensions.http_header[]; v_main extensions.http_response; v_ref extensions.http_response;
  v_file extensions.http_response; v_put1 extensions.http_response; v_put2 extensions.http_response; v_pr extensions.http_response;
  v_main_sha text; v_branch text:='fix/plp-vercel-oidc-runtime-20260917';
  v_js_sha text; v_pkg_sha text; v_js text; v_pkg jsonb; v_new_js text; v_new_pkg jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if v_token is null then return jsonb_build_object('ok',false,'stage','credential'); end if;
  v_headers:=array[extensions.http_header('Accept','application/vnd.github+json'),extensions.http_header('Authorization','Bearer '||v_token),extensions.http_header('X-GitHub-Api-Version','2022-11-28'),extensions.http_header('User-Agent','Pandora-PLP-OIDC-RuntimeFix/1.0')];
  select * into v_main from extensions.http(('GET'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/git/ref/heads/main'::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_main.status<>200 then return jsonb_build_object('ok',false,'stage','main_ref','status',v_main.status); end if;
  v_main_sha:=(v_main.content::jsonb)#>>'{object,sha}';
  if v_main_sha<>'ed90621bff03e554f7abd1c500a7aa23cb8c0bcc' then return jsonb_build_object('ok',false,'stage','stale_main','mainSha',v_main_sha); end if;
  select * into v_ref from extensions.http(('POST'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/git/refs'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('ref','refs/heads/'||v_branch,'sha',v_main_sha)::text::varchar)::extensions.http_request);
  if v_ref.status not in (201,422) then return jsonb_build_object('ok',false,'stage','create_ref','status',v_ref.status); end if;

  select * into v_file from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/api/_supabase.js?ref='||v_branch)::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_file.status<>200 then return jsonb_build_object('ok',false,'stage','get_js','status',v_file.status); end if;
  v_js_sha:=(v_file.content::jsonb)->>'sha';
  v_js:=convert_from(decode(replace((v_file.content::jsonb)->>'content',E'\n',''),'base64'),'UTF8');
  if position('getVercelOidcToken' in v_js)=0 then
    v_new_js:='import { getVercelOidcToken } from ''@vercel/oidc'';'||E'\n'||v_js;
  else v_new_js:=v_js; end if;
  v_new_js:=replace(v_new_js,
    'return Boolean(process.env.VERCEL_OIDC_TOKEN || (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY));',
    'return Boolean(process.env.VERCEL || process.env.VERCEL_ENV || process.env.VERCEL_OIDC_TOKEN || (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY));');
  v_new_js:=replace(v_new_js,
    '  const oidcToken = process.env.VERCEL_OIDC_TOKEN;',
    '  const oidcToken = process.env.VERCEL || process.env.VERCEL_ENV ? await getVercelOidcToken() : process.env.VERCEL_OIDC_TOKEN;');
  select * into v_put1 from extensions.http(('PUT'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/api/_supabase.js'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('message','fix(plp): use Vercel runtime OIDC token API','content',replace(encode(convert_to(v_new_js,'UTF8'),'base64'),E'\n',''),'sha',v_js_sha,'branch',v_branch)::text::varchar)::extensions.http_request);
  if v_put1.status not in (200,201) then return jsonb_build_object('ok',false,'stage','put_js','status',v_put1.status); end if;

  select * into v_file from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/package.json?ref='||v_branch)::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_file.status<>200 then return jsonb_build_object('ok',false,'stage','get_package','status',v_file.status); end if;
  v_pkg_sha:=(v_file.content::jsonb)->>'sha';
  v_pkg:=convert_from(decode(replace((v_file.content::jsonb)->>'content',E'\n',''),'base64'),'UTF8')::jsonb;
  v_new_pkg:=jsonb_set(v_pkg,'{dependencies,@vercel/oidc}','"latest"'::jsonb,true);
  select * into v_put2 from extensions.http(('PUT'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/package.json'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('message','fix(plp): add Vercel OIDC runtime helper','content',replace(encode(convert_to(jsonb_pretty(v_new_pkg)||E'\n','UTF8'),'base64'),E'\n',''),'sha',v_pkg_sha,'branch',v_branch)::text::varchar)::extensions.http_request);
  if v_put2.status not in (200,201) then return jsonb_build_object('ok',false,'stage','put_package','status',v_put2.status); end if;

  select * into v_pr from extensions.http(('POST'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/pulls'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('title','fix(plp): use Vercel runtime OIDC token API','head',v_branch,'base','main','body','Fixes the temporary PLP backend bridge to obtain the workload identity using Vercel''s supported @vercel/oidc getVercelOidcToken() API at runtime. No Supabase service-role key is stored in Vercel.')::text::varchar)::extensions.http_request);
  v_token:=null;
  return jsonb_build_object('ok',v_pr.status in (201,422),'branch',v_branch,'baseSha',v_main_sha,'jsCommitSha',(v_put1.content::jsonb)#>>'{commit,sha}','packageCommitSha',(v_put2.content::jsonb)#>>'{commit,sha}','prNumber',case when v_pr.status=201 then (v_pr.content::jsonb)->>'number' else null end,'prStatus',v_pr.status);
end $fn$;
revoke all on function private.publish_plp_oidc_runtime_fix_20260917() from public,anon,authenticated;
