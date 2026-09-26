
do $fix$
declare
  v_cron text;
  v_verify text;
  v_changed text;
begin
  select pg_get_functiondef(p.oid) into strict v_cron
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_ops_native_cron_tick_v1';

  if position($needle$
    v_merge_sha:=v_pr#>>'{body,merge_commit_sha}';
    v_head_sha:=v_pr#>>'{body,head,sha}';
    if v_merge_sha!~'^[0-9a-f]{40}$' or v_head_sha!~'^[0-9a-f]{40}$' then
      raise exception 'OPS_NATIVE_CRON_SOURCE_INVALID';
    end if;
$needle$ in v_cron)=0
     or position($needle2$      'headSha',v_merge_sha,$needle2$ in v_cron)=0 then
    raise exception 'OPS_NATIVE_CRON_SOURCE_FIX_BASE_MISMATCH';
  end if;

  v_changed := replace(
    v_cron,
    $needle$
    v_merge_sha:=v_pr#>>'{body,merge_commit_sha}';
    v_head_sha:=v_pr#>>'{body,head,sha}';
    if v_merge_sha!~'^[0-9a-f]{40}$' or v_head_sha!~'^[0-9a-f]{40}$' then
      raise exception 'OPS_NATIVE_CRON_SOURCE_INVALID';
    end if;
$needle$,
    $replacement$
    v_merge_sha:=v_pr#>>'{body,merge_commit_sha}';
    v_head_sha:=v_pr#>>'{body,head,sha}';
    if v_head_sha!~'^[0-9a-f]{40}$' then
      raise exception 'OPS_NATIVE_CRON_SOURCE_INVALID';
    end if;
$replacement$
  );
  v_changed := replace(v_changed,$needle2$      'headSha',v_merge_sha,$needle2$,$replacement2$      'headSha',v_head_sha,$replacement2$);
  execute v_changed;

  select pg_get_functiondef(p.oid) into strict v_verify
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='pandora_ops_native_release_verify_v1';

  if position($vneedle$ if v_head!~'^[0-9a-f]{40}$' or v_merge is distinct from t.head_sha then$vneedle$ in v_verify)=0 then
    raise exception 'OPS_NATIVE_VERIFY_SOURCE_FIX_BASE_MISMATCH';
  end if;

  v_changed := replace(
    v_verify,
    $vneedle$ if v_head!~'^[0-9a-f]{40}$' or v_merge is distinct from t.head_sha then$vneedle$,
    $vreplacement$ if v_head!~'^[0-9a-f]{40}$' or v_head is distinct from t.head_sha then$vreplacement$
  );
  execute v_changed;
end
$fix$;
