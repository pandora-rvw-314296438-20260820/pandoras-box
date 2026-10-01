create or replace function private.gate_plp_pr8_20260918(p_merge boolean default false)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_token text; v_headers extensions.http_header[]; v_pr extensions.http_response; v_status extensions.http_response; v_main extensions.http_response; v_merge extensions.http_response; v_checks extensions.http_response;
  v_head text; v_base text; v_main_sha text; v_state text; v_mergeable boolean; v_mergeable_state text; v_total int:=0; v_completed int:=0; v_failed int:=0;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if v_token is null then return jsonb_build_object('ok',false,'stage','credential'); end if;
  v_headers:=array[extensions.http_header('Accept','application/vnd.github+json'),extensions.http_header('Authorization','Bearer '||v_token),extensions.http_header('X-GitHub-Api-Version','2022-11-28'),extensions.http_header('User-Agent','Pandora-PLP-PR8-Gate/1.0')];
  select * into v_pr from extensions.http(('GET'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/pulls/8'::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_pr.status<>200 then return jsonb_build_object('ok',false,'stage','pr','status',v_pr.status); end if;
  v_head:=(v_pr.content::jsonb)#>>'{head,sha}'; v_base:=(v_pr.content::jsonb)#>>'{base,sha}'; v_mergeable:=coalesce(((v_pr.content::jsonb)->>'mergeable')::boolean,false); v_mergeable_state:=(v_pr.content::jsonb)->>'mergeable_state';
  select * into v_status from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/commits/'||v_head||'/status')::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  v_state:=case when v_status.status=200 then (v_status.content::jsonb)->>'state' else 'unknown' end;
  select * into v_checks from extensions.http(('GET'::extensions.http_method,('https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/commits/'||v_head||'/check-runs?per_page=100')::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_checks.status=200 then
    select count(*), count(*) filter(where x->>'status'='completed'), count(*) filter(where x->>'status'='completed' and coalesce(x->>'conclusion','') not in ('success','neutral','skipped'))
      into v_total,v_completed,v_failed from jsonb_array_elements(coalesce((v_checks.content::jsonb)->'check_runs','[]'::jsonb)) x;
  end if;
  select * into v_main from extensions.http(('GET'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/git/ref/heads/main'::varchar,v_headers,'application/json'::varchar,null::varchar)::extensions.http_request);
  v_main_sha:=(v_main.content::jsonb)#>>'{object,sha}';
  if not p_merge then v_token:=null; return jsonb_build_object('ok',true,'head',v_head,'base',v_base,'main',v_main_sha,'status',v_state,'mergeable',v_mergeable,'mergeableState',v_mergeable_state,'checksTotal',v_total,'checksCompleted',v_completed,'checksFailed',v_failed); end if;
  if v_head<>'a4ce39b98ab56beded0e4d100c1a7522ab74d8cf' or v_base<>v_main_sha or v_state<>'success' or not v_mergeable or v_failed<>0 or v_total<>v_completed then
    v_token:=null; return jsonb_build_object('ok',false,'stage','gate','head',v_head,'base',v_base,'main',v_main_sha,'status',v_state,'mergeable',v_mergeable,'mergeableState',v_mergeable_state,'checksTotal',v_total,'checksCompleted',v_completed,'checksFailed',v_failed);
  end if;
  select * into v_merge from extensions.http(('PUT'::extensions.http_method,'https://api.github.com/repos/pandora-rvw-314296438-20260820/plp/pulls/8/merge'::varchar,v_headers||extensions.http_header('Content-Type','application/json'),'application/json'::varchar,jsonb_build_object('sha',v_head,'merge_method','merge')::text::varchar)::extensions.http_request);
  v_token:=null;
  return jsonb_build_object('ok',v_merge.status=200,'status',v_merge.status,'merged',coalesce(((v_merge.content::jsonb)->>'merged')::boolean,false),'mergeSha',(v_merge.content::jsonb)->>'sha','message',(v_merge.content::jsonb)->>'message');
end $fn$;
revoke all on function private.gate_plp_pr8_20260918(boolean) from public,anon,authenticated;
