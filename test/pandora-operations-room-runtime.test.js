"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const C = require("../packages/pandora-operations-room/contracts");
const {
	planAssignments,
	adaptiveConcurrency,
} = require("../packages/pandora-operations-room/scheduler");
const {
	OperationsRuntime,
	validateHandoff,
	requireVerification,
} = require("../packages/pandora-operations-room/runtime");
const {
	ACTIONS,
	GovernedProviderActions,
	actionEnvelope,
} = require("../packages/pandora-operations-room/provider-actions");
const {
	adbCommand,
	emulatorReadiness,
} = require("../packages/pandora-operations-room/ares");
const {
	INPUT_COLUMNS,
	ingestRows,
	planSheetWriteback,
} = require("../packages/pandora-operations-room/sheet-adapter");
const SHA = "a".repeat(40),
	now = 1800000000000;
function spec(id = "A", patch = {}) {
	return C.normalizeTask({
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
		source: { repository: C.REPOSITORIES[0], baseSha: SHA },
		...patch,
	});
}
function record(id, patch = {}) {
	return {
		spec: spec(id),
		status: "queued",
		attempt: 0,
		revision: 0,
		queuedAt: now,
		...patch,
	};
}
function worker(id = "W1", patch = {}) {
	return {
		id,
		engine: "chatgpt",
		acknowledged: true,
		connected: true,
		health: "ready",
		heartbeatAt: now,
		lanes: ["backend"],
		capabilities: ["source.write"],
		capacity: 8,
		...patch,
	};
}
function snapshot(tasks, patch = {}) {
	return {
		tasks,
		workers: [worker()],
		leases: [],
		controls: {
			maxConcurrency: 8,
			revision: 0,
			paused: false,
			noProduction: true,
		},
		budget: { availableMicros: 1000 },
		now,
		...patch,
	};
}
const rejects = (fn, code) =>
	assert.throws(fn, (e) => e.code === code || e.message === code);
test("task schema and nested resources are immutable", () => {
	const t = spec();
	assert.ok(Object.isFrozen(t.resources[0]));
	rejects(() => spec("A", { status: "complete" }), "UNKNOWN_FIELD");
});
test("source tasks bind one exact canonical repository SHA", () => {
	rejects(() => spec("A", { source: null }), "EXACT_SOURCE_REQUIRED");
	rejects(
		() => spec("A", { source: { repository: "wrong/repo", baseSha: SHA } }),
		"SOURCE_INVALID",
	);
});
test("resource traversal and ancestor collisions fail closed", () => {
	rejects(
		() =>
			spec("A", { resources: [{ key: "source/../escape", mode: "write" }] }),
		"RESOURCE_KEY_INVALID",
	);
	assert.equal(
		C.conflicts(
			{ key: "source/box", mode: "write" },
			{ key: "source/box/a", mode: "read" },
		),
		true,
	);
	assert.equal(
		C.conflicts(
			{ key: "source/box/a", mode: "write" },
			{ key: "source/box/ab", mode: "read" },
		),
		false,
	);
});
test("missing, self and cyclic dependencies are rejected", () => {
	rejects(
		() => C.validateGraph([spec("A", { dependsOn: ["B"] })]),
		"DEPENDENCY_MISSING",
	);
	rejects(() => spec("A", { dependsOn: ["A"] }), "SELF_DEPENDENCY");
	rejects(
		() =>
			C.validateGraph([
				spec("A", { dependsOn: ["B"] }),
				spec("B", { dependsOn: ["A"] }),
			]),
		"DEPENDENCY_CYCLE",
	);
});
test("independent tasks fill acknowledged available slots", () => {
	const r = planAssignments(snapshot(["A", "B", "C"].map((id) => record(id))));
	assert.equal(r.assignments.length, 3);
});
test("a proposal does not mutate task state or create a worker", () => {
	const s = snapshot([record("A")], { workers: [] });
	const r = planAssignments(s);
	assert.equal(r.assignments.length, 0);
	assert.equal(s.tasks[0].status, "queued");
	assert.equal(r.blocked[0].reason, "no_acknowledged_compatible_worker");
});
for (const [name, patch] of Object.entries({
	unacknowledged: { acknowledged: false },
	offline: { connected: false },
	stale: { heartbeatAt: now - 60001 },
	future: { heartbeatAt: now + 6000 },
	wrongEngine: { engine: "generic" },
	wrongLane: { lanes: ["web"] },
	missingCapability: { capabilities: [] },
}))
	test("worker admission rejects " + name, () =>
		assert.equal(
			planAssignments(
				snapshot([record("A")], { workers: [worker("W", patch)] }),
			).assignments.length,
			0,
		),
	);
test("shared readers proceed, overlapping writers wait", () => {
	const read = (id) =>
		record(id, {
			spec: spec(id, {
				risk: "read",
				resources: [{ key: "device/emulator", mode: "read" }],
			}),
		});
	assert.equal(
		planAssignments(snapshot([read("A"), read("B")])).assignments.length,
		2,
	);
	assert.equal(
		planAssignments(
			snapshot([
				read("A"),
				record("B", {
					spec: spec("B", {
						resources: [{ key: "device/emulator", mode: "write" }],
					}),
				}),
			]),
		).assignments.length,
		1,
	);
});
test("expired lease is still held until provider reconciliation", () => {
	const leases = [
		{
			workerId: "old",
			resources: [{ key: "source/box/A", mode: "write" }],
			expiresAt: now - 999,
			state: "reconcile",
		},
	];
	assert.equal(
		planAssignments(snapshot([record("A")], { leases })).blocked[0].reason,
		"resource_conflict",
	);
});
test("implementation handoff does not unlock dependent release work", () => {
	const tasks = [
		record("A", { status: "handed_off" }),
		record("B", { spec: spec("B", { dependsOn: ["A"] }) }),
	];
	assert.equal(planAssignments(snapshot(tasks)).assignments.length, 0);
	tasks[0].status = "complete";
	assert.equal(planAssignments(snapshot(tasks)).assignments.length, 1);
});
test("priority and dependency unlock value choose the next work", () => {
	const tasks = [
		record("B"),
		record("A"),
		record("C", { spec: spec("C", { dependsOn: ["A"] }) }),
	];
	const s = snapshot(tasks, {
		controls: { maxConcurrency: 1, revision: 3, noProduction: true },
	});
	assert.equal(planAssignments(s).assignments[0].taskId, "A");
});
test("cost reservation constrains parallelism without overspend", () => {
	const r = planAssignments(
		snapshot([record("A"), record("B")], { budget: { availableMicros: 15 } }),
	);
	assert.equal(r.assignments.length, 1);
	assert.equal(r.remainingMicros, 5);
	assert.equal(r.blocked[0].reason, "cost_budget_exhausted");
});
test("pause, production hold, exhausted attempt and capacity all stop dispatch", () => {
	assert.equal(
		planAssignments(
			snapshot([record("A")], {
				controls: { maxConcurrency: 1, revision: 0, paused: true },
			}),
		).blocked[0].reason,
		"workspace_paused",
	);
	assert.equal(
		planAssignments(
			snapshot([record("A", { spec: spec("A", { risk: "production" }) })]),
		).blocked[0].reason,
		"production_paused",
	);
	assert.equal(
		planAssignments(snapshot([record("A", { attempt: 2 })])).blocked[0].reason,
		"attempt_budget_exhausted",
	);
	assert.equal(
		planAssignments(
			snapshot([record("A"), record("B")], {
				workers: [worker("W", { capacity: 1 })],
			}),
		).assignments.length,
		1,
	);
});
test("adaptive concurrency uses evidence and backpressure, not persona count", () => {
	const m = {
		current: 4,
		ceiling: 8,
		sampleSize: 10,
		throughput: 5,
		previousThroughput: 4,
		errorRate: 0,
		verificationBacklog: 1,
	};
	assert.equal(adaptiveConcurrency(m), 5);
	assert.equal(adaptiveConcurrency({ ...m, sampleSize: 1 }), 4);
	assert.equal(adaptiveConcurrency({ ...m, verificationBacklog: 20 }), 2);
	assert.equal(adaptiveConcurrency({ ...m, errorRate: 0.4 }), 2);
});
test("task graph supports 500 independent rows without fixed lane count", () => {
	const tasks = Array.from({ length: 500 }, (_, i) => record("T" + i));
	const r = planAssignments(
		snapshot(tasks, {
			workers: Array.from({ length: 16 }, (_, i) =>
				worker("W" + i, { capacity: 8 }),
			),
			controls: { maxConcurrency: 128, revision: 1, noProduction: true },
			budget: { availableMicros: 5000 },
		}),
	);
	assert.equal(r.assignments.length, 128);
	assert.equal(new Set(r.assignments.map((a) => a.taskId)).size, 128);
});
test("durable runtime rejects in-memory authority", () =>
	rejects(
		() =>
			new OperationsRuntime({
				store: { durability: "memory" },
				workerDispatch: async () => {},
			}),
		"DURABLE_STORE_REQUIRED",
	));
test("dispatch intent precedes worker call and matching ACK is required", async () => {
	const order = [];
	const claim = {
		claimed: true,
		taskId: "A",
		workerId: "W1",
		generation: 1,
		leaseId: "lease",
	};
	const store = {
		durability: "durable",
		snapshot: async () => snapshot([record("A")]),
		claim: async () => claim,
		beginDispatch: async () => {
			order.push("intent");
			return { dispatchId: "D", canSend: true };
		},
		acknowledgeDispatch: async () => order.push("ack"),
		markReconciliationRequired: async () => order.push("reconcile"),
	};
	const runtime = new OperationsRuntime({
		store,
		clock: () => now,
		workerDispatch: async (x) => {
			order.push("call");
			return { ...claim, accepted: true, dispatchId: x.dispatchId };
		},
	});
	assert.equal(
		(await runtime.tick({ organizationId: "O", projectId: "P" })).receipts[0]
			.state,
		"dispatched",
	);
	assert.deepEqual(order, ["intent", "call", "ack"]);
});
test("unknown dispatch outcome keeps lease and does not blind retry", async () => {
	let calls = 0,
		held = false;
	const store = {
		durability: "durable",
		snapshot: async () => snapshot([record("A")]),
		claim: async () => ({
			claimed: true,
			taskId: "A",
			workerId: "W",
			generation: 1,
		}),
		beginDispatch: async () => ({ dispatchId: "D", canSend: true }),
		markReconciliationRequired: async () => {
			held = true;
		},
	};
	const r = new OperationsRuntime({
		store,
		clock: () => now,
		workerDispatch: async () => {
			calls++;
			throw new Error("network lost after send");
		},
	});
	assert.equal((await r.tick({})).receipts[0].state, "reconciliation_required");
	assert.equal(calls, 1);
	assert.equal(held, true);
});
test("handoff needs exact head, PR and evidence but never says released", () => {
	const h = validateHandoff(
		{
			taskId: "A",
			workerId: "W",
			generation: 1,
			headSha: SHA,
			pullRequest: 1,
			tests: ["node tests passed"],
			evidenceRefs: ["github:run:1"],
			implementationComplete: true,
		},
		spec(),
	);
	assert.equal(h.releaseVerified, false);
	assert.equal(h.state, "handed_off");
});
test("provider action inventory includes every required infrastructure class", () => {
	assert.deepEqual(
		[...new Set(Object.values(ACTIONS).map((a) => a.provider))].sort(),
		["ares", "github", "supabase", "vercel"],
	);
});
const scope = {
	organizationId: "O",
	projectId: "P",
	taskId: "A",
	generation: 1,
	sourceSha: SHA,
	targets: ["source/box"],
};
const action = {
	operation: "github.branch.create",
	taskId: "A",
	generation: 1,
	requestId: "request-0001",
	target: "source/box",
	sourceSha: SHA,
	parameters: { branch: "feat/test" },
};
test("raw shell, SQL, secret payloads and unregistered actions are denied", () => {
	rejects(
		() => actionEnvelope({ ...action, operation: "shell.run" }, scope),
		"ACTION_NOT_REGISTERED",
	);
	for (const k of ["sql", "shell", "command", "token"])
		rejects(
			() => actionEnvelope({ ...action, parameters: { [k]: "bad" } }, scope),
			"RAW_EXECUTION_DENIED",
		);
	rejects(
		() =>
			actionEnvelope(
				{ ...action, parameters: { value: "github_pat_" + "x".repeat(40) } },
				scope,
			),
		"CREDENTIAL_OR_PAYLOAD_REJECTED",
	);
});
test("provider target, generation and source changes are rejected", () => {
	rejects(
		() => actionEnvelope({ ...action, target: "other" }, scope),
		"TARGET_NOT_AUTHORIZED",
	);
	rejects(
		() => actionEnvelope({ ...action, generation: 2 }, scope),
		"ACTION_SCOPE_MISMATCH",
	);
	rejects(
		() => actionEnvelope({ ...action, sourceSha: "b".repeat(40) }, scope),
		"SOURCE_DRIFT",
	);
});
test("provider success requires matching independent authoritative readback", async () => {
	let calls = 0;
	const p = new GovernedProviderActions({
		verifyCurrentLease: async () => true,
		executeGoverned: async () => {
			calls++;
			return { state: "completed", receiptRef: "provider:one" };
		},
		readback: async () => ({ verified: false }),
	});
	assert.equal(
		(await p.invoke(action, scope)).state,
		"reconciliation_required",
	);
	assert.equal(calls, 1);
});
test("authority denial never invokes a readback or alternate provider", async () => {
	let reads = 0;
	const p = new GovernedProviderActions({
		verifyCurrentLease: async () => true,
		executeGoverned: async () => ({ state: "denied" }),
		readback: async () => {
			reads++;
		},
	});
	assert.equal((await p.invoke(action, scope)).state, "denied");
	assert.equal(reads, 0);
});
test("provider successful receipt binds exact action hash", async () => {
	let binding;
	const p = new GovernedProviderActions({
		verifyCurrentLease: async () => true,
		executeGoverned: async (a, b) => {
			binding = b;
			return { state: "completed", receiptRef: "provider:one" };
		},
		readback: async () => ({
			verified: true,
			receiptRef: "provider:readback",
			actionHash: binding.actionHash,
		}),
	});
	assert.equal((await p.invoke(action, scope)).state, "completed");
});
const device = {
	serial: "emulator-5554",
	adbPath: "C:\\Android\\sdk\\platform-tools\\adb.exe",
};
test("ARES uses argv without a host shell and rejects adb-shell injection", () => {
	assert.equal(
		adbCommand({ kind: "tap", x: 1, y: 2 }, device).options.shell,
		false,
	);
	for (const value of ["hello; reboot", "$(id)", "x&y", "`whoami`"])
		rejects(
			() => adbCommand({ kind: "type", text: value }, device),
			"ADB_TEXT_UNSAFE",
		);
	rejects(
		() =>
			adbCommand(
				{ kind: "health" },
				{ ...device, serial: "emulator-5554;reboot" },
			),
		"ADB_SERIAL_INVALID",
	);
});
test("ARES install needs verified APK inside assigned workspace", () => {
	rejects(
		() => adbCommand({ kind: "install" }, device),
		"VERIFIED_APK_REQUIRED",
	);
	rejects(
		() =>
			adbCommand(
				{ kind: "install" },
				{
					...device,
					verifiedApk: true,
					workspaceRoot: "C:\\work",
					artifactPath: "C:\\other\\x.apk",
				},
			),
		"ARTIFACT_PATH_ESCAPE",
	);
	const c = adbCommand(
		{ kind: "install" },
		{
			...device,
			verifiedApk: true,
			workspaceRoot: "C:\\work",
			artifactPath: "C:\\work\\a.apk",
		},
	);
	assert.ok(c.args.includes("install"));
	assert.equal(c.physicalDeviceVerified, false);
});
test("ARES marks clear-data destructive and limits app package scope", () => {
	assert.equal(adbCommand({ kind: "clear_data" }, device).destructive, true);
	rejects(
		() =>
			adbCommand(
				{ kind: "package" },
				{ ...device, packageName: "com.bank.app" },
			),
		"PACKAGE_NOT_ALLOWLISTED",
	);
});
test("host liveness alone cannot certify emulator readiness or ABI", () => {
	assert.equal(
		emulatorReadiness({ hostReachable: true, adbState: "offline" }).ready,
		false,
	);
	const r = emulatorReadiness({
		hostReachable: true,
		adbState: "device",
		bootCompleted: "1",
		shellResponsive: true,
		guestAbi: ["x86_64"],
		apkAbi: "arm64-v8a",
	});
	assert.equal(r.ready, false);
	assert.equal(r.physicalDeviceVerified, false);
});
function row(id = "A") {
	return [
		id,
		"Task " + id,
		"backend",
		1,
		"",
		"source/box/" + id + "|write",
		"source.write",
		10,
		60,
		2,
		"source",
		"exact-source tests",
		C.REPOSITORIES[0],
		SHA,
	];
}
test("spreadsheet decoding ignores owner-supplied completion claims", () => {
	const h = [...INPUT_COLUMNS, "STATUS", "WORKER"],
		r = [...row(), "complete", "fake"];
	const p = ingestRows(h, [r]);
	assert.equal(p.tasks.length, 1);
	assert.equal(p.tasks[0].status, undefined);
	assert.equal(p.tasks[0].worker, undefined);
});
test("spreadsheet formulas, duplicate task IDs and broken DAG fail closed", () => {
	const r = row();
	r[1] = '=IMPORTDATA("evil")';
	rejects(() => ingestRows(INPUT_COLUMNS, [r]), "FORMULA_INPUT_REJECTED");
	rejects(() => ingestRows(INPUT_COLUMNS, [row(), row()]), "DUPLICATE_TASK");
	const b = row("B");
	b[4] = "missing";
	rejects(() => ingestRows(INPUT_COLUMNS, [b]), "DEPENDENCY_MISSING");
});
test("sheet writeback cannot change owner input or overwrite changed rows", () => {
	const headers = [...INPUT_COLUMNS, "STATUS"],
		rows = [[...row(), "queued"]],
		d = ingestRows(headers, rows).sourceDigest;
	rejects(
		() =>
			planSheetWriteback({
				expectedInputDigest: d,
				currentHeaders: headers,
				currentRows: rows,
				statuses: [{ taskId: "A", TITLE: "bad" }],
			}),
		"OWNER_COLUMN_WRITE_DENIED",
	);
	rejects(
		() =>
			planSheetWriteback({
				expectedInputDigest: "wrong",
				currentHeaders: headers,
				currentRows: rows,
				statuses: [],
			}),
		"SHEET_CHANGED_RECONCILE",
	);
	const p = planSheetWriteback({
		expectedInputDigest: d,
		currentHeaders: headers,
		currentRows: rows,
		statuses: [{ taskId: "A", STATUS: "claimed" }],
	});
	assert.equal(p[0].row, 2);
});

test("missing or non-string task IDs cannot pass regex coercion", () => {
	for (const id of [undefined, null, 123])
		rejects(() => spec(id === undefined ? "A" : id, { id }), "TASK_ID_INVALID");
});
test("foreign-project held resources block a conflicting scheduler proposal", () => {
	const p = planAssignments(
		snapshot([record("A")], {
			foreignLeases: [{ resources: [{ key: "source/box", mode: "write" }] }],
		}),
	);
	assert.equal(p.assignments.length, 0);
	assert.equal(p.blocked[0].reason, "resource_conflict");
});
test("verification cannot use a different worker name under the builder principal", () => {
	const t = spec(),
		h = { taskId: "A", workerId: "W", generation: 1, headSha: SHA },
		builder = { id: "W", principalId: "same" },
		verifier = {
			id: "V",
			principalId: "same",
			verifiedIdentity: true,
			lane: "release",
		};
	rejects(
		() =>
			requireVerification({
				task: t,
				handoff: h,
				builder,
				verifier,
				receipt: {},
			}),
		"INDEPENDENT_VERIFIER_REQUIRED",
	);
	rejects(
		() => requireVerification({ task: t, handoff: h, verifier, receipt: {} }),
		"BUILDER_IDENTITY_REQUIRED",
	);
});
test("verification binds authenticated reviewer, source and required acceptance criteria", () => {
	const task = spec(),
		handoff = { taskId: "A", workerId: "W", generation: 1, headSha: SHA },
		builder = { id: "W", principalId: "builder" },
		verifier = {
			id: "V",
			principalId: "reviewer",
			verifiedIdentity: true,
			lane: "release",
		},
		receipt = {
			taskId: "A",
			generation: 1,
			headSha: SHA,
			verified: true,
			ref: "fixture:verification",
			criteria: task.acceptance,
			providerReadback: true,
			verifierPrincipalId: "reviewer",
		};
	assert.equal(
		requireVerification({ task, handoff, builder, verifier, receipt }).state,
		"complete",
	);
	rejects(
		() =>
			requireVerification({
				task,
				handoff,
				builder,
				verifier,
				receipt: { ...receipt, criteria: [] },
			}),
		"ACCEPTANCE_INCOMPLETE",
	);
});
test("production task cannot select a weaker canonical verification profile", () =>
	rejects(
		() =>
			spec("A", { risk: "production", verificationProfile: "backend_service" }),
		"VERIFICATION_PROFILE_INVALID",
	));
test("only reviewed learning candidates are produced; no automatic canonical promotion", () => {
	const {
		learningCandidate,
		recoveryRoute,
	} = require("../packages/pandora-operations-room/learning");
	const c = learningCandidate({
		taskId: "A",
		headSha: SHA,
		verificationRef: "fixture:verified",
		outcome: "verified_failure",
		lesson: "A lost provider response must be reconciled before retry.",
		rootCause: "ambiguous mutation",
		fix: "retain fence",
		evidenceRefs: ["fixture:readback"],
	});
	assert.equal(c.requiresReview, true);
	assert.equal(c.canonicalMemoryWritten, false);
	assert.equal(
		recoveryRoute({ domain: "database", outcomeKnown: false }).retry,
		false,
	);
});
test("Operations view does not manufacture progress or physical acceptance", () => {
	const {
		operationsView,
	} = require("../packages/pandora-operations-room/operations-view");
	const v = operationsView(snapshot([record("A", { status: "claimed" })]), {
		observedAt: now,
	});
	assert.equal(v.completed, 0);
	assert.equal(v.physicalDeviceVerified, false);
	assert.deepEqual(v.buildTheatreEvents, []);
});

test("sheet output refresh is replay-safe but owner edits invalidate the row fingerprint", () => {
	const headers = [...INPUT_COLUMNS, "STATUS", "BLOCKER"],
		rows = [[...row(), "queued", ""]];
	const first = ingestRows(headers, rows);
	const refreshed = [[...row(), "implementing", ""]];
	const plan = planSheetWriteback({
		expectedInputDigest: first.sourceDigest,
		currentHeaders: headers,
		currentRows: refreshed,
		statuses: [
			{ taskId: "A", STATUS: "handed_off", BLOCKER: "=untrusted receipt text" },
		],
	});
	assert.equal(plan[0].valueInputOption, "RAW");
	assert.equal(plan[0].values.BLOCKER, "=untrusted receipt text");
	const changed = [[...row(), "queued", ""]];
	changed[0][1] = "Changed owner requirement";
	rejects(
		() =>
			planSheetWriteback({
				expectedInputDigest: first.sourceDigest,
				currentHeaders: headers,
				currentRows: changed,
				statuses: [],
			}),
		"SHEET_CHANGED_RECONCILE",
	);
});
test("malformed sheet rows are rejected instead of silently dropped", () =>
	rejects(
		() => ingestRows(INPUT_COLUMNS, [row(), { TASK_ID: "hidden-task" }]),
		"SHEET_ROWS_INVALID",
	));
