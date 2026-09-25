/** Immutable identity of the merged #728 foundation. This is not release authority. */
export const REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
export const PROJECT_REF = "jcyqixttuebxqqfkjonq";
export const SOURCE_SHA = "23441474c590d35902a1790b3c2cfa9130dc9109";
export const MIGRATION_VERSION = "20260925101319";
export const MIGRATION_NAME = "pandora_operations_room_runtime_v1";
export const EDGE_SLUG = "pandora-operations-runtime";
export const FILES = Object.freeze([
	Object.freeze({
		path: "supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql",
		sha256: "b364fddc0a04df652aba986469c330d279cfb5b6791d015c84ac983170c108f9",
	}),
	Object.freeze({
		path: "supabase/functions/pandora-operations-runtime/index.ts",
		sha256: "c7085cca8ea1c4809d1a33cb56df661d2dc5c9097d939ea39180528d2e676e07",
	}),
	Object.freeze({
		path: "supabase/functions/pandora-operations-runtime/handler.mjs",
		sha256: "89d3b60ae9b3562c724f0d632043badd233686918629fcef8f0ea5cddf3ed7e4",
	}),
]);
export const TABLES = Object.freeze([
	"pandora_ops_project_bindings", "pandora_ops_workspaces", "pandora_ops_workers",
	"pandora_ops_tasks", "pandora_ops_dependencies", "pandora_ops_leases",
	"pandora_ops_dispatch_outbox", "pandora_ops_events",
]);
export const RPCS = Object.freeze([
	"pandora_ops_project_binding_v1", "pandora_ops_project_scope_v1",
	"pandora_ops_initialize_v1", "pandora_ops_ingest_v1",
	"pandora_ops_register_worker_v1", "pandora_ops_heartbeat_v1",
	"pandora_ops_claim_v1", "pandora_ops_dispatch_v1",
	"pandora_ops_reconcile_required_v1", "pandora_ops_control_v1",
	"pandora_ops_snapshot_v1", "pandora_ops_handoff_v1",
	"pandora_ops_verify_v1", "pandora_ops_recover_v1",
	"pandora_ops_owner_request_v1",
]);
export const HELPERS = Object.freeze([
	"pandora_ops_event_v1", "pandora_ops_immutable_event_v1",
	"pandora_ops_validate_spec_v1", "pandora_ops_settle_v1",
]);
export const TARGETS = Object.freeze({
	database: `supabase/${PROJECT_REF}/migrations/${MIGRATION_VERSION}`,
	edge: `supabase/${PROJECT_REF}/functions/${EDGE_SLUG}`,
});
