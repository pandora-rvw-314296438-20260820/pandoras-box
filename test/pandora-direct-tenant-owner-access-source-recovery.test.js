"use strict";

const assert = require("node:assert/strict");
const { randomUUID, createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migration = readFileSync(join(__dirname,
  "../supabase/migrations/20261003065936_pandora_core_owner_system_v1.sql"), "utf8");
const recovered = readFileSync(join(__dirname, "../supabase/migrations/20261003190317_pandora_direct_tenant_owner_access_v1.sql"), "utf8");
const fixture = readFileSync(join(__dirname,
  "fixtures/pandora-core-owner-schema.sql"), "utf8");
const composerFixture = readFileSync(join(__dirname,
  "fixtures/pandora-core-composer-provider-schema.sql"), "utf8");

// These UUIDs exercise the migration's exact bootstrap binding. All auth rows,
// sessions, claims, and commercial records below are synthetic test fixtures.
const platform = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const client = "076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const otherClient = "10000000-0000-4000-8000-000000000003";
const owner = "a0d6f184-3039-4735-8d11-63ce403636e2";
const legacyOwner = "76a3bf0a-5bfa-4ce2-b92a-3646824e5754";
const clientOwner = "f17558e4-e1b2-4b8d-a215-b96775b1a470";
const platformAdmin = "20000000-0000-4000-8000-000000000004";
const scopedOperator = "20000000-0000-4000-8000-000000000005";
const unrelated = "20000000-0000-4000-8000-000000000006";
const finance = "20000000-0000-4000-8000-000000000007";
const clientProperty = "ada9befb-b821-4ae6-86bf-a6d93376815b";
const legacyProperty = "1b919585-20ac-4fb1-a4a9-b3f4261f0b1f";

const users = [owner, legacyOwner, clientOwner, platformAdmin, scopedOperator,
  unrelated, finance];
const sessions = new Map(users.map((user, index) => [user,
  `30000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`]));
let db;


async function asActor(user, options = {}) {
  const role = options.role || "authenticated";
  await db.exec("reset role");
  const claims = {
    role,
    sub: user || undefined,
    is_anonymous: false,
    aal: options.aal || "aal2",
    session_id: Object.hasOwn(options, "sessionId") ? options.sessionId : sessions.get(user),
    ...options.claims,
  };
  await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify(claims)]);
  // Role names are a fixed test allowlist, never derived from a request payload.
  assert.ok(["anon", "authenticated", "service_role"].includes(role));
  await db.exec(`set role ${role}`);
}

async function rejectedSql(sql, params = [], expected = /denied|required|forbidden|permission|unauthori|invalid/i) {
  await db.exec("savepoint expected_rejection");
  try {
    await assert.rejects(db.query(sql, params), expected);
  } finally {
    await db.exec("rollback to savepoint expected_rejection");
    await db.exec("release savepoint expected_rejection");
  }
}

test.before(async () => {
  db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(fixture);
  await db.exec(composerFixture);
  for (const [index, user] of users.entries()) {
    await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())",
      [user, `owner-core-fixture-${index}@example.invalid`]);
    await db.query("insert into auth.sessions(id,user_id,aal,not_after) values($1,$2,'aal2',now()+interval '1 hour')",
      [sessions.get(user), user]);
  }
  await db.query(`insert into public.organizations(id,name,slug,created_by) values
    ($1,'Pandora platform fixture','mcpmaster-staging',$4),
    ($2,'PLP Boracay','plp-boracay',$5),
    ($3,'Another customer fixture','another-customer-fixture',$6)`,
  [platform, client, otherClient, owner, clientOwner, unrelated]);
  for (const [organization, user, role] of [
    [platform, owner, "owner"], [platform, legacyOwner, "owner"],
    [platform, platformAdmin, "admin"], [platform, scopedOperator, "operator"],
    [platform, finance, "member"], [client, clientOwner, "owner"],
    [otherClient, unrelated, "owner"],
  ]) {
    await db.query(`insert into public.memberships
      (organization_id,user_id,role,status,joined_at) values($1,$2,$3,'active',now())`,
    [organization, user, role]);
  }
  await db.query(`insert into public.enterprise_properties
    (id,organization_id,slug,display_name,source_status,source_observed_at) values
    ($1,$2,'plp-boracay','PLP Boracay','healthy',now()),
    ($3,$4,'plp-boracay','Legacy property fixture','stale',now()-interval '14 days')`,
  [clientProperty, client, legacyProperty, platform]);
  try {
    await db.exec(migration);
    // The bounded live ACL readback includes these existing grants. The earlier
    // Core fixture is not a full migration replay; CREATE OR REPLACE must retain
    // this pre-existing ACL, not manufacture it as part of source recovery.
    await db.exec("grant execute on function public.pandora_enterprise_chat_authority_v1(uuid,uuid), public.pandora_enterprise_my_workspaces_v1() to service_role");
    await db.exec(recovered);
  } catch (error) {
    // PGlite attaches the complete SQL to errors. Keep CI failure output focused.
    const position = Number(error.position);
    const line = position ? migration.slice(0, position).split("\n").length : "unknown";
    throw new Error(`Recovery fixture initialization failed: ${error.message}; baseline position ${line}`);
  }
});

test.after(async () => { if (db) await db.close(); });
test.beforeEach(async () => { await db.exec("reset role; begin"); });
test.afterEach(async () => { await db.exec("rollback; reset role"); });

async function authority(organization = client, entryId = null) {
  return (await db.query("select public.pandora_enterprise_chat_authority_v1($1,$2) result", [organization, entryId])).rows[0].result;
}
async function tenantRole(role, status = "active") {
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,$3,$4,now()) on conflict(organization_id,user_id) do update set role=excluded.role,status=excluded.status", [client, owner, role, status]);
  await asActor(owner);
}
async function enter() {
  return (await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic exact-source recovery test') result", [client])).rows[0].result.entry_id;
}

test("source recovery preserves exact provider bytes and has no production mutation claim", () => {
  const receipt = JSON.parse(readFileSync(join(__dirname, "../docs/supabase/recovery/jcyqixttuebxqqfkjonq/20261003-source-parity-recovery.json"), "utf8"));
  const manifest = JSON.parse(readFileSync(join(__dirname, "../docs/migrations/migration-authority-manifest.json"), "utf8"));
  assert.equal(receipt.classification, "recovery_candidate");
  assert.equal(receipt.repository, "pandora-rvw-314296438-20260820/pandoras-box");
  assert.equal(receipt.providerHistoryMutated, false);
  assert.equal(receipt.productionLiveSchemaReplayed, false);
  assert.equal(receipt.originalAuthor, null);
  assert.equal(receipt.executor.hostedIncludeAllQualified, false);
  assert.deepEqual(receipt.entries.map(e => e.version), ["20261003190317", "20261003201314"]);
  for (const entry of receipt.entries) {
    const bytes = readFileSync(join(__dirname, "..", entry.path));
    assert.equal(bytes.length, entry.bytes);
    assert.equal(createHash("sha256").update(bytes).digest("hex"), entry.sha256);
    assert.equal(createHash("md5").update(bytes).digest("hex"), entry.md5);
    assert.equal(entry.statementCount, 1);
    assert.equal(entry.replayMode, "provider_exact_executable");
    assert.equal(entry.transformation, "none");
    assert.equal(entry.path, `supabase/migrations/${entry.version}_${entry.name}.sql`);
    assert.deepEqual(manifest.providerExactRecoveries.find(e => e.version === entry.version), {
      version: entry.version, path: entry.path, sha256: entry.sha256,
      provenance: "docs/supabase/recovery/jcyqixttuebxqqfkjonq/20261003-source-parity-recovery.json",
      authorityState: "recovery_candidate",
    });
  }
});

test("internal tenant owners and admins enter their own member scope without acquiring Core authority", async () => {
  for (const role of ["owner", "admin"]) {
    await tenantRole(role);
    const r = await authority();
    assert.equal(r.organization_id, client);
    assert.equal(r.actor_role, role);
    assert.equal(r.scope_kind, "member");
    assert.equal(r.requires_operator_entry, false);
    assert.equal(r.can_execute_core, false);
    assert.equal(r.core_role, null);
    const listing = (await db.query("select public.pandora_enterprise_my_workspaces_v1() result")).rows[0].result;
    assert.equal(listing.workspaces.find(w => w.organization_id === client).requires_operator_entry, false);
    await db.exec("reset role");
    assert.equal((await db.query("select private.pandora_enterprise_session_scope_v1($1) allowed", [client])).rows[0].allowed, true);
    assert.equal((await db.query("select private.pandora_enterprise_assert_v1($1,null,true) role", [client])).rows[0].role, role);
  }
});

test("other internal tenant roles still require a current audited entry", async () => {
  await tenantRole("member");
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [client], /CLIENT_ENTRY_REQUIRED/);
  const listing = (await db.query("select public.pandora_enterprise_my_workspaces_v1() result")).rows[0].result;
  assert.equal(listing.workspaces.find(w => w.organization_id === client).requires_operator_entry, true);
  await db.exec("reset role");
  assert.equal((await db.query("select private.pandora_enterprise_session_scope_v1($1) allowed", [client])).rows[0].allowed, false);
  await asActor(owner);
  const id = await enter();
  const r = await authority(client, id);
  assert.equal(r.scope_kind, "administrator");
  assert.equal(r.requires_operator_entry, true);
  assert.equal(r.can_execute_core, false);
});

test("supplying an entry preserves validation even when direct owner access is available", async () => {
  await tenantRole("owner");
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,$2)", [client, randomUUID()], /CLIENT_ENTRY_REQUIRED/);
  const id = await enter();
  assert.equal((await authority(client, id)).scope_kind, "administrator");
  for (const mutation of ["ended_at=now()", "started_at=now()-interval '2 minutes',expires_at=now()-interval '1 minute'", "actor_user_id='20000000-0000-4000-8000-000000000006'", "organization_id=(select organization_id from public.pandora_enterprise_accounts where organization_id<>'076a9306-5c4e-4d9d-98d3-e3a6fea968fb' limit 1)"]) {
    await db.exec("reset role; savepoint invalid_entry");
    await db.query(`update private.pandora_client_entry_sessions set ${mutation} where id=$1`, [id]);
    await asActor(owner);
    await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,$2)", [client, id], /CLIENT_ENTRY_REQUIRED|ACCESS_DENIED/);
    await db.exec("reset role; rollback to savepoint invalid_entry; release savepoint invalid_entry");
  }
});

test("tenant membership and lifecycle revocation remain immediate and fail closed", async () => {
  await tenantRole("admin");
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [otherClient], /ACCESS_DENIED/);
  await tenantRole("admin", "revoked");
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [client], /ACCESS_DENIED/);
  await tenantRole("admin");
  for (const state of ["suspended", "offboarding", "archived"]) {
    await db.exec("reset role");
    await db.query("update public.pandora_enterprise_accounts set lifecycle_state=$1 where organization_id=$2", [state, client]);
    await asActor(owner);
    await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [client], /ACCESS_DENIED/);
    const listing = (await db.query("select public.pandora_enterprise_my_workspaces_v1() result")).rows[0].result;
    assert.equal(listing.workspaces.some(w => w.organization_id === client), false);
  }
});

test("external tenant owner retains member authority while Core still requires its independent assertion", async () => {
  await asActor(clientOwner, { aal: "aal1", sessionId: null });
  assert.equal((await authority()).scope_kind, "member");
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [platform]);
  await asActor(owner);
  const core = await authority(platform);
  assert.equal(core.scope_kind, "platform");
  assert.equal(core.core_role, "owner");
  assert.equal(core.can_execute_core, true);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,$2)", [platform, randomUUID()]);
});

test("anonymous, deleted and banned identities cannot discover or enter tenant scope", async () => {
  await asActor(null, { role: "anon" });
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [client]);
  await rejectedSql("select public.pandora_enterprise_my_workspaces_v1()");
  for (const change of ["is_anonymous=true", "deleted_at=now()", "banned_until=now()+interval '1 hour'"]) {
    await db.exec("reset role; savepoint invalid_actor");
    await db.query(`update auth.users set ${change} where id=$1`, [clientOwner]);
    await asActor(clientOwner, { aal: "aal1", sessionId: null });
    await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)", [client]);
    await rejectedSql("select public.pandora_enterprise_my_workspaces_v1()");
    await db.exec("reset role; rollback to savepoint invalid_actor; release savepoint invalid_actor");
  }
});

test("exact recovered helper privileges and search paths match bounded live readback", async () => {
  const receipt = JSON.parse(readFileSync(join(__dirname, "../docs/supabase/recovery/jcyqixttuebxqqfkjonq/20261003-source-parity-recovery.json"), "utf8"));
  const liveFunctions = receipt.entries.find(e => e.version === "20261003190317").functionReceipts;
  const functions = (await db.query(`select n.nspname schema,p.proname name,p.prosecdef security_definer,p.proconfig config,md5(p.prosrc) body_md5,
    has_function_privilege('anon',p.oid,'execute') anon,
    has_function_privilege('authenticated',p.oid,'execute') authenticated,
    has_function_privilege('service_role',p.oid,'execute') service_role
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.proname in('pandora_enterprise_session_scope_v1','pandora_enterprise_assert_v1','pandora_enterprise_chat_authority_v1','pandora_enterprise_my_workspaces_v1')`)).rows;
  assert.equal(functions.length, 4);
  for (const f of functions) {
    assert.equal(f.body_md5, liveFunctions.find(live => live.function_name === f.name && live.schema_name === f.schema).body_md5);
    assert.equal(f.security_definer, true);
    assert.deepEqual(f.config, ['search_path=""']);
    assert.equal(f.anon, false);
    assert.equal(f.authenticated, f.schema === "public");
    assert.equal(f.service_role, f.schema === "public");
  }
});
