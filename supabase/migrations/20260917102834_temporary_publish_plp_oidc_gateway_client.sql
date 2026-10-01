create or replace function private.publish_plp_oidc_client_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_token text; v_headers extensions.http_header[]; v_main extensions.http_response; v_ref extensions.http_response; v_file extensions.http_response; v_put extensions.http_response; v_pr extensions.http_response;
  v_main_sha text; v_blob_sha text; v_old text; v_new text; v_branch text:='feature/plp-oidc-backend-20260917';
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if v_token is null then return jsonb_build_object('ok',false,'stage','credential'); end if;
  v_headers:=array[extensions.http_header('Accept','application/vnd.github+json'),extensions.http_header('Authorization','Bearer '||v_token),extensions.http_header('X-GitHub-Api-Version','2022-11-28'),extensions.http_header('User-Agent','Pandora-PLP-OIDC/1.0')];
  select * into v_main from extensions.http(('GET'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/git/ref/heads/main'::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_main.status<>200 then return jsonb_build_object('ok',false,'stage','main_ref','status',v_main.status); end if;
  v_main_sha:=(v_main.content::jsonb)#>>'{object,sha}';
  if v_main_sha<>'54f1d3414c38439a578b1aec3652598108067434' then return jsonb_build_object('ok',false,'stage','stale_main','mainSha',v_main_sha); end if;
  select * into v_ref from extensions.http(('POST'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/git/refs'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('ref','refs/heads/'||v_branch,'sha',v_main_sha)::text::varchar)::extensions.http_request);
  if v_ref.status not in (201,422) then return jsonb_build_object('ok',false,'stage','create_ref','status',v_ref.status); end if;
  select * into v_file from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/api/_supabase.js?ref='||v_branch)::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_file.status<>200 then return jsonb_build_object('ok',false,'stage','get_file','status',v_file.status); end if;
  v_blob_sha:=(v_file.content::jsonb)->>'sha';
  v_old:=convert_from(decode(replace((v_file.content::jsonb)->>'content',E'\n',''),'base64'),'UTF8');
  if position('PLP_RUNTIME_GATEWAY_URL' in v_old)>0 then v_new:=v_old; else
    if position('const SUPABASE_SCHEMA = process.env.PLP_SUPABASE_SCHEMA || ''public'';' in v_old)=0 then return jsonb_build_object('ok',false,'stage','anchor_schema'); end if;
    if position('async function supabaseRequest(path, { method = ''GET'', body, prefer = ''return=representation'' } = {}) {' in v_old)=0 then return jsonb_build_object('ok',false,'stage','anchor_request'); end if;
    v_new:=replace(v_old,
      'const SUPABASE_SCHEMA = process.env.PLP_SUPABASE_SCHEMA || ''public'';',
      'const SUPABASE_SCHEMA = process.env.PLP_SUPABASE_SCHEMA || ''public'';'||E'\n'||'const PLP_RUNTIME_GATEWAY_URL = process.env.PLP_RUNTIME_GATEWAY_URL || ''https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-merge-pr162-20260830'';');
    v_new:=replace(v_new,
      'return Boolean(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);',
      'return Boolean(process.env.VERCEL_OIDC_TOKEN || (SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY));');
    v_new:=replace(v_new,
      'async function supabaseRequest(path, { method = ''GET'', body, prefer = ''return=representation'' } = {}) {'||E'\n'||'  if (!isSupabaseConfigured()) throw new Error(getSupabaseConfigError());',
      'async function supabaseRequest(path, { method = ''GET'', body, prefer = ''return=representation'' } = {}) {'||E'\n'||'  const oidcToken = process.env.VERCEL_OIDC_TOKEN;'||E'\n'||'  if (oidcToken) {'||E'\n'||'    const response = await fetch(PLP_RUNTIME_GATEWAY_URL, {'||E'\n'||'      method: ''POST'','||E'\n'||'      headers: { Authorization: `Bearer ${oidcToken}`, ''Content-Type'': ''application/json'' },'||E'\n'||'      body: JSON.stringify({ path, method, body, prefer }),'||E'\n'||'    });'||E'\n'||'    const text = await response.text();'||E'\n'||'    const data = text ? JSON.parse(text) : null;'||E'\n'||'    if (!response.ok) {'||E'\n'||'      const detail = typeof data === ''object'' && data ? data.message || data.error || JSON.stringify(data) : text;'||E'\n'||'      throw new Error(detail || `PLP runtime gateway failed: ${response.status}`);'||E'\n'||'    }'||E'\n'||'    return data;'||E'\n'||'  }'||E'\n'||'  if (!isSupabaseConfigured()) throw new Error(getSupabaseConfigError());');
  end if;
  select * into v_put from extensions.http(('PUT'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/contents/api/_supabase.js'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('message','feat(plp): authenticate temporary backend with Vercel OIDC','content',replace(encode(convert_to(v_new,'UTF8'),'base64'),E'\n',''),'sha',v_blob_sha,'branch',v_branch)::text::varchar)::extensions.http_request);
  if v_put.status not in (200,201) then return jsonb_build_object('ok',false,'stage','update_file','status',v_put.status); end if;
  select * into v_pr from extensions.http(('POST'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/pulls'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('title','feat(plp): authenticate temporary backend with Vercel OIDC','head',v_branch,'base','main','body','Uses VERCEL_OIDC_TOKEN to authenticate PLP server functions to the isolated plp_runtime Supabase gateway. No Supabase service-role key is stored in Vercel. Direct secret-based Supabase access remains only as a local-development fallback.')::text::varchar)::extensions.http_request);
  v_token:=null;
  return jsonb_build_object('ok',v_pr.status in (201,422),'branch',v_branch,'baseSha',v_main_sha,'commitSha',(v_put.content::jsonb)#>>'{commit,sha}','prNumber',case when v_pr.status=201 then (v_pr.content::jsonb)->>'number' else null end,'prStatus',v_pr.status);
end $fn$;
revoke all on function private.publish_plp_oidc_client_20260917() from public,anon,authenticated;
