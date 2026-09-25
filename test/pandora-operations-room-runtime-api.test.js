"use strict";
const test = require("node:test"),
	assert = require("node:assert/strict");
const ORG = "11111111-1111-4111-8111-111111111111",
	PROJECT = "22222222-2222-4222-8222-222222222222",
	USER = "33333333-3333-4333-8333-333333333333";
let createOperationsHandler;
test.before(async () => {
	({ createOperationsHandler } = await import(
		"../supabase/functions/pandora-operations-runtime/handler.mjs"
	));
});
function req(body, options = {}) {
	return new Request("https://example.test/ops", {
		method: "POST",
		headers: { "content-type": "application/json", ...options.headers },
		body: JSON.stringify({
			organizationId: ORG,
			projectId: PROJECT,
			operation: "overview",
			...body,
		}),
	});
}
function fixture(actorPatch = {}) {
	const calls = [];
	const handler = createOperationsHandler({
		authenticate: async () => ({
			userId: USER,
			active: true,
			role: "owner",
			organizationId: ORG,
			projectId: PROJECT,
			...actorPatch,
		}),
		rpc: async (name, params) => {
			calls.push({ name, params });
			return { data: { ok: true }, error: null };
		},
		allowedOrigins: ["https://owner.example.test"],
	});
	return { handler, calls };
}
test("owner API derives actor identity from authentication and uses DB owner gate", async () => {
	const f = fixture();
	const r = await f.handler(req());
	assert.equal(r.status, 200);
	assert.equal(f.calls[0].name, "pandora_ops_owner_request_v1");
	assert.equal(f.calls[0].params.p_actor_id, USER);
	assert.equal(f.calls[0].params.p_operation, "overview");
});
for (const [name, actor] of Object.entries({
	nonadmin: { role: "member" },
	inactive: { active: false },
	otherOrg: { organizationId: "other" },
	otherProject: { projectId: "other" },
	noIdentity: { userId: null },
}))
	test("owner API blocks " + name, async () => {
		const f = fixture(actor);
		assert.equal((await f.handler(req())).status, 403);
		assert.equal(f.calls.length, 0);
	});
test("owner API cannot register workers, claim jobs or submit verification", async () => {
	for (const operation of [
		"register_worker",
		"claim",
		"verify",
		"deploy",
		"execute_sql",
	]) {
		const f = fixture();
		assert.equal((await f.handler(req({ operation }))).status, 400);
		assert.equal(f.calls.length, 0);
	}
});
test("owner API rejects forged actor, authority and completion fields", async () => {
	for (const k of ["userId", "role", "approved", "verification", "workerId"]) {
		const f = fixture();
		assert.equal((await f.handler(req({ [k]: "forged" }))).status, 400);
		assert.equal(f.calls.length, 0);
	}
});
test("owner controls require CAS revision and do not widen production scope", async () => {
	const f = fixture();
	assert.equal((await f.handler(req({ operation: "pause" }))).status, 400);
	assert.equal(
		(await f.handler(req({ operation: "resume", expectedRevision: 2 }))).status,
		200,
	);
	assert.equal(f.calls[0].params.p_payload.expectedRevision, 2);
	assert.equal(
		(
			await f.handler(
				req({ operation: "allow_production", expectedRevision: 2 }),
			)
		).status,
		400,
	);
});
test("owner API refuses unexpected origins and wildcard CORS policy", async () => {
	const f = fixture();
	assert.equal(
		(
			await f.handler(
				req({}, { headers: { origin: "https://attacker.example" } }),
			)
		).status,
		403,
	);
	assert.throws(
		() =>
			createOperationsHandler({
				authenticate: () => {},
				rpc: () => {},
				allowedOrigins: ["*"],
			}),
		/WILDCARD/,
	);
});
test("owner API body size and secret rejection happen before persistence", async () => {
	const f = fixture();
	assert.equal(
		(await f.handler(req({}, { headers: { "content-length": "3000000" } })))
			.status,
		413,
	);
	assert.equal(
		(
			await f.handler(
				req({
					operation: "ingest",
					tasks: [{ title: "github_pat_" + "x".repeat(40) }],
				}),
			)
		).status,
		400,
	);
	assert.equal(f.calls.length, 0);
});
test("owner API rejects malformed scopes and non-JSON input", async () => {
	const f = fixture();
	assert.equal(
		(await f.handler(req({ projectId: "not-a-project" }))).status,
		400,
	);
	assert.equal(
		(
			await f.handler(
				new Request("https://example.test", { method: "POST", body: "x" }),
			)
		).status,
		415,
	);
});
test("owner API never returns raw database error text", async () => {
	const h = createOperationsHandler({
		authenticate: async () => ({
			userId: USER,
			active: true,
			role: "owner",
			organizationId: ORG,
			projectId: PROJECT,
		}),
		rpc: async () => ({
			error: { code: "XX000", message: "private-stack-and-credential" },
			data: null,
		}),
	});
	const r = await h(req());
	assert.equal(r.status, 409);
	assert.ok(!(await r.text()).includes("private-stack"));
});
