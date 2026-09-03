const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { existsSync, readFileSync, readdirSync } = require('node:fs');
const { basename, join } = require('node:path');
const test = require('node:test');

const repositoryRoot = join(__dirname, '..');
const migrationRoot = join(repositoryRoot, 'supabase', 'migrations');
const evidenceRoot = join(
  repositoryRoot,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
);
const manifest = JSON.parse(
  readFileSync(join(evidenceRoot, 'migration-parity-manifest.json'), 'utf8'),
);
const recoveryReplayResult = JSON.parse(
  readFileSync(join(evidenceRoot, 'pglite-replay-result.json'), 'utf8'),
);
const currentReplayResult = JSON.parse(
  readFileSync(
    join(evidenceRoot, 'pglite-replay-result-20260817145929.json'),
    'utf8',
  ),
);
const reconciledReplayResult = JSON.parse(
  readFileSync(
    join(
      evidenceRoot,
      'pglite-replay-result-20260823-source-alignment.json',
    ),
    'utf8',
  ),
);

const remoteHistoryReceiptManifest = JSON.parse(
  readFileSync(
    join(
      repositoryRoot,
      'docs',
      'status',
      'SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_20260825.json',
    ),
    'utf8',
  ),
);
const remoteHistoryReceiptFiles = new Set(
  remoteHistoryReceiptManifest.entries.map(
    (entry) => `${entry.version}_${entry.name}.sql`,
  ),
);

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function migrationSource(version) {
  const entry = manifest.history.find((candidate) => candidate.version === version);
  assert.ok(entry, `missing manifest entry ${version}`);
  return readFileSync(join(repositoryRoot, entry.active.path), 'utf8');
}

function chainSha256(filenames) {
  const chain = filenames
    .map((filename) => {
      const source = readFileSync(join(migrationRoot, filename));
      return `${filename}:${sha256(source)}`;
    })
    .join('\n') + '\n';
  return sha256(Buffer.from(chain));
}

function receiptSourceChainSha256(filenames) {
  const chain = filenames
    .map((filename) => {
      const source = readFileSync(join(migrationRoot, filename));
      return `${filename}\t${sha256(source)}\n`;
    })
    .join('');
  return sha256(Buffer.from(chain));
}

function receiptVersionChainSha256(filenames) {
  return sha256(
    Buffer.from(filenames.map((filename) => `${filename.slice(0, 14)}\n`).join('')),
  );
}

test('active Supabase history preserves the captured 52-file recovery chain and appends governed changes', () => {
  const files = readdirSync(migrationRoot)
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))

    .sort();
  const activeFiles = files.filter(
    (filename) => !remoteHistoryReceiptFiles.has(filename),
  );
  const governedForwardFiles = new Set([
    '20260830155431_pandora_build_theatre_latest_job_guard_v1.sql',
    '20260830155516_pandora_static_build_tick_v1.sql',
    '20260830155544_pandora_static_build_cron_v1.sql',
    '20260830160025_pandora_static_build_tick_diagnostics_v2.sql',
    '20260830160159_pandora_static_build_provider_bootstrap_v3.sql',
    '20260830160323_pandora_static_build_fallback_convergence_v4.sql',
    '20260830160904_pandora_observable_acceptance_reverification_v5a.sql',
    '20260830161010_pandora_verified_failure_recovery_v6.sql',
    '20260830191842_vault_backed_legacy_secret_broker_convergence.sql',
    '20260830193644_pandora_supabase_static_production_fallback_v1.sql',
    '20260830193816_pandora_supabase_static_postcommit_verification_v2.sql',
    '20260830194423_pandora_project_version_parent_lineage_v1.sql',
    '20260830224000_pandora_static_site_fullwire_convergence_v1.sql',
    '20260830224500_pandora_production_release_convergence_v1.sql',
    '20260830225000_pandora_static_fallback_hardening_v1.sql',
    '20260830225100_pandora_observable_acceptance_convergence_patch_v5b.sql',
    '20260830233000_pandora_self_healing_source_convergence_v1.sql',
    '20260830235000_pandora_self_healing_projection_state_patch_v2.sql',
    '20260831040500_pandora_project_version_parent_lineage_finalize_v1.sql',
    '20260831045000_pandora_worker_i_project_spec_selection_v1.sql',
    '20260831052000_pandora_source_convergence_release_allowlist_v1.sql',
    '20260831061500_pandora_worker_i_live_trust_verification_v1.sql',
    '20260831063000_pandora_rollback_worker_c_static_v1.sql',
    '20260831070000_pandora_rollback_explicit_approval_v2.sql',
    '20260831080000_pandora_worker_i_live_materialization_queue_v1.sql',
    '20260831083000_pandora_worker_i_required_primitives_array_append_v1.sql',
    '20260831084000_pandora_worker_i_verification_run_lineage_v1.sql',
    '20260831085000_pandora_project_experience_projection_v1.sql',
    '20260831090000_pandora_project_experience_projection_privilege_hardening_v2.sql',
    '20260831143000_pandora_project_experience_drift_telemetry_v1.sql',
    '20260901004803_pandora_intent_distillation_naming_v1.sql',
    '20260901004825_pandora_live_code_stream_v1.sql',
    '20260901035000_align_recovery_authority_and_vercel_scope.sql',
    '20260901040000_align_recovery_authority_constraints.sql',
    '20260901042000_align_vercel_connector_account_identity.sql',
    '20260901054500_pandora_customer_repo_provisioning_v1.sql',
    '20260901060000_pandora_customer_vercel_project_domain_v1.sql',
    '20260901061023_pandora_live_build_protocol_v2.sql',
    '20260901071500_pandora_intent_distillation_naming_v1.sql',
    '20260901074500_pandora_live_code_stream_v1.sql',
    '20260901075624_pandora_build_approval_receipts_v1.sql',
    '20260901075716_pandora_project_conversation_projection_v1.sql',
    '20260901080049_pandora_publish_receipts_v1.sql',
    '20260901080546_pandora_server_owned_build_admission_v1.sql',
    '20260901093000_pandora_publish_receipts_v1.sql',
    '20260901134500_pandora_build_approval_receipts_v1.sql',
    '20260901134600_pandora_project_conversation_projection_v1.sql',
    '20260901150000_pandora_server_owned_build_admission_v1.sql',
    '20260901153000_pandora_build_watchdog_v1.sql',
    '20260901162500_pandora_worker_d_vercel_sandbox_log_readback_v1.sql',
    '20260901162600_pandora_visible_execution_event_protocol_v2.sql',
    '20260901162700_pandora_preview_deployment_stream_trust_v1.sql',
    '20260901173359_pandora_kimi_vault_transport_v1.sql',
    '20260901182500_pandora_build_stream_nonpreview_trigger_fix_v1.sql',
    '20260901183204_pandora_intelligence_thread_routing_state_v1.sql',
    '20260901184000_pandora_model_telemetry_economics_v1.sql',
    '20260901193000_pandora_source_dispatch_exhaustion_watchdog_v1.sql',
    '20260901194449_pandora_kimi_shared_deadline_budget_v2.sql',
    '20260901194558_pandora_kimi_transport_security_hardening_v2.sql',
    '20260901202428_chat_c_kimi_runtime_provider_config_v1.sql',
    '20260901202441_chat_c_edge_runtime_convergence_v1.sql',
    '20260902004500_pandora_change_impact_assessment_v1.sql',
    '20260902013000_pandora_source_entitlements_v1.sql',
    '20260902023000_pandora_database_change_tool_gateway_binding_v1.sql',
    '20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql',
    '20260902040000_align_vercel_supabase_connect_identity.sql',
    '20260902043800_pandora_database_change_apply_identity_fix_v1.sql',
    '20260902045500_pandora_database_change_action_binding_v2.sql',
    '20260902070000_pandora_source_privilege_hardening_v1.sql',
    '20260902094000_pandora_build_model_cost_guard_v1.sql',
    '20260902095600_pandora_stream_event_budget_and_expiry_index_v1.sql',
    '20260903013000_pandora_visible_memory_response_contract_v2.sql',
    '20260903082500_pandora_visible_creation_canary_control_v1.sql',
    '20260903100000_pandora_cost_ledger_append_only_hardening_v1.sql',
    '20260903110000_pandora_generated_intake_replay_semantic_hardening_v1.sql',
    '20260903111000_pandora_primary_project_table_acl_hardening_v1.sql'
  ]);
  const manifestBoundFiles = activeFiles.filter(
    (filename) => !governedForwardFiles.has(filename),
  );
  assert.equal(
    files.length,
    activeFiles.length + remoteHistoryReceiptFiles.size,
  );
  const capturedFiles = [
    ...manifest.history.map((entry) => basename(entry.active.path)),
    basename(manifest.pending_change.path),
    basename(manifest.source_authority_change.path),
  ].sort();
  const capturedSet = new Set(capturedFiles);
  const appendedFiles = activeFiles.filter((filename) => !capturedSet.has(filename));
  const liveIdentityFiles = [
    ...manifest.history.map((entry) => basename(entry.active.path)),
    basename(manifest.pending_change.path),
    basename(manifest.source_authority_change.path),
    ...manifest.identity_reconciliation.shared_post_capture_paths.map((path) =>
      basename(path),
    ),
    ...manifest.source_alignment_records.map((entry) => basename(entry.path)),
  ].sort();
  const replaySnapshotLast = '20260817145929_add_vercel_async_git_link_queue.sql';
  const historicalCurrentFiles = activeFiles.filter((filename) => filename <= replaySnapshotLast);
  const postRecoveryPreSnapshotFiles = historicalCurrentFiles.filter(
    (filename) => !capturedSet.has(filename),
  );
  const capturedPostSnapshotFiles = capturedFiles.filter(
    (filename) => filename > replaySnapshotLast,
  );
  const postSnapshotFiles = activeFiles.filter((filename) => filename > replaySnapshotLast);

  assert.equal(manifest.invariants.historical_identity_count, 50);
  assert.equal(manifest.invariants.active_file_count, 52);
  assert.equal(manifest.invariants.applied_change_count, 2);
  assert.equal(manifest.history.length, 50);
  assert.equal(new Set(manifest.history.map((entry) => entry.version)).size, 50);
  assert.deepEqual(
    manifest.history.map((entry) => entry.version),
    [...manifest.history.map((entry) => entry.version)].sort(),
  );
  assert.equal(new Set(capturedFiles).size, manifest.invariants.active_file_count);
  assert.ok(capturedFiles.every((filename) => activeFiles.includes(filename)));
  assert.deepEqual(appendedFiles, [
    '20260817130000_projectos_memory_full_capacity_context_gate.sql',
    '20260817145550_add_vercel_control_adapter.sql',
    '20260817145659_add_vercel_git_binding_clear.sql',
    '20260817145929_add_vercel_async_git_link_queue.sql',
    '20260820085400_plp_vercel_env_metadata_probe_20260820.sql',
    '20260820085633_plp_hotfix_preview_env_bridge_20260820.sql',
    '20260820085705_plp_hotfix_preview_deploy_20260820.sql',
    '20260820090000_add_pandora_outcome_lifecycle_contracts.sql',
    '20260821024500_projectos_owner_read_completion.sql',
    '20260823143000_add_governed_owner_worker_dispatch.sql',
    '20260823150000_add_safe_execution_terminal_outcomes.sql',
    '20260823153000_harden_governed_worker_lease_and_key_binding.sql',
    '20260823153552_canonical_release_status_readback.sql',
    '20260823155000_add_governed_worker_reviewer_attestation.sql',
    '20260823160000_add_canonical_release_attestations.sql',
    '20260823163000_harden_execution_plan_context_immutability.sql',
    '20260823164000_harden_governed_worker_validation_boundaries.sql',
    '20260823170000_add_immutable_physical_android_receipts.sql',
    '20260823171000_harden_owner_worker_external_authority.sql',
    '20260826005701_pandora_organization_user_administration_v1.sql',
    '20260826010748_pandora_user_administration_service_boundary_v1.sql',
    '20260826011131_remove_legacy_pandora_user_admin_rpc_v1.sql',
    '20260828122655_index_release_worker_foreign_keys.sql',
    '20260828132500_pandora_project_runtime.sql',
    '20260828153500_pandora_project_spec_control_plane_v1.sql',
    '20260828170000_pandora_durable_execution_lineage_v1.sql',
    '20260828181500_pandora_economics_runtime_safety_v1.sql',
    '20260828193000_pandora_realtime_audit_security_v1.sql',
    '20260829103000_pandora_worker_b_gemini_vault_transport.sql',
    '20260829104000_pandora_worker_f_runtime_state.sql',
    '20260829104500_pandora_project_spec_compiler_v1.sql',
    '20260829111500_pandora_worker_f_vercel_scope_rebind.sql',
    '20260829113000_pandora_worker_d_vercel_sandbox_broker_v1.sql',
    '20260829114000_pandora_worker_f_runtime_constraint_idempotency.sql',
    '20260829114500_pandora_worker_f_vercel_webhook_v1.sql',
    '20260829115500_pandora_primitive_lineage_v1.sql',
    '20260829120000_pandora_worker_d_vercel_sandbox_protocol_fix.sql',
    '20260829121000_pandora_generated_source_identity_v1.sql',
    '20260829122000_pandora_project_build_intake_v1.sql',
    '20260829123000_pandora_runtime_release_closure_v1.sql',
    '20260829124000_pandora_live_verification_customer_db_v1.sql',
    '20260829125000_pandora_build_authorization_acl_v1.sql',
    '20260829173000_pandora_runtime_bundle_source_root_transition_v1.sql',
    '20260829173334_pandora_generated_build_rpc_bridge_v1.sql',
    '20260829174000_pandora_runtime_bundle_parent_insert_v1.sql',
    '20260829175000_pandora_runtime_storage_duplicate_replay_v1.sql',
    '20260829176000_pandora_runtime_storage_resume_v1.sql',
    '20260829177000_pandora_runtime_bundle_ledger_state_fix_v1.sql',
    '20260830043500_pandora_worker_b_gemini_generation_timeout_90s.sql',
    '20260830090000_pandora_vercel_domain_registrar.sql',
    '20260830091000_pandora_domain_checkout_payments_v1.sql',
    '20260830092000_pandora_domain_checkout_public_flow_v1.sql',
    '20260830093000_pandora_trusted_intelligence_catalog_convergence_v1.sql',
    '20260830104500_pandora_intelligence_chat_v1.sql',
    '20260830155431_pandora_build_theatre_latest_job_guard_v1.sql',
    '20260830155516_pandora_static_build_tick_v1.sql',
    '20260830155544_pandora_static_build_cron_v1.sql',
    '20260830160025_pandora_static_build_tick_diagnostics_v2.sql',
    '20260830160159_pandora_static_build_provider_bootstrap_v3.sql',
    '20260830160323_pandora_static_build_fallback_convergence_v4.sql',
    '20260830160904_pandora_observable_acceptance_reverification_v5a.sql',
    '20260830161010_pandora_verified_failure_recovery_v6.sql',
    '20260830191842_vault_backed_legacy_secret_broker_convergence.sql',
    '20260830193644_pandora_supabase_static_production_fallback_v1.sql',
    '20260830193816_pandora_supabase_static_postcommit_verification_v2.sql',
    '20260830194423_pandora_project_version_parent_lineage_v1.sql',
    '20260830210000_pandora_worker_f_safe_first_preview.sql',
    '20260830211000_pandora_trusted_intelligence_context_v1.sql',
    '20260830220000_pandora_intelligence_reviewer_gateway_v1.sql',
    '20260830224000_pandora_static_site_fullwire_convergence_v1.sql',
    '20260830224500_pandora_production_release_convergence_v1.sql',
    '20260830225000_pandora_static_fallback_hardening_v1.sql',
    '20260830225100_pandora_observable_acceptance_convergence_patch_v5b.sql',
    '20260830233000_pandora_self_healing_source_convergence_v1.sql',
    '20260830235000_pandora_self_healing_projection_state_patch_v2.sql',
    '20260831040500_pandora_project_version_parent_lineage_finalize_v1.sql',
    '20260831045000_pandora_worker_i_project_spec_selection_v1.sql',
    '20260831052000_pandora_source_convergence_release_allowlist_v1.sql',
    '20260831061500_pandora_worker_i_live_trust_verification_v1.sql',
    '20260831063000_pandora_rollback_worker_c_static_v1.sql',
    '20260831070000_pandora_rollback_explicit_approval_v2.sql',
    '20260831080000_pandora_worker_i_live_materialization_queue_v1.sql',
    '20260831083000_pandora_worker_i_required_primitives_array_append_v1.sql',
    '20260831084000_pandora_worker_i_verification_run_lineage_v1.sql',
    '20260831085000_pandora_project_experience_projection_v1.sql',
    '20260831090000_pandora_project_experience_projection_privilege_hardening_v2.sql',
    '20260831143000_pandora_project_experience_drift_telemetry_v1.sql',
    '20260901004803_pandora_intent_distillation_naming_v1.sql',
    '20260901004825_pandora_live_code_stream_v1.sql',
    '20260901035000_align_recovery_authority_and_vercel_scope.sql',
    '20260901040000_align_recovery_authority_constraints.sql',
    '20260901042000_align_vercel_connector_account_identity.sql',
    '20260901054500_pandora_customer_repo_provisioning_v1.sql',
    '20260901060000_pandora_customer_vercel_project_domain_v1.sql',
    '20260901061023_pandora_live_build_protocol_v2.sql',
    '20260901071500_pandora_intent_distillation_naming_v1.sql',
    '20260901074500_pandora_live_code_stream_v1.sql',
    '20260901075624_pandora_build_approval_receipts_v1.sql',
    '20260901075716_pandora_project_conversation_projection_v1.sql',
    '20260901080049_pandora_publish_receipts_v1.sql',
    '20260901080546_pandora_server_owned_build_admission_v1.sql',
    '20260901093000_pandora_publish_receipts_v1.sql',
    '20260901134500_pandora_build_approval_receipts_v1.sql',
    '20260901134600_pandora_project_conversation_projection_v1.sql',
    '20260901150000_pandora_server_owned_build_admission_v1.sql',
    '20260901153000_pandora_build_watchdog_v1.sql',
    '20260901162500_pandora_worker_d_vercel_sandbox_log_readback_v1.sql',
    '20260901162600_pandora_visible_execution_event_protocol_v2.sql',
    '20260901162700_pandora_preview_deployment_stream_trust_v1.sql',
    '20260901173359_pandora_kimi_vault_transport_v1.sql',
    '20260901182500_pandora_build_stream_nonpreview_trigger_fix_v1.sql',
    '20260901183204_pandora_intelligence_thread_routing_state_v1.sql',
    '20260901184000_pandora_model_telemetry_economics_v1.sql',
    '20260901193000_pandora_source_dispatch_exhaustion_watchdog_v1.sql',
    '20260901194449_pandora_kimi_shared_deadline_budget_v2.sql',
    '20260901194558_pandora_kimi_transport_security_hardening_v2.sql',
    '20260901202428_chat_c_kimi_runtime_provider_config_v1.sql',
    '20260901202441_chat_c_edge_runtime_convergence_v1.sql',
    '20260902004500_pandora_change_impact_assessment_v1.sql',
    '20260902013000_pandora_source_entitlements_v1.sql',
    '20260902023000_pandora_database_change_tool_gateway_binding_v1.sql',
    '20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql',
    '20260902040000_align_vercel_supabase_connect_identity.sql',
    '20260902043800_pandora_database_change_apply_identity_fix_v1.sql',
    '20260902045500_pandora_database_change_action_binding_v2.sql',
    '20260902070000_pandora_source_privilege_hardening_v1.sql',
    '20260902094000_pandora_build_model_cost_guard_v1.sql',
    '20260902095600_pandora_stream_event_budget_and_expiry_index_v1.sql',
    '20260903013000_pandora_visible_memory_response_contract_v2.sql',
    '20260903082500_pandora_visible_creation_canary_control_v1.sql',
    '20260903100000_pandora_cost_ledger_append_only_hardening_v1.sql',
    '20260903110000_pandora_generated_intake_replay_semantic_hardening_v1.sql',
    '20260903111000_pandora_primary_project_table_acl_hardening_v1.sql'
  ]);
  assert.deepEqual(postSnapshotFiles, [
    '20260820085400_plp_vercel_env_metadata_probe_20260820.sql',
    '20260820085633_plp_hotfix_preview_env_bridge_20260820.sql',
    '20260820085705_plp_hotfix_preview_deploy_20260820.sql',
    '20260820090000_add_pandora_outcome_lifecycle_contracts.sql',
    '20260821024500_projectos_owner_read_completion.sql',
    '20260823143000_add_governed_owner_worker_dispatch.sql',
    '20260823150000_add_safe_execution_terminal_outcomes.sql',
    '20260823153000_harden_governed_worker_lease_and_key_binding.sql',
    '20260823153552_canonical_release_status_readback.sql',
    '20260823155000_add_governed_worker_reviewer_attestation.sql',
    '20260823160000_add_canonical_release_attestations.sql',
    '20260823163000_harden_execution_plan_context_immutability.sql',
    '20260823164000_harden_governed_worker_validation_boundaries.sql',
    '20260823170000_add_immutable_physical_android_receipts.sql',
    '20260823171000_harden_owner_worker_external_authority.sql',
    '20260826005701_pandora_organization_user_administration_v1.sql',
    '20260826010748_pandora_user_administration_service_boundary_v1.sql',
    '20260826011131_remove_legacy_pandora_user_admin_rpc_v1.sql',
    '20260828122655_index_release_worker_foreign_keys.sql',
    '20260828132500_pandora_project_runtime.sql',
    '20260828153500_pandora_project_spec_control_plane_v1.sql',
    '20260828170000_pandora_durable_execution_lineage_v1.sql',
    '20260828181500_pandora_economics_runtime_safety_v1.sql',
    '20260828193000_pandora_realtime_audit_security_v1.sql',
    '20260829103000_pandora_worker_b_gemini_vault_transport.sql',
    '20260829104000_pandora_worker_f_runtime_state.sql',
    '20260829104500_pandora_project_spec_compiler_v1.sql',
    '20260829111500_pandora_worker_f_vercel_scope_rebind.sql',
    '20260829113000_pandora_worker_d_vercel_sandbox_broker_v1.sql',
    '20260829114000_pandora_worker_f_runtime_constraint_idempotency.sql',
    '20260829114500_pandora_worker_f_vercel_webhook_v1.sql',
    '20260829115500_pandora_primitive_lineage_v1.sql',
    '20260829120000_pandora_worker_d_vercel_sandbox_protocol_fix.sql',
    '20260829121000_pandora_generated_source_identity_v1.sql',
    '20260829122000_pandora_project_build_intake_v1.sql',
    '20260829123000_pandora_runtime_release_closure_v1.sql',
    '20260829124000_pandora_live_verification_customer_db_v1.sql',
    '20260829125000_pandora_build_authorization_acl_v1.sql',
    '20260829173000_pandora_runtime_bundle_source_root_transition_v1.sql',
    '20260829173334_pandora_generated_build_rpc_bridge_v1.sql',
    '20260829174000_pandora_runtime_bundle_parent_insert_v1.sql',
    '20260829175000_pandora_runtime_storage_duplicate_replay_v1.sql',
    '20260829176000_pandora_runtime_storage_resume_v1.sql',
    '20260829177000_pandora_runtime_bundle_ledger_state_fix_v1.sql',
    '20260830043500_pandora_worker_b_gemini_generation_timeout_90s.sql',
    '20260830090000_pandora_vercel_domain_registrar.sql',
    '20260830091000_pandora_domain_checkout_payments_v1.sql',
    '20260830092000_pandora_domain_checkout_public_flow_v1.sql',
    '20260830093000_pandora_trusted_intelligence_catalog_convergence_v1.sql',
    '20260830104500_pandora_intelligence_chat_v1.sql',
    '20260830155431_pandora_build_theatre_latest_job_guard_v1.sql',
    '20260830155516_pandora_static_build_tick_v1.sql',
    '20260830155544_pandora_static_build_cron_v1.sql',
    '20260830160025_pandora_static_build_tick_diagnostics_v2.sql',
    '20260830160159_pandora_static_build_provider_bootstrap_v3.sql',
    '20260830160323_pandora_static_build_fallback_convergence_v4.sql',
    '20260830160904_pandora_observable_acceptance_reverification_v5a.sql',
    '20260830161010_pandora_verified_failure_recovery_v6.sql',
    '20260830191842_vault_backed_legacy_secret_broker_convergence.sql',
    '20260830193644_pandora_supabase_static_production_fallback_v1.sql',
    '20260830193816_pandora_supabase_static_postcommit_verification_v2.sql',
    '20260830194423_pandora_project_version_parent_lineage_v1.sql',
    '20260830210000_pandora_worker_f_safe_first_preview.sql',
    '20260830211000_pandora_trusted_intelligence_context_v1.sql',
    '20260830220000_pandora_intelligence_reviewer_gateway_v1.sql',
    '20260830224000_pandora_static_site_fullwire_convergence_v1.sql',
    '20260830224500_pandora_production_release_convergence_v1.sql',
    '20260830225000_pandora_static_fallback_hardening_v1.sql',
    '20260830225100_pandora_observable_acceptance_convergence_patch_v5b.sql',
    '20260830233000_pandora_self_healing_source_convergence_v1.sql',
    '20260830235000_pandora_self_healing_projection_state_patch_v2.sql',
    '20260831040500_pandora_project_version_parent_lineage_finalize_v1.sql',
    '20260831045000_pandora_worker_i_project_spec_selection_v1.sql',
    '20260831052000_pandora_source_convergence_release_allowlist_v1.sql',
    '20260831061500_pandora_worker_i_live_trust_verification_v1.sql',
    '20260831063000_pandora_rollback_worker_c_static_v1.sql',
    '20260831070000_pandora_rollback_explicit_approval_v2.sql',
    '20260831080000_pandora_worker_i_live_materialization_queue_v1.sql',
    '20260831083000_pandora_worker_i_required_primitives_array_append_v1.sql',
    '20260831084000_pandora_worker_i_verification_run_lineage_v1.sql',
    '20260831085000_pandora_project_experience_projection_v1.sql',
    '20260831090000_pandora_project_experience_projection_privilege_hardening_v2.sql',
    '20260831143000_pandora_project_experience_drift_telemetry_v1.sql',
    '20260901004803_pandora_intent_distillation_naming_v1.sql',
    '20260901004825_pandora_live_code_stream_v1.sql',
    '20260901035000_align_recovery_authority_and_vercel_scope.sql',
    '20260901040000_align_recovery_authority_constraints.sql',
    '20260901042000_align_vercel_connector_account_identity.sql',
    '20260901054500_pandora_customer_repo_provisioning_v1.sql',
    '20260901060000_pandora_customer_vercel_project_domain_v1.sql',
    '20260901061023_pandora_live_build_protocol_v2.sql',
    '20260901071500_pandora_intent_distillation_naming_v1.sql',
    '20260901074500_pandora_live_code_stream_v1.sql',
    '20260901075624_pandora_build_approval_receipts_v1.sql',
    '20260901075716_pandora_project_conversation_projection_v1.sql',
    '20260901080049_pandora_publish_receipts_v1.sql',
    '20260901080546_pandora_server_owned_build_admission_v1.sql',
    '20260901093000_pandora_publish_receipts_v1.sql',
    '20260901134500_pandora_build_approval_receipts_v1.sql',
    '20260901134600_pandora_project_conversation_projection_v1.sql',
    '20260901150000_pandora_server_owned_build_admission_v1.sql',
    '20260901153000_pandora_build_watchdog_v1.sql',
    '20260901162500_pandora_worker_d_vercel_sandbox_log_readback_v1.sql',
    '20260901162600_pandora_visible_execution_event_protocol_v2.sql',
    '20260901162700_pandora_preview_deployment_stream_trust_v1.sql',
    '20260901173359_pandora_kimi_vault_transport_v1.sql',
    '20260901182500_pandora_build_stream_nonpreview_trigger_fix_v1.sql',
    '20260901183204_pandora_intelligence_thread_routing_state_v1.sql',
    '20260901184000_pandora_model_telemetry_economics_v1.sql',
    '20260901193000_pandora_source_dispatch_exhaustion_watchdog_v1.sql',
    '20260901194449_pandora_kimi_shared_deadline_budget_v2.sql',
    '20260901194558_pandora_kimi_transport_security_hardening_v2.sql',
    '20260901202428_chat_c_kimi_runtime_provider_config_v1.sql',
    '20260901202441_chat_c_edge_runtime_convergence_v1.sql',
    '20260902004500_pandora_change_impact_assessment_v1.sql',
    '20260902013000_pandora_source_entitlements_v1.sql',
    '20260902023000_pandora_database_change_tool_gateway_binding_v1.sql',
    '20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql',
    '20260902040000_align_vercel_supabase_connect_identity.sql',
    '20260902043800_pandora_database_change_apply_identity_fix_v1.sql',
    '20260902045500_pandora_database_change_action_binding_v2.sql',
    '20260902070000_pandora_source_privilege_hardening_v1.sql',
    '20260902094000_pandora_build_model_cost_guard_v1.sql',
    '20260902095600_pandora_stream_event_budget_and_expiry_index_v1.sql',
    '20260903013000_pandora_visible_memory_response_contract_v2.sql',
    '20260903082500_pandora_visible_creation_canary_control_v1.sql',
    '20260903100000_pandora_cost_ledger_append_only_hardening_v1.sql',
    '20260903110000_pandora_generated_intake_replay_semantic_hardening_v1.sql',
    '20260903111000_pandora_primary_project_table_acl_hardening_v1.sql'
  ]);
  assert.equal(historicalCurrentFiles.length, currentReplayResult.migration_count);
  assert.equal(
    currentReplayResult.migration_count,
    recoveryReplayResult.migration_count - capturedPostSnapshotFiles.length +
      postRecoveryPreSnapshotFiles.length,
  );
  assert.equal(manifest.live_chain.first, '20260724010000');
  assert.equal(manifest.live_chain.last, '20260821024500');
  assert.equal(manifest.live_chain.historical_recovery_last, '20260810104737');
  assert.equal(manifest.live_chain.migration_count, 59);
  assert.equal(manifest.invariants.live_identity_count, 59);
  assert.equal(manifest.invariants.source_file_count, manifestBoundFiles.length);
  assert.equal(manifest.invariants.source_live_identity_coverage, 59);
  assert.equal(manifest.invariants.source_only_forward_count, manifestBoundFiles.length - 59);
  assert.equal(liveIdentityFiles.length, manifest.invariants.live_identity_count);
  assert.equal(new Set(liveIdentityFiles).size, liveIdentityFiles.length);
  assert.ok(liveIdentityFiles.every((filename) => activeFiles.includes(filename)));
  assert.equal(
    receiptVersionChainSha256(liveIdentityFiles),
    manifest.live_chain.ordered_version_chain_sha256,
  );
  assert.equal(manifest.pending_change.version, '20260813014555');
  assert.equal(manifest.pending_change.provider_version, '20260813014555');
  assert.equal(manifest.pending_change.legacy_source_version, '20260812034825');
  assert.equal(manifest.pending_change.live_at_capture, true);
  assert.equal(manifest.source_authority_change.version, '20260813105011');
  assert.equal(manifest.source_authority_change.provider_version, '20260813105011');
  assert.equal(manifest.source_authority_change.live_at_capture, true);

  for (const entry of manifest.history) {
    const payload = readFileSync(join(repositoryRoot, entry.active.path));
    assert.equal(payload.length, entry.active.bytes, entry.version);
    assert.equal(sha256(payload), entry.active.sha256, entry.version);
    assert.equal(entry.active.path.split('/').pop().slice(0, 14), entry.version);
    assert.equal(entry.live.sha256.length, 64);
    assert.ok(entry.live.bytes > 0);
  }

  const pending = readFileSync(join(repositoryRoot, manifest.pending_change.path));
  assert.equal(pending.length, manifest.pending_change.bytes);
  assert.equal(sha256(pending), manifest.pending_change.sha256);
  assert.equal(pending.length, manifest.pending_change.provider_bytes);
  assert.equal(sha256(pending), manifest.pending_change.provider_sha256);

  const sourceAuthority = readFileSync(
    join(repositoryRoot, manifest.source_authority_change.path),
  );
  assert.equal(sourceAuthority.length, manifest.source_authority_change.bytes);
  assert.equal(sha256(sourceAuthority), manifest.source_authority_change.sha256);
  const providerSourceAuthority = Buffer.from(
    sourceAuthority.toString('utf8').replace(/\n$/, ''),
  );
  assert.equal(providerSourceAuthority.length, manifest.source_authority_change.provider_bytes);
  assert.equal(
    sha256(providerSourceAuthority),
    manifest.source_authority_change.provider_sha256,
  );

  assert.equal(recoveryReplayResult.migration_count, manifest.invariants.active_file_count);
  assert.equal(
    recoveryReplayResult.chain_sha256,
    manifest.identity_reconciliation.legacy_recovery_chain_sha256,
  );
  assert.equal(
    chainSha256(capturedFiles),
    manifest.identity_reconciliation.reconciled_recovery_chain_sha256,
  );
  assert.equal(
    chainSha256(historicalCurrentFiles),
    manifest.identity_reconciliation.reconciled_aug17_chain_sha256,
  );
  assert.equal(
    currentReplayResult.chain_sha256,
    manifest.identity_reconciliation.legacy_aug17_chain_sha256,
  );
  assert.equal(
    chainSha256(manifestBoundFiles),
    manifest.identity_reconciliation.current_source_replay_chain_sha256,
  );
  assert.equal(
    receiptSourceChainSha256(manifestBoundFiles),
    manifest.identity_reconciliation.current_source_receipt_chain_sha256,
  );
  assert.equal(
    receiptVersionChainSha256(manifestBoundFiles),
    manifest.identity_reconciliation.expected_applied_receipt_chain_sha256,
  );
  // Preserve the dated 2026-08-23 replay receipt as historical evidence.
  assert.equal(reconciledReplayResult.migration_count, 74);
  assert.equal(
    reconciledReplayResult.chain_sha256,
    'fa5039cd8ef4297c1dd01e258c4e8cdfe8725a7aba19b82c48b8ddb24fd8a127',
  );
  // Bind current source independently to current manifest truth.
  assert.equal(
    chainSha256(manifestBoundFiles),
    manifest.validation.reconciled_chain_sha256,
  );
  assert.equal(
    manifestBoundFiles.length,
    manifest.validation.reconciled_migration_count,
  );
  assert.equal(currentReplayResult.provider_equivalence, false);
  assert.equal(manifest.validation.authorization_smoke, 'pass');
  assert.deepEqual(currentReplayResult.assertions.authorization_smoke, {
    aal1_owner_without_session: 'approved',
    operator: 'denied',
    anonymous_owner: 'denied',
    high_risk_requester_as_approver: 'denied',
    audit_event_appended: true,
  });
  assert.deepEqual(currentReplayResult.assertions.source_authority, {
    owner_wildcard: 'mbanatao/*',
    historical_binding_count: 14,
    canonical_fxpass_binding: 'active',
    mixed_case_repository_insert: 'denied',
  });
});

test('remote recovery migration receipts preserve provider history without replaying retired transports', () => {
  assert.equal(remoteHistoryReceiptManifest.schemaVersion, 1);
  assert.equal(remoteHistoryReceiptManifest.projectRef, 'jcyqixttuebxqqfkjonq');
  assert.equal(
    remoteHistoryReceiptManifest.repository,
    'pandora-rvw-314296438-20260820/pandoras-box',
  );
  assert.equal(
    remoteHistoryReceiptManifest.mode,
    'remote_history_receipts_without_replaying_temporary_recovery_surfaces',
  );
  assert.equal(
    remoteHistoryReceiptManifest.migrationCount,
    remoteHistoryReceiptManifest.entries.length,
  );
  assert.equal(
    remoteHistoryReceiptFiles.size,
    remoteHistoryReceiptManifest.migrationCount,
  );

  const receiptFiles = readdirSync(migrationRoot)
    .filter((filename) => remoteHistoryReceiptFiles.has(filename))
    .sort();
  const expectedReceiptFiles = remoteHistoryReceiptManifest.entries
    .map((entry) => `${entry.version}_${entry.name}.sql`)
    .sort();

  assert.deepEqual(receiptFiles, expectedReceiptFiles);
  assert.equal(new Set(expectedReceiptFiles).size, expectedReceiptFiles.length);

  for (const entry of remoteHistoryReceiptManifest.entries) {
    const filename = `${entry.version}_${entry.name}.sql`;
    const source = readFileSync(join(migrationRoot, filename), 'utf8');
    const executableLines = source
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('--'));

    assert.match(entry.version, /^\d{14}$/);
    assert.match(entry.name, /^[a-z0-9_]+$/);
    assert.match(entry.originalSqlSha256, /^[0-9a-f]{64}$/);
    assert.equal(entry.replayMode, 'history_receipt_noop');
    assert.match(source, /^-- Pandora remote migration history receipt\./);
    assert.match(source, new RegExp(`-- Version: ${entry.version}`));
    assert.match(source, new RegExp(`-- Name: ${entry.name}`));
    assert.match(source, new RegExp(entry.originalSqlSha256));
    assert.deepEqual(executableLines, ['select 1;'], filename);
    assert.doesNotMatch(
      executableLines.join('\n'),
      /(vault\.decrypted_secrets|extensions\.http|create\s+or\s+replace\s+function|grant\s+execute)/i,
    );
  }
});

test('live-only privileged hotfix identities are preserved without republishing executable bodies', () => {
  assert.equal(manifest.invariants.identity_only_source_record_count, 3);
  assert.equal(manifest.identity_reconciliation.production_history_rewritten, false);
  assert.equal(manifest.identity_reconciliation.live_only_sensitive_bodies_republished, false);
  assert.equal(
    existsSync(
      join(repositoryRoot, manifest.pending_change.legacy_source_path_at_capture),
    ),
    false,
  );
  assert.equal(manifest.pending_change.legacy_source_path_expected_absent, true);
  assert.equal(existsSync(join(repositoryRoot, manifest.pending_change.path)), true);

  assert.deepEqual(
    manifest.source_alignment_records.map((entry) => entry.version),
    ['20260820085400', '20260820085633', '20260820085705'],
  );

  for (const entry of manifest.source_alignment_records) {
    const payload = readFileSync(join(repositoryRoot, entry.path));
    const source = payload.toString('utf8');
    const executableLines = source
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('--'));

    assert.equal(entry.classification, 'sensitive_obsolete_identity_only');
    assert.equal(entry.live_at_capture, true);
    assert.equal(entry.executable_body_republished, false);
    assert.equal(payload.length, entry.active_bytes, entry.version);
    assert.equal(sha256(payload), entry.active_sha256, entry.version);
    assert.match(source, /SOURCE-ALIGNMENT RECORD ONLY/);
    assert.match(source, new RegExp(entry.provider_sha256));
    assert.deepEqual(executableLines, [], entry.version);
  }
});

test('credential-bearing historical payloads are replaced with database-only values', () => {
  assert.equal(manifest.invariants.raw_provider_payloads_committed, false);
  assert.equal(manifest.invariants.live_secret_or_verifier_literals_committed, false);
  assert.equal(manifest.invariants.historical_sensitive_exposure_remediated, false);
  assert.equal(manifest.invariants.coordinated_rotation_required, true);
  assert.equal(
    existsSync(join(evidenceRoot, 'recorded-payloads')) &&
      readdirSync(join(evidenceRoot, 'recorded-payloads')).length > 0,
    false,
  );
  assert.equal(
    existsSync(join(evidenceRoot, 'recorded-sql')) &&
      readdirSync(join(evidenceRoot, 'recorded-sql')).length > 0,
    false,
  );

  const cases = [
    ['20260728171559', 2],
    ['20260731092135', 1],
    ['20260807083337', 1],
  ];
  const quotedCredential = /'(?:[a-f0-9]{64}|[A-Za-z0-9+/_=-]{64,})'/;

  for (const [version, generatedValueCount] of cases) {
    const source = migrationSource(version);
    assert.equal(
      (source.match(/encode\(extensions\.gen_random_bytes\(32\), 'hex'\)/g) || []).length,
      generatedValueCount,
      version,
    );
    assert.match(source, /on conflict \([^)]*\) do nothing;/i);
    assert.doesNotMatch(source, quotedCredential);
    assert.match(source, /SEMANTIC REDACTION/);
  }
});

test('45 non-sensitive provider payloads retain their exact executable bodies', () => {
  const semanticCopies = manifest.history.filter(
    (entry) => entry.classification === 'semantic_copy',
  );
  assert.equal(semanticCopies.length, 45);
  assert.equal(
    manifest.history.filter((entry) => entry.classification.includes('foundation')).length,
    2,
  );
  assert.equal(
    manifest.history.filter(
      (entry) => entry.classification === 'secret_safe_semantic_reconstruction',
    ).length,
    3,
  );

  for (const entry of semanticCopies) {
    const active = readFileSync(join(repositoryRoot, entry.active.path), 'utf8');
    const separator = active.indexOf('\n\n');
    assert.ok(separator > 0, `${entry.version}: governed header missing`);
    const executableBody = active.slice(separator + 2);
    const possibleProviderHashes = new Set([
      sha256(Buffer.from(executableBody)),
      sha256(Buffer.from(executableBody.replace(/\n$/, ''))),
    ]);
    assert.ok(
      possibleProviderHashes.has(entry.live.sha256),
      `${entry.version}: executable body differs from the recorded provider payload`,
    );
  }
});

test('foundation limitations remain explicit in active recovery source', () => {
  const first = migrationSource('20260724010000');
  const second = migrationSource('20260724030000');

  assert.match(first, /Equivalence to the live historical statement is unprovable/);
  assert.match(first, /create type public\.member_role/);
  assert.match(second, /Reconstructed schema-shape hypothesis/);
  assert.match(second, /Positive grants are intentionally deferred/);
  assert.match(second, /REPLAY-SAFETY INVARIANT, NOT RECOVERED HISTORICAL DDL/);
  assert.doesNotMatch(second, /INACTIVE RECOVERY CANDIDATE/);
});

test('pending ordinary approval boundary is AAL1 owner/admin and fail-closed', () => {
  const source = readFileSync(join(repositoryRoot, manifest.pending_change.path), 'utf8');
  assert.doesNotMatch(source, /auth\.sessions/i);
  assert.doesNotMatch(source, /auth\.aal_level/i);
  assert.doesNotMatch(source, /current_session_id/i);
  assert.match(source, /array\['owner', 'admin'\]::public\.member_role\[\]/);
  assert.doesNotMatch(source, /array\[[^\]]*'operator'/);
  assert.match(source, /is_anonymous/);
  assert.match(source, /approval_row\.decision <> 'pending'/);
  assert.match(source, /approval_row\.expires_at <= timezone\('utc', now\(\)\)/);
  assert.match(source, /step_risk in \('R3'.*'R4'/);
  assert.match(source, /append_audit_event/);
});

test('database rollback restores the exact prior AAL2 executable body', () => {
  const prior = migrationSource('20260810083416');
  const priorBody = prior.slice(prior.indexOf('\n\n') + 2);
  const rollbackPath = join(
    evidenceRoot,
    'rollback',
    '20260812034825_restore_projectos_approval_aal2.sql',
  );
  const rollback = readFileSync(rollbackPath, 'utf8');
  const rollbackBody = rollback.slice(rollback.indexOf('\n\n') + 2);

  assert.equal(rollbackBody, priorBody);
  assert.match(rollbackBody, /auth\.sessions/);
  assert.match(rollbackBody, /current_session_id/);
  assert.match(rollbackBody, /'aal2'/i);
  assert.deepEqual(currentReplayResult.assertions.database_rollback_smoke, {
    restore_previous_aal2_definition: 'pass',
    reapply_aal1_definition: 'pass',
  });
});


test('Worker F historical runtime migration bytes remain immutable', () => {
  const payload = readFileSync(join(migrationRoot, '20260829104000_pandora_worker_f_runtime_state.sql'));
  assert.equal(sha256(payload), '3575e2e38bd22a683159ebb58041ea353b7f17344343fc67207c1b3e58518159');
});
