create or replace function public.pandora_enterprise_github_runtime_material_20260917()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, vault, public
as $$
declare v_token text;
begin
  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='Github_supabase' limit 1;
  if nullif(trim(v_token),'') is null then raise exception 'GitHub provider credential unavailable' using errcode='55000'; end if;
  return jsonb_build_object('token',v_token);
end;
$$;
revoke all on function public.pandora_enterprise_github_runtime_material_20260917() from public, anon, authenticated;
grant execute on function public.pandora_enterprise_github_runtime_material_20260917() to service_role;

create table if not exists private.enterprise_repo_upload_staging_20260917(
  run_id uuid not null,
  repository text not null,
  source_sha text not null,
  path text not null,
  digest text not null,
  size bigint not null,
  created_at timestamptz not null default now(),
  primary key(run_id,path)
);

create or replace function public.pandora_enterprise_stage_upload_refs_20260917(
  p_run_id uuid, p_repository text, p_source_sha text, p_refs jsonb
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, private, public
as $$
declare v_count integer;
begin
  if p_run_id is null or p_repository is null or p_source_sha !~ '^[0-9a-f]{40}$' or jsonb_typeof(p_refs) <> 'array' then
    raise exception 'invalid staging input' using errcode='22023';
  end if;
  insert into private.enterprise_repo_upload_staging_20260917(run_id,repository,source_sha,path,digest,size)
  select p_run_id,p_repository,p_source_sha,x->>'file',x->>'sha',greatest(0,coalesce((x->>'size')::bigint,0))
  from jsonb_array_elements(p_refs) x
  where coalesce(x->>'file','')<>'' and (x->>'sha') ~ '^[0-9a-f]{40}$'
  on conflict(run_id,path) do update set digest=excluded.digest,size=excluded.size,source_sha=excluded.source_sha,repository=excluded.repository,created_at=now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.pandora_enterprise_stage_upload_refs_20260917(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_enterprise_stage_upload_refs_20260917(uuid,text,text,jsonb) to service_role;

create or replace function public.pandora_enterprise_get_upload_refs_20260917(p_run_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog, private
as $$
  select jsonb_build_object(
    'count',count(*),
    'repository',min(repository),
    'sourceSha',min(source_sha),
    'files',coalesce(jsonb_agg(jsonb_build_object('file',path,'sha',digest,'size',size) order by path),'[]'::jsonb)
  ) from private.enterprise_repo_upload_staging_20260917 where run_id=p_run_id;
$$;
revoke all on function public.pandora_enterprise_get_upload_refs_20260917(uuid) from public,anon,authenticated;
grant execute on function public.pandora_enterprise_get_upload_refs_20260917(uuid) to service_role;

create or replace function public.pandora_enterprise_clear_upload_refs_20260917(p_run_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, private
as $$ declare v_count integer; begin delete from private.enterprise_repo_upload_staging_20260917 where run_id=p_run_id; get diagnostics v_count=row_count; return v_count; end $$;
revoke all on function public.pandora_enterprise_clear_upload_refs_20260917(uuid) from public,anon,authenticated;
grant execute on function public.pandora_enterprise_clear_upload_refs_20260917(uuid) to service_role;
