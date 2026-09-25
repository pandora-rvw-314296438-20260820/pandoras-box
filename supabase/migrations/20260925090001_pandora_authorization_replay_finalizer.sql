-- Forward replay identity generated from the actual repository maximum (20260925090000) plus one second.
-- This is an ordering identifier, not a claimed execution timestamp. This forward file is not yet applied in production.
-- Its idempotent blocks were applied and verified separately as provider migrations 20260925063604 and 20260925062441.
-- Preserve both earlier history entries. Reassert after later Meta/tax definitions during a clean chronological replay.
-- Reassert authorization AFTER all existing September 25 dispatcher definitions.
-- Preserve earlier applied migrations and receipt history rather than renaming them.
create or replace function private.pandora_require_provider_resource_v1(
 p_organization_id uuid,p_provider text,p_resource_key text,p_write boolean default false
) returns void language plpgsql security invoker set search_path=''
as $resource$
declare v_resource text;
begin
 if not private.pandora_is_active_org_admin_v1(p_organization_id) then
  raise exception 'pandora_provider_active_org_admin_required' using errcode='42501';
 end if;
 if p_provider is null or p_resource_key is null or p_write is null then
  raise exception 'pandora_provider_resource_not_authorized' using errcode='42501';
 end if;
 v_resource:=case when p_provider='github' then lower(btrim(p_resource_key)) else p_resource_key end;
 if exists(select 1 from private.pandora_provider_resource_grants g
   where g.organization_id=p_organization_id and g.provider=p_provider
    and (case when p_provider='github' then lower(btrim(g.resource_key)) else g.resource_key end)=v_resource
    and g.active and (not p_write or g.write_allowed)) then return; end if;
 if p_provider='github' and not p_write and v_resource not in (
  'pandora-rvw-314296438-20260820/pandoras-box',
  'pandora-rvw-314296438-20260820/pandoras-box-memory',
  'pandora-rvw-314296438-20260820/plp') and exists(
   select 1 from public.pandora_projects p where p.organization_id=p_organization_id
    and lower(btrim(p.repository))=v_resource and p.status='active') then return; end if;
 raise exception 'pandora_provider_resource_not_authorized' using errcode='42501';
end; $resource$;
revoke all on function private.pandora_require_provider_resource_v1(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function private.pandora_require_provider_resource_v1(uuid,text,text,boolean) to service_role;

do $reassert$
declare r record; b text; a text; token text; guard text;
begin
 for r in select p.oid,p.proname,p.oid::regprocedure::text identity
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.proname=any(array[
   'pandora_chat_capability_registry_v1','pandora_chat_capability_registry_v3',
   'pandora_chat_capability_dispatch_native_v1','pandora_chat_universal_dispatch_v1',
   'pandora_chat_universal_dispatch_v2','pandora_chat_universal_dispatch_v9',
   'pandora_chat_repository_snapshot_v1','pandora_enterprise_direct_github_v1',
   'pandora_meta_connection_v1','pandora_meta_oauth_prepare_v1',
   'pandora_google_workspace_connection_v1','pandora_google_workspace_oauth_prepare_v1'
  ])
 loop
  b:=pg_get_functiondef(r.oid);
  a:=regexp_replace(b,
   'if[[:space:]]+v_role[[:space:]]+not[[:space:]]+in[[:space:]]*\(''owner'',[[:space:]]*''admin''\)[[:space:]]+then',
   'if not private.pandora_is_active_org_admin_v1(p_organization_id) then','gi');
  if position('private.pandora_is_active_org_admin_v1(p_organization_id)' in a)=0 then
   raise exception 'Unknown final membership guard in %; manual reconciliation required',r.identity;
  end if;
  if r.proname='pandora_enterprise_direct_github_v1' and position('private.pandora_require_provider_resource_v1(' in a)=0 then
   token:='if v_method not in (''GET'',''POST'',''PATCH'') then';
   if position(token in a)=0 then raise exception 'Final direct-provider anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''github'',''pandora-rvw-314296438-20260820/plp'',v_method<>''GET'');'||E'\n  '||token);
  elsif r.proname='pandora_chat_capability_dispatch_native_v1' then
   guard:='private.pandora_require_provider_resource_v1(p_organization_id,''github'',v_repo,false)';
   token:='v_env := private.pandora_integration_github_api_20260825(';
   if position(guard in a)=0 then
    if position(token in a)=0 then raise exception 'Final native GitHub anchor missing'; end if;
    a:=replace(a,token,'perform '||guard||';'||E'\n        '||token);
   end if;
   guard:='private.pandora_require_provider_resource_v1(p_organization_id,''supabase'',v_project_ref,false)';
   token:='select decrypted_secret into v_token';
   if position(guard in a)=0 then
    if position(token in a)=0 then raise exception 'Final native Supabase anchor missing'; end if;
    a:=replace(a,token,'perform '||guard||';'||E'\n      '||token);
   end if;
   guard:='private.pandora_require_provider_resource_v1(p_organization_id,''vercel'',v_project_id,false)';
   token:='v_env := private.pandora_worker_f_vercel_api_20260829(';
   if position(guard in a)=0 then
    if position(token in a)=0 then raise exception 'Final native Vercel anchor missing'; end if;
    a:=replace(a,token,'perform '||guard||';'||E'\n      '||token);
   end if;
  elsif r.proname='pandora_chat_repository_snapshot_v1' and position('private.pandora_require_provider_resource_v1(' in a)=0 then
   token:='v_repo_response := private.pandora_project_github_read_v1(';
   if position(token in a)=0 then raise exception 'Final snapshot provider anchor missing'; end if;
   a:=replace(a,token,'perform private.pandora_require_provider_resource_v1(p_organization_id,''github'',v_project.repository,false);'||E'\n  '||token);
  end if;
  if a<>b then execute a; end if;
  insert into private.pandora_security_patch_receipts(migration_key,function_identity,before_sha256,after_sha256,before_definition,after_definition)
  values('pandora_authorization_replay_finalizer_v1',r.identity,
   encode(extensions.digest(b,'sha256'),'hex'),encode(extensions.digest(a,'sha256'),'hex'),b,a)
  on conflict do nothing;
 end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and has_function_privilege('authenticated',p.oid,'execute')
  and p.prosrc ~* 'if[[:space:]]+v_role[[:space:]]+not[[:space:]]+in') then
  raise exception 'Final replay reintroduced a nullable membership guard';
 end if;
end; $reassert$;

-- Internal trigger hardening only; no filing, rule-pack, or customer-data changes.
-- PostgreSQL invokes this routine through its existing triggers, not a client RPC.
do $guard$
declare v_oid oid;
begin
 v_oid:=to_regprocedure('public.pandora_tax_guard_rule_support_mutation_v1()');
 if v_oid is null then return; end if;
 if (select prorettype from pg_proc where oid=v_oid)<>'trigger'::regtype then
  raise exception 'Expected tax support guard to remain a trigger routine';
 end if;
 revoke all on function public.pandora_tax_guard_rule_support_mutation_v1() from public,anon,authenticated;
 grant execute on function public.pandora_tax_guard_rule_support_mutation_v1() to service_role;
 if has_function_privilege('anon',v_oid,'execute') or has_function_privilege('authenticated',v_oid,'execute') then
  raise exception 'Tax internal trigger remains directly executable by client roles';
 end if;
end; $guard$;
