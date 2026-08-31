alter table public.pandora_project_version_primitives
  add column if not exists primitive_verification_run_id uuid
  references public.pandora_primitive_verification_runs(id) on delete restrict;

create index if not exists pandora_project_version_primitives_verification_run_idx
  on public.pandora_project_version_primitives(primitive_verification_run_id)
  where primitive_verification_run_id is not null;

create or replace function private.pandora_validate_materialized_primitive_verification_20260831()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.pandora_primitive_verification_runs%rowtype;
begin
  if new.trust_state = 'TRUSTED' then
    if new.primitive_verification_run_id is null then
      raise exception 'trusted materialized primitive requires Worker E verification'
        using errcode = '23514';
    end if;

    select * into v_run
    from public.pandora_primitive_verification_runs
    where id = new.primitive_verification_run_id;

    if v_run.id is null
      or v_run.status <> 'PASS'
      or v_run.verifier_identity <> 'pandora-verification-engine'
      or v_run.primitive_name <> new.primitive_name
      or v_run.primitive_version <> new.primitive_version
      or v_run.source_digest <> new.source_digest
    then
      raise exception 'materialized primitive Worker E evidence mismatch'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists pandora_project_version_primitives_worker_e_guard
  on public.pandora_project_version_primitives;
create trigger pandora_project_version_primitives_worker_e_guard
before insert or update on public.pandora_project_version_primitives
for each row execute function private.pandora_validate_materialized_primitive_verification_20260831();

create or replace function private.pandora_worker_i_materialize_project_spec_primitives_20260831(
  p_project_spec_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_resolution jsonb;
  v_selection jsonb;
  v_catalog public.pandora_primitive_catalog_entries%rowtype;
  v_run public.pandora_primitive_verification_runs%rowtype;
  v_manifest_response jsonb;
  v_manifest jsonb;
  v_manifest_text text;
  v_manifest_file jsonb;
  v_file_response jsonb;
  v_content text;
  v_source_path text;
  v_target_path text;
  v_expected_sha text;
  v_actual_sha text;
  v_bundle_input text;
  v_bundle_digest text;
  v_plan_input text := '';
  v_plan_digest text;
  v_files jsonb := '[]'::jsonb;
  v_selections jsonb := '[]'::jsonb;
  v_seen_paths text[] := array[]::text[];
  v_existing_sha text;
  v_primitive_count int := 0;
begin
  if p_project_spec_id is null then
    raise exception 'PROJECT_SPEC_REQUIRED' using errcode = '22023';
  end if;

  v_resolution := public.pandora_worker_i_resolve_project_spec_primitives_20260831(
    p_project_spec_id,
    true
  );

  if coalesce(v_resolution->>'state','') <> 'READY' then
    raise exception 'TRUSTED_PRIMITIVE_UNAVAILABLE' using errcode = '55000';
  end if;

  for v_selection in
    select value
    from jsonb_array_elements(coalesce(v_resolution->'selections','[]'::jsonb))
    order by value->>'name'
  loop
    select * into v_catalog
    from public.pandora_primitive_catalog_entries
    where primitive_name = v_selection->>'name'
      and primitive_version = v_selection->>'version';

    if v_catalog.primitive_name is null
      or v_catalog.trust_state <> 'TRUSTED'
      or v_catalog.source_commit !~ '^[0-9a-f]{40}$'
      or v_catalog.source_manifest_path !~ '^packages/primitives/[A-Za-z0-9_./-]+/SOURCE_MANIFEST[.]json$'
      or v_catalog.source_manifest_path ~ '(^|/)[.][.]?(/|$)'
      or v_catalog.source_digest !~ '^sha256:[0-9a-f]{64}$'
      or v_catalog.worker_e_evidence_ref is null
      or v_catalog.worker_e_evidence_ref !~ '^[0-9a-f-]{36}$'
    then
      raise exception 'TRUSTED_PRIMITIVE_IDENTITY_INVALID' using errcode = '23514';
    end if;

    select * into v_run
    from public.pandora_primitive_verification_runs
    where id = v_catalog.worker_e_evidence_ref::uuid;

    if v_run.id is null
      or v_run.status <> 'PASS'
      or v_run.verifier_identity <> 'pandora-verification-engine'
      or v_run.primitive_name <> v_catalog.primitive_name
      or v_run.primitive_version <> v_catalog.primitive_version
      or v_run.source_commit <> v_catalog.source_commit
      or v_run.source_manifest_path <> v_catalog.source_manifest_path
      or v_run.source_digest <> v_catalog.source_digest
    then
      raise exception 'TRUSTED_PRIMITIVE_EVIDENCE_INVALID' using errcode = '23514';
    end if;

    v_manifest_response := private.pandora_integration_github_api_20260825(
      'GET',
      '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/' ||
        v_catalog.source_manifest_path || '?ref=' || v_catalog.source_commit,
      null
    );
    if coalesce((v_manifest_response->>'status')::int,0) <> 200 then
      raise exception 'PRIMITIVE_MANIFEST_FETCH_FAILED' using errcode = '58000';
    end if;

    begin
      v_manifest_text := convert_from(
        decode(regexp_replace(v_manifest_response#>>'{body,content}','[[:space:]]','','g'),'base64'),
        'UTF8'
      );
      v_manifest := v_manifest_text::jsonb;
    exception when others then
      raise exception 'PRIMITIVE_MANIFEST_INVALID' using errcode = '22023';
    end;

    if v_manifest->>'primitive' <> v_catalog.primitive_name || '@' || v_catalog.primitive_version
      or v_manifest->>'bundleDigest' <> v_catalog.source_digest
      or jsonb_typeof(v_manifest->'files') <> 'array'
      or jsonb_array_length(v_manifest->'files') < 1
      or jsonb_array_length(v_manifest->'files') > 100
    then
      raise exception 'PRIMITIVE_MANIFEST_IDENTITY_MISMATCH' using errcode = '23514';
    end if;

    v_bundle_input := '';
    for v_manifest_file in
      select value
      from jsonb_array_elements(v_manifest->'files')
      order by value->>'path'
    loop
      v_source_path := coalesce(v_manifest_file->>'path','');
      v_expected_sha := lower(coalesce(v_manifest_file->>'sha256',''));
      if v_source_path = ''
        or v_source_path !~ '^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*$'
        or v_source_path ~ '(^|/)[.][.]?(/|$)'
        or v_expected_sha !~ '^[0-9a-f]{64}$'
      then
        raise exception 'PRIMITIVE_FILE_IDENTITY_INVALID' using errcode = '23514';
      end if;

      v_file_response := private.pandora_integration_github_api_20260825(
        'GET',
        '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/packages/primitives/' ||
          v_source_path || '?ref=' || v_catalog.source_commit,
        null
      );
      if coalesce((v_file_response->>'status')::int,0) <> 200 then
        raise exception 'PRIMITIVE_FILE_FETCH_FAILED' using errcode = '58000';
      end if;

      begin
        v_content := convert_from(
          decode(regexp_replace(v_file_response#>>'{body,content}','[[:space:]]','','g'),'base64'),
          'UTF8'
        );
      exception when others then
        raise exception 'PRIMITIVE_FILE_INVALID' using errcode = '22023';
      end;

      if octet_length(v_content) < 1 or octet_length(v_content) > 524288 then
        raise exception 'PRIMITIVE_FILE_SIZE_INVALID' using errcode = '22023';
      end if;
      v_actual_sha := encode(extensions.digest(convert_to(v_content,'UTF8'),'sha256'),'hex');
      if v_actual_sha <> v_expected_sha then
        raise exception 'PRIMITIVE_FILE_HASH_MISMATCH' using errcode = '23514';
      end if;

      v_bundle_input := v_bundle_input || v_source_path || chr(0) || v_actual_sha || E'\n';
      v_target_path := 'pandora-primitives/' || v_source_path;

      if v_target_path = any(v_seen_paths) then
        select f->>'sha256' into v_existing_sha
        from jsonb_array_elements(v_files) f
        where f->>'path' = v_target_path
        limit 1;
        if v_existing_sha <> v_actual_sha then
          raise exception 'PRIMITIVE_FILE_CONFLICT' using errcode = '23505';
        end if;
      else
        v_seen_paths := array_append(v_seen_paths,v_target_path);
        v_files := v_files || jsonb_build_array(jsonb_build_object(
          'path',v_target_path,
          'content',v_content,
          'sha256',v_actual_sha,
          'primitiveName',v_catalog.primitive_name,
          'primitiveVersion',v_catalog.primitive_version,
          'sourcePath',v_source_path
        ));
      end if;
    end loop;

    v_bundle_digest := 'sha256:' || encode(
      extensions.digest(convert_to(v_bundle_input,'UTF8'),'sha256'),
      'hex'
    );
    if v_bundle_digest <> v_catalog.source_digest then
      raise exception 'PRIMITIVE_BUNDLE_HASH_MISMATCH' using errcode = '23514';
    end if;

    v_selections := v_selections || jsonb_build_array(jsonb_build_object(
      'name',v_catalog.primitive_name,
      'version',v_catalog.primitive_version,
      'trustState',v_catalog.trust_state,
      'sourceCommit',v_catalog.source_commit,
      'sourceDigest',v_catalog.source_digest,
      'sourceManifestPath',v_catalog.source_manifest_path,
      'workerEEvidenceRef',v_catalog.worker_e_evidence_ref
    ));
    v_primitive_count := v_primitive_count + 1;
  end loop;

  select coalesce(string_agg(
    f->>'path' || chr(0) || f->>'sha256' || E'\n',
    '' order by f->>'path'
  ),'') into v_plan_input
  from jsonb_array_elements(v_files) f;

  v_plan_digest := 'sha256:' || encode(
    extensions.digest(convert_to(v_plan_input,'UTF8'),'sha256'),
    'hex'
  );

  return jsonb_build_object(
    'state','READY',
    'projectSpecId',p_project_spec_id,
    'primitiveCount',v_primitive_count,
    'selectionDigest',v_resolution->>'selectionDigest',
    'manifestDigest',v_resolution->>'selectionDigest',
    'materializationPlanDigest',v_plan_digest,
    'selections',v_selections,
    'files',v_files
  );
end;
$function$;

create or replace function public.pandora_worker_i_materialize_project_spec_primitives_20260831(
  p_project_spec_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select private.pandora_worker_i_materialize_project_spec_primitives_20260831(p_project_spec_id);
$function$;

revoke all on function public.pandora_worker_i_materialize_project_spec_primitives_20260831(uuid) from public, anon, authenticated;
grant execute on function public.pandora_worker_i_materialize_project_spec_primitives_20260831(uuid) to service_role;

create or replace function private.pandora_worker_i_record_project_version_composition_20260831(
  p_project_version_id uuid,
  p_project_spec_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_version public.pandora_project_versions%rowtype;
  v_materialization jsonb;
  v_selection jsonb;
  v_composition_id uuid;
  v_configuration_digest text := 'sha256:' || encode(extensions.digest('{}','sha256'),'hex');
  v_count int;
begin
  select * into v_version
  from public.pandora_project_versions
  where id = p_project_version_id;

  if v_version.id is null or v_version.project_spec_id <> p_project_spec_id then
    raise exception 'PROJECT_VERSION_SPEC_MISMATCH' using errcode = '23514';
  end if;

  v_materialization := private.pandora_worker_i_materialize_project_spec_primitives_20260831(
    p_project_spec_id
  );
  v_count := coalesce((v_materialization->>'primitiveCount')::int,0);
  if v_count = 0 then
    return jsonb_build_object(
      'state','NONE',
      'projectVersionId',p_project_version_id,
      'primitiveCount',0
    );
  end if;

  insert into public.pandora_project_version_compositions(
    organization_id,
    project_id,
    project_version_id,
    manifest_digest,
    materialization_plan_digest,
    primitive_count
  ) values (
    v_version.organization_id,
    v_version.project_id,
    v_version.id,
    v_materialization->>'manifestDigest',
    v_materialization->>'materializationPlanDigest',
    v_count
  )
  on conflict (project_version_id) do update set
    manifest_digest = excluded.manifest_digest,
    materialization_plan_digest = excluded.materialization_plan_digest,
    primitive_count = excluded.primitive_count
  returning id into v_composition_id;

  for v_selection in
    select value
    from jsonb_array_elements(v_materialization->'selections')
    order by value->>'name'
  loop
    insert into public.pandora_project_version_primitives(
      composition_id,
      organization_id,
      project_id,
      project_version_id,
      primitive_name,
      primitive_version,
      trust_state,
      definition_digest,
      source_digest,
      configuration_digest,
      customization_digest,
      verification_evidence_id,
      primitive_verification_run_id
    ) values (
      v_composition_id,
      v_version.organization_id,
      v_version.project_id,
      v_version.id,
      v_selection->>'name',
      v_selection->>'version',
      'TRUSTED',
      v_selection->>'sourceDigest',
      v_selection->>'sourceDigest',
      v_configuration_digest,
      v_configuration_digest,
      null,
      (v_selection->>'workerEEvidenceRef')::uuid
    )
    on conflict (project_version_id,primitive_name) do update set
      composition_id = excluded.composition_id,
      primitive_version = excluded.primitive_version,
      trust_state = excluded.trust_state,
      definition_digest = excluded.definition_digest,
      source_digest = excluded.source_digest,
      configuration_digest = excluded.configuration_digest,
      customization_digest = excluded.customization_digest,
      primitive_verification_run_id = excluded.primitive_verification_run_id;
  end loop;

  return jsonb_build_object(
    'state','RECORDED',
    'projectVersionId',p_project_version_id,
    'compositionId',v_composition_id,
    'primitiveCount',v_count,
    'manifestDigest',v_materialization->>'manifestDigest',
    'materializationPlanDigest',v_materialization->>'materializationPlanDigest'
  );
end;
$function$;

create or replace function public.pandora_worker_i_record_project_version_composition_20260831(
  p_project_version_id uuid,
  p_project_spec_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select private.pandora_worker_i_record_project_version_composition_20260831(
    p_project_version_id,
    p_project_spec_id
  );
$function$;

revoke all on function public.pandora_worker_i_record_project_version_composition_20260831(uuid,uuid) from public, anon, authenticated;
grant execute on function public.pandora_worker_i_record_project_version_composition_20260831(uuid,uuid) to service_role;
