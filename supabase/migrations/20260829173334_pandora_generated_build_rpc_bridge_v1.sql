-- Service-role-only PostgREST bridge for the generated Build intake.
-- The Edge Function cannot call private-schema RPCs through the standard Supabase client.

create or replace function public.pandora_commit_generated_build_intake_service_20260830(
  p_organization_id uuid,
  p_project_id uuid,
  p_project_spec_id uuid,
  p_requested_by uuid,
  p_idempotency_key text,
  p_source_sha256 text,
  p_source_byte_size bigint,
  p_storage_path text,
  p_model_run_id uuid,
  p_build_adapter text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.pandora_commit_generated_build_intake_v2_20260829(
    p_organization_id,
    p_project_id,
    p_project_spec_id,
    p_requested_by,
    p_idempotency_key,
    p_source_sha256,
    p_source_byte_size,
    p_storage_path,
    p_model_run_id,
    p_build_adapter
  );
$$;

revoke all on function public.pandora_commit_generated_build_intake_service_20260830(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) from public, anon, authenticated;
grant execute on function public.pandora_commit_generated_build_intake_service_20260830(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) to service_role;
