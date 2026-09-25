"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { PGlite } = require("@electric-sql/pglite");
const root = path.resolve(__dirname, "..");
const inventory = fs.readFileSync(path.join(root, "scripts/operations-room-rollout/database-inventory.sql"), "utf8");
const counts = fs.readFileSync(path.join(root, "scripts/operations-room-rollout/runtime-counts.sql"), "utf8");
const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql"), "utf8");
async function database(installed) {
	const db = new PGlite();
	await db.exec(`
		create role anon; create role authenticated; create role service_role;
		create schema private; create schema extensions; create schema supabase_migrations;
		create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
		create table public.organizations(id uuid primary key);
		create table public.memberships(organization_id uuid,user_id uuid,status text,role text);
		create table public.pandora_verification_runs(id uuid primary key,organization_id uuid,project_id uuid,
		 status text,completed_at timestamptz,source_commit text,required_check_profile text);
		create function extensions.digest(bytea,text) returns bytea language sql immutable as 'select sha256($1)';
	`);
	if (installed) {
		await db.exec(migration);
		await db.query("insert into supabase_migrations.schema_migrations(version,name,statements) values($1,$2,$3)",
			["20260925101319", "pandora_operations_room_runtime_v1", [migration]]);
	}
	return db;
}
test("actual PostgreSQL catalogue reports all missing objects without querying absent tables", async () => {
	const db = await database(false);
	try {
		const { rows } = await db.query(inventory);
		assert.equal(rows[0].inventory.tables.length, 8);
		assert.equal(rows[0].inventory.functions.length, 19);
		assert.ok(rows[0].inventory.tables.every((r) => r.exists === false));
		assert.ok(rows[0].inventory.functions.every((r) => r.overloads === 0));
		assert.equal(rows[0].inventory.migration.count, 0);
	} finally { await db.close(); }
});
test("actual merged migration satisfies paused foundation ACL and default contract", async () => {
	const db = await database(true);
	try {
		const [{ inspectFoundation }, m] = await Promise.all([
			import("../scripts/operations-room-rollout/rollout.mjs"),
			import("../scripts/operations-room-rollout/manifest.mjs"),
		]);
		const catalog = (await db.query(inventory)).rows[0].inventory;
		const runtime = (await db.query(counts)).rows[0].runtime_counts;
		const now = Date.now();
		const report = inspectFoundation({ projectRef: m.PROJECT_REF, observedAt: new Date(now).toISOString(),
			catalog, counts: runtime, edge: { projectRef: m.PROJECT_REF, slug: m.EDGE_SLUG,
				observedAt: new Date(now).toISOString(), state: "absent" } }, now);
		assert.equal(report.databaseState, "installed_paused", JSON.stringify(report));
		assert.equal(report.foundationStaged, false);
		assert.equal(runtime.workers, 0); assert.equal(runtime.bindings, 0);
		assert.equal(runtime.events, 0); assert.equal(runtime.dispatches, 0);
		assert.equal(runtime.activeLeases, 0);
	} finally { await db.close(); }
});
test("effective PUBLIC and column grants are visible, not mistaken for RLS exposure", async () => {
	const db = await database(true);
	try {
		await db.exec("grant select (task_key) on private.pandora_ops_tasks to authenticated");
		let c = (await db.query(inventory)).rows[0].inventory;
		assert.equal(c.tables.find((r) => r.name === "pandora_ops_tasks").authenticatedAccess, true);
		assert.equal(c.tables.find((r) => r.name === "pandora_ops_tasks").rls, true);
		await db.exec("grant execute on function public.pandora_ops_project_scope_v1(uuid,uuid) to public");
		c = (await db.query(inventory)).rows[0].inventory;
		const rpc = c.functions.find((r) => r.name === "pandora_ops_project_scope_v1");
		assert.equal(rpc.anonExecute, true); assert.equal(rpc.authenticatedExecute, true);
	} finally { await db.close(); }
});
test("browser roles cannot register a worker through the installed service-only RPC", async () => {
	const db = await database(true);
	try {
		await db.exec("set role authenticated");
		await assert.rejects(db.query("select public.pandora_ops_register_worker_v1(null,null,'fake','fake',array['backend'],array['read'],1,'not-evidence')"),
			(error) => error.code === "42501");
	} finally { await db.close(); }
});


test("function manifest matches independently executed immutable migration, not just catalogue names", async () => {
	const db = await database(true);
	try {
		const m = await import("../scripts/operations-room-rollout/manifest.mjs");
		const catalog = (await db.query(inventory)).rows[0].inventory;
		assert.equal(catalog.migration.statementSha256, m.FILES[0].sha256);
		assert.equal(Object.keys(m.FUNCTION_BODY_SHA256).length, 19);
		for (const fn of catalog.functions)
			assert.equal(fn.bodySha256, m.FUNCTION_BODY_SHA256[`${fn.schema}.${fn.name}`], fn.name);
	} finally { await db.close(); }
});
test("out-of-band routine replacement is detected with unchanged migration receipt and ACL shape", async () => {
	const db = await database(true);
	try {
		const m = await import("../scripts/operations-room-rollout/manifest.mjs");
		await db.exec("create or replace function public.pandora_ops_project_scope_v1(p_organization_id uuid,p_project_id uuid) returns boolean language sql stable security definer set search_path='' as 'select true'");
		const catalog = (await db.query(inventory)).rows[0].inventory;
		const fn = catalog.functions.find((r) => r.name === "pandora_ops_project_scope_v1");
		assert.equal(catalog.migration.statementSha256, m.FILES[0].sha256);
		assert.equal(fn.overloads, 1); assert.equal(fn.anonExecute, false);
		assert.equal(fn.authenticatedExecute, false); assert.equal(fn.serviceRoleExecute, true);
		assert.notEqual(fn.bodySha256, m.FUNCTION_BODY_SHA256["public.pandora_ops_project_scope_v1"]);
	} finally { await db.close(); }
});
