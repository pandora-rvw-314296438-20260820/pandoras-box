"use strict";
const test = require("node:test"),
	assert = require("node:assert/strict"),
	{ randomUUID } = require("node:crypto"),
	fs = require("node:fs"),
	path = require("node:path");
const { PGlite } = require("@electric-sql/pglite");
const {
	normalizeTask,
	REPOSITORIES,
} = require("../packages/pandora-operations-room/contracts");
const {
	SupabaseOperationsStore,
} = require("../packages/pandora-operations-room/postgres-store");
const {
	OperationsRuntime,
} = require("../packages/pandora-operations-room/runtime");
const migration = fs.readFileSync(
	path.join(
		__dirname,
		"../supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql",
	),
	"utf8",
);
let db;
const SHA = "a".repeat(40);
function spec(id = "A", patch = {}) {
	return normalizeTask({
		id,
		title: "Task " + id,
		lane: "backend",
		priority: 1,
		dependsOn: [],
		resources: [{ key: "source/box/" + id, mode: "write" }],
		requiredCapabilities: ["source.write"],
		maxCostMicros: 10,
		maxDurationSeconds: 60,
		maxAttempts: 2,
		risk: "source",
		acceptance: ["exact-source tests"],
		source: { repository: REPOSITORIES[0], baseSha: SHA },
		...patch,
	});
}
