# Production migration reconciliation audit — 2026-10-03

Read-only comparison of canonical repo `7ce01075b42d9d4666cca089f7b9abf3cc98e406` and production Supabase project `jcyqixttuebxqqfkjonq`. No migration was applied, reverted, repaired, or pushed during this audit.

## Inventory

- Local migration files: 926
- Production migration-history records: 858
- Local versions absent from production history: 68
- Same migration name already recorded under another production version: 57
- Local migration names with no production history record at all: 11

Supabase migration tracking is version/timestamp based, so all 68 version gaps matter to `db push`. They are not equivalent to 68 unapplied schema changes: 57 already have an equivalent migration name recorded under another timestamp and must be verified before any history repair.

## Local names with no production record

| Local version | Name |
| --- | --- |
| `20260925090001` | `pandora_authorization_replay_finalizer` |
| `20260925091800` | `execution_audit_head_adjacency_v2` |
| `20260927090000` | `operations_preflight_source_route_v1` |
| `20260927111500` | `operations_rdp_artemis_verifier_v1` |
| `20260927112500` | `operations_model_rdp_vercel_hobby_hold_v1` |
| `20260928170000` | `operations_native_reasoning_rdp_consolidation_v1` |
| `20260929115500` | `operations_merged_dispatched_source_reconciliation_v1` |
| `20261001134500` | `plp_resort_transaction_v1` |
| `20261002091500` | `pandora_lane_f_model_control_v1` |
| `20261002102000` | `pandora_lane_f_bedrock_live_catalog_v2` |
| `20261003015000` | `pandora_chat_model_picker_projection_v1` |

## Version gaps whose migration name already exists remotely

| Local version | Name | Production recorded version(s) |
| --- | --- | --- |
| `20260926044500` | `operations_vercel_cron_wake_v1` | `20260926081711` |
| `20260926121500` | `pandora_meta_business_login_config_id_v1` | `20260926141512` |
| `20260926142630` | `operations_generic_source_worker_v1` | `20260927021055` |
| `20260927020000` | `operations_source_release_fail_closed_v1` | `20260927032623` |
| `20260927041500` | `facebook_first_party_event_contract_v1` | `20260927042934` |
| `20260927043500` | `pandora_meta_readiness_projection_v1` | `20260927102008` |
| `20260927050137` | `operations_rdp_worker_v1` | `20260927052607` |
| `20260927070752` | `operations_reasoning_fleet_v1` | `20260927080647` |
| `20260927081217` | `bedrock_provider_hold_v1` | `20260927082711` |
| `20260927093535` | `operations_model_rdp_bridge_v1` | `20260927110738` |
| `20260927105500` | `operations_chatgpt_direct_ingress_v1` | `20260927110744` |
| `20260927170700` | `operations_source_release_receipt_selection_v1` | `20260928121636` |
| `20260928031824` | `operations_external_success_reconciliation_v1` | `20260928075531` |
| `20260928072000` | `operations_private_rls_hardening_v1` | `20260928075537` |
| `20260928080500` | `operations_external_success_stale_base_v1` | `20260928200644` |
| `20260928190000` | `operations_merged_release_reconciliation_v1` | `20260928230530` |
| `20260928203000` | `pandora_meta_plugin_runtime_v4_bridge` | `20260929005202` |
| `20260928210000` | `pandora_meta_existing_grants_health_refresh` | `20260929005209` |
| `20260929013000` | `pandora_learning_outbox_fencing_v2` | `20260929005215` |
| `20260929014500` | `pandora_tracking_minimization_v1` | `20260929005222` |
| `20260929023000` | `pandora_meta_runtime_secret_expiry_fail_closed_v1` | `20260929005230` |
| `20260929040000` | `growth_learning_outbox_delivery_v1` | `20260929005237` |
| `20260929044500` | `pandora_meta_disconnect_local_v1` | `20260929014014` |
| `20260929070000` | `pandora_facebook_measurement_foundation_v1` | `20260929021429`, `20260929021451` |
| `20260929104000` | `growth_test_traffic_truth_v1` | `20260929040419`, `20260929040530` |
| `20260929121000` | `operations_provider_verified_source_adoption_v1` | `20260929041356` |
| `20260929121500` | `facebook_controlled_capi_acceptance_v1` | `20260929050221` |
| `20260929121600` | `operations_provider_source_adoption_merge_binding_fix_v1` | `20260929041536` |
| `20260929122500` | `growth_learning_native_delivery_v1` | `20260929100101` |
| `20260929122600` | `growth_learning_pandora_identity_v2` | `20260929100108` |
| `20260929123000` | `marketing_growth_command_center_v1` | `20260929044932` |
| `20260929134500` | `facebook_g2_audit_acceptance_v1` | `20260929060252` |
| `20260929135000` | `operations_provider_source_adoption_merge_binding_fix_v1` | `20260929041536` |
| `20260929143000` | `meta_zero_delivery_action_broker_v1` | `20260929210115` |
| `20260929150000` | `growth_experiment_evaluator_v1` | `20260929190731` |
| `20260930012000` | `marketing_growth_direct_workspace_v2` | `20260929192027` |
| `20260930100000` | `pandora_universal_core_foundation_v1` | `20260930040608` |
| `20260930101500` | `pandora_universal_core_registry_rls_v1` | `20260930044344` |
| `20260930110000` | `pandora_universal_core_compatibility_activation_v1` | `20260930065306` |
| `20260930111000` | `pandora_capability_provider_activation_v1` | `20260930065313` |
| `20260930112000` | `pandora_industry_packs_onboarding_v1` | `20260930065324` |
| `20260930113000` | `pandora_consent_enforcement_v1` | `20260930114627` |
| `20260930114000` | `pandora_universal_closeout_v1` | `20260930144310` |
| `20261001044500` | `plp_resort_command_center_v1` | `20260930211707` |
| `20261001070000` | `plp_resort_operations_v1` | `20260930235216`, `20261001001525` |
| `20261001130000` | `pandora_connections_lane_a_v1` | `20261001133304` |
| `20261001133930` | `pandora_connections_public_execute_hardening` | `20261001135901`, `20261001135940`, `20261001142120` |
| `20261001140500` | `pandora_google_workspace_oidc_verification_v2` | `20261001143709` |
| `20261001140843` | `pandora_ph_government_public_connections` | `20261001145904` |
| `20261001143000` | `pandora_connections_provider_readback_hardening_v1` | `20261001143713` |
| `20261001144500` | `pandora_connection_write_step_up_hardening_v1` | `20261001143716` |
| `20261001150414` | `pandora_public_safe_read_secret_false_allowlist_v1` | `20261001151811` |
| `20261002103500` | `pandora_connection_verification_observations_v1` | `20261002104041` |
| `20261002104500` | `pandora_connection_verify_vault_no_spend_v1` | `20261002104333` |
| `20261002112500` | `pandora_bedrock_catalog_sync_v2` | `20261002114025` |
| `20261002120500` | `pandora_bedrock_control_trigger_v1` | `20261002115959` |
| `20261002124000` | `pandora_bedrock_sync_preserve_runtime_v1` | `20261002131717` |

## Safe reconciliation plan — report only, do not execute yet

1. Capture a fresh production schema and migration-history snapshot.
2. For each same-name timestamp drift, compare the local SQL's intended post-state with live schema/functions/policies. Only when the post-state is provider-verified equivalent should the local timestamp be marked applied in migration history; do not replay SQL merely to make timestamps match.
3. For each name with no production record, classify it as already present by live evidence, superseded, intentionally unapplied, or genuinely required. Do not infer from filename alone.
4. Treat `20261002102000_pandora_lane_f_bedrock_live_catalog_v2` specially: after this PR its legacy constraint block is safe against the newer #911/#917 table shape. Still dry-run the complete pending sequence before any production change.
5. Run a migration dry-run after any approved history repair. The resulting pending set must contain only SQL that genuinely needs execution.
6. Apply only an explicitly approved pending set, then read back migration history, Bedrock constraints/functions/catalog state and app-facing RPC behavior.
7. Do not delete or rewrite production history just to make lists visually identical.

## #907 forward-compatibility rationale

Production already contains the newer #911/#917 Bedrock shape, including `entitlement_status`, and live rows use runtime states including `authorized`, `entitled`, `region_available`, `runtime_tested`, `routable`, and `retired`. The original #907 unconditionally replaced the runtime-state check with the older vocabulary and also added legacy checks. A late #907 replay would therefore reject valid newer rows.

The repaired #907 detects the newer `entitlement_status` column and skips only its legacy constraint block. Fresh installs that have not reached #911 still receive the original #907 checks, preserving ordered migration behavior.
