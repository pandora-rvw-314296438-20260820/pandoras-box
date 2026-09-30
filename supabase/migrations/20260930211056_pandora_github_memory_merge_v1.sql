
begin;

create or replace function public.pandora_github_memory_merge_v1(
  p_pull_request_number integer,
  p_expected_head_sha text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $function$
declare
  v_repo constant text := 'pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_pr jsonb;
  v_checks jsonb;
  v_main jsonb;
  v_merge jsonb;
  v_post jsonb;
  v_base_sha text;
  v_merge_sha text;
  v_main_sha text;
  v_pending integer:=0;
  v_failed integer:=0;
  v_total integer:=0;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_MEMORY_MERGE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if p_pull_request_number is null or p_pull_request_number<1
     or p_expected_head_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_MEMORY_MERGE_INPUT_INVALID' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pandora-memory-vault-merge',0));

  v_pr:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/pulls/'||p_pull_request_number::text,null
  );
  if coalesce((v_pr->>'status')::integer,0)<>200
     or v_pr#>>'{body,head,sha}'<>p_expected_head_sha
     or v_pr#>>'{body,base,ref}'<>'main'
     or v_pr#>>'{body,state}'<>'open'
     or coalesce((v_pr#>>'{body,draft}')::boolean,false)
     or coalesce((v_pr#>>'{body,mergeable}')::boolean,false) is not true then
    raise exception 'PANDORA_MEMORY_MERGE_PR_IDENTITY_INVALID';
  end if;
  v_base_sha:=v_pr#>>'{body,base,sha}';

  v_checks:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/commits/'||p_expected_head_sha||'/check-runs?per_page=100',null
  );
  if coalesce((v_checks->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_MEMORY_MERGE_CHECK_READ_FAILED';
  end if;
  v_total:=coalesce((v_checks#>>'{body,total_count}')::integer,0);
  if v_total=0 or v_total>100 then
    raise exception 'PANDORA_MEMORY_MERGE_CHECK_SET_INVALID';
  end if;
  select
    count(*) filter(where c->>'status'<>'completed'),
    count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped'))
  into v_pending,v_failed
  from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;
  if v_pending<>0 or v_failed<>0 then
    raise exception 'PANDORA_MEMORY_MERGE_CHECKS_NOT_GREEN pending=% failed=%',v_pending,v_failed;
  end if;

  v_main:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/branches/main',null);
  if coalesce((v_main->>'status')::integer,0)<>200
     or v_main#>>'{body,commit,sha}'<>v_base_sha then
    raise exception 'PANDORA_MEMORY_MERGE_MAIN_MOVED' using errcode='40001';
  end if;

  v_merge:=private.pandora_integration_github_api_20260825(
    'PUT',v_prefix||'/pulls/'||p_pull_request_number::text||'/merge',
    jsonb_build_object(
      'sha',p_expected_head_sha,
      'merge_method','merge',
      'commit_title','Pandora Memory governed merge PR #'||p_pull_request_number::text,
      'commit_message','All exact-head Memory checks terminal and acceptable; exact head '||p_expected_head_sha||'.'
    )
  );
  if coalesce((v_merge->>'status')::integer,0)<>200
     or coalesce((v_merge#>>'{body,merged}')::boolean,false) is not true
     or coalesce(v_merge#>>'{body,sha}','') !~ '^[0-9a-f]{40}$' then
    raise exception 'PANDORA_MEMORY_MERGE_PROVIDER_REJECTED';
  end if;
  v_merge_sha:=v_merge#>>'{body,sha}';

  v_post:=private.pandora_integration_github_api_20260825(
    'GET',v_prefix||'/pulls/'||p_pull_request_number::text,null
  );
  if coalesce((v_post->>'status')::integer,0)<>200
     or coalesce((v_post#>>'{body,merged}')::boolean,false) is not true
     or v_post#>>'{body,head,sha}'<>p_expected_head_sha then
    raise exception 'PANDORA_MEMORY_MERGE_PR_READBACK_FAILED';
  end if;

  v_main:=private.pandora_integration_github_api_20260825('GET',v_prefix||'/branches/main',null);
  if coalesce((v_main->>'status')::integer,0)<>200 then
    raise exception 'PANDORA_MEMORY_MERGE_MAIN_READBACK_FAILED';
  end if;
  v_main_sha:=v_main#>>'{body,commit,sha}';
  if v_main_sha<>v_merge_sha then
    raise exception 'PANDORA_MEMORY_MERGE_MAIN_SHA_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok',true,'repository',v_repo,'pullRequest',p_pull_request_number,
    'headSha',p_expected_head_sha,'baseSha',v_base_sha,'mergeSha',v_merge_sha,
    'observedCheckCount',v_total,'allChecksTerminal',true,'allChecksAcceptable',true,
    'credentialSource','supabase-vault','providerReadbackVerified',true
  );
end;
$function$;

revoke all on function public.pandora_github_memory_merge_v1(integer,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_memory_merge_v1(integer,text)
to service_role;

commit;
;
