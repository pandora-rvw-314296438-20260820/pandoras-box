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
async function rpc(name, args) {
	const values = Object.values(args);
	const q =
		"select public." +
		name +
		"(" +
		Object.keys(args)
			.map((key, i) => key + "=> $" + (i + 1))
			.join(",") +
		") as value";
	const r = await db.query(
		q,
		values.map((x) =>
			typeof x === "object" && !Array.isArray(x) && x !== null
				? JSON.stringify(x)
				: x,
		),
	);
	return r.rows[0].value;
}
async function setup({
	concurrency = 8,
	budget = 1000,
	otherProject = null,
} = {}) {
	const org = otherProject?.org ?? randomUUID(),
		project = randomUUID();
	if (!otherProject)
		await db.query("insert into public.organizations(id) values($1)", [org]);
	await db.query(
		"insert into public.pandora_projects(id,organization_id) values($1,$2)",
		[project, org],
	);
	const args = { p_organization_id: org, p_project_id: project };
	await rpc("pandora_ops_initialize_v1", {
		...args,
		p_budget_micros: budget,
		p_max_concurrency: concurrency,
	});
	await rpc("pandora_ops_register_worker_v1", {
		...args,
		p_worker_key: "W1",
		p_principal_key: "chatgpt-session-builder",
		p_lanes: ["backend"],
		p_capabilities: ["source.write"],
		p_capacity: 8,
		p_receipt_ref: "worker-session:registration-fixture",
	});
	return { org, project, args };
}
async function ingest(s, tasks) {
	return rpc("pandora_ops_ingest_v1", {
		...s.args,
		p_tasks: JSON.stringify(tasks),
	});
}
async function resume(s) {
	return rpc("pandora_ops_control_v1", {
		...s.args,
		p_expected_revision: 0,
		p_action: "resume",
	});
}
async function claim(s, key = "A", worker = "W1", revision = 0, control = 1) {
	return rpc("pandora_ops_claim_v1", {
		...s.args,
		p_task_key: key,
		p_worker_key: worker,
		p_task_revision: revision,
		p_control_revision: control,
	});
}
async function snapshot(s) {
	return rpc("pandora_ops_snapshot_v1", s.args);
}
test.before(async () => {
	db = await PGlite.create();
	await db.exec(
		`create role anon; create role authenticated; create role service_role; create schema private; create schema extensions; create table public.organizations(id uuid primary key); create table public.test_project_identity(id uuid primary key,organization_id uuid not null references public.organizations(id),status text not null default 'active'); create view public.pandora_projects with(security_invoker=true) as select id,organization_id,status from public.test_project_identity; create table public.memberships(organization_id uuid,user_id uuid,role text,status text); create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,project_id uuid not null,status text not null,source_commit text,required_check_profile text,completed_at timestamptz); create function extensions.digest(data bytea,algorithm text) returns bytea language plpgsql immutable as $$ begin if algorithm<>'sha256' then raise exception 'unsupported digest'; end if; return pg_catalog.sha256(data); end $$;`,
	);
	await db.exec(migration);
});
test.after(async () => {
	await db?.close();
});
test("DB rejects cross-organization project initialization", async () => {
	const s = await setup();
	await assert.rejects(
		() =>
			rpc("pandora_ops_initialize_v1", {
				p_organization_id: randomUUID(),
				p_project_id: s.project,
				p_budget_micros: 0,
				p_max_concurrency: 1,
			}),
		/OPS_PROJECT_SCOPE_DENIED/,
	);
});
test("DB import is atomic and idempotent; immutable task edits conflict", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await ingest(s, [spec()]);
	assert.equal((await snapshot(s)).tasks.length, 1);
	await assert.rejects(
		() => ingest(s, [spec("B"), spec("A", { title: "changed" })]),
		/OPS_TASK_SPEC_CONFLICT/,
	);
	assert.equal((await snapshot(s)).tasks.length, 1);
});
test("DB independently rejects cycles and missing dependencies", async () => {
	const s = await setup();
	await assert.rejects(
		() =>
			ingest(s, [
				spec("A", { dependsOn: ["B"] }),
				spec("B", { dependsOn: ["A"] }),
			]),
		/OPS_DEPENDENCY_CYCLE/,
	);
	await assert.rejects(
		() => ingest(s, [spec("C", { dependsOn: ["missing"] })]),
		/foreign key/,
	);
	assert.equal((await snapshot(s)).tasks.length, 0);
});
test("DB starts paused and rejects unregistered workers", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	assert.equal((await claim(s, "A", "W1", 0, 0)).claimed, false);
	await resume(s);
	assert.equal((await claim(s, "A", "unknown")).claimed, false);
});
test("DB reserves budget/generation and excludes ancestor resources atomically", async () => {
	const s = await setup();
	await ingest(s, [
		spec("A", { resources: [{ key: "device/emulator", mode: "write" }] }),
		spec("B", {
			risk: "read",
			resources: [{ key: "device/emulator/screen", mode: "read" }],
		}),
	]);
	await resume(s);
	const a = await claim(s);
	assert.equal(a.claimed, true);
	assert.equal(a.generation, 1);
	assert.equal((await claim(s, "B")).reason, "resource_conflict");
	assert.equal((await snapshot(s)).budget.availableMicros, 990);
});
test("DB claim replay never double-charges or creates another attempt", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s),
		b = await claim(s);
	assert.equal(b.leaseId, a.leaseId);
	assert.equal(b.replayed, true);
	assert.equal((await snapshot(s)).tasks[0].attempt, 1);
	assert.equal((await snapshot(s)).budget.availableMicros, 990);
});
test("DB fences stale controls and worker heartbeat", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	assert.equal((await claim(s, "A", "W1", 0, 0)).claimed, false);
	await db.query(
		"update private.pandora_ops_workers set heartbeat_at=clock_timestamp()-interval '61 seconds' where project_id=$1",
		[s.project],
	);
	assert.equal((await claim(s)).reason, "worker_unavailable");
});
test("DB expired leases remain reserved until reconciliation", async () => {
	const s = await setup();
	await ingest(s, [
		spec("A"),
		spec("B", { resources: [{ key: "source/box/A", mode: "write" }] }),
	]);
	await resume(s);
	const a = await claim(s);
	await db.query(
		"update private.pandora_ops_leases set expires_at=clock_timestamp()-interval '1 second' where id=$1",
		[a.leaseId],
	);
	assert.equal((await claim(s)).reason, "claim_requires_reconciliation");
	assert.equal((await claim(s, "B")).reason, "resource_conflict");
});
test("DB dispatch intent is durable and ACK is task/worker/generation-bound", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	const args = { ...s.args, p_lease_id: a.leaseId, p_generation: 1 };
	const d = await rpc("pandora_ops_dispatch_v1", args);
	assert.equal(d.acknowledged, false);
	await assert.rejects(
		() => rpc("pandora_ops_dispatch_v1", { ...args, p_generation: 2 }),
		/OPS_LEASE_FENCED/,
	);
	const ack = {
		accepted: true,
		dispatchId: d.dispatchId,
		workerId: "W1",
		taskId: "A",
		generation: 1,
	};
	await assert.rejects(
		() =>
			rpc("pandora_ops_dispatch_v1", {
				...args,
				p_ack: { ...ack, workerId: "intruder" },
			}),
		/OPS_WORKER_ACK_MISMATCH/,
	);
	await rpc("pandora_ops_dispatch_v1", { ...args, p_ack: ack });
	assert.equal((await snapshot(s)).tasks[0].status, "implementing");
});
test("DB rejects archived projects at initialization, claim and owner admission", async () => {
	const s = await setup(), actor = randomUUID();
	await ingest(s, [spec()]);
	await resume(s);
	await db.query("insert into public.memberships values($1,$2,'owner','active')", [s.org, actor]);
	await db.query("update public.test_project_identity set status='archived' where id=$1", [s.project]);
	await assert.rejects(
		() => rpc("pandora_ops_initialize_v1", { ...s.args, p_budget_micros: 1000, p_max_concurrency: 1 }),
		/OPS_PROJECT_SCOPE_DENIED/,
	);
	await assert.rejects(() => claim(s), /OPS_PROJECT_SCOPE_DENIED/);
	await assert.rejects(
		() => rpc("pandora_ops_owner_request_v1", { ...s.args, p_actor_id: actor, p_operation: "overview" }),
		/OPS_PROJECT_SCOPE_DENIED/,
	);
});
test("DB refuses dispatch after project archival or removal without releasing claimed resources", async () => {
	for (const removed of [false, true]) {
		const s = await setup();
		await ingest(s, [spec()]);
		await resume(s);
		const c = await claim(s);
		if (removed)
			await db.query("delete from public.test_project_identity where id=$1", [s.project]);
		else
			await db.query("update public.test_project_identity set status='archived' where id=$1", [s.project]);
		await assert.rejects(
			() => rpc("pandora_ops_dispatch_v1", { ...s.args, p_lease_id: c.leaseId, p_generation: c.generation }),
			/OPS_PROJECT_SCOPE_DENIED/,
		);
		const r = await db.query(
			"select l.state as lease_state, w.reserved_micros::integer as reserved_micros, count(o.id)::integer as outbox_count from private.pandora_ops_leases l join private.pandora_ops_workspaces w on w.organization_id=l.organization_id and w.project_id=l.project_id left join private.pandora_ops_dispatch_outbox o on o.lease_id=l.id where l.id=$1 group by l.state,w.reserved_micros",
			[c.leaseId],
		);
		assert.deepEqual(r.rows, [{ lease_state: "held", reserved_micros: 10, outbox_count: 0 }]);
	}
});
test("DB refuses a late ACK after archival and keeps in-flight ownership for reconciliation", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const c = await claim(s);
	const args = { ...s.args, p_lease_id: c.leaseId, p_generation: c.generation };
	const d = await rpc("pandora_ops_dispatch_v1", args);
	assert.equal(d.canSend, true);
	await db.query("update public.test_project_identity set status='archived' where id=$1", [s.project]);
	await assert.rejects(
		() => rpc("pandora_ops_dispatch_v1", { ...args, p_ack: {
			accepted: true, dispatchId: d.dispatchId, workerId: "W1", taskId: "A", generation: c.generation,
		} }),
		/OPS_PROJECT_SCOPE_DENIED/,
	);
	const r = await db.query(
		"select l.state as lease_state, o.state as outbox_state, w.reserved_micros::integer as reserved_micros from private.pandora_ops_leases l join private.pandora_ops_dispatch_outbox o on o.lease_id=l.id join private.pandora_ops_workspaces w on w.organization_id=l.organization_id and w.project_id=l.project_id where l.id=$1",
		[c.leaseId],
	);
	assert.deepEqual(r.rows, [{ lease_state: "dispatching", outbox_state: "sending", reserved_micros: 10 }]);
});
test("DB cancellation retains running-resource ownership pending actual stop", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	await rpc("pandora_ops_control_v1", {
		...s.args,
		p_expected_revision: 1,
		p_action: "cancel_task",
		p_task_key: "A",
	});
	const state = (await snapshot(s)).tasks[0];
	assert.equal(state.status, "claimed");
	assert.equal(state.cancelRequested, true);
	assert.equal((await snapshot(s)).leases.length, 1);
	await assert.rejects(
		() =>
			rpc("pandora_ops_dispatch_v1", {
				...s.args,
				p_lease_id: a.leaseId,
				p_generation: 1,
			}),
		/OPS_EXECUTION_PAUSED/,
	);
});
test("DB ambiguous outcome keeps cost reservation and lease", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	const r = await rpc("pandora_ops_reconcile_required_v1", {
		...s.args,
		p_lease_id: a.leaseId,
		p_generation: 1,
		p_reason: "DISPATCH_OUTCOME_UNKNOWN",
	});
	assert.equal(r.leaseRetained, true);
	const p = await snapshot(s);
	assert.equal(p.tasks[0].status, "blocked");
	assert.equal(p.leases[0].state, "reconcile");
	assert.equal(p.budget.availableMicros, 990);
});
test("DB enforces cost and parallel slot limits independently of planner", async () => {
	const s = await setup({ budget: 15 });
	await ingest(s, [spec("A"), spec("B")]);
	await resume(s);
	await claim(s);
	assert.equal((await claim(s, "B")).reason, "cost_budget_exhausted");
	const t = await setup({ concurrency: 1 });
	await ingest(t, [spec("A"), spec("B")]);
	await resume(t);
	await claim(t);
	assert.equal((await claim(t, "B")).reason, "capacity_backpressure");
});
test("DB anon/authenticated roles cannot register or claim workers", async () => {
	for (const role of ["anon", "authenticated"]) {
		await db.exec("set role " + role);
		try {
			await assert.rejects(
				() =>
					db.query("select public.pandora_ops_snapshot_v1($1,$2)", [
						randomUUID(),
						randomUUID(),
					]),
				/permission denied/,
			);
			await assert.rejects(
				() => db.query("select * from private.pandora_ops_workers"),
				/permission denied/,
			);
		} finally {
			await db.exec("reset role");
		}
	}
});
test("DB event history is immutable and snapshots omit lease credentials", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	assert.ok(!JSON.stringify(await snapshot(s)).includes(a.leaseId));
	await assert.rejects(
		() =>
			db.query(
				"update private.pandora_ops_events set event_type=$1 where project_id=$2",
				["fake_complete", s.project],
			),
		/OPS_EVENT_IMMUTABLE/,
	);
});
test("JS scheduler with real SQL store dispatches two independent logical jobs", async () => {
	const s = await setup();
	await ingest(s, [spec("A"), spec("B")]);
	await resume(s);
	const client = {
		rpc: async (name, args) => {
			try {
				return { data: await rpc(name, args), error: null };
			} catch (e) {
				return { data: null, error: { code: e.message } };
			}
		},
	};
	const store = new SupabaseOperationsStore(client);
	let calls = 0;
	const engine = new OperationsRuntime({
		store,
		workerDispatch: async ({ claim, dispatchId }) => {
			calls++;
			return {
				taskId: claim.taskId,
				workerId: claim.workerId,
				generation: claim.generation,
				dispatchId,
				accepted: true,
			};
		},
	});
	const result = await engine.tick({
		organizationId: s.org,
		projectId: s.project,
	});
	assert.equal(
		result.receipts.filter((x) => x.state === "dispatched").length,
		2,
	);
	assert.equal(calls, 2);
	assert.equal(
		(await snapshot(s)).tasks.filter((t) => t.status === "implementing").length,
		2,
	);
});

async function startAndHandoff(s) {
	await ingest(s, [spec("A"), spec("B", { dependsOn: ["A"] })]);
	await resume(s);
	const a = await claim(s);
	const args = { ...s.args, p_lease_id: a.leaseId, p_generation: 1 };
	const d = await rpc("pandora_ops_dispatch_v1", args);
	await rpc("pandora_ops_dispatch_v1", {
		...args,
		p_ack: {
			accepted: true,
			dispatchId: d.dispatchId,
			taskId: "A",
			workerId: "W1",
			generation: 1,
		},
	});
	const h = {
		taskId: "A",
		workerId: "W1",
		generation: 1,
		headSha: SHA,
		pullRequest: 123,
		tests: ["fixture:node-tests"],
		receiptRef: "fixture:implementation-evidence",
	};
	const r = await rpc("pandora_ops_handoff_v1", {
		...args,
		p_principal_key: "chatgpt-session-builder",
		p_handoff: h,
		p_actual_cost_micros: 7,
	});
	return { a, h, r };
}
test("DB handoff releases builder resources but does not mark work verified", async () => {
	const s = await setup(),
		{ r } = await startAndHandoff(s);
	assert.equal(r.releaseVerified, false);
	assert.equal((await snapshot(s)).leases.length, 0);
	assert.equal((await snapshot(s)).budget.availableMicros, 993);
	assert.equal((await claim(s, "B")).reason, "dependency_not_verified");
});
test("DB verifier requires distinct principal and a canonical exact-source PASS", async () => {
	const s = await setup();
	await startAndHandoff(s);
	await rpc("pandora_ops_register_worker_v1", {
		...s.args,
		p_worker_key: "V_BAD",
		p_principal_key: "chatgpt-session-builder",
		p_lanes: ["release"],
		p_capabilities: [],
		p_capacity: 1,
		p_receipt_ref: "fixture:bad-verifier",
	});
	const args = {
		...s.args,
		p_task_key: "A",
		p_generation: 1,
		p_verifier_key: "V_BAD",
		p_principal_key: "chatgpt-session-builder",
		p_verification_run_id: randomUUID(),
		p_receipt: {},
	};
	await assert.rejects(
		() => rpc("pandora_ops_verify_v1", args),
		/OPS_INDEPENDENT_VERIFIER_REQUIRED/,
	);
	await rpc("pandora_ops_register_worker_v1", {
		...s.args,
		p_worker_key: "V",
		p_principal_key: "independent-review-session",
		p_lanes: ["release"],
		p_capabilities: [],
		p_capacity: 1,
		p_receipt_ref: "fixture:verifier",
	});
	await assert.rejects(
		() =>
			rpc("pandora_ops_verify_v1", {
				...args,
				p_verifier_key: "V",
				p_principal_key: "independent-review-session",
			}),
		/OPS_CANONICAL_VERIFICATION_REQUIRED/,
	);
});
test("DB canonical verified completion unlocks dependencies and rejects conflicting replay", async () => {
	const s = await setup();
	await startAndHandoff(s);
	await rpc("pandora_ops_register_worker_v1", {
		...s.args,
		p_worker_key: "V",
		p_principal_key: "independent-review-session",
		p_lanes: ["release"],
		p_capabilities: [],
		p_capacity: 1,
		p_receipt_ref: "fixture:verifier",
	});
	const run = randomUUID();
	await db.query(
		"insert into public.pandora_verification_runs values($1,$2,$3,'PASS',$4,'backend_service',clock_timestamp())",
		[run, s.org, s.project, SHA],
	);
	const task = (await snapshot(s)).tasks.find((t) => t.spec.id === "A");
	const receipt = {
		taskId: "A",
		generation: 1,
		headSha: SHA,
		taskSpecDigest: task.specDigest,
		verificationRunId: run,
		ref: "fixture:canonical-verification",
		criteria: task.spec.acceptance,
	};
	const args = {
		...s.args,
		p_task_key: "A",
		p_generation: 1,
		p_verifier_key: "V",
		p_principal_key: "independent-review-session",
		p_verification_run_id: run,
		p_receipt: receipt,
	};
	assert.equal((await rpc("pandora_ops_verify_v1", args)).complete, true);
	assert.equal((await claim(s, "B")).claimed, true);
	assert.equal((await rpc("pandora_ops_verify_v1", args)).replayed, true);
	await assert.rejects(
		() =>
			rpc("pandora_ops_verify_v1", {
				...args,
				p_receipt: { ...receipt, ref: "fixture:changed" },
			}),
		/OPS_VERIFICATION_REPLAY_CONFLICT/,
	);
});
test("DB recovery needs known provider outcome and fencing before requeue", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	await rpc("pandora_ops_reconcile_required_v1", {
		...s.args,
		p_lease_id: a.leaseId,
		p_generation: 1,
		p_reason: "DISPATCH_OUTCOME_UNKNOWN",
	});
	const args = {
		...s.args,
		p_lease_id: a.leaseId,
		p_generation: 1,
		p_outcome: "not_executed",
		p_cost_micros: 1,
		p_receipt: {
			taskId: "A",
			generation: 1,
			ref: "fixture:readback",
			providerOutcomeKnown: true,
			workerFenced: false,
		},
	};
	await assert.rejects(
		() => rpc("pandora_ops_recover_v1", args),
		/OPS_RECOVERY_READBACK_REQUIRED/,
	);
	const r = await rpc("pandora_ops_recover_v1", {
		...args,
		p_receipt: { ...args.p_receipt, workerFenced: true },
	});
	assert.equal(r.state, "queued");
	const second = await claim(s, "A", "W1", 2, 1);
	assert.equal(second.generation, 2);
	await assert.rejects(
		() =>
			rpc("pandora_ops_dispatch_v1", {
				...s.args,
				p_lease_id: a.leaseId,
				p_generation: 1,
			}),
		/OPS_LEASE_FENCED/,
	);
});
test("DB resource exclusion works across projects in one organization", async () => {
	const s = await setup(),
		t = await setup({ otherProject: s });
	await ingest(s, [spec()]);
	await ingest(t, [spec()]);
	await resume(s);
	await resume(t);
	await claim(s);
	assert.equal((await claim(t)).reason, "resource_conflict");
	assert.equal((await snapshot(t)).foreignLeases.length, 1);
});
test("DB admits one dispatch sender even when multiple coordinators re-read the same claim", async () => {
	const s = await setup();
	await ingest(s, [spec()]);
	await resume(s);
	const a = await claim(s);
	const args = { ...s.args, p_lease_id: a.leaseId, p_generation: 1 };
	const d1 = await rpc("pandora_ops_dispatch_v1", args),
		d2 = await rpc("pandora_ops_dispatch_v1", args);
	assert.equal(d1.canSend, true);
	assert.equal(d2.canSend, false);
	assert.equal(d1.dispatchId, d2.dispatchId);
});
test("DB owner request rechecks current membership and denies privileged operation names", async () => {
	const s = await setup(),
		actor = randomUUID();
	await db.query(
		"insert into public.memberships values($1,$2,'owner','active')",
		[s.org, actor],
	);
	const args = { ...s.args, p_actor_id: actor, p_operation: "overview" };
	assert.equal(
		(await rpc("pandora_ops_owner_request_v1", args)).tasks.length,
		0,
	);
	await assert.rejects(
		() =>
			rpc("pandora_ops_owner_request_v1", { ...args, p_operation: "verify" }),
		/OPS_OWNER_OPERATION_NOT_EXPOSED/,
	);
	await db.query(
		"update public.memberships set role='member' where user_id=$1",
		[actor],
	);
	await assert.rejects(
		() => rpc("pandora_ops_owner_request_v1", args),
		/OPS_OWNER_SCOPE_DENIED/,
	);
});

// Review regression: the database must validate raw callers, not trust JS normalization.
for (const [name, mutate] of [
  ['string priority', s=>{s.priority='1';}],
  ['string max attempts', s=>{s.maxAttempts='2';}],
  ['string duration', s=>{s.maxDurationSeconds='60';}],
  ['string budget', s=>{s.maxCostMicros='10';}],
  ['leading title space', s=>{s.title=' title';}],
  ['trailing title tab', s=>{s.title='title\t';}],
  ['title control', s=>{s.title='ti\u0001tle';}],
  ['title NBSP', s=>{s.title='\u00a0title';}],
  ['acceptance whitespace', s=>{s.acceptance=[' test'];}],
  ['acceptance control', s=>{s.acceptance=['te\u001fst'];}],
  ['duplicate dependency', s=>{s.dependsOn=['B','B'];}],
  ['duplicate capability', s=>{s.requiredCapabilities=['source.write','source.write'];}],
  ['duplicate acceptance', s=>{s.acceptance=['test','test'];}],
  ['extra source field', s=>{s.source.extra='forbidden';}],
  ['array source', s=>{s.source=[];}],
  ['numeric title', s=>{s.title=12;}],
]) {
 test('DB rejects raw spec divergence: '+name,async()=>{
   const raw=structuredClone(spec()); mutate(raw);
   assert.throws(()=>normalizeTask(raw));
   await assert.rejects(()=>db.query('select private.pandora_ops_validate_spec_v1($1::jsonb)',[JSON.stringify(raw)]),/OPS_/);
 });
}
for(const state of ['queued','handed_off','verifying']) {
 test('DB cancellation terminalizes lease-free '+state, async()=>{
   const s=await setup();
   if(state==='queued') {await ingest(s,[spec()]); await resume(s);}
   else {await startAndHandoff(s); if(state==='verifying') await db.query("update private.pandora_ops_tasks set status='verifying' where project_id=$1 and task_key='A'",[s.project]);}
   const before=await snapshot(s);
   await rpc('pandora_ops_control_v1',{...s.args,p_expected_revision:before.controls.revision,p_action:'cancel_task',p_task_key:'A'});
   const after=await snapshot(s), task=after.tasks.find(t=>t.spec.id==='A');
   assert.equal(task.status,'cancelled'); assert.equal(task.cancelRequested,true);
   assert.equal(after.leases.length,0); assert.equal(after.budget.availableMicros,before.budget.availableMicros);
 });
}
for (const [error,code] of [
 [{message:'OPS_CONTROL_REVISION_CONFLICT',code:'P0001'},'OPS_CONTROL_REVISION_CONFLICT'],
 [{message:'OPS_WORKSPACE_MISSING',code:'P0001'},'OPS_WORKSPACE_MISSING'],
 [{message:'unexpected provider diagnostic',code:'42501'},'42501'],
 [{message:'OPS_INVALID secret-looking suffix',code:'P0001'},'P0001'],
]) test('store preserves bounded operation reason '+code,async()=>{
 const store=new SupabaseOperationsStore({rpc:async()=>({error})});
 await assert.rejects(()=>store.snapshot({organizationId:'o',projectId:'p'}), e=>e.code===code&&e.sqlState===error.code&&e.message==='OPERATIONS_STORE_FAILURE');
});
test('scheduler handles full project larger than the intake batch limit',()=>{
 const {validateGraph}=require('../packages/pandora-operations-room/contracts');
 const {planAssignments}=require('../packages/pandora-operations-room/scheduler');
 const tasks=Array.from({length:5001},(_,i)=>spec('T'+i));
 assert.throws(()=>validateGraph(tasks),/TASK_BATCH_INVALID/);
 const r=planAssignments({tasks:tasks.map(s=>({spec:s,status:'queued',attempt:0,revision:0})),workers:[],leases:[],controls:{revision:0,maxConcurrency:1},budget:{availableMicros:0},now:100});
 assert.equal(r.assignments.length,0);assert.equal(r.blocked.length,5001);
});
test('dedicated main workflow watches verification profile changes',()=>{
 const workflow=fs.readFileSync(path.join(__dirname,'../.github/workflows/operations-room-runtime.yml'),'utf8');
 const push=workflow.split('  push:')[1].split('  workflow_dispatch:')[0];
 assert.ok(push.includes('packages/pandora-verification/src/registry.js'));
});
