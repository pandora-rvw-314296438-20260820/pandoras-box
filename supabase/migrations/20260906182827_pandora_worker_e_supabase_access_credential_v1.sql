begin;

do $migration$
declare
  v_def text;
  v_old text := 'where name in (''mcpmaster_supabase_account_1_pat'',''mcpmaster_supabase_account_2_pat'')';
  v_new text := 'where name in (''Supabase_access'',''mcpmaster_supabase_account_1_pat'',''mcpmaster_supabase_account_2_pat'')';
  v_old_order text := 'order by case name when ''mcpmaster_supabase_account_1_pat'' then 1 else 2 end';
  v_new_order text := 'order by case name when ''Supabase_access'' then 0 when ''mcpmaster_supabase_account_1_pat'' then 1 else 2 end';
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid)'::regprocedure
  ) into v_def;

  if position('Supabase_access' in v_def) = 0 then
    if position(v_old in v_def) = 0 or position(v_old_order in v_def) = 0 then
      raise exception 'WORKER_E_SUPABASE_ACCESS_PATCH_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def := replace(v_def, v_old, v_new);
    v_def := replace(v_def, v_old_order, v_new_order);
    execute v_def;
  end if;

  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid)'::regprocedure
  ) into v_def;
  if position('Supabase_access' in v_def) = 0 then
    raise exception 'WORKER_E_SUPABASE_ACCESS_PATCH_VERIFY_FAILED' using errcode='55000';
  end if;
end
$migration$;

comment on function private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid) is
'Worker E Supabase preview verifier prefers the current Vault-backed Supabase_access management credential and falls back to legacy PAT names without exposing credentials.';

commit;
