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

// Exact #728 routine bodies; independently checked against disposable migration execution.
export const FUNCTION_BODY_SHA256 = Object.freeze({
    "public.pandora_ops_claim_v1": "9bfb8b3ee34581fdfa1995aec1086afc1f5d6f63f3b77c346b8193d702a4597a",
    "private.pandora_ops_event_v1": "871d8d4b122385a2b67b9219144c43e70479f514c18a27e482b66adab1eb3bc7",
    "public.pandora_ops_ingest_v1": "864fac17d374ede7ce89be4a6fa4be827edaaf853d26598f919a27a692793dfc",
    "public.pandora_ops_verify_v1": "52a8f889cedd8e0fe191d935ec282ab310fa51a9a8fd5d00daa6c7c6d764885e",
    "private.pandora_ops_settle_v1": "0d9f201fd25d3f896d122d52369f802caf2d8729fec41725741be6081d57258e",
    "public.pandora_ops_control_v1": "7fdfc9e24876d267c35a5f6d978eb62bf801d23544d23b980cf42f9f63a8f00c",
    "public.pandora_ops_handoff_v1": "c68d1bcd4ac68276addc52942bda1d2a6be5518acf5f59fb287a719e525b0ce2",
    "public.pandora_ops_recover_v1": "0bdd289a4c5748272bb2c67df370f57f4b4167efb71d376ffdb23d75328972de",
    "public.pandora_ops_dispatch_v1": "9526c8b6dd27e1cfe6ad2a2ba5c0cd63395aef89fad418ba913aa820bc928c37",
    "public.pandora_ops_snapshot_v1": "15cb52dcc9da7d77ba43ee974004a6019fdea0ed02fba41500bb18579dbf738e",
    "public.pandora_ops_heartbeat_v1": "3921219af7337200fe66bd6947cd9a63b075a1c40005c7877cd6a94d0704d90c",
    "public.pandora_ops_initialize_v1": "f84efffc9f3ba3a806acaf8aeb27257545095a5b8e8e72287c84907646c8bbd6",
    "public.pandora_ops_owner_request_v1": "14bdc203728e768dfc3fbc172142571fd6cf6a1046db80b016c593931a97f596",
    "public.pandora_ops_project_scope_v1": "3b3e0011c4bd3b5dbc14cc39ada77dd88fc0f85f7989dd4cb02fdbac9cb0931d",
    "private.pandora_ops_validate_spec_v1": "deca2d27b92f94adf0eea3765b4b9ef7cbeb82128b976203a8d43d46878cc395",
    "public.pandora_ops_project_binding_v1": "4f6b77b6d02ae2a00d8e476d6b8fb45de075777f0dba074b9b21d5f5ba01d32d",
    "public.pandora_ops_register_worker_v1": "fcfde28aebff96e653fcb6a18f96c2b07272e42a2952d26ea8eb20bc1e593f95",
    "private.pandora_ops_immutable_event_v1": "b09580a458cd9faac158e027c32b6ccadbfc606fccdc02c9dae2187e099a9cb6",
    "public.pandora_ops_reconcile_required_v1": "83955114376e3c792d1fde1650401c99985b220b308c11ad066c08eeb823d03f"
});
