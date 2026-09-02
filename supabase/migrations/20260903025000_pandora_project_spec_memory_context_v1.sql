
create or replace function public.pandora_commit_compiled_project_spec_v3_20260903(
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
  p_model_revision text,
  p_model_context_sha256 text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_project_spec_id uuid;
  v_updated integer := 0;
begin
  if p_model_context_sha256 is not null
     and p_model_context_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid model context sha256' using errcode = '22023';
  end if;

  v_result := public.pandora_commit_compiled_project_spec_v2_20260901(
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

  if p_model_context_sha256 is null or v_result->>'state' <> 'succeeded' then
    return v_result;
  end if;

  begin
    v_project_spec_id := (v_result->>'projectSpecId')::uuid;
  exception when others then
    raise exception 'compiled project spec result missing projectSpecId' using errcode = '22023';
  end;

  update public.pandora_model_runs
  set context_sha256 = p_model_context_sha256
  where project_spec_id = v_project_spec_id
    and request_id = p_model_request_id
    and task = 'compile_project_spec'
    and status = 'succeeded'
    and (context_sha256 is null or context_sha256 = p_model_context_sha256);
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'compiled project spec model context binding failed' using errcode = '55000';
  end if;

  return v_result;
end;
$function$;

revoke all on function public.pandora_commit_compiled_project_spec_v3_20260903(
  uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text,text
) from public, anon, authenticated;
grant execute on function public.pandora_commit_compiled_project_spec_v3_20260903(
  uuid,uuid,jsonb,text,text,text,jsonb,text,text,text,text,bigint,bigint,bigint,text,text
) to service_role;
