"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { GovernedProviderActions } = require("../packages/pandora-operations-room/provider-actions");
const modules = Promise.all([
	import("../scripts/operations-room-rollout/rollout.mjs"),
	import("../scripts/operations-room-rollout/manifest.mjs"),
]);
const NOW = Date.parse("2026-09-25T19:00:00Z");
const time = new Date(NOW).toISOString();
function fixture(m, installed = false, deployed = false) {
	return {
		projectRef: m.PROJECT_REF, observedAt: time,
		catalog: {
			observedAt: time, rolesReady: true,
			migration: { version: m.MIGRATION_VERSION, count: installed ? 1 : 0,
				name: installed ? m.MIGRATION_NAME : null, aliases: [] },
			tables: m.TABLES.map((name) => ({ name, exists: installed, kind: installed ? "r" : null,
				rls: installed ? true : null, anonAccess: installed ? false : null,
				authenticatedAccess: installed ? false : null, serviceRoleAccess: installed ? false : null })),
			functions: [...m.RPCS, ...m.HELPERS].map((name) => ({ name,
				schema: m.RPCS.includes(name) ? "public" : "private", overloads: installed ? 1 : 0,
				securityDefiner: installed, searchPathPinned: installed,
				anonExecute: installed ? false : null, authenticatedExecute: installed ? false : null,
				serviceRoleExecute: installed ? m.RPCS.includes(name) : null })),
			pausedDefault: installed ? true : null, noProductionDefault: installed ? true : null,
		},
		counts: installed ? { observedAt: time, bindings: 0, workspaces: 0, unpausedWorkspaces: 0,
			productionEnabledWorkspaces: 0, workers: 0, freshAcknowledgedWorkers: 0,
			tasks: 0, activeLeases: 0, dispatches: 0, events: 0 } : null,
		edge: { projectRef: m.PROJECT_REF, slug: m.EDGE_SLUG, observedAt: time,
			state: deployed ? "active" : "absent", ...(deployed ? {
				version: 1, verifyJwt: true,
				files: Object.fromEntries(m.FILES.slice(1).map((f) => [path.basename(f.path), f.sha256])),
			} : {}) },
	};
}
function sourceReader(m) {
	return async (request) => ({ ...request,
		content: fs.readFileSync(path.join(__dirname, "..", request.path), "utf8") });
}
function scope(m) {
	return { taskId: "OPS-ACTIVATION-CANARY", generation: 1,
		organizationId: "00000000-0000-4000-8000-000000000001",
		projectId: "00000000-0000-4000-8000-000000000002",
		sourceSha: m.SOURCE_SHA, targets: Object.values(m.TARGETS) };
}
test("missing foundation is not an empty successful installation", async () => {
	const [r, m] = await modules;
	const result = r.inspectFoundation(fixture(m), NOW);
	assert.equal(result.databaseState, "absent");
	assert.equal(result.edgeState, "absent");
	assert.equal(result.foundationStaged, false);
	assert.equal(result.autonomyAccepted, false);
});
test("paused source parity is foundation staging, never whole-sheet acceptance", async () => {
	const [r, m] = await modules;
	const result = r.inspectFoundation(fixture(m, true, true), NOW);
	assert.equal(result.foundationStaged, true);
	assert.equal(result.autonomyAccepted, false);
	assert.deepEqual(result.issues, []);
});
const mutations = [
	["wrong project", (s) => { s.projectRef = "another_project"; }],
	["stale snapshot", (s) => { s.observedAt = new Date(NOW - 30001).toISOString(); }],
	["future snapshot", (s) => { s.observedAt = new Date(NOW + 1).toISOString(); }],
	["invalid timestamp", (s) => { s.observedAt = "yesterday"; }],
	["missing roles", (s) => { s.catalog.rolesReady = false; }],
	["stale catalog", (s) => { s.catalog.observedAt = new Date(NOW - 30001).toISOString(); }],
	["empty table roster", (s) => { s.catalog.tables = []; }],
	["duplicate table roster", (s) => { s.catalog.tables[0] = s.catalog.tables[1]; }],
	["wrong table object kind", (s) => { s.catalog.tables[0].kind = "v"; }],
	["disabled RLS", (s) => { s.catalog.tables[0].rls = false; }],
	["anonymous table grant", (s) => { s.catalog.tables[0].anonAccess = true; }],
	["authenticated table grant", (s) => { s.catalog.tables[0].authenticatedAccess = true; }],
	["service direct table grant", (s) => { s.catalog.tables[0].serviceRoleAccess = true; }],
	["empty RPC roster", (s) => { s.catalog.functions = []; }],
	["unexpected RPC overload", (s) => { s.catalog.functions[0].overloads = 2; }],
	["anonymous RPC execution", (s) => { s.catalog.functions[0].anonExecute = true; }],
	["authenticated RPC execution", (s) => { s.catalog.functions[0].authenticatedExecute = true; }],
	["service execution missing", (s) => { s.catalog.functions[0].serviceRoleExecute = false; }],
	["mutable search path", (s) => { s.catalog.functions[0].searchPathPinned = false; }],
	["private helper exposed", (s) => { s.catalog.functions.at(-1).serviceRoleExecute = true; }],
	["wrong RPC schema", (s) => { s.catalog.functions[0].schema = "private"; }],
	["unsafe pause default", (s) => { s.catalog.pausedDefault = false; }],
	["unsafe production default", (s) => { s.catalog.noProductionDefault = false; }],
	["missing exact migration", (s) => { s.catalog.migration.count = 0; }],
	["migration count string", (s) => { s.catalog.migration.count = "1"; }],
	["migration alias", (s) => { s.catalog.migration.aliases = ["20260926000100"]; }],
	["different migration name", (s) => { s.catalog.migration.name = "unreviewed_replacement"; }],
	["counts unknown", (s) => { s.counts = null; }],
	["stale counts", (s) => { s.counts.observedAt = new Date(NOW - 30001).toISOString(); }],
	["string zero count", (s) => { s.counts.workers = "0"; }],
	["negative count", (s) => { s.counts.workers = -1; }],
	["unsafe large count", (s) => { s.counts.workers = Number.MAX_SAFE_INTEGER + 1; }],
	["inconsistent worker count", (s) => { s.counts.freshAcknowledgedWorkers = 1; }],
	["unpaused workspace", (s) => { s.counts.workspaces = 1; s.counts.unpausedWorkspaces = 1; }],
	["production enabled", (s) => { s.counts.workspaces = 1; s.counts.productionEnabledWorkspaces = 1; }],
	["active lease", (s) => { s.counts.activeLeases = 1; }],
	["wrong Edge project", (s) => { s.edge.projectRef = "other"; }],
	["wrong Edge slug", (s) => { s.edge.slug = "pandora-worker-dispatch"; }],
	["Edge JWT disabled", (s) => { s.edge.verifyJwt = false; }],
	["Edge version string", (s) => { s.edge.version = "1"; }],
	["Edge source absent", (s) => { s.edge.files = {}; }],
	["unexpected Edge sibling", (s) => { s.edge.files["extra.ts"] = "unreviewed"; }],
	["Edge source drift", (s) => { s.edge.files["handler.mjs"] = "0".repeat(64); }],
	["stale Edge inventory", (s) => { s.edge.observedAt = new Date(NOW - 30001).toISOString(); }],
];
for (const [label, mutate] of mutations) test(`fail closed: ${label}`, async () => {
	const [r, m] = await modules;
	const s = fixture(m, true, true); mutate(s);
	const result = r.inspectFoundation(s, NOW);
	assert.equal(result.foundationStaged, false);
	assert.equal(result.autonomyAccepted, false);
	assert.ok(result.issues.length > 0);
});
test("partial schema is never eligible for blind migration replay", async () => {
	const [r, m] = await modules;
	const s = fixture(m); s.catalog.tables[0].exists = true;
	assert.equal(r.inspectFoundation(s, NOW).databaseState, "partial_or_mismatched");
});
test("collector does not query missing runtime tables", async () => {
	const [r, m] = await modules;
	const s = fixture(m), calls = [];
	const result = await r.collectFoundation({ clock: () => NOW,
		readDatabase: async (q) => { calls.push(q.kind); return { projectRef: m.PROJECT_REF, data: s.catalog }; },
		readEdge: async () => s.edge });
	assert.deepEqual(calls, ["catalog"]);
	assert.equal(result.snapshot.counts, null);
});
test("collector reads actual counts only after catalogue presence", async () => {
	const [r, m] = await modules;
	const s = fixture(m, true, true), calls = [];
	const result = await r.collectFoundation({ clock: () => NOW,
		readDatabase: async (q) => { calls.push(q.kind); return { projectRef: m.PROJECT_REF,
			data: q.kind === "catalog" ? s.catalog : s.counts }; }, readEdge: async () => s.edge });
	assert.deepEqual(calls, ["catalog", "counts"]);
	assert.equal(result.assessment.foundationStaged, true);
});
test("collector rejects wrong database transport target", async () => {
	const [r, m] = await modules;
	await assert.rejects(r.collectFoundation({ clock: () => NOW,
		readDatabase: async () => ({ projectRef: "other", data: fixture(m).catalog }),
		readEdge: async () => fixture(m).edge }), /DATABASE_TRANSPORT_SCOPE_MISMATCH/);
});
test("immutable manifest matches actual checked-in #728 bytes", async () => {
	const [r, m] = await modules;
	assert.equal((await r.verifyFoundationSource(sourceReader(m))).length, 3);
});
for (const field of ["sourceSha", "repository", "path", "content"]) test(`source binding rejects changed ${field}`, async () => {
	const [r, m] = await modules;
	await assert.rejects(r.verifyFoundationSource(async (request) => {
		const source = await sourceReader(m)(request); source[field] = "changed"; return source;
	}), /EXACT_SOURCE_DIGEST_MISMATCH/);
});
function harness(m, options = {}) {
	let db = options.installed === true, edge = options.deployed === true;
	const calls = [];
	const actions = new GovernedProviderActions({
		verifyCurrentLease: async () => options.revoked !== true,
		executeGoverned: async (action, evidence) => {
			calls.push(action);
			if (options.throwProvider) throw new Error("private provider diagnostics must not escape");
			if (options.blocked) return { state: "blocked", executed: false };
			if (action.operation === "supabase.migration.apply") db = true;
			else edge = true;
			return { state: "completed", receiptRef: `provider:${evidence.actionHash}` };
		},
		readback: async (_, result) => ({ verified: !options.uncertain, actionHash: result.receiptRef.slice(9), receiptRef: "provider:readback" }),
	});
	return { calls, actions, clock: () => NOW, readSource: sourceReader(m),
		observe: async () => fixture(m, db, edge) };
}
test("staging uses existing governed boundary in database-then-Edge order", async () => {
	const [r, m] = await modules; const h = harness(m);
	const result = await r.stageFoundation(h, scope(m));
	assert.equal(result.state, "foundation_staged");
	assert.equal(result.autonomyAccepted, false);
	assert.equal(result.receipts.length, 2);
	assert.deepEqual(h.calls.map((x) => x.operation), ["supabase.migration.apply", "supabase.edge.deploy"]);
	assert.equal(h.calls[0].parameters.repairHistory, false);
	assert.equal(h.calls[1].parameters.verifyJwt, true);
	assert.equal(h.calls[1].parameters.allowOverwrite, false);
	for (const action of h.calls) for (const key of ["sql", "query", "token", "shell", "command"])
		assert.equal(Object.hasOwn(action.parameters, key), false);
});
test("already staged foundation is a verified no-op, not a repeated deployment", async () => {
	const [r, m] = await modules; const h = harness(m, { installed: true, deployed: true });
	assert.equal((await r.stageFoundation(h, scope(m))).state, "foundation_staged");
	assert.equal(h.calls.length, 0);
});
test("existing database needs only missing Edge deployment", async () => {
	const [r, m] = await modules; const h = harness(m, { installed: true });
	assert.equal((await r.stageFoundation(h, scope(m))).state, "foundation_staged");
	assert.deepEqual(h.calls.map((a) => a.operation), ["supabase.edge.deploy"]);
});
for (const kind of ["blocked", "throwProvider", "uncertain", "revoked"]) test(`no retry or next action after ${kind}`, async () => {
	const [r, m] = await modules; const h = harness(m, { [kind]: true });
	const result = await r.stageFoundation(h, scope(m));
	assert.notEqual(result.state, "foundation_staged");
	assert.equal(result.autonomyAccepted, false);
	assert.ok(h.calls.length <= 1);
	assert.ok(!JSON.stringify(result).includes("private provider diagnostics"));
});
test("no standalone allow boolean can replace M3 authorization and execution", async () => {
	const [r, m] = await modules;
	await assert.rejects(r.stageFoundation({ ...harness(m), actions: { invoke: async () => ({ state: "completed" }) } }, scope(m)), /GOVERNED_RELEASE_ADAPTER_REQUIRED/);
});
test("live source lease cannot stage a different SHA", async () => {
	const [r, m] = await modules;
	await assert.rejects(r.stageFoundation(harness(m), { ...scope(m), sourceSha: "a".repeat(40) }), /RELEASE_SCOPE_INVALID/);
});
test("existing active work blocks staging without any provider mutation", async () => {
	const [r, m] = await modules; const h = harness(m, { installed: true });
	h.observe = async () => { const s = fixture(m, true); s.counts.activeLeases = 1; return s; };
	assert.equal((await r.stageFoundation(h, scope(m))).state, "blocked");
	assert.equal(h.calls.length, 0);
});
