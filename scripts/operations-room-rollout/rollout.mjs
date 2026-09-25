import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import {
	REPOSITORY, PROJECT_REF, SOURCE_SHA, MIGRATION_VERSION, MIGRATION_NAME,
	EDGE_SLUG, FILES, TABLES, RPCS, HELPERS, TARGETS,
} from "./manifest.mjs";
const { GovernedProviderActions } = createRequire(import.meta.url)(
	"../../packages/pandora-operations-room/provider-actions.js",
);
const INVENTORY_SQL = readFileSync(new URL("./database-inventory.sql", import.meta.url), "utf8");
const COUNTS_SQL = readFileSync(new URL("./runtime-counts.sql", import.meta.url), "utf8");
const COUNT_KEYS = Object.freeze([
	"bindings", "workspaces", "unpausedWorkspaces", "productionEnabledWorkspaces",
	"workers", "freshAcknowledgedWorkers", "tasks", "activeLeases", "dispatches", "events",
]);
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const assert = (ok, code) => { if (!ok) throw new Error(code); };
const hash = (s) => createHash("sha256").update(s, "utf8").digest("hex");

const deadline = (ms) => {
	assert(Number.isSafeInteger(ms) && ms >= 1 && ms <= 30000, "IO_DEADLINE_INVALID");
	return ms;
};
async function bounded(call, ms, code) {
	const controller = new AbortController();
	let timer;
	try {
		return await Promise.race([
			Promise.resolve().then(() => call(controller.signal)),
			new Promise((_, reject) => {
				timer = setTimeout(() => {
					controller.abort();
					reject(new Error(code));
				}, ms);
			}),
		]);
	} catch {
		// Do not leak transport errors, response bodies or credentials to the caller.
		throw new Error(code);
	} finally {
		clearTimeout(timer);
	}
}

const recent = (value, now) => {
	if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT.*(?:Z|[+-]\d\d:\d\d)$/.test(value)) return false;
	const time = Date.parse(value);
	return Number.isFinite(time) && time <= now && now - time <= 30000;
};
const exactRoster = (rows, expected, key = "name") => Array.isArray(rows)
	&& rows.length === expected.length
	&& new Set(rows.map((r) => r?.[key])).size === expected.length
	&& expected.every((name) => rows.some((r) => object(r) && r[key] === name));
const allAbsent = (catalog) => exactRoster(catalog.tables, TABLES)
	&& catalog.tables.every((r) => r.exists === false)
	&& exactRoster(catalog.functions, [...RPCS, ...HELPERS])
	&& catalog.functions.every((r) => r.overloads === 0);
const cleanCatalog = (catalog) => exactRoster(catalog.tables, TABLES)
	&& catalog.tables.every((r) => r.exists === true && r.kind === "r" && r.rls === true
		&& r.anonAccess === false && r.authenticatedAccess === false && r.serviceRoleAccess === false)
	&& exactRoster(catalog.functions, [...RPCS, ...HELPERS])
	&& catalog.functions.every((r) => r.overloads === 1 && r.anonExecute === false
		&& r.authenticatedExecute === false && r.searchPathPinned === true
		&& (RPCS.includes(r.name)
			? r.schema === "public" && r.securityDefiner === true && r.serviceRoleExecute === true
			: r.schema === "private" && r.serviceRoleExecute === false))
	&& catalog.pausedDefault === true && catalog.noProductionDefault === true;
const countsValid = (counts, now) => object(counts) && recent(counts.observedAt, now)
	&& COUNT_KEYS.every((k) => Number.isSafeInteger(counts[k]) && counts[k] >= 0)
	&& counts.unpausedWorkspaces <= counts.workspaces
	&& counts.productionEnabledWorkspaces <= counts.workspaces
	&& counts.freshAcknowledgedWorkers <= counts.workers;

/** Observations are evidence inputs, not credentials or permission to mutate. */
export function inspectFoundation(snapshot, now = Date.now()) {
	assert(Number.isSafeInteger(now) && now >= 0, "CLOCK_INVALID");
	const issues = [];
	let databaseState = "unknown", edgeState = "unknown";
	if (!object(snapshot) || snapshot.projectRef !== PROJECT_REF || !recent(snapshot.observedAt, now)) {
		return { databaseState, edgeState, foundationStaged: false, autonomyAccepted: false,
			issues: ["SNAPSHOT_SCOPE_OR_FRESHNESS_INVALID"] };
	}
	const catalog = snapshot.catalog;
	if (!object(catalog) || catalog.rolesReady !== true || !recent(catalog.observedAt, now)) {
		issues.push("DATABASE_OBSERVATION_UNAVAILABLE");
	} else if (!object(catalog.migration) || catalog.migration.version !== MIGRATION_VERSION
		|| !Number.isSafeInteger(catalog.migration.count) || catalog.migration.count < 0
		|| !Array.isArray(catalog.migration.aliases) || catalog.migration.aliases.length !== 0) {
		issues.push("MIGRATION_IDENTITY_REQUIRES_RECONCILIATION");
	} else if (catalog.migration.count === 0 && allAbsent(catalog)) {
		databaseState = "absent";
	} else if (catalog.migration.count === 1 && catalog.migration.name === MIGRATION_NAME && cleanCatalog(catalog)) {
		if (!countsValid(snapshot.counts, now)) {
			issues.push("EXACT_RUNTIME_COUNTS_REQUIRED");
		} else if (snapshot.counts.unpausedWorkspaces !== 0 || snapshot.counts.productionEnabledWorkspaces !== 0
			|| snapshot.counts.activeLeases !== 0) {
			databaseState = "active_requires_handoff";
			issues.push("ACTIVE_WORK_MUST_NOT_BE_RECONFIGURED");
		} else databaseState = "installed_paused";
	} else {
		databaseState = "partial_or_mismatched";
		issues.push("DATABASE_PARITY_OR_PRIVILEGE_MISMATCH");
	}
	const edge = snapshot.edge;
	if (!object(edge) || edge.projectRef !== PROJECT_REF || edge.slug !== EDGE_SLUG || !recent(edge.observedAt, now)) {
		issues.push("EDGE_OBSERVATION_UNAVAILABLE");
	} else if (edge.state === "absent") {
		edgeState = "absent";
	} else if (edge.state === "active" && Number.isSafeInteger(edge.version) && edge.version > 0
		&& edge.verifyJwt === true && object(edge.files)
		&& Object.keys(edge.files).length === 2
		&& FILES.slice(1).every((f) => edge.files[f.path.split("/").at(-1)] === f.sha256)) {
		edgeState = "staged";
	} else {
		edgeState = "mismatched";
		issues.push("EDGE_IDENTITY_OR_AUTH_MISMATCH");
	}
	return { databaseState, edgeState,
		foundationStaged: databaseState === "installed_paused" && edgeState === "staged",
		// This layer deliberately cannot certify whole-sheet or physical-device acceptance.
		autonomyAccepted: false, issues };
}

/** Trusted readers must bind project identity server-side and reject uncertain inventories. */
export async function collectFoundation({ readDatabase, readEdge, clock = Date.now, ioDeadlineMs = 12000 }) {
	deadline(ioDeadlineMs);
	assert(typeof readDatabase === "function" && typeof readEdge === "function", "TRUSTED_READERS_REQUIRED");
	const start = clock();
	const db = await bounded((signal) => readDatabase({ projectRef: PROJECT_REF, query: INVENTORY_SQL, kind: "catalog", signal }), ioDeadlineMs, "DATABASE_READ_UNAVAILABLE");
	assert(db?.projectRef === PROJECT_REF && object(db.data), "DATABASE_TRANSPORT_SCOPE_MISMATCH");
	const catalog = db.data;
	let counts = null;
	if (exactRoster(catalog.tables, TABLES) && catalog.tables.every((r) => r.exists === true)) {
		const state = await bounded((signal) => readDatabase({ projectRef: PROJECT_REF, query: COUNTS_SQL, kind: "counts", signal }), ioDeadlineMs, "DATABASE_READ_UNAVAILABLE");
		assert(state?.projectRef === PROJECT_REF && object(state.data), "DATABASE_TRANSPORT_SCOPE_MISMATCH");
		counts = state.data;
	}
	const edge = await bounded((signal) => readEdge({ projectRef: PROJECT_REF, slug: EDGE_SLUG, includeSourceHashes: true, signal }), ioDeadlineMs, "EDGE_READ_UNAVAILABLE");
	const snapshot = { projectRef: PROJECT_REF, observedAt: new Date(start).toISOString(), catalog, counts, edge };
	return { snapshot, assessment: inspectFoundation(snapshot, clock()) };
}

/** Only exact immutable source is admitted. A moving branch or matching filename is insufficient. */
export async function verifyFoundationSource(readSource, { ioDeadlineMs = 12000 } = {}) {
	deadline(ioDeadlineMs);
	assert(typeof readSource === "function", "SOURCE_READER_REQUIRED");
	const files = [];
	for (const expected of FILES) {
		const source = await bounded((signal) => readSource({ repository: REPOSITORY, sourceSha: SOURCE_SHA, path: expected.path, signal }), ioDeadlineMs, "SOURCE_READ_UNAVAILABLE");
		assert(source?.repository === REPOSITORY && source.sourceSha === SOURCE_SHA
			&& source.path === expected.path && typeof source.content === "string"
			&& Buffer.byteLength(source.content, "utf8") <= 1048576
			&& hash(source.content) === expected.sha256, "EXACT_SOURCE_DIGEST_MISMATCH");
		files.push({ path: expected.path, sha256: expected.sha256 });
	}
	return Object.freeze(files.map(Object.freeze));
}

function proposal(kind, scope, files) {
	const database = kind === "database";
	return {
		operation: database ? "supabase.migration.apply" : "supabase.edge.deploy",
		taskId: scope.taskId, generation: scope.generation,
		requestId: `ops-foundation:${scope.taskId}:${scope.generation}:${kind}`,
		target: TARGETS[kind], sourceSha: SOURCE_SHA,
		artifactRef: `github:${REPOSITORY}@${SOURCE_SHA}:${database ? FILES[0].path : `supabase/functions/${EDGE_SLUG}`}`,
		parameters: database
			? { migrationVersion: MIGRATION_VERSION, migrationName: MIGRATION_NAME, sourceDigest: files[0].sha256,
				phase: "paused-foundation", repairHistory: false }
			: { slug: EDGE_SLUG, entrypoint: "index.ts", verifyJwt: true,
				files: files.slice(1), phase: "paused-foundation", allowOverwrite: false },
	};
}

/**
 * Bounded release adapter, not another scheduler or permission oracle.
 * Uses the EXISTING M3/lease/provider-readback boundary. Never creates workers,
 * changes billing, repairs historical migration aliases, unpauses or promotes Vercel.
 * Any ambiguous write stops the sequence without a retry.
 */
export async function stageFoundation({ actions, observe, readSource, clock = Date.now, ioDeadlineMs = 12000 }, trustedScope) {
	deadline(ioDeadlineMs);
	assert(actions instanceof GovernedProviderActions && typeof observe === "function", "GOVERNED_RELEASE_ADAPTER_REQUIRED");
	const scope = structuredClone(trustedScope);
	assert(scope?.sourceSha === SOURCE_SHA && Array.isArray(scope.targets)
		&& Object.values(TARGETS).every((t) => scope.targets.includes(t))
		&& typeof scope.taskId === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$/.test(scope.taskId)
		&& Number.isSafeInteger(scope.generation) && scope.generation > 0, "RELEASE_SCOPE_INVALID");
	const files = await verifyFoundationSource(readSource, { ioDeadlineMs });
	const receipts = [];
	const read = async () => inspectFoundation(
		await bounded((signal) => observe({ signal }), ioDeadlineMs, "FOUNDATION_READ_UNAVAILABLE"), clock(),
	);
	const unreadable = (code) => ({ state: receipts.length ? "reconciliation_required" : "blocked",
		issues: [code], receipts, autonomyAccepted: false });
	for (const kind of ["database", "edge"]) {
		let before;
		try { before = await read(); }
		catch { return unreadable("PRE_WRITE_READBACK_UNAVAILABLE"); }
		if (before.issues.length) return { state: "blocked", issues: before.issues, receipts, autonomyAccepted: false };
		if (kind === "edge" && before.databaseState !== "installed_paused")
			return unreadable("DATABASE_FOUNDATION_CHANGED_BEFORE_EDGE");
		const alreadyStaged = kind === "database" ? before.databaseState === "installed_paused" : before.edgeState === "staged";
		if (alreadyStaged) continue;
		let result;
		try {
			// Deadline bounds waiting, not provider execution. M3 retains reconciliation ownership.
			result = await bounded(() => actions.invoke(proposal(kind, scope, files), scope),
				ioDeadlineMs, "PROVIDER_INVOCATION_UNCERTAIN");
		} catch {
			return { state: "reconciliation_required", issues: ["PROVIDER_INVOCATION_UNCERTAIN"], receipts, autonomyAccepted: false };
		}
		if (result.state !== "completed") return { state: result.state === "reconciliation_required" ? result.state : "blocked",
			issues: ["GOVERNED_PROVIDER_DID_NOT_COMPLETE"], receipts, autonomyAccepted: false };
		receipts.push({ kind, actionHash: result.actionHash, receiptRef: result.receiptRef, readbackRef: result.readbackRef });
		let after;
		try { after = await read(); }
		catch { return unreadable("POST_WRITE_READBACK_UNAVAILABLE"); }
		if (after.issues.length || (kind === "database" ? after.databaseState !== "installed_paused" : after.edgeState !== "staged")) {
			return { state: "reconciliation_required", issues: ["POST_WRITE_READBACK_MISMATCH"], receipts, autonomyAccepted: false };
		}
	}
	let final;
	try { final = await read(); }
	catch { return unreadable("FINAL_READBACK_UNAVAILABLE"); }
	return { state: final.foundationStaged && !final.issues.length ? "foundation_staged" : "reconciliation_required",
		issues: final.issues, receipts, autonomyAccepted: false };
}
