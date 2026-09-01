
-- Pandora intent distillation + owner-facing project naming v1.
-- The model proposes the display name only for the initial create intent.
-- Provider/resource identities remain stable and are not renamed with the UI title.

create or replace function private.pandora_commit_compiled_project_spec_v2_20260901(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_candidate jsonb,
  p_compiler_provider text,
  p_compiler_model text,
  p_compiler_version text,
  p_compiler_provenance jsonb,
  p_content_sha256 text,
  p_model_request_id text,
  p_model_request_sha256 text,
  p_model_response_sha256 text,
  p_model_input_tokens bigint,
  p_model_output_tokens bigint,
  p_model_total_tokens bigint,
  p_model_revision text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','private','public'
as $$
declare
  v_result jsonb;
  v_org uuid;
  v_project uuid;
  v_intent_kind text;
  v_metadata jsonb;
  v_project_name text;
  v_intent_summary text;
  v_config jsonb;
  v_journey jsonb;
begin
  v_metadata := coalesce(p_candidate->'metadata','{}'::jsonb);
  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'ProjectSpec metadata must be an object' using errcode='22023';
  end if;
  v_project_name := trim(coalesce(v_metadata->>'projectName',''));
  v_intent_summary := trim(coalesce(v_metadata->>'intentSummary',''));
  if length(v_project_name) not between 2 and 80
     or array_length(regexp_split_to_array(v_project_name,'[[:space:]]+'),1) > 8
     or v_project_name ~ E'[\\r\\n]' then
    raise exception 'invalid owner project name' using errcode='22023';
  end if;
  if length(v_intent_summary) not between 10 and 280
     or v_intent_summary ~ E'[\\r\\n]' then
    raise exception 'invalid owner intent summary' using errcode='22023';
  end if;

  v_result := private.pandora_commit_compiled_project_spec_20260829(
    p_source_intent_id,
    p_claim_token,
    p_candidate,
    p_compiler_provider,
    p_compiler_model,
    p_compiler_version,
    p_compiler_provenance,
    p_content_sha256,
    p_model_request_id,
    p_model_request_sha256,
    p_model_response_sha256,
    p_model_input_tokens,
    p_model_output_tokens,
    p_model_total_tokens,
    p_model_revision
  );

  if coalesce(v_result->>'state','') <> 'succeeded' then
    return v_result;
  end if;

  select organization_id, project_id, intent_kind
    into v_org, v_project, v_intent_kind
  from public.pandora_project_intents
  where id=p_source_intent_id;
  if v_project is null then
    raise exception 'source intent not found' using errcode='22023';
  end if;

  if v_intent_kind = 'create' then
    select config into v_config
    from public.projectos_projects
    where id=v_project and organization_id=v_org
    for update;
    if not found then
      raise exception 'project not found' using errcode='55000';
    end if;

    v_journey := coalesce(v_config->'customerJourney','{}'::jsonb) || jsonb_build_object(
      'intentSummary',v_intent_summary,
      'autoNameSource','gemini_project_spec',
      'autoNamedAt',now(),
      'autoNameLocked',false
    );
    update public.projectos_projects
    set name=v_project_name,
        config=jsonb_set(coalesce(v_config,'{}'::jsonb),'{customerJourney}',v_journey,true),
        updated_at=now()
    where id=v_project and organization_id=v_org;
  end if;

  return v_result || jsonb_build_object(
    'projectName',v_project_name,
    'intentSummary',v_intent_summary
  );
end;
$$;

revoke all on function private.pandora_commit_compiled_project_spec_v2_20260901(uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function private.pandora_commit_compiled_project_spec_v2_20260901(uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text) to service_role;

create or replace function public.pandora_commit_compiled_project_spec_v2_20260901(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_candidate jsonb,
  p_compiler_provider text,
  p_compiler_model text,
  p_compiler_version text,
  p_compiler_provenance jsonb,
  p_content_sha256 text,
  p_model_request_id text,
  p_model_request_sha256 text,
  p_model_response_sha256 text,
  p_model_input_tokens bigint,
  p_model_output_tokens bigint,
  p_model_total_tokens bigint,
  p_model_revision text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.pandora_commit_compiled_project_spec_v2_20260901(
    p_source_intent_id,p_claim_token,p_candidate,p_compiler_provider,p_compiler_model,
    p_compiler_version,p_compiler_provenance,p_content_sha256,p_model_request_id,
    p_model_request_sha256,p_model_response_sha256,p_model_input_tokens,
    p_model_output_tokens,p_model_total_tokens,p_model_revision
  );
$$;

revoke all on function public.pandora_commit_compiled_project_spec_v2_20260901(uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.pandora_commit_compiled_project_spec_v2_20260901(uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text) to service_role;
