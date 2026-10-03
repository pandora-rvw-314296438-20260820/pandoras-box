import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { tryCoreOwnerCommand, validateCoreChatScope } from "../supabase/functions/pandora-intelligence-chat/core-owner-commands.ts";

const platform = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const client = "076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const second = "f1200000-0000-4000-8000-000000000002";
const entry = "f1200000-0000-4000-8000-000000000003";
const noScope = { context: null, kind: "none", targetOrganizationId: null, snapshot: null };
const ownerContext = (target) => ({ surface: "enterprise_settings", route: "/enterprise/core/home", identityScope: "pandora_organization", selectedObject: { coreMode: "owner", coreSection: target ? "client" : "home", ...(target ? { organizationId: target } : {}) } });
const workspaceContext = (target = client, entryId = entry) => ({ surface: "enterprise_overview", route: "/enterprise/plp-boracay/alfred", identityScope: "enterprise_workspace", selectedObject: { organizationId: target, entryId, workspaceSlug: "plp-boracay" } });
function snapshot(overrides = {}) {
  return {
    schema_version: "1", generated_at: "2026-10-03T05:00:00Z", operator: { role: "owner", platform_organization_id: platform },
    clients: [
      { organization_id: client, display_name: "PLP Boracay", slug: "plp-boracay", lifecycle_state: "onboarding", onboarding_state: "blocked", health: "onboarding" },
      { organization_id: second, display_name: "BOK", slug: "bok", lifecycle_state: "active", onboarding_state: "complete", health: "unverified" },
    ],
    connections: [], usage: [], deployments: [], models: [], business: { usage: [] }, ...overrides,
  };
}
function caller(data = snapshot(), error = null) {
  const calls = [];
  return { calls, rpc: async (name, parameters) => { calls.push({ name, parameters }); return { data, error }; } };
}

test("ordinary conversation performs no Core read and preserves the regular chat lane", async () => {
  const user = caller();
  assert.equal(await tryCoreOwnerCommand(user, platform, "Help me write a meeting agenda", noScope), null);
  assert.deepEqual(user.calls, []);
});

test("owner context is authenticated by the caller RPC, not its role label", async () => {
  const user = caller(null, { code: "42501", message: "secret provider detail" });
  await assert.rejects(validateCoreChatScope(user, platform, ownerContext()), { message: "CORE_ACCESS_DENIED" });
  assert.deepEqual(user.calls, [{ name: "pandora_core_snapshot_v1", parameters: { p_section: "home", p_organization_id: null } }]);
});

test("owner management keeps a target distinct from the owner conversation organization", async () => {
  const user = caller(snapshot({ clients: [snapshot().clients[0]] }));
  const scope = await validateCoreChatScope(user, platform, ownerContext(client));
  assert.equal(scope.kind, "owner");
  assert.equal(scope.targetOrganizationId, client);
  assert.deepEqual(user.calls[0].parameters, { p_section: "client", p_organization_id: client });
});

test("owner data cannot be persisted into a customer-scoped conversation", async () => {
  await assert.rejects(validateCoreChatScope(caller(), client, ownerContext()), { message: "CORE_SCOPE_MISMATCH" });
});

test("owner navigation cannot be relabeled as a customer business hydrator", async () => {
  const user = caller();
  await assert.rejects(validateCoreChatScope(user, platform, { ...ownerContext(), route: "/enterprise/plp-boracay/alfred" }), { message: "CORE_SCOPE_MISMATCH" });
  assert.equal(user.calls.length, 0);
});

test("a target-scoped response must contain exactly the authorized customer", async () => {
  await assert.rejects(validateCoreChatScope(caller(), platform, ownerContext(client)), { message: "CORE_ACCESS_DENIED" });
  await assert.rejects(validateCoreChatScope(caller(snapshot({ clients: [{ organization_id: second }] })), platform, ownerContext(client)), { message: "CORE_ACCESS_DENIED" });
});

test("client entry validates the receipt with the caller JWT and exact organization", async () => {
  const user = caller(true);
  const scope = await validateCoreChatScope(user, client, workspaceContext());
  assert.equal(scope.kind, "client");
  assert.deepEqual(user.calls, [{ name: "pandora_core_validate_entry_v1", parameters: { p_entry_id: entry, p_organization_id: client } }]);
});

test("client scope mismatch is rejected before any query or provider execution", async () => {
  const user = caller(true);
  await assert.rejects(validateCoreChatScope(user, platform, workspaceContext()), { message: "CORE_SCOPE_MISMATCH" });
  assert.deepEqual(user.calls, []);
  await assert.rejects(validateCoreChatScope(user, client, workspaceContext(client, "invalid")), { message: "CORE_SCOPE_MISMATCH" });
});

test("expired, revoked, missing and failed client-entry receipts fail closed", async () => {
  for (const data of [false, null, {}, "true"]) {
    await assert.rejects(validateCoreChatScope(caller(data), client, workspaceContext()), { message: "CORE_ENTRY_REQUIRED" });
  }
  await assert.rejects(validateCoreChatScope(caller(true, { message: "Bearer hidden-credential" }), client, workspaceContext()), { message: "CORE_ENTRY_REQUIRED" });
});

test("an active client entry returns to owner mode before reading other clients", async () => {
  const user = caller();
  const result = await tryCoreOwnerCommand(user, client, "Which clients need attention?", { ...noScope, kind: "client", targetOrganizationId: client });
  assert.equal(result.handoff.action, "return_owner");
  assert.equal(result.providerReadback.snapshotVerified, false);
  assert.deepEqual(user.calls, []);
  assert.doesNotMatch(result.reply, /BOK|PLP/);
});

test("attention and onboarding come from actual account state without claiming health", async () => {
  const user = caller();
  const attention = await tryCoreOwnerCommand(user, platform, "Which clients need attention?", noScope);
  assert.match(attention.reply, /PLP Boracay/);
  assert.doesNotMatch(attention.reply, /BOK/);
  assert.match(attention.reply, /onboarding blocked/);
  const onboarding = await tryCoreOwnerCommand(user, platform, "Which clients have not completed onboarding?", noScope);
  assert.match(onboarding.reply, /Incomplete onboarding: 1/);
  const empty = await tryCoreOwnerCommand(caller(snapshot({ clients: [] })), platform, "Which clients need attention?", noScope);
  assert.match(empty.reply, /recorded account state/);
  assert.doesNotMatch(empty.reply, /Platform healthy|All clients are healthy/);
});

test("failed and stale connections remain distinct and raw provider errors are never echoed", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ connections: [
    { client_name: "Pandora", provider: "github", status: "needs_attention", health: "unhealthy", failure_code: "Bearer hidden-provider-credential" },
    { client_name: "PLP", provider: "google", status: "connected", health: "stale" },
    { client_name: "PLP", provider: "vercel", status: "connected", health: "healthy" },
  ] })), platform, "Show me every connection failing right now", noScope);
  assert.match(result.reply, /1 connection needs attention/);
  assert.match(result.reply, /1 other connection is awaiting current verification/);
  assert.doesNotMatch(JSON.stringify(result), /hidden-provider|Bearer|failure_code/);
});

test("customer cost totals separate currency, estimates and billed evidence and exclude Pandora costs", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ usage: [
    { organization_id: client, currency: "USD", estimated_cost_micros: 1250000, billed_cost_micros: null, requests: 3, requests_with_cost: 2 },
    { organization_id: client, currency: "USD", estimated_cost_micros: 4200, billed_cost_micros: null, requests: 1, requests_with_cost: 1 },
    { organization_id: second, currency: "PHP", estimated_cost_micros: "9007199254740993", billed_cost_micros: "8000000000000000", requests: 1, requests_with_cost: 1 },
    { organization_id: platform, currency: "USD", estimated_cost_micros: 999999999, billed_cost_micros: 999999999, requests: 99, requests_with_cost: 99 },
  ] })), platform, "How much did AI cost by client this month?", noScope);
  assert.match(result.reply, /USD 1\.2542 estimated \(partial coverage\)/);
  assert.match(result.reply, /PHP 9007199254\.740993 estimated/);
  assert.match(result.reply, /PHP 8000000000\.00 reconciled billed cost/);
  assert.match(result.reply, /billed cost unverified/);
  assert.doesNotMatch(result.reply, /999\.999999|99 recorded requests/);
  assert.match(result.reply, /Currencies are kept separate/);
});

test("absent, unpriced and unknown-currency usage never becomes a zero bill", async () => {
  const empty = await tryCoreOwnerCommand(caller(), platform, "How much did AI cost by client this month?", noScope);
  assert.match(empty.reply, /evidence gap, not a verified zero bill/);
  const unknown = await tryCoreOwnerCommand(caller(snapshot({ usage: [{ organization_id: client, currency: null, estimated_cost_micros: 5000000, billed_cost_micros: 5000000, requests: 1, requests_with_cost: 1 }] })), platform, "Which customer cost me the most this month?", noScope);
  assert.match(unknown.reply, /estimate unavailable; billed cost unverified/);
  assert.doesNotMatch(unknown.reply, /USD|PHP|5\.00/);
});

test("support authority does not turn denied commercial data into an empty financial view", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ operator: { role: "support", platform_organization_id: platform } })), platform, "How much did AI cost by client this month?", noScope);
  assert.match(result.reply, /Commercial access is required/);
  assert.doesNotMatch(result.reply, /No customer AI usage/);
});

test("near-limit customers require explicit active limits and recorded consumption", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ usage_allowances: [
    { client_name: "PLP Boracay", subscription_state: "active", request_limit: 100, requests_recorded: 85, token_limit: 1000, tokens_recorded: 500 },
    { client_name: "BOK", subscription_state: "active", request_limit: null, requests_recorded: 9000, token_limit: null, tokens_recorded: 9000 },
    { client_name: "Inactive customer", subscription_state: "draft", request_limit: 100, requests_recorded: 99 },
  ] })), platform, "Show me customers nearing their usage limit", noScope);
  assert.match(result.reply, /PLP Boracay — 85 of 100 requests recorded \(85%\)/);
  assert.doesNotMatch(result.reply, /BOK|Inactive customer/);
  assert.match(result.reply, /does not establish remaining billed allowance or an enforced execution quota/);
  const unknown = await tryCoreOwnerCommand(caller(snapshot({ usage_allowances: [] })), platform, "Which tenants are nearing their allowance?", noScope);
  assert.match(unknown.reply, /No active customer allowance can be compared/);
});

test("unbound or stale releases do not become verified live deployments", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ deployments: [
    { provider: "vercel", environment: "production", status: "ready", source_commit_sha: null, evidence_state: "source_unbound" },
    { provider: "vercel", environment: "production", status: "ready", source_commit_sha: "a".repeat(40), evidence_state: "stale" },
  ] })), platform, "Why did yesterday's deployment fail?", noScope);
  assert.match(result.reply, /do not establish a verified cause/);
  assert.match(result.reply, /source unknown; source not linked/);
  assert.match(result.reply, /aaaaaaaaaaaa; stale provider evidence/);
  assert.doesNotMatch(result.reply, /Live|production verified|deployed successfully/);
});

test("model recommendations and local savings remain unproven without comparable evidence", async () => {
  const provider = await tryCoreOwnerCommand(caller(snapshot({ models: [{ provider: "outdated-provider", evidence_state: "stale", success_count: 999 }] })), platform, "Which provider should we stop using?", noScope);
  assert.match(provider.reply, /cannot support a stop-or-switch recommendation/);
  assert.doesNotMatch(provider.reply, /outdated-provider|999 verified/);
  assert.match(provider.reply, /No paid model probe was run/);
  const local = await tryCoreOwnerCommand(caller(), platform, "How much of PLP inference ran locally?", noScope);
  assert.match(local.reply, /not available|not yet available/);
  assert.doesNotMatch(local.reply, /\d+%|saved \$/);
});

test("new-client and proposal requests hand off to governed UI without mutation", async () => {
  for (const [message, action] of [["Create a new enterprise client", "create_client"], ["Prepare a proposal for this prospect", "prepare_proposal"]]) {
    const user = caller();
    const result = await tryCoreOwnerCommand(user, platform, message, noScope);
    assert.equal(result.handoff.kind, "core_navigation");
    assert.equal(result.handoff.source, "core_navigation");
    assert.equal(result.handoff.action, action);
    assert.ok(result.handoff.request);
    assert.equal(result.providerReadback.actionExecuted, false);
    assert.ok(user.calls.every((call) => call.name === "pandora_core_snapshot_v1"));
  }
});

test("a named client's administrator request cannot mutate the current platform team", async () => {
  const user = caller();
  for (const message of ["Give PLP another administrator", "Invite alice@example.test to PLP as admin", "Add a client administrator for PLP"]) {
    const result = await tryCoreOwnerCommand(user, platform, message, noScope);
    assert.equal(result.handoff.organizationId, client);
    assert.equal(result.handoff.action, "manage_users");
    assert.match(result.reply, /No access has changed/);
  }
  assert.ok(user.calls.every((call) => call.name === "pandora_core_snapshot_v1"));
});

test("ambiguous target names demand selection rather than choosing the first tenant", async () => {
  const result = await tryCoreOwnerCommand(caller(), platform, "Give PLP and BOK another administrator", noScope);
  assert.equal(result.handoff.organizationId, null);
  assert.equal(result.handoff.action, "inspect");
  assert.match(result.reply, /more than one customer/);
});

test("denied or failed owner reads stop a client invite instead of falling into a pending team mutation", async () => {
  for (const error of [{ code: "42501", message: "Bearer hidden-auth" }, { code: "XX000", message: "postgres://user:password@private" }]) {
    for (const message of ["Give PLP another administrator", "Invite alice@example.test to PLP as admin"]) {
      const result = await tryCoreOwnerCommand(caller(null, error), platform, message, noScope);
      assert.ok(result);
      assert.equal(result.providerReadback.actionExecuted, false);
      assert.doesNotMatch(JSON.stringify(result), /hidden-auth|postgres:|password@|alice@example/);
    }
  }
});

test("an explicitly current-team request retains existing independent tenant administration", async () => {
  const result = await tryCoreOwnerCommand(caller(null, { code: "42501" }), client, "Invite alice@example.test as member of my team", noScope);
  assert.equal(result, null);
});

test("stored display labels are bounded and cannot leak credential-shaped material", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ clients: [{ ...snapshot().clients[0], display_name: "Authorization: Bearer customer-secret" }] })), platform, "Which clients need attention?", noScope);
  assert.doesNotMatch(JSON.stringify(result), /Authorization|Bearer|customer-secret/);
  assert.match(result.reply, /Client —/);
});

test("malformed snapshots fail closed rather than reporting successful empty data", async () => {
  const invalid = await tryCoreOwnerCommand(caller(snapshot({ clients: null })), platform, "Which clients need attention?", noScope);
  assert.equal(invalid.providerReadback.snapshotVerified, false);
  assert.match(invalid.reply, /could not load/);
  await assert.rejects(tryCoreOwnerCommand(caller(snapshot({ usage: [{ organization_id: client, currency: "USD", requests: 1, requests_with_cost: 2 }] })), platform, "How much did AI cost by client this month?", noScope), { message: "CORE_CONTEXT_UNAVAILABLE" });
});

test("chat validates entry before hydrators and routes Core before team or model dispatch", () => {
  const source = readFileSync("supabase/functions/pandora-intelligence-chat/index.ts", "utf8");
  const handle = source.slice(source.indexOf("async function handle(req:Request)"));
  assert.ok(handle.indexOf("validateCoreChatScope(c.user,c.organizationId,i.enterpriseContext)") < handle.indexOf("hydratePlpBusinessContext(c.user,i.enterpriseContext)"));
  assert.ok(handle.indexOf("tryCoreOwnerCommand(c.user,c.organizationId,controlState.message,coreScope)") < handle.indexOf("tryTeamAdminChat(c,"));
  assert.ok(handle.indexOf("tryCoreOwnerCommand(c.user,c.organizationId,controlState.message,coreScope)") < handle.indexOf("universalDispatch(c.user,"));
  assert.match(source, /const tid=await thread\(c\.admin,c\.organizationId,c\.userId,i\.threadId,i\.projectId,i\.message\)/);
  assert.match(source, /CORE_ENTRY_REQUIRED:\[403,/);
  const module = readFileSync("supabase/functions/pandora-intelligence-chat/core-owner-commands.ts", "utf8");
  assert.doesNotMatch(module, /fetch\(|\.from\(|service_role|SUPABASE_SERVICE_ROLE_KEY|\.rpc\("pandora_core_operate/);
});
