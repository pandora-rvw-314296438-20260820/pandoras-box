"use strict";
const test = require("node:test"),
	assert = require("node:assert/strict"),
	{ randomUUID } = require("node:crypto"),
	fs = require("node:fs"),
	path = require("node:path"),
	{ PGlite } = require("@electric-sql/pglite"),
	{ normalizeTask, REPOSITORIES } = require("../packages/pandora-operations-room/contracts");

const runtimeMigration = fs.readFileSync(
	path.join(__dirname, "../supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql"),
	"utf8",
);
const reconciliationMigration = fs.readFileSync(
	path.join(__dirname, "../supabase/migrations/20260928031824_operations_external_success_reconciliation_v1.sql"),
	"utf8",
);
const staleBaseMigration = fs.readFileSync(
	path.join(__dirname, "../supabase/migrations/20260928080500_operations_external_success_stale_base_v1.sql"),
	"utf8",
);
const controlSource = fs.readFileSync(
	path.join(__dirname, "../supabase/functions/mcpmaster-supabase-control/index.ts"),
	"utf8",
);

const REPOSITORY = REPOSITORIES[0];
const BRANCH = "enterprise-ui-business-1";
const PULL_REQUEST = 753;
const REQUESTED_BASE = "a".repeat(40);
const OBSERVED_BASE = "b".repeat(40);
const OBSERVED_HEAD = "c".repeat(40);
const OTHER_HEAD = "d".repeat(40);
let db;

function spec(id = "OPS-EXTERNAL-753") {
	return normalizeTask({
		id,
		title: "Adopt externally completed PR branch update",
		lane: "backend",
		priority: 1,
		dependsOn: [],
		resources: [
			{ key: `git/branch/${BRANCH}`, mode: "write" },
			{ key: `release/pr/${PULL_REQUEST}`, mode: "write" },
		],
		requiredCapabilities: ["source.write"],
		maxCostMicros: 10,
		maxDurationSeconds: 60,
		maxAttempts: 2,
		risk: "source",
		acceptance: ["Adopt only the exact externally observed source for independent verification."],
		source: { repository: REPOSITORY, baseSha: REQUESTED_BASE },
		verificationProfile: "backend_service",
	});
}

async function rpc(name, args) {
	const values = Object.values(args);
	const query = `select public.${name}(${Object.keys(args)
		.map((key, index) => `${key} => $${index + 1}`)
		.join(",")}) as value`;
	const result = await db.query(
		query,
		values.map((value) =>
			typeof value === "object" && value !== null && !Array.isArray(value)
				? JSON.stringify(value)
				: value,
		),
	);
	return result.rows[0].value;
}

async function setGithubReadback({ head = OBSERVED_HEAD, branch = BRANCH, base = OBSERVED_BASE, main = null } = {}) {
	await db.query("delete from private.github_readback_fixture");
	const mainSha = main || base;
	const fixtures = [
		[
			`/repos/${REPOSITORY}/pulls/${PULL_REQUEST}`,
			{
				status: 200,
				body: {
					state: "open",
					head: { sha: head, ref: branch, repo: { full_name: REPOSITORY } },
					base: { sha: base, ref: "main", repo: { full_name: REPOSITORY } },
				},
			},
		],
		[`/repos/${REPOSITORY}/git/ref/heads/main`, { status: 200, body: { object: { sha: mainSha } } }],
		[
			`/repos/${REPOSITORY}/compare/${base}%2E%2E%2E${head}`,
			{ status: 200, body: { status: "ahead", behind_by: 0 } },
		],
		[
			`/repos/${REPOSITORY}/compare/${REQUESTED_BASE}%2E%2E%2E${base}`,
			{ status: 200, body: { status: "ahead", behind_by: 0 } },
		],
	];
	if (mainSha !== base) {
		fixtures.push([
			`/repos/${REPOSITORY}/compare/${base}%2E%2E%2E${mainSha}`,
			{ status: 200, body: { status: "ahead", behind_by: 0 } },
		]);
	}
	for (const [fixturePath, response] of fixtures) {
		await db.query(
			"insert into private.github_readback_fixture(path,response) values($1,$2)",
			[fixturePath, JSON.stringify(response)],
		);
	}
}

async function setup({ dispatch = false } = {}) {
	const organizationId = randomUUID();
	const projectId = randomUUID();
	await db.query("insert into public.organizations(id) values($1)", [organizationId]);
	const scope = { p_organization_id: organizationId, p_project_id: projectId };
	await rpc("pandora_ops_project_binding_v1", {
		...scope,
		p_state: "active",
		p_evidence_ref: "fixture:binding",
	});
	await rpc("pandora_ops_initialize_v1", {
		...scope,
		p_budget_micros: 100,
		p_max_concurrency: 2,
	});
	await rpc("pandora_ops_register_worker_v1", {
		...scope,
		p_worker_key: "builder",
		p_principal_key: "builder-principal",
		p_lanes: ["backend"],
		p_capabilities: ["source.write"],
		p_capacity: 1,
		p_receipt_ref: "fixture:builder",
	});
	await rpc("pandora_ops_register_worker_v1", {
		...scope,
		p_worker_key: "release",
		p_principal_key: "release-principal",
		p_lanes: ["release"],
		p_capabilities: ["provider.readback", "release.verify"],
		p_capacity: 1,
		p_receipt_ref: "fixture:release",
	});
	const taskSpec = spec();
	await rpc("pandora_ops_ingest_v1", { ...scope, p_tasks: JSON.stringify([taskSpec]) });
	await rpc("pandora_ops_control_v1", {
		...scope,
		p_expected_revision: 0,
		p_action: "resume",
	});
	const claim = await rpc("pandora_ops_claim_v1", {
		...scope,
		p_task_key: taskSpec.id,
		p_worker_key: "builder",
		p_task_revision: 0,
		p_control_revision: 1,
	});
	if (dispatch) {
		await rpc("pandora_ops_dispatch_v1", {
			...scope,
			p_lease_id: claim.leaseId,
			p_generation: claim.generation,
			p_ack: null,
		});
	}
	await db.query(
		"update private.pandora_ops_leases set expires_at=clock_timestamp()-interval '1 second' where id=$1",
		[claim.leaseId],
	);
	await rpc("pandora_ops_reconcile_required_v1", {
		...scope,
		p_lease_id: claim.leaseId,
		p_generation: claim.generation,
		p_reason: "EXTERNAL_PROVIDER_SUCCESS_REQUIRES_ADOPTION",
	});
	const taskRow = (
		await db.query(
			"select * from private.pandora_ops_tasks where organization_id=$1 and project_id=$2 and task_key=$3",
			[organizationId, projectId, taskSpec.id],
		)
	).rows[0];
	const receipt = {
		taskId: taskSpec.id,
		taskSpecDigest: taskRow.spec_digest,
		repository: REPOSITORY,
		pullRequest: PULL_REQUEST,
		branch: BRANCH,
		observedHeadSha: OBSERVED_HEAD,
		ref: `github-readback:pr-${PULL_REQUEST}:${OBSERVED_HEAD}`,
	};
	return { organizationId, projectId, scope, claim, taskSpec, receipt };
}

async function reconcile(fixture, receipt = fixture.receipt, identity = {}) {
	return rpc("pandora_ops_reconcile_external_success_v1", {
		...fixture.scope,
		p_lease_id: fixture.claim.leaseId,
		p_generation: fixture.claim.generation,
		p_reconciler_worker_key: identity.workerKey || "release",
		p_reconciler_principal_key: identity.principalKey || "release-principal",
		p_receipt: receipt,
	});
}

async function state(fixture) {
	const [taskResult, leaseResult, receiptResult, eventResult] = await Promise.all([
		db.query(
			"select status,head_sha,handoff,revision from private.pandora_ops_tasks where organization_id=$1 and project_id=$2 and task_key=$3",
			[fixture.organizationId, fixture.projectId, fixture.taskSpec.id],
		),
		db.query("select state,charged_micros from private.pandora_ops_leases where id=$1", [fixture.claim.leaseId]),
		db.query("select * from private.pandora_ops_external_success_receipts where lease_id=$1", [fixture.claim.leaseId]),
		db.query("select event_type from private.pandora_ops_events where event_key=$1", [`external-success:${fixture.claim.leaseId}`]),
	]);
	return {
		task: taskResult.rows[0],
		lease: leaseResult.rows[0],
		receipts: receiptResult.rows,
		events: eventResult.rows,
	};
}

async function assertHeld(fixture) {
	const current = await state(fixture);
	assert.equal(current.task.status, "blocked");
	assert.equal(current.task.head_sha, null);
	assert.equal(current.task.handoff, null);
	assert.equal(current.lease.state, "reconcile");
	assert.equal(current.receipts.length, 0);
	assert.equal(current.events.length, 0);
}

test.before(async () => {
	db = await PGlite.create();
	await db.exec(`
		create role anon;
		create role authenticated;
		create role service_role;
		create schema private;
		create schema extensions;
		create schema auth;
		create table public.organizations(id uuid primary key);
		create table public.memberships(organization_id uuid,user_id uuid,role text,status text);
		create table public.pandora_verification_runs(
			id uuid primary key,organization_id uuid not null,project_id uuid not null,
			status text not null,source_commit text,required_check_profile text,completed_at timestamptz
		);
		create function extensions.digest(data bytea,algorithm text) returns bytea
		language plpgsql immutable as $$
		begin
			if algorithm<>'sha256' then raise exception 'unsupported digest'; end if;
			return pg_catalog.sha256(data);
		end $$;
		create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
	`);
	await db.exec(runtimeMigration);
	await db.exec(`
		create table private.pandora_ops_source_execution_receipts (
			organization_id uuid not null,project_id uuid not null,task_key text not null,
			generation bigint not null,builder_worker_key text not null,builder_principal_key text not null,
			requested_base_sha text not null,effective_base_sha text not null,branch_name text not null,
			head_sha text not null,pull_request integer not null,pull_request_url text not null,
			provider_readback jsonb not null,authority_ref text not null,created_at timestamptz default clock_timestamp(),
			primary key(organization_id,project_id,task_key,generation)
		);
		create table private.github_readback_fixture(path text primary key,response jsonb not null);
		create function private.pandora_integration_github_api_20260825(
			p_method text,p_path text,p_body jsonb default null
		) returns jsonb language sql stable set search_path='' as $$
			select response from private.github_readback_fixture
			where p_method='GET' and path=p_path and p_body is null
		$$;
	`);
	await db.exec(reconciliationMigration);
	await db.exec(staleBaseMigration);
});

test.after(async () => {
	await db?.close();
});

test("external branch success is adopted only for independent verification", async () => {
	const fixture = await setup();
	await setGithubReadback();
	const result = await reconcile(fixture);
	assert.deepEqual(
		{
			state: result.state,
			headSha: result.headSha,
			leaseReleased: result.leaseReleased,
			complete: result.complete,
			replayed: result.replayed,
		},
		{
			state: "verifying",
			headSha: OBSERVED_HEAD,
			leaseReleased: true,
			complete: false,
			replayed: false,
		},
	);
	const current = await state(fixture);
	assert.equal(current.task.status, "verifying");
	assert.equal(current.task.head_sha, OBSERVED_HEAD);
	assert.equal(current.task.handoff, null);
	assert.equal(current.lease.state, "released");
	assert.equal(Number(current.lease.charged_micros), 0);
	assert.equal(current.receipts.length, 1);
	assert.equal(current.receipts[0].provider_operation_id, `github:pull_request_branch_update:${PULL_REQUEST}:${OBSERVED_HEAD}`);
	assert.match(current.receipts[0].provider_receipt_sha256, /^[a-f0-9]{64}$/);
	assert.equal(current.receipts[0].observed_base_sha, OBSERVED_BASE);
	assert.equal(current.events[0].event_type, "external_success_reconciled");
});

test("verified provider success is preserved and requeued when canonical main advanced linearly", async () => {
	const fixture = await setup();
	const currentMain = "f".repeat(40);
	await setGithubReadback({ main: currentMain });
	const result = await reconcile(fixture);
	assert.equal(result.state, "queued");
	assert.equal(result.staleBase, true);
	assert.equal(result.currentMainSha, currentMain);
	assert.equal(result.leaseReleased, true);
	assert.equal(result.complete, false);
	const current = await state(fixture);
	assert.equal(current.task.status, "queued");
	assert.equal(current.task.head_sha, OBSERVED_HEAD);
	assert.equal(current.lease.state, "released");
	assert.equal(current.receipts.length, 1);
	assert.equal(current.receipts[0].provider_readback.staleBase, true);
	assert.equal(current.receipts[0].provider_readback.currentMainSha, currentMain);
	assert.equal(current.events[0].event_type, "external_success_reconciled_stale_base");
});

test("exact replay is idempotent and conflicting replay is rejected", async () => {
	const fixture = await setup();
	await setGithubReadback();
	await reconcile(fixture);
	assert.equal((await reconcile(fixture)).replayed, true);
	await assert.rejects(
		() => reconcile(fixture, { ...fixture.receipt, ref: "changed" }),
		/OPS_EXTERNAL_SUCCESS_REPLAY_CONFLICT/,
	);
	await db.query(
		"update private.pandora_ops_tasks set head_sha=$1 where organization_id=$2 and project_id=$3 and task_key=$4",
		[OTHER_HEAD, fixture.organizationId, fixture.projectId, fixture.taskSpec.id],
	);
	await assert.rejects(() => reconcile(fixture), /OPS_EXTERNAL_SUCCESS_REPLAY_STATE_CONFLICT/);
	await db.query(
		"update private.pandora_ops_tasks set status='complete',head_sha=$1 where organization_id=$2 and project_id=$3 and task_key=$4",
		[OBSERVED_HEAD, fixture.organizationId, fixture.projectId, fixture.taskSpec.id],
	);
	const completedReplay = await reconcile(fixture);
	assert.equal(completedReplay.state, "complete");
	assert.equal(completedReplay.complete, true);
	const current = await state(fixture);
	assert.equal(current.receipts.length, 1);
	assert.equal(current.task.status, "complete");
});

test("caller success or fencing assertions are rejected rather than trusted", async () => {
	const fixture = await setup();
	await setGithubReadback();
	await assert.rejects(
		() => reconcile(fixture, { ...fixture.receipt, providerOutcomeKnown: true, workerFenced: true }),
		/OPS_EXTERNAL_SUCCESS_RECEIPT_INVALID/,
	);
	await assertHeld(fixture);
});

test("PR and branch must match immutable task write resources", async () => {
	const wrongPr = await setup();
	await assert.rejects(
		() => reconcile(wrongPr, { ...wrongPr.receipt, pullRequest: 754 }),
		/OPS_EXTERNAL_SUCCESS_RESOURCE_BINDING_MISMATCH/,
	);
	await assertHeld(wrongPr);

	const wrongBranch = await setup();
	await assert.rejects(
		() => reconcile(wrongBranch, { ...wrongBranch.receipt, branch: "unrelated-branch" }),
		/OPS_EXTERNAL_SUCCESS_RESOURCE_BINDING_MISMATCH/,
	);
	await assertHeld(wrongBranch);
});

test("an existing prior source receipt must bind the prior task head, PR and branch", async () => {
	const fixture = await setup();
	await db.query(
		"update private.pandora_ops_tasks set head_sha=$1 where organization_id=$2 and project_id=$3 and task_key=$4",
		[OTHER_HEAD, fixture.organizationId, fixture.projectId, fixture.taskSpec.id],
	);
	await db.query(
		`insert into private.pandora_ops_source_execution_receipts(
			organization_id,project_id,task_key,generation,builder_worker_key,builder_principal_key,
			requested_base_sha,effective_base_sha,branch_name,head_sha,pull_request,pull_request_url,
			provider_readback,authority_ref
		) values($1,$2,$3,$4,'builder','builder-principal',$5,$5,$6,$7,$8,'fixture:url','{}','fixture:authority')`,
		[
			fixture.organizationId,
			fixture.projectId,
			fixture.taskSpec.id,
			fixture.claim.generation,
			REQUESTED_BASE,
			BRANCH,
			"e".repeat(40),
			PULL_REQUEST,
		],
	);
	await assert.rejects(() => reconcile(fixture), /OPS_EXTERNAL_SUCCESS_PRIOR_SOURCE_RECEIPT_MISMATCH/);
	const current = await state(fixture);
	assert.equal(current.task.status, "blocked");
	assert.equal(current.task.head_sha, OTHER_HEAD);
	assert.equal(current.lease.state, "reconcile");
	assert.equal(current.receipts.length, 0);
});

test("canonical GitHub readback must match exact head and current main ancestry", async () => {
	const wrongHead = await setup();
	await setGithubReadback({ head: OTHER_HEAD });
	await assert.rejects(() => reconcile(wrongHead), /OPS_EXTERNAL_SUCCESS_PR_IDENTITY_MISMATCH/);
	await assertHeld(wrongHead);

	const divergent = await setup();
	await setGithubReadback();
	await db.query(
		"update private.github_readback_fixture set response=$1 where path=$2",
		[
			JSON.stringify({ status: 200, body: { status: "diverged", behind_by: 1 } }),
			`/repos/${REPOSITORY}/compare/${OBSERVED_BASE}%2E%2E%2E${OBSERVED_HEAD}`,
		],
	);
	await assert.rejects(() => reconcile(divergent), /OPS_EXTERNAL_SUCCESS_SOURCE_DIVERGED/);
	await assertHeld(divergent);
});

test("an existing task head must remain an ancestor of the adopted head", async () => {
	const fixture = await setup();
	await setGithubReadback();
	await db.query(
		"update private.pandora_ops_tasks set head_sha=$1 where organization_id=$2 and project_id=$3 and task_key=$4",
		[OTHER_HEAD, fixture.organizationId, fixture.projectId, fixture.taskSpec.id],
	);
	await db.query(
		"insert into private.github_readback_fixture(path,response) values($1,$2)",
		[
			`/repos/${REPOSITORY}/compare/${OTHER_HEAD}%2E%2E%2E${OBSERVED_HEAD}`,
			JSON.stringify({ status: 200, body: { status: "diverged", behind_by: 1 } }),
		],
	);
	await assert.rejects(() => reconcile(fixture), /OPS_EXTERNAL_SUCCESS_PRIOR_HEAD_DIVERGED/);
	const current = await state(fixture);
	assert.equal(current.task.status, "blocked");
	assert.equal(current.task.head_sha, OTHER_HEAD);
	assert.equal(current.lease.state, "reconcile");
	assert.equal(current.receipts.length, 0);
	assert.equal(current.events.length, 0);
	await db.query(
		"update private.github_readback_fixture set response=$1 where path=$2",
		[
			JSON.stringify({ status: 200, body: { status: "ahead", behind_by: 0 } }),
			`/repos/${REPOSITORY}/compare/${OTHER_HEAD}%2E%2E%2E${OBSERVED_HEAD}`,
		],
	);
	assert.equal((await reconcile(fixture)).state, "verifying");
	const adopted = await state(fixture);
	assert.equal(adopted.receipts[0].provider_readback.priorHeadSha, OTHER_HEAD);
	assert.equal(adopted.receipts[0].provider_readback.priorHeadLineageStatus, "ahead");
	assert.equal(Number(adopted.receipts[0].provider_readback.priorHeadBehindBy), 0);
});

test("unexpired or potentially dispatched work cannot be adopted", async () => {
	const unexpired = await setup();
	await db.query(
		"update private.pandora_ops_leases set expires_at=clock_timestamp()+interval '60 seconds' where id=$1",
		[unexpired.claim.leaseId],
	);
	await assert.rejects(() => reconcile(unexpired), /OPS_EXTERNAL_SUCCESS_LEASE_FENCED/);
	await assertHeld(unexpired);

	const dispatched = await setup({ dispatch: true });
	await assert.rejects(() => reconcile(dispatched), /OPS_EXTERNAL_SUCCESS_DISPATCH_PRESENT/);
	await assertHeld(dispatched);
});

test("OIDC action fixes the independent release identity and SQL performs GET-only readback", () => {
	assert.match(controlSource, /operations_external_success_reconcile/);
	assert.match(controlSource, /p_reconciler_worker_key: release\.workerKey/);
	assert.match(controlSource, /p_reconciler_principal_key: release\.principalKey/);
	assert.doesNotMatch(reconciliationMigration, /pandora_direct_box_code_edit|p_method\s*=>\s*'(POST|PUT|PATCH|DELETE)'/i);
	assert.match(reconciliationMigration, /'GET','\/repos\/'.*'\/pulls\/'/s);
	assert.doesNotMatch(reconciliationMigration, /pandora_ops_(record_verification|verify)_v1\s*\(/);
});
