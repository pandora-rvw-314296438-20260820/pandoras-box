-- Defense-in-depth hardening for private server-only Pandora tables.
-- The private schema is already unavailable to anon/authenticated and these
-- roles have no table grants. RLS is still enabled so a future grant cannot
-- accidentally turn these tables into unrestricted client data.

revoke all on schema private from public,anon,authenticated;

do $rls$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pandora_project_memory_context_receipts',
    'pandora_edge_function_retirement_receipts',
    'pandora_base44_identity_links',
    'pandora_google_workspace_oauth_states',
    'pandora_google_workspace_connections',
    'pandora_external_worker_dispatches',
    'pandora_coordinator_gate_decisions',
    'pandora_coordinator_gate_state',
    'pandora_coordinator_repository_fence',
    'pandora_coordinator_snapshot_promotions',
    'pandora_coordinator_snapshot_revocations',
    'pandora_ci_rescue_jobs',
    'phone_local_ai_acceptance_challenges',
    'phone_local_ai_acceptance_receipts',
    'plp_staff_task_action_receipts',
    'pandora_meta_oauth_states',
    'pandora_meta_connections',
    'pandora_meta_page_tokens'
  ] loop
    if to_regclass('private.'||v_table) is not null then
      execute format('alter table private.%I enable row level security',v_table);
      execute format('revoke all on table private.%I from public,anon,authenticated',v_table);
    end if;
  end loop;
end;
$rls$;

