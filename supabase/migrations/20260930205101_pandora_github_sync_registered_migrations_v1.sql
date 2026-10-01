
begin;

create or replace function public.pandora_github_sync_registered_migrations_v1(
  p_versions text[],
  p_commit_message text,
  p_branch_suffix text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','supabase_migrations'
as $function$
declare
  v_files jsonb;
  v_requested integer:=coalesce(cardinality(p_versions),0);
  v_found integer;
begin
  if session_user not in ('postgres','service_role','supabase_admin')
     and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' then
    raise exception 'PANDORA_GITHUB_MIGRATION_SYNC_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if v_requested not between 1 and 12 then
    raise exception 'PANDORA_GITHUB_MIGRATION_SYNC_INVALID_COUNT' using errcode='22023';
  end if;

  select count(*),coalesce(jsonb_agg(
    jsonb_build_object(
      'path','supabase/migrations/'||m.version||'_'||m.name||'.sql',
      'content',array_to_string(m.statements,E';\n\n')||E';\n'
    )
    order by m.version
  ),'[]'::jsonb)
  into v_found,v_files
  from supabase_migrations.schema_migrations m
  where m.version=any(p_versions)
    and (
      m.name like 'pandora_growth_%'
      or m.name in (
        'pandora_github_deterministic_source_sync_v1',
        'pandora_github_sync_registered_migrations_v1'
      )
    );

  if v_found<>v_requested then
    raise exception 'PANDORA_GITHUB_MIGRATION_SYNC_VERSION_MISMATCH requested=% found=%',v_requested,v_found using errcode='22023';
  end if;

  return public.pandora_github_source_sync_v1(
    v_files,p_commit_message,p_branch_suffix
  );
end;
$function$;

revoke all on function public.pandora_github_sync_registered_migrations_v1(text[],text,text)
from public,anon,authenticated;
grant execute on function public.pandora_github_sync_registered_migrations_v1(text[],text,text)
to service_role;

comment on function public.pandora_github_sync_registered_migrations_v1(text[],text,text)
is 'Reads exact migration statements from the Supabase migration ledger and publishes only allowlisted Facebook/Growth closeout migration files through the Vault-backed deterministic GitHub source-sync broker.';

commit;
;
