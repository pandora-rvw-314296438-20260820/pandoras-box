import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { authorizeCoreChatActor, authorizeCoreChatRequest, bindPlpBusinessSnapshot, revalidateCoreExecutionScope, tryCoreOwnerCommand, validateCoreChatScope } from "../supabase/functions/pandora-intelligence-chat/core-owner-commands.ts";

const platform = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const client = "076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const second = "f1200000-0000-4000-8000-000000000002";
const entry = "f1200000-0000-4000-8000-000000000003";
const noScope = { context: null, kind: "none", targetOrganizationId: null, snapshot: null };
const ownerContext = (target) => ({ surface: "enterprise_settings", route: "/enterprise/core/home", identityScope: "pandora_organization", selectedObject: { coreMode: "owner", coreSection: target ? "client" : "home", ...(target ? { organizationId: target } : {}) } });
const workspaceContext = (target = client, entryId = entry) => ({ surface: "enterprise_overview", route: "/enterprise/plp-boracay/alfred", identityScope: "enterprise_workspace", selectedObject: { organizationId: target, entryId, workspaceSlug: "plp-boracay" } });
const commonContext = (target = client, mode = "member", section = "overview") => ({ surface: "enterprise_overview", route: `/enterprise/workspace/${target}/${section}`, identityScope: "enterprise_workspace", selectedObject: { organizationId: target, workspaceMode: mode, adapterKey: "enterprise_core_v1", workspaceKey: "customer", section, ...(mode === "administrator" ? { entryId: entry } : {}) } });
function memberSnapshot(overrides = {}) {
  return { schema_version: "1", generated_at: "2026-10-03T05:00:00Z", organization_id: client, section: "overview",
    workspace: { organization_id: client, display_name: "Customer workspace", adapter: "enterprise_core_v1" },
    actor_role: "member", entry_id: null, viewing_as: "member", permissions: { can_manage_work: true },
    counts: { open_tasks: 2, overdue_tasks: 1, documents: 1, people: 2 },
    tasks: [{ title: "Receive delivery", state: "open", due_at: "2026-10-02T10:00:00Z" }],
    documents: [{ title: "Supplier agreement", source_name: "Document system" }],
    people: [{ display_name: "Workspace member", role: "member" }],
    activity: [{ title: "Delivery received", occurred_at: "2026-10-03T04:00:00Z" }],
    sources: [{ name: "Warehouse", status: "stale" }], ...overrides };
}
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
function chatAuthority(kind = "platform", role = "owner", overrides = {}) {
  return { organization_id: kind === "platform" ? platform : client, actor_role: role, scope_kind: kind,
    requires_operator_entry: kind === "administrator", adapter_key: kind === "platform" ? "pandora_core_v1" : "enterprise_core_v1",
    core_role: kind === "platform" ? "owner" : null, can_execute_core: kind === "platform", ...overrides };
}
function requestCaller(authority = chatAuthority(), projection = snapshot(), authorityError = null) {
  const calls = [];
  return { calls, rpc: async (name, parameters) => {
    calls.push({ name, parameters });
    if (name === "pandora_enterprise_chat_authority_v1") {
      if (authorityError instanceof Error) throw authorityError;
      return { data: authority, error: authorityError };
    }
    if (name === "pandora_core_validate_entry_v1") return { data: true, error: null };
    assert.ok(["pandora_core_snapshot_v1", "pandora_enterprise_workspace_v1"].includes(name));
    return { data: projection, error: null };
  } };
}

test("every context-less platform chat first verifies explicit server authority", async () => {
  const user = requestCaller();
  const scope = await authorizeCoreChatRequest(user, platform, "owner", null, null);
  assert.equal(scope.kind, "none");
  assert.equal(scope.authority.scopeKind, "platform");
  assert.deepEqual(user.calls, [{ name: "pandora_enterprise_chat_authority_v1", parameters: { p_organization_id: platform, p_entry_id: null } }]);
});

test("omitting all context cannot turn customer owner membership into legacy execution authority", async () => {
  const user = requestCaller(chatAuthority("member", "owner"));
  await assert.rejects(authorizeCoreChatRequest(user, client, "owner", null, null), { message: "CORE_WORKSPACE_ACTION_UNAVAILABLE" });
  assert.equal(user.calls.length, 1);
  assert.equal(user.calls[0].name, "pandora_enterprise_chat_authority_v1");
});

test("an internal customer owner cannot omit a receipt or relabel itself as a normal member", async () => {
  for (const context of [null, commonContext()]) {
    const user = requestCaller(null, null, { code: "42501", message: "CLIENT_ENTRY_REQUIRED" });
    await assert.rejects(authorizeCoreChatRequest(user, client, "owner", context, null), { message: "CORE_ACCESS_DENIED" });
    assert.deepEqual(user.calls.map((call) => call.name), ["pandora_enterprise_chat_authority_v1"]);
  }
});

test("customer mode cannot query owner records by adding owner UI labels", async () => {
  const user = requestCaller(chatAuthority("member", "owner"));
  await assert.rejects(authorizeCoreChatRequest(user, client, "owner", ownerContext(), null), { message: "CORE_SCOPE_MISMATCH" });
  assert.equal(user.calls.length, 1);
});

test("ordinary member transport binds server authority to the common workspace read", async () => {
  const user = requestCaller(chatAuthority("member", "member"), memberSnapshot());
  const scope = await authorizeCoreChatRequest(user, client, "member", commonContext(), null);
  assert.equal(scope.kind, "workspace");
  assert.equal(scope.context.actorRole, "member");
  assert.deepEqual(user.calls.map((call) => call.name), ["pandora_enterprise_chat_authority_v1", "pandora_enterprise_workspace_v1"]);
  await assert.rejects(revalidateCoreExecutionScope(user, client, scope), { message: "CORE_WORKSPACE_ACTION_UNAVAILABLE" });
});

test("administrator authority requires the verified receipt and the actual tenant adapter", async () => {
  const user = requestCaller(chatAuthority("administrator", "admin", { adapter_key: "plp_v1" }));
  const scope = await authorizeCoreChatRequest(user, client, "admin", workspaceContext(), null);
  assert.equal(scope.kind, "client");
  assert.equal(user.calls[0].parameters.p_entry_id, entry);
  const wrongAdapter = requestCaller(chatAuthority("administrator", "admin"));
  await assert.rejects(authorizeCoreChatRequest(wrongAdapter, client, "admin", workspaceContext(), null), { message: "CORE_SCOPE_MISMATCH" });
});

test("malformed role, scope and execution flags fail before any owner read", async () => {
  for (const change of [{ organization_id: client }, { actor_role: "member" }, { core_role: "support", can_execute_core: true },
    { can_execute_core: "true" }, { requires_operator_entry: true }, { adapter_key: "plp_v1" }]) {
    const user = requestCaller(chatAuthority("platform", "owner", change));
    await assert.rejects(authorizeCoreChatRequest(user, platform, "owner", ownerContext(), null), { message: "CORE_SCOPE_MISMATCH" });
    assert.equal(user.calls.length, 1);
  }
});

test("scope authority failures redact database details and never fall back to metadata", async () => {
  for (const error of [new Error("Bearer confidential-transport"), { code: "XX000", message: "postgres://private:credential@internal" }]) {
    const user = requestCaller(null, null, error);
    await assert.rejects(authorizeCoreChatRequest(user, platform, "owner", ownerContext(), null), { message: "CORE_CONTEXT_UNAVAILABLE" });
    assert.equal(user.calls.length, 1);
  }
});

test("support and finance retain authorized Core reads without inheriting owner engine power", async () => {
  for (const coreRole of ["support", "finance"]) {
    const user = requestCaller(chatAuthority("platform", "owner", { core_role: coreRole, can_execute_core: false }),
      snapshot({ operator: { role: coreRole, platform_organization_id: platform } }));
    const scope = await authorizeCoreChatRequest(user, platform, "owner", null, null);
    const result = await tryCoreOwnerCommand(user, platform, "Which clients need attention?", scope);
    assert.match(result.reply, /PLP Boracay/);
    await assert.rejects(revalidateCoreExecutionScope(user, platform, scope), { message: "CORE_WORKSPACE_ACTION_UNAVAILABLE" });
  }
});

test("platform grants and temporary entries are checked again immediately before legacy execution", async () => {
  const user = requestCaller();
  const scope = await authorizeCoreChatRequest(user, platform, "owner", null, null);
  const revoked = requestCaller(null, null, { code: "42501", message: "ACCESS_DENIED" });
  await assert.rejects(revalidateCoreExecutionScope(revoked, platform, scope), { message: "CORE_ACCESS_DENIED" });
  const downgraded = requestCaller(chatAuthority("platform", "owner", { core_role: "support", can_execute_core: false }));
  await assert.rejects(revalidateCoreExecutionScope(downgraded, platform, scope), { message: "CORE_WORKSPACE_ACTION_UNAVAILABLE" });
  const admin = requestCaller(chatAuthority("administrator", "admin", { adapter_key: "plp_v1" }));
  const entered = await authorizeCoreChatRequest(admin, client, "admin", workspaceContext(), null);
  await assert.rejects(revalidateCoreExecutionScope(revoked, client, entered), { message: "CORE_ACCESS_DENIED" });
});

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

test("protected request allowance uses admitted turns and leaves other commercial limits unenforced", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ usage_allowances: [
    { client_name: "PLP Boracay", request_admission_enabled: true, request_admission_state: "enforcing", requests_admitted: 8,
      request_limit: 10, requests_remaining: 2, requests_recorded: 500, tokens_recorded: 99999, token_limit: 100,
      request_effective_from: "2026-10-03T08:00:00Z", request_reset_at: "2026-11-01T00:00:00Z" },
    { client_name: "BOK", request_admission_enabled: true, request_admission_state: "policy_unavailable", requests_remaining: null },
    { client_name: "Not enrolled", request_admission_enabled: false, request_limit: 1, requests_recorded: 1000 },
  ] })), platform, "Which customers are nearing their allowance?", noScope);
  assert.match(result.reply, /PLP Boracay — 8 of 10 cloud-chat requests admitted; 2 remaining/);
  assert.match(result.reply, /Effective from 2026-10-03T08:00:00Z; resets 2026-11-01T00:00:00Z/);
  assert.match(result.reply, /BOK — cloud-chat requests are blocked/);
  assert.match(result.reply, /Token, cost, seat and device allowances remain commercial records, not runtime hard limits/);
  assert.doesNotMatch(result.reply, /500|99999|1000|Not enrolled/);
});

test("missing protected quota evidence stays unknown and zero limit blocks admission", async () => {
  const result = await tryCoreOwnerCommand(caller(snapshot({ usage_allowances: [
    { client_name: "Missing evidence", request_admission_enabled: true, request_admission_state: "enforcing", requests_admitted: null,
      request_limit: 10, requests_remaining: null },
    { client_name: "Zero allowance", request_admission_enabled: true, request_admission_state: "limit_reached", requests_admitted: 0,
      request_limit: 0, requests_remaining: 0 },
  ] })), platform, "Which clients are nearing their limit?", noScope);
  assert.match(result.reply, /Missing evidence — request admission evidence is unavailable; remaining allowance is unknown/);
  assert.match(result.reply, /Zero allowance — 0 of 0 cloud-chat requests admitted; 0 remaining; further requests blocked/);
});

test("release observations keep candidate and serving production source separate", async () => {
  const user = caller(snapshot({ deployments: [
    { release_observation_kind: "candidate", provider_state: "READY", source_commit_sha: "b".repeat(40), last_observed_at: "2026-10-03T07:12:00Z", evidence_state: "deployment_ready", runtime_verified: false, owner_flow_verified: false, client_flow_verified: false },
    { release_observation_kind: "canonical_production", provider_state: "READY", source_commit_sha: "a".repeat(40), last_observed_at: "2026-10-03T07:13:00Z", evidence_state: "stale", runtime_verified: false, owner_flow_verified: false, client_flow_verified: false },
  ] }));
  const result = await tryCoreOwnerCommand(user, platform, "Which version is deployed?", noScope);
  assert.match(result.reply, /Latest candidate — READY; bbbbbbbbbbbb; observed 2026-10-03T07:12:00Z/);
  assert.match(result.reply, /Canonical production — READY; aaaaaaaaaaaa; observed 2026-10-03T07:13:00Z; stale provider evidence/);
  assert.match(result.reply, /runtime and owner\/client flow verification not established/);
  assert.match(result.reply, /READY does not promote it to canonical production/);
  assert.equal(user.calls.length, 1);
  assert.equal(user.calls[0].name, "pandora_core_snapshot_v1");
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

test("new-client and unselected proposal requests hand off to governed UI without mutation", async () => {
  for (const [message, action] of [["Create a new enterprise client", "create_client"], ["Prepare a proposal for this prospect", "inspect"]]) {
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

const proposalRecords = (overrides = {}) => snapshot({
  pipeline: [{ id: client, company_name: "Harbor Logistics", stage: "proposal", estimated_value_micros: 987654321000000 }],
  plans: [{ id: second, code: "managed", name: "Managed", state: "active", currency: "PHP", monthly_fee_micros: 2500000000,
    entitlements: ["documents.read"], support_tier: "standard" }], ...overrides,
});

test("proposal preparation uses only the explicitly selected prospect and active plan terms", async () => {
  const user = caller(proposalRecords());
  const result = await tryCoreOwnerCommand(user, platform, "Prepare a proposal for Harbor Logistics using plan Managed", noScope);
  assert.match(result.reply, /Draft proposal — Harbor Logistics/);
  assert.match(result.reply, /Monthly fee: PHP 2500\.00/);
  assert.match(result.reply, /Recorded entitlements: documents\.read/);
  assert.match(result.reply, /provider connections require separate verification/);
  assert.match(result.reply, /Source: manually maintained/);
  assert.match(result.reply, /no proposal was sent and no agreement or subscription was created/);
  assert.doesNotMatch(result.reply, /987654321/);
  assert.equal(result.providerReadback.draftPrepared, true);
  assert.equal(result.providerReadback.prospectId, client);
  assert.equal(result.providerReadback.planId, second);
  assert.equal(result.providerReadback.actionExecuted, false);
  assert.equal(result.providerReadback.financialActionExecuted, false);
  assert.deepEqual(user.calls.map((call) => call.name), ["pandora_core_snapshot_v1"]);
});

test("proposal drafts never substitute prospect estimates for absent fees or fabricate terms", async () => {
  const data = proposalRecords();
  data.plans[0].monthly_fee_micros = null;
  const result = await tryCoreOwnerCommand(caller(data), platform, "Draft a proposal for Harbor Logistics using Managed", noScope);
  assert.match(result.reply, /Monthly fee: not recorded/);
  assert.match(result.reply, /Contract dates, setup fees, taxes, discounts and payment terms are not specified/);
  assert.doesNotMatch(result.reply, /987654321|PHP 0|12.month|30.day|99\.9%/);
});

test("ambiguous or missing commercial selections cannot produce a quoted proposal", async () => {
  const cases = [
    proposalRecords({ pipeline: [] }),
    proposalRecords({ pipeline: [...proposalRecords().pipeline, { ...proposalRecords().pipeline[0], id: entry }] }),
    proposalRecords({ plans: [...proposalRecords().plans, { ...proposalRecords().plans[0], id: entry }] }),
    proposalRecords({ plans: [{ ...proposalRecords().plans[0], state: "draft" }] }),
    proposalRecords({ pipeline: [{ ...proposalRecords().pipeline[0], stage: "won" }] }),
  ];
  for (const data of cases) {
    const result = await tryCoreOwnerCommand(caller(data), platform, "Prepare a proposal for Harbor Logistics using Managed", noScope);
    assert.match(result.reply, /one matching current Pipeline prospect and one matching active plan/);
    assert.doesNotMatch(result.reply, /Draft proposal —|2500\.00/);
    assert.equal(result.providerReadback.draftPrepared, undefined);
  }
  const unspecified = await tryCoreOwnerCommand(caller(proposalRecords()), platform, "Prepare a proposal for Harbor Logistics", noScope);
  assert.match(unspecified.reply, /Choose the prospect and an active plan by name/);
  assert.doesNotMatch(unspecified.reply, /2500\.00/);
});

test("proposal data stays behind owner commercial and exact conversation scope", async () => {
  for (const [organizationId, data, error] of [[client, proposalRecords(), null],
    [platform, proposalRecords({ operator: { role: "support", platform_organization_id: platform } }), null],
    [platform, null, { code: "42501", message: "private commercial data" }]]) {
    const result = await tryCoreOwnerCommand(caller(data, error), organizationId, "Prepare a proposal for Harbor Logistics using Managed", noScope);
    assert.doesNotMatch(result.reply, /2500\.00|documents\.read|private commercial data/);
    assert.equal(result.providerReadback.draftPrepared, undefined);
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

test("ordinary member mode uses the exact caller-scoped workspace RPC", async () => {
  const user = caller(memberSnapshot());
  const scope = await validateCoreChatScope(user, client, commonContext());
  assert.equal(scope.kind, "workspace");
  assert.equal(authorizeCoreChatActor("member", scope, null).actorRole, "member");
  assert.deepEqual(user.calls, [{ name: "pandora_enterprise_workspace_v1", parameters: { p_organization_id: client, p_section: "overview", p_entry_id: null } }]);
});

test("client members cannot relabel or select a different organization through UI metadata", async () => {
  const user = caller(memberSnapshot());
  await assert.rejects(validateCoreChatScope(user, client, commonContext(second)), { message: "CORE_SCOPE_MISMATCH" });
  await assert.rejects(validateCoreChatScope(user, client, { ...commonContext(), route: `/enterprise/workspace/${second}/overview` }), { message: "CORE_SCOPE_MISMATCH" });
  const mislabeled = commonContext();
  mislabeled.selectedObject.adapterKey = "plp_v1";
  await assert.rejects(validateCoreChatScope(user, client, mislabeled), { message: "CORE_SCOPE_MISMATCH" });
  assert.deepEqual(user.calls, []);
});

test("member mode validates returned organization, membership role and adapter", async () => {
  for (const change of [{ organization_id: second }, { workspace: { organization_id: second, adapter: "enterprise_core_v1" } }, { viewing_as: "pandora_administrator" }, { actor_role: "superuser" }, { entry_id: entry }]) {
    await assert.rejects(validateCoreChatScope(caller(memberSnapshot(change)), client, commonContext()), { message: "CORE_SCOPE_MISMATCH" });
  }
  const scope = await validateCoreChatScope(caller(memberSnapshot()), client, commonContext());
  assert.throws(() => authorizeCoreChatActor("viewer", scope, null), { message: "CORE_SCOPE_MISMATCH" });
  assert.throws(() => authorizeCoreChatActor("member", scope, second), { message: "CORE_SCOPE_MISMATCH" });
});

test("ordinary non-owner roles cannot reach legacy owner/admin execution without a verified common workspace", () => {
  for (const role of ["operator", "member", "viewer"]) {
    assert.throws(() => authorizeCoreChatActor(role, noScope, null), { message: "OWNER_ROLE_REQUIRED" });
    assert.throws(() => authorizeCoreChatActor(role, { ...noScope, kind: "client" }, null), { message: "OWNER_ROLE_REQUIRED" });
  }
});

test("common administrator mode requires a matching server-verified live entry envelope", async () => {
  const user = caller(memberSnapshot({ entry_id: entry, viewing_as: "pandora_administrator", actor_role: "admin" }));
  const scope = await validateCoreChatScope(user, client, commonContext(client, "administrator"));
  assert.equal(scope.kind, "workspace");
  assert.equal(authorizeCoreChatActor("admin", scope, null).actorRole, "admin");
  assert.equal(user.calls[0].parameters.p_entry_id, entry);
  const missing = commonContext(client, "administrator");
  delete missing.selectedObject.entryId;
  await assert.rejects(validateCoreChatScope(user, client, missing), { message: "CORE_SCOPE_MISMATCH" });
  await assert.rejects(validateCoreChatScope(caller(null, { code: "42501", message: "CLIENT_ENTRY_REQUIRED" }), client, commonContext(client, "administrator")), { message: "CORE_ACCESS_DENIED" });
});

test("specialized PLP administrator entry remains receipt-gated without becoming common member authority", async () => {
  const context = workspaceContext();
  context.selectedObject.workspaceMode = "administrator";
  context.selectedObject.adapterKey = "plp_v1";
  const user = caller(true);
  const scope = await validateCoreChatScope(user, client, context);
  assert.equal(scope.kind, "client");
  assert.equal(user.calls[0].name, "pandora_core_validate_entry_v1");
  assert.equal(authorizeCoreChatActor("admin", scope, null).actorRole, "admin");
  context.selectedObject.workspaceMode = "member";
  delete context.selectedObject.entryId;
  await assert.rejects(validateCoreChatScope(user, client, context), { message: "CORE_SCOPE_MISMATCH" });
});

test("ordinary member read/ask answers only the authenticated workspace projection", async () => {
  const user = caller(memberSnapshot());
  const scope = await validateCoreChatScope(user, client, commonContext());
  for (const [message, expected] of [["What work needs attention?", /Receive delivery/], ["Show documents", /Supplier agreement/], ["Who is in this workspace?", /Workspace member/], ["What happened recently?", /Delivery received/], ["Show connected sources", /Warehouse — stale/]]) {
    const result = await tryCoreOwnerCommand(user, client, message, scope);
    assert.equal(result.conversationLane, "enterprise_workspace");
    assert.equal(result.providerReadback.organizationId, client);
    assert.equal(result.providerReadback.source, "pandora_enterprise_workspace_v1");
    assert.equal(result.providerReadback.actionExecuted, false);
    assert.match(result.reply, expected);
  }
  assert.equal(user.calls.length, 1);
});

test("member owner/security/commercial commands never fall through to owner projections or mutations", async () => {
  const user = caller(memberSnapshot());
  const scope = await validateCoreChatScope(user, client, commonContext());
  for (const message of ["Which clients need attention?", "Give PLP another administrator", "How much did AI cost by client?", "Show all customers", "Create a new enterprise client", "Which provider should we stop using?", "Deploy this release"]) {
    const result = await tryCoreOwnerCommand(user, client, message, scope);
    assert.ok(result);
    assert.equal(result.handoff, null);
    assert.equal(result.providerReadback.actionExecuted, false);
    assert.match(result.reply, /unavailable|no verified execution path/);
    assert.doesNotMatch(result.reply, /BOK|PLP Boracay|USD|PHP/);
  }
  assert.equal(user.calls.length, 1);
});

test("member task commands direct to permitted UI and viewer role does not gain writes", async () => {
  const memberUser = caller(memberSnapshot());
  const memberScope = await validateCoreChatScope(memberUser, client, commonContext());
  const memberTurn = await tryCoreOwnerCommand(memberUser, client, "Create a task to call the supplier", memberScope);
  assert.match(memberTurn.reply, /Work to review and save the task/);
  assert.match(memberTurn.reply, /No task has changed/);
  const viewerUser = caller(memberSnapshot({ actor_role: "viewer", permissions: { can_manage_work: false } }));
  const viewerScope = await validateCoreChatScope(viewerUser, client, commonContext());
  assert.equal(authorizeCoreChatActor("viewer", viewerScope, null).actorRole, "viewer");
  const viewerTurn = await tryCoreOwnerCommand(viewerUser, client, "Update the task", viewerScope);
  assert.match(viewerTurn.reply, /can read work/);
  assert.equal(viewerTurn.providerReadback.actionExecuted, false);
});

test("administrator owner commands return to Pandora while common member mode never receives that control", async () => {
  const user = caller(memberSnapshot({ entry_id: entry, viewing_as: "pandora_administrator", actor_role: "admin" }));
  const scope = await validateCoreChatScope(user, client, commonContext(client, "administrator"));
  const result = await tryCoreOwnerCommand(user, client, "Show every customer's costs", scope);
  assert.equal(result.handoff.action, "return_owner");
  assert.equal(result.providerReadback.snapshotVerified, false);
  assert.equal(user.calls.length, 1);
});

test("expired operator entries stop immediately before legacy side effects and common mode is never admitted", async () => {
  const scope = await validateCoreChatScope(caller(true), client, workspaceContext());
  const revoked = caller(false);
  await assert.rejects(revalidateCoreExecutionScope(revoked, client, scope), { message: "CORE_ENTRY_REQUIRED" });
  assert.equal(revoked.calls[0].name, "pandora_core_validate_entry_v1");
  await assert.rejects(revalidateCoreExecutionScope(caller(), client, { ...noScope, kind: "workspace" }), { message: "CORE_WORKSPACE_ACTION_UNAVAILABLE" });
});

test("implicit PLP bootstrap results cannot be relabeled into another organization's conversation", () => {
  const secretData = { organization: { id: client }, today: { bookings: "client-only booking evidence" }, generatedAt: "2026-10-03T05:00:00Z" };
  assert.throws(() => bindPlpBusinessSnapshot({ selectedObject: { organizationId: second, workspaceSlug: "plp-boracay" } }, second, secretData), { message: "CORE_SCOPE_MISMATCH" });
  assert.throws(() => bindPlpBusinessSnapshot({}, client, { today: { bookings: "missing organization" } }), { message: "CORE_SCOPE_MISMATCH" });
  const result = bindPlpBusinessSnapshot({}, client, secretData);
  assert.equal(result.businessSnapshot.bookings, "client-only booking evidence");
});

test("chat validates entry before hydrators and routes Core before team or model dispatch", () => {
  const source = readFileSync("supabase/functions/pandora-intelligence-chat/index.ts", "utf8");
  const handle = source.slice(source.indexOf("async function handle("));
  const authorityGuard = handle.indexOf("authorizeCoreChatRequest(c.user,c.organizationId,c.role,i.enterpriseContext,i.projectId)");
  assert.ok(authorityGuard >= 0 && authorityGuard < handle.indexOf("hydratePlpBusinessContext(c.user,c.organizationId,i.enterpriseContext)"));
  assert.ok(authorityGuard < handle.indexOf("claimActivityExecution("));
  assert.match(handle, /if\(coreScope\.kind!=="workspace"\)\{i\.enterpriseContext=await hydratePlpBusinessContext/);
  assert.match(handle, /if\(!\["owner","admin"\]\.includes\(c\.role\)\)throw Error\("OWNER_ROLE_REQUIRED"\);await revalidateCoreExecutionScope/);
  assert.match(handle, /await revalidateCoreExecutionScope\(c\.user,c\.organizationId,coreScope\);dispatched=/);
  assert.match(handle, /const cand=list\[index\];await revalidateCoreExecutionScope/);
  assert.ok(handle.indexOf("tryCoreOwnerCommand(c.user,c.organizationId,controlState.message,coreScope)") < handle.indexOf("tryTeamAdminChat(c,"));
  assert.ok(handle.indexOf("tryCoreOwnerCommand(c.user,c.organizationId,controlState.message,coreScope)") < handle.indexOf("universalDispatch(c.user,"));
  assert.match(source, /const tid=await thread\(c\.admin,c\.organizationId,c\.userId,i\.threadId,i\.projectId,i\.message\)/);
  assert.match(source, /CORE_ENTRY_REQUIRED:\[403,/);
  const module = readFileSync("supabase/functions/pandora-intelligence-chat/core-owner-commands.ts", "utf8");
  assert.doesNotMatch(module, /fetch\(|\.from\(|service_role|SUPABASE_SERVICE_ROLE_KEY|\.rpc\("pandora_core_operate/);
});
