"use strict";

const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migration = readFileSync(join(__dirname,
  "../supabase/migrations/20261003065936_pandora_core_owner_system_v1.sql"), "utf8");
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
let providerFenceBaselines;

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

async function snapshot(section = "home", organization = null) {
  return (await db.query("select public.pandora_core_snapshot_v1($1,$2) as result",
    [section, organization])).rows[0].result;
}

async function operate(operation, organization, payload, key = randomUUID()) {
  return (await db.query("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4) as result",
    [operation, organization, JSON.stringify(payload), key])).rows[0].result;
}

async function enterpriseSnapshot(organization, section = "overview", entryId = null) {
  return (await db.query("select public.pandora_enterprise_workspace_v1($1,$2,$3) as result",
    [organization,section,entryId])).rows[0].result;
}

async function enterpriseOperate(organization, operation, payload, key = randomUUID(), entryId = null) {
  return (await db.query("select public.pandora_enterprise_operate_v1($1,$2,$3::jsonb,$4,$5) as result",
    [organization,operation,JSON.stringify(payload),key,entryId])).rows[0].result;
}

test.before(async () => {
  db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(fixture);
  await db.exec(composerFixture);
  const fenceSignatures=[...migration.matchAll(/\('(public\.[a-z0-9_]+\([^']+\))','[a-f0-9]{64}','perform private\./g)].map((m)=>m[1]);
  providerFenceBaselines=[];
  for(const signature of fenceSignatures){
    providerFenceBaselines.push((await db.query("select pg_get_functiondef(to_regprocedure($1)) as definition",[signature])).rows[0].definition);
  }
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
  } catch (error) {
    // PGlite attaches the complete SQL to errors. Keep CI failure output focused.
    const position = Number(error.position);
    const line = position ? migration.slice(0, position).split("\n").length : "unknown";
    throw new Error(`Core migration failed at line ${line}: ${error.message}`);
  }
});

test.after(async () => { if (db) await db.close(); });
test.beforeEach(async () => { await db.exec("reset role; begin"); });
test.afterEach(async () => { await db.exec("rollback; reset role"); });

test("Core rejects anonymous, unrelated customer, and ungranted platform identities", async () => {
  for (const [user, role] of [[null, "anon"], [clientOwner, "authenticated"],
    [platformAdmin, "authenticated"], [legacyOwner, "authenticated"],
    [unrelated, "authenticated"]]) {
    await asActor(user, { role });
    await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  }
});

test("editable user metadata cannot confer Pandora operator authority", async () => {
  await db.query("update auth.users set raw_user_meta_data=$1::jsonb where id=$2",
    [JSON.stringify({ role: "owner", platform_role: "owner", is_admin: true }), platformAdmin]);
  await asActor(platformAdmin, { claims: {
    user_metadata: { role: "owner", platform_role: "owner", is_admin: true },
  } });
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
});

test("Core owner is explicit and membership revocation takes effect without claim refresh", async () => {
  await asActor(owner);
  const result = await snapshot();
  assert.ok(result && typeof result === "object");
  await db.exec("reset role");
  await db.query("update public.memberships set status='revoked' where organization_id=$1 and user_id=$2",
    [platform, owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
});

test("bootstrap binds the actual PLP organization and never substitutes the legacy property", async () => {
  const account = (await db.query(`select organization_id,property_id,lifecycle_state
    from public.pandora_enterprise_accounts where organization_id=$1`, [client])).rows[0];
  assert.deepEqual(account, {
    organization_id: client, property_id: clientProperty, lifecycle_state: "onboarding",
  });
  assert.equal((await db.query(`select count(*)::int as n
    from public.pandora_enterprise_accounts where organization_id=$1`, [platform])).rows[0].n, 0);
  const grants = (await db.query(`select user_id,role,organization_id
    from private.pandora_operator_grants where state='active'`)).rows;
  assert.deepEqual(grants, [{ user_id: owner, role: "owner", organization_id: null }]);
  await asActor(owner);
  const home = await snapshot();
  assert.equal(home.health.clients, 4);
  assert.equal(home.health.active_clients, 0);
  assert.deepEqual(home.clients.map((c) => c.workspace_type).sort(), ["batalla", "bok", "eurofish", "plp"]);
  assert.ok(home.clients.every((c) => c.lifecycle_state === "onboarding"));
  for (const customer of home.clients.filter((c) => c.organization_id !== client)) {
    assert.equal(customer.users, 0);
    assert.equal(customer.connections, 0);
    assert.equal(customer.devices, 0);
    assert.equal(customer.plan, null);
    assert.equal(customer.can_enter, false);
  }
});

test("revoked and expired explicit grants fail closed even with active platform membership", async () => {
  for (const change of ["state='revoked'", "expires_at=now()-interval '1 second'"]) {
    await db.exec("reset role");
    await db.query(`update private.pandora_operator_grants
      set state='active',expires_at=null where user_id=$1`, [owner]);
    await db.query(`update private.pandora_operator_grants set ${change} where user_id=$1`, [owner]);
    await asActor(owner);
    await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  }
});

test("suspending the platform organization stops operator access", async () => {
  await db.query("update public.organizations set status='suspended' where id=$1", [platform]);
  await asActor(owner);
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
});

test("banned account claims cannot retain operator access", async () => {
  await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1", [owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
});

test("a scoped support grant can read one client and cannot become global operator access", async () => {
  await db.query(`insert into private.pandora_operator_grants
    (user_id,organization_id,role,granted_by,reason) values($1,$2,'support',$3,'Synthetic support assignment')`,
  [scopedOperator, client, owner]);
  await asActor(scopedOperator);
  const accounts = (await db.query(`select organization_id from public.pandora_enterprise_accounts
    order by organization_id`)).rows;
  assert.deepEqual(accounts, [{ organization_id: client }]);
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  await rejectedSql("select public.pandora_core_snapshot_v1('client',$1)", [otherClient]);
  await rejectedSql(`insert into private.pandora_operator_grants
    (user_id,role,granted_by,reason) values($1,'owner',$1,'Forged owner grant')`,
  [scopedOperator], /permission denied/i);
});

test("client users cannot read owner accounts, commercial data, cases, or private grants", async () => {
  // Populate each protected domain first: an empty-table denial is not evidence.
  await asActor(owner);
  const plan = await operate("plan.save",null,{code:"isolation-fixture",name:"Isolation fixture",
    currency:"PHP",state:"active",monthly_fee_micros:1000000});
  await operate("subscription.save",client,{plan_id:plan.id,state:"trial"});
  const invoice = await operate("invoice.save",client,{invoice_number:"ISOLATION-FIXTURE",
    currency:"PHP",amount_micros:1000000,state:"issued"});
  await operate("payment.record",client,{invoice_id:invoice.id,currency:"PHP",amount_micros:100000,
    reference:"Synthetic isolation payment",occurred_on:"2026-10-03"});
  await operate("case.save",client,{subject:"Synthetic private support record"});
  await operate("contract.save",client,{title:"Synthetic commercial agreement"});
  await operate("prospect.save",null,{company_name:"Synthetic private prospect"});
  await operate("incident.save",client,{title:"Synthetic security incident",impact:"Synthetic private impact"});
  await operate("partner.save",null,{name:"Synthetic private vendor",kind:"vendor"});
  const protectedTables = ["pandora_enterprise_accounts", "pandora_customer_subscriptions",
    "pandora_customer_invoices", "pandora_customer_payments", "pandora_customer_cases",
    "pandora_customer_contracts", "pandora_sales_opportunities", "pandora_platform_incidents",
    "pandora_service_plans", "pandora_customer_onboarding_steps", "pandora_business_partners"];
  for (const table of protectedTables) {
    assert.ok((await db.query(`select count(*)::int as n from public.${table}`)).rows[0].n > 0,
      `${table} must contain protected fixture data before a denial can be proved`);
  }
  await asActor(clientOwner);
  for (const table of protectedTables) {
    assert.equal((await db.query(`select count(*)::int as n from public.${table}`)).rows[0].n,
      0, `${table} must be invisible to customer members`);
  }
  await rejectedSql("select * from private.pandora_operator_grants", [], /permission denied/i);
  await rejectedSql(`update public.pandora_enterprise_accounts set lifecycle_state='active'
    where organization_id=$1`, [client], /permission denied/i);
});

test("account property binding rejects a cross-tenant property even for database administrators", async () => {
  await rejectedSql(`update public.pandora_enterprise_accounts set property_id=$1
    where organization_id=$2`, [legacyProperty, client], /foreign key|violates/i);
});

test("scoped operator access cannot disclose the Pandora internal administration roster", async () => {
  await db.query(`insert into private.pandora_operator_grants
    (user_id,organization_id,role,granted_by,reason) values($1,$2,'operator',$3,'Synthetic client assignment')`,
  [scopedOperator, client, owner]);
  await asActor(scopedOperator);
  const scoped = await snapshot("client", client);
  assert.equal(scoped.client.organization_id, client);
  await rejectedSql("select public.pandora_core_snapshot_v1('administration',$1)", [client]);
});

test("provider activation metadata cannot override failed, stale, or expired broker evidence", async () => {
  const connectionId = (await db.query(`insert into private.pandora_connection_accounts_v1
    (organization_id,provider_key,manifest_version,connected_by,account_subject_hash,
     account_label,tenant_key,credential_secret_id,status,health_state,last_verified_at)
    values($1,'fixture-provider','1.0.0',$2,$3,'Synthetic connection','fixture-account',$4,
      'needs_attention','unhealthy',now()) returning id`,
  [client, owner, "a".repeat(64), randomUUID()])).rows[0].id;
  await db.query(`insert into public.pandora_provider_activations
    (organization_id,provider_key,manifest_version,activation_state,health_state,last_verified_at)
    values($1,'fixture-provider','1.0.0','authorized','healthy',now()-interval '3 days')`, [client]);
  await asActor(owner);
  let result = await snapshot("platform", client);
  assert.equal(result.health.connections_healthy, 0);
  assert.equal(result.connections[0].health, "unhealthy");
  assert.equal(result.providers[0].evidence_state, "activation_metadata_only");

  for (const [changes, expectedHealth] of [
    ["status='connected',health_state='healthy',last_verified_at=now()-interval '2 days'", "stale"],
    ["status='connected',health_state='healthy',last_verified_at=now(),credential_expires_at=now()-interval '1 hour'", "expired"],
  ]) {
    await db.exec("reset role");
    await db.query(`update private.pandora_connection_accounts_v1 set ${changes} where id=$1`, [connectionId]);
    await asActor(owner);
    result = await snapshot("platform", client);
    assert.equal(result.connections[0].health, expectedHealth);
    assert.equal(result.health.connections_healthy, 0);
    assert.equal(result.clients[0].connections_healthy, 0);
  }
});

test("a non-connected account cannot be counted healthy even if its health flag says healthy", async () => {
  await db.query(`insert into private.pandora_connection_accounts_v1
    (organization_id,provider_key,manifest_version,connected_by,account_subject_hash,
     account_label,tenant_key,credential_secret_id,status,health_state,last_verified_at)
    values($1,'fixture-provider','1.0.0',$2,$3,'Inconsistent fixture','fixture-account',$4,
      'needs_attention','healthy',now())`,
  [client, owner, "b".repeat(64), randomUUID()]);
  await asActor(owner);
  const result = await snapshot("platform", client);
  assert.equal(result.health.connections_healthy, 0);
  assert.notEqual(result.connections[0].health, "healthy");
});

test("unknown estimates and disputed billing never become known costs or local savings", async () => {
  await db.query(`insert into public.pandora_model_pricing_versions
    (provider,model,pricing_version,currency,input_micros_per_million_tokens,
     cached_input_micros_per_million_tokens,output_micros_per_million_tokens,
     effective_at,source_ref,source_verified_at)
    values('fixture-provider','fixture-model','fixture-v1','USD',100,50,200,
      now()-interval '1 day','https://example.invalid/fixture-price',now())`);
  await db.query(`insert into public.pandora_model_runs
    (organization_id,request_id,task,request_sha256,provider,model,status,pricing_version,
     input_tokens,output_tokens,total_tokens,estimated_cost_micros,cost_estimate_status,
     billed_cost_micros,billing_reconciliation_status)
    values($1,'core-fixture-known','chat',$2,'fixture-provider','fixture-model','succeeded','fixture-v1',
      10,2,12,125000,'estimated',0,'pending'),
      ($1,'core-fixture-unknown','chat',$2,'fixture-provider','fixture-model','succeeded','fixture-v1',
      10,2,12,0,'unavailable',999999,'disputed')`, [client, "c".repeat(64)]);
  await asActor(owner);
  const result = await snapshot("business", client);
  assert.equal(result.usage.length, 1);
  const usage = result.usage[0];
  assert.equal(usage.requests, 2);
  assert.equal(usage.requests_with_cost, 1);
  assert.equal(usage.estimated_cost_micros, 125000);
  assert.equal(usage.billed_cost_micros, null);
  assert.equal(usage.currency, "USD");
  assert.equal(usage.local_share, null);
  assert.equal(usage.local_savings_micros, null);
  assert.equal(usage.coverage, "recorded_model_runs_only");
});

test("manual subscription revenue stays separated by currency and evidence authority", async () => {
  await db.query(`insert into public.pandora_enterprise_accounts
    (organization_id,industry,workspace_type,created_by) values($1,'custom','generic',$2)`,
  [otherClient, owner]);
  const plans = (await db.query(`insert into public.pandora_service_plans
    (code,name,currency,monthly_fee_micros,created_by) values
    ('fixture-php','Fixture PHP','PHP',1000000,$1),
    ('fixture-usd','Fixture USD','USD',2000000,$1) returning id,currency`, [owner])).rows;
  for (const [organization, currency, amount] of [[client, "PHP", 1000000], [otherClient, "USD", 2000000]]) {
    await db.query(`insert into public.pandora_customer_subscriptions
      (organization_id,plan_id,state,currency,monthly_fee_micros,source_kind,updated_by)
      values($1,$2,'active',$3,$4,'manual',$5)`,
    [organization, plans.find((p) => p.currency === currency).id, currency, amount, owner]);
  }
  await asActor(owner);
  const result = await snapshot("business");
  const currencies = result.business.currencies.sort((a,b) => a.currency.localeCompare(b.currency));
  assert.deepEqual(currencies.map((x) => ({currency:x.currency,mrr:x.mrr_micros,arr:x.arr_micros})),
    [{currency:"PHP",mrr:1000000,arr:12000000},{currency:"USD",mrr:2000000,arr:24000000}]);
  assert.ok(currencies.every((x) => x.source_kind === "manual_or_mixed" && x.provider_verified_subscriptions === 0));
});

test("authenticated clients cannot bypass governed membership operations", async () => {
  await asActor(platformAdmin);
  await rejectedSql("update public.memberships set role='member' where organization_id=$1 and user_id=$2",
    [platform, owner], /permission denied/i);
  await rejectedSql("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())",
    [client, platformAdmin], /permission denied/i);
  await rejectedSql("delete from public.memberships where organization_id=$1 and user_id=$2",
    [platform, owner], /permission denied/i);
  await db.exec("reset role");
  assert.equal((await db.query("select role from public.memberships where organization_id=$1 and user_id=$2",
    [platform, owner])).rows[0].role, "owner");
});

test("an operator cannot enter a customer workspace without customer membership", async () => {
  await asActor(owner);
  await rejectedSql("select public.pandora_core_enter_client_v1($1,'Support inspection')", [client]);
});

test("client registration is idempotent, resumes as onboarding, and rejects changed-payload replay", async () => {
  await asActor(owner);
  const key = randomUUID();
  const payload = {
    name: "Synthetic onboarding customer", slug: "synthetic-onboarding-customer",
    industry: "custom", workspace_type: "generic",
    primary_contact_name: "Fixture contact", primary_contact_email: "fixture@example.invalid",
  };
  const first = await operate("client.register", null, payload, key);
  assert.match(first.organization_id, /^[a-f0-9-]{36}$/i);
  const replay = await operate("client.register", null, payload, key);
  assert.equal(replay.organization_id, first.organization_id);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["client.register", null, JSON.stringify({...payload,name:"Changed replay"}), key],
    /idempotency|conflict|replay|payload/i);

  const view = await snapshot("client", first.organization_id);
  assert.equal(view.client.lifecycle_state, "onboarding");
  assert.equal(view.client.users, 0);
  assert.equal(view.client.connections, 0);
  assert.equal(view.client.devices, 0);
  assert.notEqual(view.client.onboarding_state, "complete");
  assert.equal(view.client.can_enter, false);
  assert.ok(view.onboarding.some((s) => s.key === "administrator" && s.state !== "verified"));
  await db.exec("reset role");
  assert.equal((await db.query("select count(*)::int as n from public.organizations where slug=$1",
    [payload.slug])).rows[0].n, 1);
  assert.equal((await db.query(`select count(*)::int as n from private.pandora_core_operation_receipts
    where actor_user_id=$1 and idempotency_key=$2`, [owner, key])).rows[0].n, 1);
  assert.equal((await db.query("select count(*)::int as n from public.memberships where organization_id=$1",
    [first.organization_id])).rows[0].n, 0);
  assert.equal((await db.query("select count(*)::int as n from public.pandora_customer_subscriptions where organization_id=$1",
    [first.organization_id])).rows[0].n, 0);
});

test("partial onboarding cannot be changed into an active account by editing lifecycle", async () => {
  await asActor(owner);
  const created = await operate("client.register", null, {
    name:"Incomplete fixture",slug:"incomplete-fixture",industry:"trade",workspace_type:"eurofish",
  });
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["client.update",created.organization_id,JSON.stringify({lifecycle_state:"active"}),randomUUID()],
    /onboarding|required|blocked|not.ready|verification/i);
  const result = await snapshot("client", created.organization_id);
  assert.equal(result.client.lifecycle_state, "onboarding");
});

test("high-risk commercial mutations require current AAL2 and a matching live session", async () => {
  const payload = {invoice_number:"STEP-UP-FIXTURE",currency:"PHP",amount_micros:1000000,state:"issued"};
  for (const options of [
    {aal:"aal1"},
    {sessionId:null},
    {sessionId:randomUUID()},
    {sessionId:sessions.get(clientOwner)},
  ]) {
    await asActor(owner, options);
    await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
      ["invoice.save",client,JSON.stringify(payload),randomUUID()], /STEP_UP_REQUIRED|session|assurance|aal2/i);
  }
  await db.exec("reset role");
  await db.query("update auth.sessions set not_after=now()-interval '1 second' where id=$1", [sessions.get(owner)]);
  await asActor(owner);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["invoice.save",client,JSON.stringify(payload),randomUUID()], /STEP_UP_REQUIRED|session|assurance|aal2/i);
  await db.exec("reset role");
  assert.equal((await db.query("select count(*)::int as n from public.pandora_customer_invoices where invoice_number=$1",
    [payload.invoice_number])).rows[0].n, 0);
});

test("successful client entry is explicit, target-scoped, and backed by a bounded audit session", async () => {
  await db.query(`insert into public.memberships
    (organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())`, [client, owner]);
  await asActor(owner);
  const before = await snapshot("client", client);
  assert.equal(before.client.can_enter, true);
  const entry = (await db.query("select public.pandora_core_enter_client_v1($1,$2) as result",
    [client,"Synthetic support inspection"])).rows[0].result;
  assert.equal(entry.organization_id, client);
  await db.exec("reset role");
  const sessionsFound = (await db.query(`select actor_user_id,auth_session_id,organization_id,reason,
    expires_at>started_at and expires_at<=started_at+interval '1 hour' as bounded
    from private.pandora_client_entry_sessions where actor_user_id=$1 and organization_id=$2`,
  [owner,client])).rows;
  assert.equal(sessionsFound.length, 1);
  assert.equal(sessionsFound[0].auth_session_id, sessions.get(owner));
  assert.equal(sessionsFound[0].reason, "Synthetic support inspection");
  assert.equal(sessionsFound[0].bounded, true);
  assert.ok((await db.query(`select count(*)::int as n from public.audit_events
    where organization_id=$1 and actor_user_id=$2 and event_type like 'core.%'`,
  [client,owner])).rows[0].n > 0);
});

test("invoice payments preserve tenant and currency boundaries and remain manual records", async () => {
  await asActor(owner);
  await operate("invoice.save", client, {
    invoice_number:"PAYMENT-FIXTURE",currency:"PHP",amount_micros:5000000,state:"issued",
  });
  const invoice = (await db.query("select id,source_kind,verified_at from public.pandora_customer_invoices where invoice_number='PAYMENT-FIXTURE'")).rows[0];
  assert.equal(invoice.source_kind, "manual");
  assert.equal(invoice.verified_at, null);
  const payment = {invoice_id:invoice.id,currency:"PHP",amount_micros:2000000,
    reference:"MANUAL-FIXTURE",occurred_on:"2026-10-03"};
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["payment.record",client,JSON.stringify({...payment,currency:"USD"}),randomUUID()],
    /currency|mismatch|invalid/i);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["payment.record",otherClient,JSON.stringify(payment),randomUUID()],
    /scope|denied|invoice|client|not.found|invalid/i);
  await operate("payment.record",client,payment);
  const result = await snapshot("business",client);
  assert.equal(result.invoices.find((i) => i.id === invoice.id).remaining_micros, 3000000);
  const recorded = result.payments.find((p) => p.invoice_id === invoice.id);
  assert.equal(recorded.source_kind, "manual");
  assert.equal(recorded.verified_at, null);
});

test("entry receipts cannot survive another actor, organization, logout, or customer revocation", async () => {
  await db.query(`insert into public.memberships
    (organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())`, [client, owner]);
  await asActor(owner);
  const entered = (await db.query("select public.pandora_core_enter_client_v1($1,$2) as result",
    [client,"Synthetic receipt validation"])).rows[0].result;
  const valid = async (organization = client) => (await db.query(
    "select public.pandora_core_validate_entry_v1($1,$2) as valid", [entered.entry_id, organization])).rows[0].valid;
  assert.equal(await valid(), true);
  assert.notEqual(await valid(otherClient), true);
  await asActor(clientOwner);
  assert.notEqual(await valid(), true);
  await rejectedSql("select public.pandora_core_leave_client_v1($1)", [entered.entry_id]);
  await asActor(owner, { aal:"aal1" });
  assert.notEqual(await valid(), true);
  await asActor(owner);
  const closed = (await db.query("select public.pandora_core_leave_client_v1($1) as result",
    [entered.entry_id])).rows[0].result;
  assert.equal(closed.status, "closed");
  assert.notEqual(await valid(), true);

  const replacement = (await db.query("select public.pandora_core_enter_client_v1($1,$2) as result",
    [client,"Synthetic revocation validation"])).rows[0].result;
  await db.exec("reset role");
  await db.query("update public.memberships set status='revoked' where user_id=$1 and organization_id=$2",
    [owner,client]);
  await asActor(owner);
  assert.notEqual((await db.query("select public.pandora_core_validate_entry_v1($1,$2) as valid",
    [replacement.entry_id,client])).rows[0].valid, true);
});

test("plans and subscriptions are server records, with no fabricated provider authority", async () => {
  await asActor(owner);
  const planPayload = {code:"fixture-plan",name:"Fixture plan",state:"active",currency:"PHP",
    monthly_fee_micros:3000000,included_allowance_micros:500000,
    limits:{users:5,devices:2,monthly_requests:100},entitlements:["hospitality"],overage_policy:"blocked"};
  const plan = await operate("plan.save",null,planPayload);
  assert.equal(plan.source_kind,"manual");
  const selected = await operate("client.register",null,{name:"Selected plan fixture",
    slug:"selected-plan-fixture",industry:"custom",workspace_type:"generic",plan_id:plan.id});
  const draft = (await snapshot("client",selected.organization_id)).subscription;
  assert.equal(draft.state,"draft");
  assert.equal(draft.source_kind,"manual");
  await operate("subscription.save",client,{plan_id:plan.id,state:"active",currency:"PHP",
    discount_micros:1000000,starts_on:"2026-10-03",renews_on:"2027-10-03"});
  const terms = (await snapshot("client",client)).subscription;
  assert.equal(terms.monthly_fee_micros,3000000);
  assert.equal(terms.discount_micros,1000000);
  assert.equal(terms.verified_at,null);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["subscription.save",client,JSON.stringify({plan_id:plan.id,state:"active",source_kind:"provider_verified"}),randomUUID()]);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["subscription.save",client,JSON.stringify({plan_id:plan.id,state:"active",currency:"USD"}),randomUUID()],/CURRENCY_MISMATCH/);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["plan.save",null,JSON.stringify({...planPayload,id:plan.id,monthly_fee_micros:999}),randomUUID()],/PLAN_IN_USE/);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["plan.save",null,JSON.stringify({...planPayload,code:"invalid-limits",limits:{users:-1}}),randomUUID()]);
});

test("onboarding records blockers, derives real prerequisites, and labels owner attestation", async () => {
  await asActor(owner);
  await operate("onboarding.checkpoint",client,{step:"connections",state:"blocked",note:"Customer authorization is required"});
  const blocked = await snapshot("client",client);
  assert.ok(blocked.needs_you.some((x) => x.kind === "onboarding" && x.organization_id === client));
  const checked = await operate("onboarding.verify",client,{});
  assert.equal(checked.go_live,false);
  assert.equal(checked.ready_for_runtime_verification,false);
  assert.ok(checked.pending_steps > 0);
  assert.equal((await snapshot("client",client)).client.lifecycle_state,"onboarding");
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["client.go_live",client,JSON.stringify({evidence_ref:"fixture:incomplete"}),randomUUID()],/GO_LIVE_VERIFICATION_REQUIRED/);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["onboarding.attest",client,JSON.stringify({step:"administrator",state:"verified",note:"Cannot fabricate an administrator",evidence_ref:"fixture:forged"}),randomUUID()]);
  await operate("capability.activate",client,{pack_key:"hospitality",pack_version:"1.0.0"});
  const plan = await operate("plan.save",null,{code:"onboard-fixture",name:"Onboarding fixture",
    state:"active",currency:"PHP",monthly_fee_micros:0,limits:{users:5,monthly_requests:100}});
  await operate("subscription.save",client,{plan_id:plan.id,state:"trial"});
  for (const [step,state] of [["routing","verified"],["connections","not_required"],["verification","verified"]]) {
    const attested = await operate("onboarding.attest",client,{step,state,
      note:"Synthetic test owner attestation only",evidence_ref:`fixture:${step}`});
    assert.equal(attested.source_kind,"owner_attested");
  }
  const ready = await operate("onboarding.verify",client,{});
  assert.equal(ready.pending_steps,0);
  assert.equal(ready.go_live,false);
  assert.equal((await snapshot("client",client)).client.lifecycle_state,"onboarding");
  const live = await operate("client.go_live",client,{evidence_ref:"fixture:owner-go-live"});
  assert.equal(live.verification_kind,"owner_attested");
  const after = await snapshot("client",client);
  assert.equal(after.client.lifecycle_state,"active");
  assert.equal(after.client.onboarding_state,"complete");
  assert.equal(after.client.connections,0);
  assert.ok(after.onboarding.every((s) => s.source_kind !== "provider_verified"));
});

test("support cases reuse enterprise tasks and require authorized assignees and resolutions", async () => {
  await asActor(owner);
  const payload = {kind:"issue",subject:"Synthetic support issue",priority:"high",needs_owner:true,
    assigned_user_id:clientOwner,description:"Synthetic support fixture"};
  const saved = await operate("case.save",client,payload);
  let view = await snapshot("client",client);
  assert.equal(view.cases.find((c) => c.id === saved.id).state,"open");
  assert.ok(view.needs_you.some((x) => x.id === `case:${saved.id}`));
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["case.save",client,JSON.stringify({...payload,id:saved.id,assigned_user_id:unrelated}),randomUUID()],/ASSIGNEE_NOT_AUTHORIZED/);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["case.save",client,JSON.stringify({...payload,id:saved.id,state:"completed"}),randomUUID()],/RESOLUTION_REQUIRED/);
  await operate("case.save",client,{...payload,id:saved.id,state:"completed",resolution:"Synthetic fix verified"});
  view = await snapshot("client",client);
  assert.equal(view.cases.find((c) => c.id === saved.id).state,"completed");
  assert.ok(!view.needs_you.some((x) => x.id === `case:${saved.id}`));
  await db.exec("reset role");
  const task = (await db.query("select organization_id,task_state from public.enterprise_tasks where entity_id=$1",[saved.id])).rows[0];
  assert.deepEqual(task,{organization_id:client,task_state:"completed"});
});

test("an access request is recoverable and never grants customer membership", async () => {
  await asActor(owner);
  const first = await operate("access.request",client,{reason:"Synthetic support access request"});
  const again = await operate("access.request",client,{reason:"Synthetic support access request"});
  assert.equal(again.id,first.id);
  const view = await snapshot("client",client);
  assert.equal(view.cases.filter((c) => c.kind === "access").length,1);
  assert.equal(view.client.can_enter,false);
  await rejectedSql("select public.pandora_core_enter_client_v1($1,$2)",[client,"Unapproved fixture access"]);
});

test("contracts specialize canonical contracts while pipeline and vendor values remain manual", async () => {
  await asActor(owner);
  const contract = await operate("contract.save",client,{title:"Synthetic customer agreement",contract_type:"service_agreement",
    state:"draft",currency:"PHP",value_micros:10000000,document_url:"https://example.invalid/fixture-contract",
    document_sha256:"d".repeat(64),starts_on:"2026-10-03",renewal_on:"2027-10-03"});
  const prospect = await operate("prospect.save",null,{company_name:"Synthetic prospect",industry:"custom",stage:"qualified",
    next_action:"Schedule a discovery conversation",currency:"PHP",estimated_value_micros:4000000});
  const partner = await operate("partner.save",null,{name:"Synthetic vendor",kind:"vendor",service:"Fixture hosting",
    currency:"PHP",recurring_cost_micros:1000000});
  assert.equal(partner.source_kind,"manual");
  const business = await snapshot("business");
  assert.equal(business.contracts.find((c) => c.contract_entity_id === contract.id).organization_id,client);
  assert.equal(business.pipeline.find((p) => p.id === prospect.id).next_action,"Schedule a discovery conversation");
  assert.equal(business.vendors.find((v) => v.id === partner.id).recurring_cost_micros,1000000);
  await db.exec("reset role");
  assert.deepEqual((await db.query("select organization_id,contract_state from public.enterprise_contracts where entity_id=$1",
    [contract.id])).rows[0],{organization_id:platform,contract_state:"draft"});
});

test("incident recovery requires evidence and device revocation is tenant-scoped server truth", async () => {
  const deviceId = randomUUID();
  await db.query("insert into public.enterprise_entities(id,organization_id,entity_kind) values($1,$2,'device')",[deviceId,client]);
  await db.query("insert into public.enterprise_devices(entity_id,organization_id,model,trust_state) values($1,$2,'Synthetic device','trusted')",[deviceId,client]);
  await asActor(owner);
  const incidentPayload = {title:"Synthetic connection outage",severity:"high",impact:"Synthetic client could not connect"};
  const incident = await operate("incident.save",client,incidentPayload);
  assert.ok((await snapshot()).needs_you.some((x) => x.id === `incident:${incident.id}`));
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["incident.save",client,JSON.stringify({...incidentPayload,id:incident.id,state:"resolved"}),randomUUID()],/check constraint|violates/i);
  await operate("incident.save",client,{...incidentPayload,id:incident.id,state:"resolved",resolution:"Synthetic recovery confirmed",verification_ref:"fixture:recovery"});
  assert.ok(!(await snapshot()).needs_you.some((x) => x.id === `incident:${incident.id}`));
  const other = (await snapshot()).clients.find((c) => c.workspace_type === "bok").organization_id;
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["device.revoke",other,JSON.stringify({id:deviceId,reason:"Cross-tenant fixture attempt"}),randomUUID()]);
  const revoked = await operate("device.revoke",client,{id:deviceId,reason:"Synthetic lost-device response"});
  assert.equal(revoked.verification,"server_trust_revoked_device_acknowledgment_pending");
  assert.equal((await snapshot("client",client)).devices[0].trust_state,"revoked");
});

test("operator grants require an owner, internal membership, and explicit target scope", async () => {
  await asActor(owner);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["operator.grant",null,JSON.stringify({user_id:owner,role:"owner",reason:"Self-change fixture"}),randomUUID()],/SELF_CHANGE_DENIED/);
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["operator.grant",null,JSON.stringify({user_id:clientOwner,role:"owner",reason:"Customer promotion fixture"}),randomUUID()],/INTERNAL_MEMBERSHIP_REQUIRED/);
  const grantPayload = {user_id:scopedOperator,role:"support",scope_organization_id:client,reason:"Synthetic support assignment"};
  await operate("operator.grant",null,grantPayload);
  await asActor(scopedOperator);
  assert.equal((await snapshot("client",client)).operator.role,"support");
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["invoice.save",client,JSON.stringify({invoice_number:"UNAUTHORIZED",currency:"PHP",amount_micros:1}),randomUUID()]);
  await asActor(owner);
  await operate("operator.grant",null,{...grantPayload,state:"revoked"});
  await asActor(scopedOperator);
  await rejectedSql("select public.pandora_core_snapshot_v1('client',$1)",[client]);
});

test("existing user-admin brokers preserve service isolation and add only explicit Core authority", async () => {
  await asActor(owner);
  await rejectedSql("select public.pandora_admin_add_organization_member($1,$2,$3,'admin')",
    [owner,client,platformAdmin],/permission denied/i);
  const authorized = (await db.query("select public.pandora_core_authorize_user_admin_v1($1,true) as result",[client])).rows[0].result;
  assert.equal(authorized.authority,"explicit_operator_grant");
  await asActor(owner,{aal:"aal1"});
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,true)",[client],/STEP_UP_REQUIRED/);
  // Synthetic service broker boundary: production obtains this authorization
  // through the Edge function; this never sends or simulates a real invite.
  await asActor(owner,{role:"service_role"});
  const added = (await db.query("select public.pandora_admin_add_organization_member($1,$2,$3,'admin') as result",
    [owner,client,platformAdmin])).rows[0].result;
  assert.equal(added.status,"active");
  assert.equal(added.created,true);
  const changed = (await db.query("select public.pandora_admin_update_organization_member($1,$2,$3,'member','suspended') as result",
    [owner,client,platformAdmin])).rows[0].result;
  assert.equal(changed.status,"suspended");
  await rejectedSql("select public.pandora_admin_add_organization_member($1,$2,$3,'member')",
    [platformAdmin,client,finance],/administrator|owner|required/i);
});

test("suspending a customer stops existing customer data access as well as Core entry", async () => {
  await asActor(clientOwner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",
    [client])).rows[0].n,1);
  await asActor(owner);
  await operate("client.update",client,{lifecycle_state:"suspended"});
  await asActor(clientOwner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",
    [client])).rows[0].n,0,"customer RLS must reject a suspended canonical organization");
  // An existing customer administrator must not reactivate a suspended tenant.
  assert.equal((await db.query("update public.organizations set status='active' where id=$1 returning id",
    [client])).rows.length,0);
  await db.exec("reset role");
  await db.query("update public.organizations set status='active' where id=$1",[client]);
  await asActor(clientOwner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",
    [client])).rows[0].n,0,"an independently suspended customer account still denies access");
  await db.exec("reset role");
  await db.query("update public.pandora_enterprise_accounts set lifecycle_state='onboarding' where organization_id=$1",[client]);
  await asActor(clientOwner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",
    [client])).rows[0].n,1,"both organization and account must permit access");
});

test("banned or deleted customer identities cannot retain legacy enterprise RLS access", async () => {
  for (const change of ["banned_until=now()+interval '1 day'","deleted_at=now()"]) {
    await db.exec("reset role");
    await db.query("update auth.users set banned_until=null,deleted_at=null where id=$1",[clientOwner]);
    await db.query(`update auth.users set ${change} where id=$1`,[clientOwner]);
    await asActor(clientOwner);
    assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",
      [client])).rows[0].n,0);
  }
});

test("checklist attestations cannot activate a customer without a verified workspace adapter", async () => {
  await asActor(owner);
  const customer = await operate("client.register",null,{name:"Adapter missing fixture",slug:"adapter-missing-fixture",
    industry:"custom",workspace_type:"generic"});
  await db.exec("reset role");
  await db.query(`insert into public.memberships
    (organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())`,
    [customer.organization_id,clientOwner]);
  await asActor(owner);
  await operate("capability.activate",customer.organization_id,{pack_key:"custom",pack_version:"1.0.0"});
  const plan = await operate("plan.save",null,{code:"adapter-fixture",name:"Adapter fixture",state:"active",
    currency:"PHP",monthly_fee_micros:0,limits:{users:1}});
  await operate("subscription.save",customer.organization_id,{plan_id:plan.id,state:"trial"});
  for (const [step,state] of [["connections","not_required"],["routing","verified"],["verification","verified"]]) {
    await operate("onboarding.attest",customer.organization_id,{step,state,
      note:"Synthetic checklist evidence without runtime adapter",evidence_ref:`fixture:${step}`});
  }
  await rejectedSql("select public.pandora_core_operate_v1($1,$2,$3::jsonb,$4)",
    ["client.go_live",customer.organization_id,JSON.stringify({evidence_ref:"fixture:unsupported-workspace"}),randomUUID()],
    /WORKSPACE_NOT_VERIFIED|GO_LIVE_VERIFICATION_REQUIRED/);
  assert.equal((await snapshot("client",customer.organization_id)).client.lifecycle_state,"onboarding");
});

test("Needs You includes only current actionable canonical approvals for the actual authorized owner", async () => {
  const ids = {};
  for (const [key,organization,assignee,decision,expiry] of [
    ["assigned",platform,owner,"pending","1 hour"],
    ["unassigned",platform,null,"pending","1 hour"],
    ["expired",platform,owner,"pending","-1 hour"],
    ["otherAssignee",platform,platformAdmin,"pending","1 hour"],
    ["decided",platform,owner,"approved","1 hour"],
    ["customerWithoutMembership",client,owner,"pending","1 hour"],
  ]) {
    ids[key] = (await db.query(`insert into public.approvals
      (organization_id,run_id,requested_by,assigned_to,decision,action_hash,preview_redacted,
       request_reason,expires_at,decision_by,decided_at)
      values($1,$2,$3,$4,$5::public.approval_decision,$6,'{}',$7,now()+$8::interval,
       case when $5::public.approval_decision='pending' then null else $3::uuid end,
       case when $5::public.approval_decision='pending' then null else now() end) returning id`,
      [organization,randomUUID(),owner,assignee,decision,"e".repeat(64),`Synthetic ${key} approval`,expiry])).rows[0].id;
  }
  await asActor(owner);
  const visible = (await snapshot()).needs_you.filter((n) => n.kind === "approval");
  assert.deepEqual(visible.map((n) => n.id).sort(),[ids.assigned,ids.unassigned].sort());
  assert.ok(visible.every((n) => n.action === "open_approvals" && n.evidence === "e".repeat(64)));
  assert.ok(visible.every((n) => n.organization_id === platform));
  assert.equal((await snapshot("client",client)).needs_you.filter((n) => n.kind === "approval").length,0);
  // Operator status alone cannot surface a customer's approval for decision.
  // A real target membership and live audited entry are both required.
  await db.exec("reset role");
  await db.query(`insert into public.memberships
    (organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())`,[client,owner]);
  await asActor(owner);
  assert.equal((await snapshot("client",client)).needs_you.filter((n) => n.kind === "approval").length,0);
  await db.query("select public.pandora_core_enter_client_v1($1,'Review customer approval')",[client]);
  const scoped = (await snapshot("client",client)).needs_you.filter((n) => n.kind === "approval");
  assert.deepEqual(scoped.map((n) => n.id),[ids.customerWithoutMembership]);
});

test("customer workspace discovery comes from actual active membership without granting Core access", async () => {
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const found = (await db.query("select public.pandora_enterprise_my_workspaces_v1() as result")).rows[0].result;
  assert.equal(found.operator_mode,false);
  assert.equal(found.workspaces.length,1);
  assert.equal(found.workspaces[0].organization_id,client);
  assert.equal(found.workspaces[0].requires_operator_entry,false);
  assert.equal(found.workspaces[0].adapter_key,"plp_v1");
  const workspace = await enterpriseSnapshot(client);
  assert.equal(workspace.organization_id,client);
  assert.equal(workspace.workspace.organization_id,client);
  assert.equal(workspace.actor_role,"owner");
  assert.equal(workspace.viewing_as,"member");
  assert.equal(workspace.entry_id,null);
  assert.equal(workspace.workspace.adapter,"enterprise_core_v1");
  for (const forbidden of ["clients","operator","plans","subscription","invoices","cases","providers","operators","business"]) {
    assert.equal(Object.hasOwn(workspace,forbidden),false,`${forbidden} must stay outside the customer envelope`);
  }
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',null)",[otherClient]);
  await asActor(null,{role:"anon"});
  await rejectedSql("select public.pandora_enterprise_my_workspaces_v1()");
});

test("common Enterprise work is canonical, idempotent, tenant-isolated and conflict safe", async () => {
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const key = randomUUID();
  const payload = {title:"Customer fixture work",description:"Synthetic work capture",due_at:"2026-10-04T10:00:00Z"};
  const saved = await enterpriseOperate(client,"task.create",payload,key);
  assert.equal(saved.organization_id,client);
  assert.equal(saved.task.state,"open");
  assert.equal(saved.task.editable,true);
  const replay = await enterpriseOperate(client,"task.create",payload,key);
  assert.equal(replay.task.id,saved.task.id);
  assert.equal(replay.replayed,true);
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,$2,$3::jsonb,$4,null)",
    [client,"task.create",JSON.stringify({...payload,title:"Different retry"}),key],/CONFLICT/);
  const workspace = await enterpriseSnapshot(client,"work");
  assert.equal(workspace.tasks[0].id,saved.task.id);
  assert.equal(workspace.counts.open_tasks,1);
  const updated = await enterpriseOperate(client,"task.update",{id:saved.task.id,state:"completed",expected_updated_at:saved.task.updated_at});
  assert.equal(updated.task.state,"completed");
  assert.ok(updated.task.completed_at);
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,$2,$3::jsonb,$4,null)",
    [client,"task.update",JSON.stringify({id:saved.task.id,title:"Stale edit",expected_updated_at:saved.task.updated_at}),randomUUID()],/CONFLICT/);
  await db.exec("reset role");
  await db.query("insert into public.pandora_enterprise_accounts(organization_id,industry,workspace_type,created_by) values($1,'custom','generic',$2)",[otherClient,owner]);
  assert.equal((await db.query("select task_type from public.enterprise_tasks where entity_id=$1",[saved.task.id])).rows[0].task_type,"workspace_work");
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_entities where id=$1 and organization_id=$2",[saved.task.id,client])).rows[0].n,1);
  assert.equal((await db.query("select count(*)::int as n from public.audit_events where organization_id=$1 and event_type='enterprise.workspace.task.create'",[client])).rows[0].n,1);
  await asActor(unrelated);
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,$2,$3::jsonb,$4,null)",
    [otherClient,"task.update",JSON.stringify({id:saved.task.id,state:"open",expected_updated_at:updated.task.updated_at}),randomUUID()]);
  assert.equal((await enterpriseSnapshot(otherClient)).tasks.length,0);
});

test("customer viewers can read work but cannot write tasks directly or through the member RPC", async () => {
  await asActor(clientOwner);
  const saved = await enterpriseOperate(client,"task.create",{title:"Viewer fixture work"});
  await db.exec("reset role");
  await db.query("update public.memberships set role='viewer' where user_id=$1 and organization_id=$2",[clientOwner,client]);
  await asActor(clientOwner);
  const view = await enterpriseSnapshot(client);
  assert.equal(view.permissions.can_manage_work,false);
  assert.equal(view.tasks[0].editable,false);
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,'task.create',$2::jsonb,$3,null)",
    [client,JSON.stringify({title:"Forbidden viewer task"}),randomUUID()]);
  await rejectedSql("update public.enterprise_tasks set title='Bypass' where entity_id=$1",[saved.task.id],/permission denied/i);
  await rejectedSql("insert into public.enterprise_entities(organization_id,entity_kind) values($1,'task')",[client],/permission denied/i);
});

test("internal operator workspace reads and writes require the exact live entry receipt", async () => {
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())",[client,owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'work',null)",[client],/CLIENT_ENTRY_REQUIRED/);
  const entry = (await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic common workspace entry') as result",[client])).rows[0].result;
  const saved = await enterpriseOperate(client,"task.create",{title:"Operator fixture work"},randomUUID(),entry.entry_id);
  const view = await enterpriseSnapshot(client,"work",entry.entry_id);
  assert.equal(view.viewing_as,"pandora_administrator");
  assert.equal(view.entry_id,entry.entry_id);
  assert.equal(view.tasks[0].id,saved.task.id);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_tasks where organization_id=$1",[client])).rows[0].n,1);
  await db.query("select public.pandora_core_leave_client_v1($1)",[entry.entry_id]);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'work',$2)",[client,entry.entry_id],/CLIENT_ENTRY_REQUIRED/);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_tasks where organization_id=$1",[client])).rows[0].n,0,
    "direct REST reads must not bypass an ended internal entry");
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,'task.update',$2::jsonb,$3,$4)",
    [client,JSON.stringify({id:saved.task.id,state:"completed",expected_updated_at:saved.task.updated_at}),randomUUID(),entry.entry_id],/CLIENT_ENTRY_REQUIRED/);
  await db.exec("reset role");
  await db.query("update public.memberships set status='revoked' where user_id=$1 and organization_id=$2",[owner,platform]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',null)",[client],/CLIENT_ENTRY_REQUIRED/);
});

test("entry receipt expiry, another tenant, and grant revocation fail closed in the common runtime", async () => {
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())",[client,owner]);
  await asActor(owner);
  const entry = (await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic expiry validation') as result",[client])).rows[0].result;
  const other = (await snapshot()).clients.find((x) => x.workspace_type === "bok").organization_id;
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())",[other,owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',$2)",[other,entry.entry_id],/CLIENT_ENTRY_REQUIRED/);
  await db.exec("reset role");
  await db.query("update private.pandora_client_entry_sessions set started_at=now()-interval '2 hours',expires_at=now()-interval '1 hour' where id=$1",[entry.entry_id]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',$2)",[client,entry.entry_id],/CLIENT_ENTRY_REQUIRED/);
  const nextEntry = (await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic revoked grant validation') as result",[client])).rows[0].result;
  await db.exec("reset role");
  await db.query("update private.pandora_operator_grants set state='revoked' where user_id=$1",[owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',$2)",[client,nextEntry.entry_id],/CLIENT_ENTRY_REQUIRED/);
});

test("member work never exposes or mutates Pandora customer support cases", async () => {
  await asActor(owner);
  const support = await operate("case.save",client,{subject:"Private operator support case",description:"Internal escalation details",needs_owner:true});
  await asActor(clientOwner);
  const workspace = await enterpriseSnapshot(client);
  assert.equal(workspace.tasks.length,0);
  assert.equal(workspace.counts.open_tasks,0);
  assert.equal(workspace.activity.length,0);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_tasks where organization_id=$1",[client])).rows[0].n,0);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_entities where organization_id=$1",[client])).rows[0].n,0);
  await rejectedSql("select public.pandora_enterprise_operate_v1($1,'task.update',$2::jsonb,$3,null)",
    [client,JSON.stringify({id:support.id,title:"Customer attempt",expected_updated_at:new Date().toISOString()}),randomUUID()]);
});

test("common workspace documents use tenant source metadata and never emit signed or unsafe URLs", async () => {
  const connection = randomUUID();
  await db.query(`insert into public.enterprise_integration_connections
    (id,organization_id,source_system_key,display_name,connection_key) values($1,$2,'fixture.documents','Fixture documents','fixture-docs')`,[connection,client]);
  for (const [index,url] of ["https://example.invalid/document","https://example.invalid/document?token=fixture","javascript:alert(1)"].entries()) {
    const sourceId = randomUUID(), documentId = randomUUID();
    await db.query(`insert into public.enterprise_source_records
      (id,organization_id,source_connection_id,source_object_id,object_type,source_observed_at,content_sha256,source_locator,payload_metadata_redacted)
      values($1,$2,$3,$4,'document',now(),$5,$6,$7::jsonb)`,
      [sourceId,client,connection,`fixture-${index}`,"f".repeat(64),url,JSON.stringify({title:`Fixture document ${index}`,private_unrelated_field:"Never project this payload field"})]);
    await db.query("insert into public.enterprise_entities(id,organization_id,entity_kind) values($1,$2,'document')",[documentId,client]);
    await db.query(`insert into public.enterprise_documents
      (entity_id,organization_id,document_type,source_record_id,content_sha256,media_type) values($1,$2,'agreement',$3,$4,'application/pdf')`,
      [documentId,client,sourceId,"f".repeat(64)]);
  }
  await asActor(clientOwner);
  const view = await enterpriseSnapshot(client,"documents");
  assert.equal(view.documents.length,3);
  assert.equal(view.documents.filter((d) => d.source_url !== null).length,1);
  assert.equal(view.documents.find((d) => d.source_url !== null).source_url,"https://example.invalid/document");
  assert.equal(JSON.stringify(view).includes("private_unrelated_field"),false);
  assert.equal(view.sources[0].status,"configured");
  assert.equal(view.counts.documents,3);
});

test("common customer go-live requires real same-tenant recent runtime receipt and owner attestation", async () => {
  await asActor(owner);
  const customer = await operate("client.register",null,{name:"Common runtime fixture",slug:"common-runtime-fixture",industry:"trade",workspace_type:"eurofish"});
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())",[customer.organization_id,clientOwner]);
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const work = await enterpriseOperate(customer.organization_id,"task.create",{title:"Actual local test work"});
  assert.equal((await enterpriseSnapshot(customer.organization_id)).tasks[0].id,work.task.id);
  await asActor(owner);
  await operate("capability.activate",customer.organization_id,{pack_key:"trade",pack_version:"1.0.0"});
  const plan = await operate("plan.save",null,{code:"common-plan-fixture",name:"Common fixture",state:"active",currency:"PHP",monthly_fee_micros:0,limits:{users:1}});
  await operate("subscription.save",customer.organization_id,{plan_id:plan.id,state:"trial"});
  for (const [step,state] of [["connections","not_required"],["routing","verified"]]) {
    await operate("onboarding.attest",customer.organization_id,{step,state,note:"Synthetic fixture attestation",evidence_ref:`fixture:${step}`});
  }
  await operate("onboarding.attest",customer.organization_id,{step:"verification",state:"verified",note:"Synthetic actual local runtime readback",evidence_ref:work.evidence_ref});
  const live = await operate("client.go_live",customer.organization_id,{evidence_ref:work.evidence_ref});
  assert.equal(live.status,"active");
  assert.equal(live.verification_kind,"owner_attested");
  const final = await snapshot("client",customer.organization_id);
  assert.equal(final.client.adapter_key,"enterprise_core_v1");
  assert.equal(final.client.lifecycle_state,"active");
  assert.equal(final.client.property_id,null);
  await db.exec("reset role");
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_properties where organization_id=$1",[customer.organization_id])).rows[0].n,0);
});

test("new workspace guard preserves existing authorized platform reads without exposing other tenants", async () => {
  const entity = randomUUID(),task = randomUUID();
  await db.query("insert into public.enterprise_entities(id,organization_id,entity_kind) values($1,$3,'document'),($2,$3,'task')",[entity,task,platform]);
  await db.query("insert into public.enterprise_tasks(entity_id,organization_id,task_type,title) values($1,$2,'workspace_work','Existing platform work fixture')",[task,platform]);
  await asActor(owner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_entities where organization_id=$1",[platform])).rows[0].n,2);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_tasks where organization_id=$1",[platform])).rows[0].n,1);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',null)",[platform]);
  await asActor(clientOwner);
  assert.equal((await db.query("select count(*)::int as n from public.enterprise_entities where organization_id=$1",[platform])).rows[0].n,0);
});

test("scoped staff can discover and enter assigned customer work without global Core access", async () => {
  const target = (await db.query("select organization_id from public.pandora_enterprise_accounts where workspace_type='bok'")).rows[0].organization_id;
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'member','active',now())",[target,scopedOperator]);
  await db.query("insert into private.pandora_operator_grants(user_id,organization_id,role,granted_by,reason) values($1,$2,'support',$3,'Scoped common workspace fixture')",[scopedOperator,target,owner]);
  await asActor(scopedOperator);
  const discovery = (await db.query("select public.pandora_enterprise_my_workspaces_v1() as result")).rows[0].result;
  assert.equal(discovery.operator_mode,false);
  assert.equal(discovery.workspaces.length,1);
  assert.equal(discovery.workspaces[0].organization_id,target);
  assert.equal(discovery.workspaces[0].requires_operator_entry,true);
  assert.equal(discovery.workspaces[0].adapter_key,"enterprise_core_v1");
  await rejectedSql("select public.pandora_core_snapshot_v1('home',null)");
  const entry = (await db.query("select public.pandora_core_enter_client_v1($1,'Scoped customer assistance') as result",[target])).rows[0].result;
  assert.equal(entry.adapter,"enterprise_core_v1");
  const workspace = await enterpriseSnapshot(target,"overview",entry.entry_id);
  assert.equal(workspace.organization_id,target);
  assert.equal(workspace.viewing_as,"pandora_administrator");
  assert.equal(workspace.actor_role,"member");
  assert.equal(Object.hasOwn(workspace,"business"),false);
});

test("controlled Memory authorization requires a current explicit global Core owner or operator", async () => {
  await db.query("insert into private.pandora_operator_grants(user_id,organization_id,role,granted_by,reason) values($1,$2,'support',$3,'Scoped Memory denial fixture')",[scopedOperator,client,owner]);
  await db.query("insert into private.pandora_operator_grants(user_id,role,granted_by,reason) values($1,'finance',$2,'Finance Memory denial fixture')",[finance,owner]);
  for (const user of [clientOwner,platformAdmin,legacyOwner,scopedOperator,finance]) {
    await asActor(user);
    await rejectedSql("select public.pandora_core_authorize_memory_v1()");
  }
  await asActor(owner);
  assert.equal((await db.query("select public.pandora_core_authorize_memory_v1() as allowed")).rows[0].allowed,true);
  await db.exec("reset role");
  await db.query("insert into private.pandora_operator_grants(user_id,role,granted_by,reason) values($1,'operator',$2,'Global operator Memory fixture')",[platformAdmin,owner]);
  await asActor(platformAdmin);
  assert.equal((await db.query("select public.pandora_core_authorize_memory_v1() as allowed")).rows[0].allowed,true);
  await db.exec("reset role");
  await db.query("update private.pandora_operator_grants set state='revoked' where user_id=$1",[platformAdmin]);
  await asActor(platformAdmin);
  await rejectedSql("select public.pandora_core_authorize_memory_v1()");
});

test("internal client owners cannot bypass explicit Core authority or live MFA in user administration", async () => {
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())",[client,platformAdmin]);
  await asActor(platformAdmin);
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,false)",[client]);
  await asActor(platformAdmin,{role:"service_role"});
  await rejectedSql("select public.pandora_admin_add_organization_member($1,$2,$3,'member')",[platformAdmin,client,finance],/owner|administrator|required/i);
  await rejectedSql("select public.pandora_admin_update_organization_member($1,$2,$3,'member',null)",[platformAdmin,client,clientOwner],/owner|administrator|required/i);
  await db.exec("reset role");
  await db.query("insert into private.pandora_operator_grants(user_id,role,granted_by,reason) values($1,'operator',$2,'Explicit internal user-admin fixture')",[platformAdmin,owner]);
  await asActor(platformAdmin,{aal:"aal1"});
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,true)",[client],/STEP_UP_REQUIRED/);
  await asActor(platformAdmin);
  const authz = (await db.query("select public.pandora_core_authorize_user_admin_v1($1,true) as result",[client])).rows[0].result;
  assert.deepEqual(authz,{organization_id:client,role:"admin",authority:"explicit_operator_grant"});
  await asActor(platformAdmin,{role:"service_role"});
  const added = (await db.query("select public.pandora_admin_add_organization_member($1,$2,$3,'member') as result",[platformAdmin,client,finance])).rows[0].result;
  assert.equal(added.role,"member");
  await db.exec("reset role");
  await db.query("update private.pandora_operator_grants set state='revoked' where user_id=$1",[platformAdmin]);
  await asActor(platformAdmin);
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,true)",[client]);
  await asActor(platformAdmin,{role:"service_role"});
  await rejectedSql("select public.pandora_admin_update_organization_member($1,$2,$3,null,'suspended')",[platformAdmin,client,finance],/owner|administrator|required/i);
});

test("external customer administrators retain own-team authority and platform team uses explicit global Core authority", async () => {
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const customer = (await db.query("select public.pandora_core_authorize_user_admin_v1($1,true) as result",[client])).rows[0].result;
  assert.deepEqual(customer,{organization_id:client,role:"owner",authority:"tenant_membership"});
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,true)",[otherClient]);
  await asActor(clientOwner,{role:"service_role"});
  const added = (await db.query("select public.pandora_admin_add_organization_member($1,$2,$3,'viewer') as result",[clientOwner,client,unrelated])).rows[0].result;
  assert.equal(added.role,"viewer");
  await asActor(platformAdmin);
  await rejectedSql("select public.pandora_core_authorize_user_admin_v1($1,true)",[platform]);
  await asActor(owner);
  const team = (await db.query("select public.pandora_core_authorize_user_admin_v1($1,true) as result",[platform])).rows[0].result;
  assert.deepEqual(team,{organization_id:platform,role:"owner",authority:"explicit_operator_grant"});
  await asActor(owner,{role:"service_role"});
  const updated = (await db.query("select public.pandora_admin_update_organization_member($1,$2,$3,'viewer',null) as result",[owner,platform,finance])).rows[0].result;
  assert.equal(updated.role,"viewer");
});

test("administrator invitations stay pending until accepted and expose the real onboarding blocker", async () => {
  await asActor(owner);
  const customer = await operate("client.register",null,{name:"Invitation fixture",slug:"invitation-fixture",industry:"custom",workspace_type:"generic"});
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status) values($1,$2,'admin','invited')",[customer.organization_id,clientOwner]);
  await asActor(owner);
  const verification = await operate("onboarding.verify",customer.organization_id,{});
  assert.equal(verification.ready_for_runtime_verification,false);
  const view = await snapshot("client",customer.organization_id);
  const step = view.onboarding.find((s) => s.key === "administrator");
  assert.equal(step.state,"pending");
  assert.equal(step.reason,"Administrator invitation awaiting acceptance");
  assert.equal(view.client.users,0);
  assert.equal(view.client.admins,0);
  assert.equal(view.client.lifecycle_state,"onboarding");
});

async function ownerClientEntry() {
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now()) on conflict(organization_id,user_id) do update set status='active'",[client,owner]);
  await asActor(owner);
  return (await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic scope regression') as result",[client])).rows[0].result.entry_id;
}

test("chat authority derives customer mode from canonical actor and tenant rather than supplied context", async () => {
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const member=(await db.query("select public.pandora_enterprise_chat_authority_v1($1,null) as result",[client])).rows[0].result;
  assert.equal(member.scope_kind,"member");
  assert.equal(member.actor_role,"owner");
  assert.equal(member.can_execute_core,false);
  assert.equal(member.core_role,null);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)",[platform]);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)",[otherClient]);
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())",[client,owner]);
  await asActor(owner,{claims:{user_metadata:{enterpriseContext:"member",role:"owner"}}});
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)",[client],/CLIENT_ENTRY_REQUIRED/);
  const entry=(await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic classification test') as result",[client])).rows[0].result;
  const internal=(await db.query("select public.pandora_enterprise_chat_authority_v1($1,$2) as result",[client,entry.entry_id])).rows[0].result;
  assert.equal(internal.scope_kind,"administrator");
  assert.equal(internal.requires_operator_entry,true);
  assert.equal(internal.organization_id,client);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)",[client],/CLIENT_ENTRY_REQUIRED/);
});

test("platform chat permits explicit read roles while marking only owner and operator executable", async () => {
  await asActor(owner);
  let result=(await db.query("select public.pandora_enterprise_chat_authority_v1($1,null) as result",[platform])).rows[0].result;
  assert.equal(result.scope_kind,"platform");
  assert.equal(result.core_role,"owner");
  assert.equal(result.can_execute_core,true);
  await operate("operator.grant",null,{user_id:finance,role:"finance",reason:"Synthetic finance read test"});
  await asActor(finance);
  result=(await db.query("select public.pandora_enterprise_chat_authority_v1($1,null) as result",[platform])).rows[0].result;
  assert.equal(result.core_role,"finance");
  assert.equal(result.can_execute_core,false);
  await asActor(platformAdmin);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,null)",[platform]);
  await asActor(owner);
  await rejectedSql("select public.pandora_enterprise_chat_authority_v1($1,$2)",[platform,randomUUID()]);
});

test("existing activity admission and wrapper require an unexpired customer entry for internal staff", async () => {
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())",[client,owner]);
  await asActor(owner);
  await rejectedSql("select public.pandora_activity_job_begin_v1($1,'no-entry-request',null,null)",[client]);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'no-entry-wrapper',null,null,null)",[client]);
  const entry=(await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic activity regression') as result",[client])).rows[0].result.entry_id;
  const first=(await db.query("select public.pandora_core_activity_begin_v1($1,'same-activity-request',null,null,$2) as result",[client,entry])).rows[0].result;
  const again=(await db.query("select public.pandora_core_activity_begin_v1($1,'same-activity-request',null,null,$2) as result",[client,entry])).rows[0].result;
  assert.equal(first.jobId,again.jobId);
  assert.equal(first.lastSequence,1);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'exact-entry-required',null,null,null)",[client],/CLIENT_ENTRY_REQUIRED/);
  await db.exec("reset role");
  assert.equal((await db.query("select count(*)::int as n from public.pandora_activity_events where job_id=$1",[first.jobId])).rows[0].n,1);
  await db.query("update private.pandora_client_entry_sessions set started_at=now()-interval '30 minutes',expires_at=now()-interval '1 second' where id=$1",[entry]);
  await asActor(owner);
  await rejectedSql("select public.pandora_activity_job_begin_v1($1,'expired-entry-request',null,null)",[client]);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'expired-entry-wrapper',null,null,$2)",[client,entry]);
  await db.exec("reset role");
  assert.equal((await db.query("select count(*)::int as n from public.pandora_activity_jobs where organization_id=$1",[client])).rows[0].n,1);
});

test("ordinary customer activity transport binds the real actor thread and exact tenant", async () => {
  const thread=randomUUID(),otherThread=randomUUID();
  await db.query("insert into public.pandora_intelligence_threads(id,organization_id,created_by,title) values($1,$3,$4,'Customer thread'),($2,$5,$6,'Other thread')",[thread,otherThread,client,clientOwner,otherClient,unrelated]);
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const started=(await db.query("select public.pandora_core_activity_begin_v1($1,'member-activity-request',$2,null,null) as result",[client,thread])).rows[0].result;
  assert.equal(started.threadId,thread);
  assert.equal(started.projectId,null);
  const replay=(await db.query("select public.pandora_activity_replay_v1($1,$2,0,100) as result",[client,started.jobId])).rows[0].result;
  assert.equal(replay.events.length,1);
  const renamed=(await db.query("select public.pandora_intelligence_thread_manage_v1($1,$2,'rename','Updated customer thread',null) as result",[client,thread])).rows[0].result;
  assert.equal(renamed.ok,true);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'foreign-thread-request',$2,null,null)",[client,otherThread],/thread_not_available/);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'foreign-tenant-request',null,null,null)",[otherClient]);
  await rejectedSql("select public.pandora_core_activity_begin_v1($1,'forbidden-project-request',null,$2,null)",[client,randomUUID()],/INVALID_PROJECT_SCOPE/);
  await db.exec("reset role");
  await db.query("update public.memberships set status='revoked' where organization_id=$1 and user_id=$2",[client,clientOwner]);
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  await rejectedSql("select public.pandora_activity_job_begin_v1($1,'revoked-member-request',null,null)",[client]);
});

test("expired entry blocks direct REST conversation history, events and controls as well as helper-scoped property reads", async () => {
  const entry=await ownerClientEntry();
  const thread=randomUUID();
  await db.exec("reset role");
  await db.query("insert into public.pandora_intelligence_threads(id,organization_id,created_by,title) values($1,$2,$3,'Operator client thread')",[thread,client,owner]);
  await db.query("insert into public.pandora_intelligence_messages(thread_id,organization_id,author_role,content) values($1,$2,'user','Synthetic customer scoped message')",[thread,client]);
  await asActor(owner);
  const job=(await db.query("select public.pandora_core_activity_begin_v1($1,'scoped-history-request',$2,null,$3) as result",[client,thread,entry])).rows[0].result;
  await db.query("select public.pandora_activity_control_request_v1($1,$2,'scoped-control-request','cancel',null)",[client,job.jobId]);
  for(const table of ["pandora_intelligence_threads","pandora_intelligence_messages","pandora_activity_jobs","pandora_activity_events","pandora_activity_controls","enterprise_properties"]){
    assert.equal((await db.query(`select count(*)::int as n from public.${table} where organization_id=$1`,[client])).rows[0].n,1,table+" available within active entry");
  }
  await db.exec("reset role");
  await db.query("update private.pandora_client_entry_sessions set started_at=now()-interval '30 minutes',expires_at=now()-interval '1 second' where id=$1",[entry]);
  await asActor(owner);
  for(const table of ["pandora_intelligence_threads","pandora_intelligence_messages","pandora_activity_jobs","pandora_activity_events","pandora_activity_controls","enterprise_properties"]){
    assert.equal((await db.query(`select count(*)::int as n from public.${table} where organization_id=$1`,[client])).rows[0].n,0,table+" denied after entry expiry");
  }
  await rejectedSql("select public.pandora_activity_replay_v1($1,$2,0,100)",[client,job.jobId]);
  await rejectedSql("select public.pandora_activity_control_request_v1($1,$2,'expired-control-request','cancel',null)",[client,job.jobId]);
  await rejectedSql("select public.pandora_activity_device_fact_v1($1,$2,'expired-device-operation','reminder.local','acting',now())",[client,job.jobId]);
  await rejectedSql("select public.pandora_intelligence_thread_manage_v1($1,$2,'rename','Forbidden after expiry',null)",[client,thread]);
  await db.exec("reset role");
  assert.equal((await db.query("select title from public.pandora_intelligence_threads where id=$1",[thread])).rows[0].title,"Operator client thread");
  assert.equal((await db.query("select count(*)::int as n from public.pandora_activity_controls where job_id=$1",[job.jobId])).rows[0].n,1);
});

test("all inspected legacy business APIs reject internal entry omission before their unchanged provider logic", async () => {
  await asActor(owner);
  const calls=[
    ["pandora_eurofish_private_workspace_v1('overview')",[]],
    ["pandora_eurofish_workspace_v1('overview')",[]],
    ["pandora_tax_workspace_v1($1)",[client]],
    ["plp_create_staff_task_v1('fixture-request','fixture-booking','Fixture title','Fixture note','operations','normal')",[]],
    ["plp_enterprise_mobile_bootstrap_v1()",[]],
    ["plp_pandora_activity_logs_v2(null,null,null,10,null)",[]],
    ["plp_recent_business_activity_v1(10)",[]],
    ["plp_resort_audit_v1(10)",[]],
    ["plp_resort_command_center_v1()",[]],
    ["plp_resort_operating_manifest_v1()",[]],
    ["plp_resort_operations_v1()",[]],
    ["plp_resort_transaction_v1('fixture-operation','fixture-id','{}')",[]],
    ["plp_room_operations_v1()",[]],
  ];
  for(const [expression,params] of calls){
    await rejectedSql("select public."+expression,params,/CLIENT_ENTRY_REQUIRED/);
  }
});

test("read-only customer tables cannot be truncated or maintained through inherited authenticated privileges", async () => {
  for(const table of ["memberships","enterprise_entities","enterprise_tasks","enterprise_documents",
    "enterprise_source_records","enterprise_business_activity","enterprise_source_connections",
    "enterprise_integration_connections","enterprise_properties","pandora_activity_jobs",
    "pandora_activity_events","pandora_activity_controls","pandora_intelligence_threads","pandora_intelligence_messages"]){
    for(const privilege of ["INSERT","UPDATE","DELETE","TRUNCATE","REFERENCES","TRIGGER","MAINTAIN"]){
      assert.equal((await db.query("select has_table_privilege('authenticated',$1,$2) as allowed",["public."+table,privilege])).rows[0].allowed,false,table+" "+privilege);
    }
    assert.equal((await db.query("select has_table_privilege('authenticated',$1,'SELECT') as allowed",["public."+table])).rows[0].allowed,true);
  }
});

test("legacy function body fences reject unexpected source instead of patching unknown provider implementations", async () => {
  const bodyFence=migration.slice(migration.indexOf("-- These exact provider-read definitions"),migration.indexOf("create function public.pandora_core_activity_begin_v1"));
  assert.ok(bodyFence.includes("CORE_PROVIDER_BASELINE_CHANGED"));
  for(const definition of providerFenceBaselines) await db.exec(definition+";");
  await db.exec("create or replace function public.pandora_eurofish_private_workspace_v1(p_surface text default 'overview') returns jsonb language plpgsql security definer as $$begin return '{}'::jsonb;end;$$;");
  await rejectedSql(bodyFence,[],/CORE_PROVIDER_BASELINE_CHANGED: public.pandora_eurofish_private_workspace_v1/);
});



test("shared provider and tax authority retains external owners while enforcing internal entry and explicit grants", async () => {
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  assert.equal((await db.query("select public.pandora_tax_can_read_org_v1($1) as allowed",[client])).rows[0].allowed,true);
  assert.equal((await db.query("select public.pandora_tax_can_manage_org_v1($1) as allowed",[client])).rows[0].allowed,true);
  await asActor(legacyOwner);
  assert.equal((await db.query("select public.pandora_tax_can_read_org_v1($1) as allowed",[platform])).rows[0].allowed,false);
  assert.equal((await db.query("select public.pandora_tax_can_manage_org_v1($1) as allowed",[platform])).rows[0].allowed,false);
  await db.exec("reset role");
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'owner','active',now())",[client,owner]);
  await asActor(owner);
  assert.equal((await db.query("select public.pandora_tax_can_read_org_v1($1) as allowed",[client])).rows[0].allowed,false);
  const entry=(await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic provider authority test') as result",[client])).rows[0].result.entry_id;
  assert.equal((await db.query("select public.pandora_tax_can_manage_org_v1($1) as allowed",[client])).rows[0].allowed,true);
  await db.query("select public.pandora_core_leave_client_v1($1)",[entry]);
  assert.equal((await db.query("select public.pandora_tax_can_manage_org_v1($1) as allowed",[client])).rows[0].allowed,false);
  await asActor(clientOwner);
  await db.exec("reset role");
  await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[clientOwner]);
  await asActor(clientOwner);
  assert.equal((await db.query("select public.pandora_tax_can_read_org_v1($1) as allowed",[client])).rows[0].allowed,false);
});

test("retired dispatcher relays are closed to direct clients while preserving service-owned history", async () => {
  const names=["pandora_chat_capability_dispatch_v1",...Array.from({length:8},(_,i)=>"pandora_chat_universal_dispatch_v"+(i+1))];
  for(const name of names){
    const signature="public."+name+"(uuid,text,uuid,uuid)";
    for(const role of ["anon","authenticated"]){
      assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') as allowed",[role,signature])).rows[0].allowed,false);
    }
    assert.equal((await db.query("select has_function_privilege('service_role',$1,'EXECUTE') as allowed",[signature])).rows[0].allowed,true);
  }
  await asActor(owner);
  await rejectedSql("select public.pandora_chat_universal_dispatch_v8($1,'Synthetic retired call',null,null)",[platform],/permission denied/);
});

test("catalog and evidence legacy reads reject omitted or expired operator entry before accessing provider state", async () => {
  const entry=await ownerClientEntry();
  await db.exec("reset role");
  await db.query("update private.pandora_client_entry_sessions set ended_at=now() where id=$1",[entry]);
  await asActor(owner);
  for(const query of ["select public.pandora_chat_model_picker_v1($1,null)",
    "select public.pandora_intelligence_model_catalog_v1($1)",
    "select public.pandora_action_evidence_v1($1,10)"]){
    await rejectedSql(query,[client],/membership_required/);
  }
});

test("client entry reasons are redacted before audit and sequential switches leave one live receipt", async () => {
  const first=await ownerClientEntry();
  const second=(await db.query("select public.pandora_core_enter_client_v1($1,'Synthetic second audited entry') as result",[client])).rows[0].result.entry_id;
  assert.notEqual(first,second);
  assert.equal((await db.query("select public.pandora_core_validate_entry_v1($1,$2) as valid",[first,client])).rows[0].valid,false);
  assert.equal((await db.query("select public.pandora_core_validate_entry_v1($1,$2) as valid",[second,client])).rows[0].valid,true);
  await rejectedSql("select public.pandora_core_enter_client_v1($1,$2)",[client,"Bearer "+"syntheticcredential".repeat(2)],/INVALID_REQUEST/);
  await db.exec("reset role");
  const active=(await db.query("select count(*)::int as n from private.pandora_client_entry_sessions where actor_user_id=$1 and ended_at is null",[owner])).rows[0].n;
  assert.equal(active,1);
  assert.equal((await db.query("select count(*)::int as n from private.pandora_client_entry_sessions where reason like 'Bearer%'")).rows[0].n,0);
});

test("explicit MFA resume restores onboarding access without granting membership or declaring go-live", async () => {
  await asActor(owner);
  await operate("client.update",client,{lifecycle_state:"suspended"});
  await operate("client.update",client,{notes:"Synthetic profile note while suspended"});
  await asActor(clientOwner);
  await rejectedSql("select public.pandora_enterprise_workspace_v1($1,'overview',null)",[client]);
  await asActor(owner,{aal:"aal1"});
  await rejectedSql("select public.pandora_core_operate_v1('client.update',$1,$2::jsonb,$3)",[client,JSON.stringify({lifecycle_state:"onboarding"}),randomUUID()]);
  await asActor(owner);
  const resumed=await operate("client.update",client,{lifecycle_state:"onboarding"});
  assert.equal(resumed.lifecycle_state,"onboarding");
  await db.exec("reset role");
  assert.equal((await db.query("select status from public.organizations where id=$1",[client])).rows[0].status,"active");
  assert.equal((await db.query("select count(*)::int as n from public.memberships where organization_id=$1 and status='active'",[client])).rows[0].n,1);
  assert.equal((await db.query("select state from public.pandora_customer_onboarding_steps where organization_id=$1 and step='go_live'",[client])).rows[0].state,"pending");
  await asActor(clientOwner,{aal:"aal1",sessionId:null});
  const work=await enterpriseOperate(client,"task.create",{title:"Verify resumed workspace"});
  assert.equal(work.status,"saved");
  await asActor(owner);
  await operate("onboarding.attest",client,{step:"verification",state:"verified",note:"Synthetic resumed runtime write and readback verified",evidence_ref:work.evidence_ref});
  const state=await snapshot("client",client);
  assert.equal(state.client.lifecycle_state,"onboarding");
});

test("connection approvals require a current matching AAL2 Auth session and preserve external customer administration", async () => {
  const approval=randomUUID(),connection=randomUUID(),hash="a".repeat(64);
  await db.query("insert into private.pandora_connection_write_approvals_v1(id,organization_id,provider_key,connection_id,tenant_key,requested_by,operation,target_preview,target_hash,expires_at) values($1,$2,'fixture.provider',$3,'fixture-tenant',$4,'fixture.write','{}',$5,now()+interval '1 hour')",[approval,client,connection,clientOwner,hash]);
  const query="select public.pandora_connection_write_approve_v1($1,$2,'fixture.provider',$3,'fixture-tenant',$4) as result";
  for(const change of ["not_after=now()-interval '1 second'","aal='aal1'"]){
    await db.exec("reset role");
    await db.query("update auth.sessions set aal='aal2',not_after=now()+interval '1 hour' where id=$1",[sessions.get(clientOwner)]);
    await db.query("update auth.sessions set "+change+" where id=$1",[sessions.get(clientOwner)]);
    await asActor(clientOwner);
    await rejectedSql(query,[client,approval,connection,hash],/step_up_required/);
  }
  await asActor(clientOwner,{sessionId:sessions.get(owner)});
  await rejectedSql(query,[client,approval,connection,hash],/step_up_required/);
  await asActor(clientOwner,{sessionId:null});
  await rejectedSql(query,[client,approval,connection,hash],/step_up_required/);
  await db.exec("reset role");
  assert.equal((await db.query("select status from private.pandora_connection_write_approvals_v1 where id=$1",[approval])).rows[0].status,"pending");
  await db.query("update auth.sessions set aal='aal2',not_after=now()+interval '1 hour' where id=$1",[sessions.get(clientOwner)]);
  await asActor(clientOwner);
  const approved=(await db.query(query,[client,approval,connection,hash])).rows[0].result;
  assert.equal(approved.ok,true);
  assert.equal(approved.status,"approved");
  assert.equal(approved.tenantId,client);
});
