const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { webcrypto } = require("node:crypto");
const { runInNewContext } = require("node:vm");
const test = require("node:test");
const ts = require("typescript");

const organizationId = "076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const actorId = "a0d6f184-3039-4735-8d11-63ce403636e2";
const targetId = "f1200000-0000-4000-8000-000000000002";
const otherId = "f1200000-0000-4000-8000-000000000003";
const source = readFileSync("supabase/functions/pandora-user-admin/index.ts", "utf8");
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;

function harness(options = {}) {
  const events = [];
  const users = options.users ? [...options.users] : [];
  const memberships = options.memberships ? [...options.memberships] : [];
  const logs = [];
  let authCalls = 0;
  let serviceCreated = false;
  let handler;
  const authority = { organization_id: organizationId, role: options.role || "owner", authority: options.authority || "tenant_membership" };
  const userClient = {
    auth: { getUser: async () => { events.push("auth.getUser"); return { data: { user: options.signedOut ? null : { id: actorId, is_anonymous: options.anonymous === true, user_metadata: { role: "owner", operator: true } } }, error: null }; } },
    rpc: async (name, parameters) => {
      assert.equal(name, "pandora_core_authorize_user_admin_v1");
      events.push({ operation: "authorize", parameters });
      const next = options.authorizations?.[authCalls++];
      if (next instanceof Error) throw next;
      if (next) return next;
      if (options.authError) return { data: null, error: options.authError };
      return { data: options.authorityData || authority, error: null };
    },
    from: () => { throw new Error("Membership rows must not bypass the unified authority RPC"); },
  };
  const adminClient = {
    auth: { admin: {
      listUsers: async () => { events.push("auth.listUsers"); return { data: { users }, error: null }; },
      inviteUserByEmail: async (email, inviteOptions) => {
        events.push({ operation: "auth.invite", email, role: inviteOptions.data.invited_role });
        const user = { id: targetId, email, email_confirmed_at: null };
        users.push(user);
        return { data: { user }, error: null };
      },
      deleteUser: async () => { events.push("auth.deleteUser"); throw new Error("Auth cleanup must not delete shared identities"); },
    } },
    rpc: async (name, parameters) => {
      events.push({ operation: name, parameters });
      if (name === "consume_runtime_rate_limit") return { data: { allowed: true }, error: null };
      if (name === "record_audit_event") return options.auditFailure === parameters.p_event_type
        ? { data: null, error: { code: "XX000" } } : { data: 42, error: null };
      if (name === "pandora_admin_add_organization_member") {
        if (options.membershipThrows) throw options.membershipThrows;
        if (options.membershipError) return { data: null, error: options.membershipError };
        if (Object.hasOwn(options, "membershipResult")) return { data: options.membershipResult, error: null };
        const user = users.find((candidate) => candidate.id === parameters.p_target_user_id);
        const existing = memberships.find((membership) => membership.user_id === user?.id);
        const status = user?.email_confirmed_at ? "active" : "invited";
        if (!existing) memberships.push({ user_id: user.id, role: parameters.p_role, status });
        return { data: { userId: user?.id, organizationId: parameters.p_organization_id, role: parameters.p_role, status, created: !existing, restored: false }, error: null };
      }
      if (name === "pandora_admin_update_organization_member") return { data: Object.hasOwn(options, "membershipResult") ? options.membershipResult : { organizationId: parameters.p_organization_id, userId: parameters.p_target_user_id, status: parameters.p_status || "active", role: parameters.p_role || "member" }, error: null };
      throw new Error(`Unexpected RPC ${name}`);
    },
    from: (table) => {
      assert.equal(table, "memberships");
      const filters = {};
      const query = { select: () => query, eq: (key, value) => { filters[key] = value; return query; }, order: () => query,
        then: (resolve, reject) => { events.push({ operation: "memberships.select", filters }); return Promise.resolve({ data: memberships, error: null }).then(resolve, reject); } };
      return query;
    },
  };
  const env = { SUPABASE_URL: "https://fixture.example", SUPABASE_ANON_KEY: "fixture-anon", SUPABASE_SERVICE_ROLE_KEY: "fixture-service" };
  runInNewContext(compiled, {
    exports: {},
    require: (module) => module.includes("supabase-js") ? { createClient: (_url, key, configuration) => {
      if (key === env.SUPABASE_ANON_KEY) {
        assert.equal(configuration.global.headers.Authorization, "Bearer fixture-session");
        return userClient;
      }
      assert.equal(key, env.SUPABASE_SERVICE_ROLE_KEY);
      serviceCreated = true;
      events.push("service.created");
      return adminClient;
    } } : {},
    Deno: { env: { get: (key) => env[key] }, serve: (callback) => { handler = callback; } },
    Request, Response, URL, TextEncoder, crypto: webcrypto,
    console: { error: (value) => logs.push(value) },
  });
  const request = async (method = "POST", body = { email: "new-user@example.test", role: "member" }, headers = {}) => {
    const result = await handler(new Request(`https://fixture.example/functions/v1/pandora-user-admin/${method === "GET" ? "members" : method === "PATCH" ? "member" : "invite"}`, {
      method, headers: { authorization: "Bearer fixture-session", "x-organization-id": organizationId, "content-type": "application/json", ...headers },
      ...(method === "GET" ? {} : { body: JSON.stringify(body) }),
    }));
    return { status: result.status, body: await result.json() };
  };
  return { request, events, logs, users, memberships, get serviceCreated() { return serviceCreated; } };
}

test("ordinary client administrators retain actual target-role authority through the unified RPC", async () => {
  const h = harness({ role: "admin", authority: "tenant_membership" });
  const result = await h.request();
  assert.equal(result.status, 201);
  assert.equal(result.body.membership.role, "member");
  assert.equal(result.body.membership.status, "invited");
  assert.equal(result.body.inviteSent, true);
  const checks = h.events.filter((event) => event.operation === "authorize");
  assert.equal(checks.length, 3);
  assert.ok(checks.every((event) => event.parameters.p_organization_id === organizationId && event.parameters.p_write === true));
});

test("internal owner membership and editable metadata cannot bypass revoked operator authority", async () => {
  const h = harness({ authError: { code: "42501", message: "ACCESS_DENIED" } });
  const result = await h.request();
  assert.equal(result.status, 403);
  assert.equal(result.body.code, "ADMIN_ROLE_REQUIRED");
  assert.equal(h.serviceCreated, false);
  assert.equal(h.events.some((event) => event.operation === "auth.invite"), false);
});

test("internal write requiring live MFA stops before any Auth side effect", async () => {
  const h = harness({ authError: { code: "42501", message: "STEP_UP_REQUIRED" } });
  const result = await h.request();
  assert.equal(result.status, 403);
  assert.equal(result.body.code, "STEP_UP_REQUIRED");
  assert.equal(h.serviceCreated, false);
});

test("wrong organization, invalid role or unrecognized authority envelopes fail closed", async () => {
  for (const change of [{ organization_id: otherId }, { role: "member" }, { authority: "user_metadata" }, { organization_id: null }]) {
    const h = harness({ authorityData: { organization_id: organizationId, role: "owner", authority: "explicit_operator_grant", ...change } });
    assert.equal((await h.request()).status, 403);
    assert.equal(h.serviceCreated, false);
  }
});

test("caller RPC transport and provider errors are redacted without falling back to membership", async () => {
  for (const options of [{ authorizations: [new Error("Bearer confidential-transport-detail")] }, { authError: { code: "XX000", message: "postgres://internal:credential@private" } }]) {
    const h = harness(options);
    const result = await h.request();
    assert.equal(result.status, 503);
    assert.equal(result.body.code, "AUTHORITY_UNAVAILABLE");
    assert.equal(h.serviceCreated, false);
    assert.doesNotMatch(JSON.stringify({ result, logs: h.logs }), /confidential|postgres:|credential@/);
  }
});

test("ordinary admins cannot invite another owner/admin", async () => {
  const h = harness({ role: "admin" });
  const result = await h.request("POST", { email: "new-user@example.test", role: "owner" });
  assert.equal(result.status, 403);
  assert.equal(result.body.code, "ROLE_GRANT_NOT_ALLOWED");
  assert.equal(h.events.includes("auth.listUsers"), false);
  assert.equal(h.events.some((event) => event.operation === "auth.invite"), false);
});

test("revocation or downgrade during directory lookup stops the external invitation", async () => {
  const owner = { data: { organization_id: organizationId, role: "owner", authority: "explicit_operator_grant" }, error: null };
  for (const next of [{ data: null, error: { code: "42501", message: "ACCESS_DENIED" } }, { data: { organization_id: organizationId, role: "admin", authority: "explicit_operator_grant" }, error: null }]) {
    const h = harness({ authorizations: [owner, next] });
    const result = await h.request("POST", { email: "new-user@example.test", role: "owner" });
    assert.equal(result.status, 403);
    assert.ok(h.events.includes("auth.listUsers"));
    assert.equal(h.events.some((event) => event.operation === "auth.invite"), false);
  }
});

test("authorized invitation has durable existing audit evidence before and after Auth acceptance", async () => {
  const h = harness();
  assert.equal((await h.request()).status, 201);
  const requested = h.events.findIndex((event) => event.operation === "record_audit_event" && event.parameters.p_event_type === "core.user_invitation.requested");
  const invited = h.events.findIndex((event) => event.operation === "auth.invite");
  const accepted = h.events.findIndex((event) => event.operation === "record_audit_event" && event.parameters.p_event_type === "core.user_invitation.accepted_by_auth");
  const membership = h.events.findIndex((event) => event.operation === "pandora_admin_add_organization_member");
  assert.ok(requested >= 0 && requested < invited && invited < accepted && accepted < membership);
  const evidence = h.events[requested].parameters;
  assert.equal(evidence.p_organization_id, organizationId);
  assert.equal(evidence.p_actor_user_id, actorId);
  assert.match(evidence.p_payload_redacted.target_email_sha256, /^[0-9a-f]{64}$/);
  assert.doesNotMatch(JSON.stringify(evidence), /new-user@example/);
  assert.equal(h.events[accepted].parameters.p_payload_redacted.delivery_verification, "not_confirmed");
});

test("an audit failure before Auth blocks sending; an after-acceptance failure preserves the account", async () => {
  const before = harness({ auditFailure: "core.user_invitation.requested" });
  assert.equal((await before.request()).body.code, "INVITATION_AUDIT_UNAVAILABLE");
  assert.equal(before.events.some((event) => event.operation === "auth.invite"), false);
  const after = harness({ auditFailure: "core.user_invitation.accepted_by_auth" });
  const result = await after.request();
  assert.equal(result.status, 409);
  assert.equal(result.body.code, "INVITATION_ACCEPTED_EVIDENCE_PENDING");
  assert.equal(after.users.length, 1);
  assert.equal(after.events.includes("auth.deleteUser"), false);
});

test("membership failure preserves the shared identity, audits pending access, and retry does not resend", async () => {
  const options = { membershipError: { message: "active owner or administrator membership required" } };
  const h = harness(options);
  const first = await h.request();
  assert.equal(first.status, 409);
  assert.equal(first.body.code, "INVITATION_SENT_ACCESS_PENDING");
  assert.equal(h.users.length, 1);
  assert.equal(h.events.includes("auth.deleteUser"), false);
  const pending = h.events.find((event) => event.operation === "record_audit_event" && event.parameters.p_event_type === "core.user_invitation.access_pending");
  assert.equal(pending.parameters.p_payload_redacted.next_action, "retry_existing_account");
  delete options.membershipError;
  const retry = await h.request();
  assert.equal(retry.status, 201);
  assert.equal(retry.body.existingAccount, true);
  assert.equal(retry.body.inviteSent, false);
  assert.equal(retry.body.membership.status, "invited");
  assert.equal(h.events.filter((event) => event.operation === "auth.invite").length, 1);
});

test("membership transport ambiguity after Auth acceptance remains auditable and resume-safe", async () => {
  const options = { membershipThrows: new Error("Bearer confidential-membership-transport") };
  const h = harness(options);
  const first = await h.request();
  assert.equal(first.status, 409);
  assert.equal(first.body.code, "INVITATION_SENT_ACCESS_PENDING");
  assert.match(first.body.plainMessage, /Auth accepted/);
  const pending = h.events.find((event) => event.operation === "record_audit_event" && event.parameters.p_event_type === "core.user_invitation.access_pending");
  assert.equal(pending.parameters.p_payload_redacted.reason_code, "MEMBERSHIP_RESULT_UNCONFIRMED");
  assert.doesNotMatch(JSON.stringify({ first, events: h.events, logs: h.logs }), /confidential-membership/);
  delete options.membershipThrows;
  assert.equal((await h.request()).status, 201);
  assert.equal(h.events.filter((event) => event.operation === "auth.invite").length, 1);
});

test("MFA or authority loss after Auth acceptance stops the broker with recoverable pending access", async () => {
  const permitted = { data: { organization_id: organizationId, role: "owner", authority: "explicit_operator_grant" }, error: null };
  const h = harness({ authorizations: [permitted, permitted, { data: null, error: { code: "42501", message: "STEP_UP_REQUIRED" } }] });
  const result = await h.request();
  assert.equal(result.status, 409);
  assert.equal(result.body.code, "INVITATION_SENT_ACCESS_PENDING");
  assert.equal(h.events.some((event) => event.operation === "pandora_admin_add_organization_member"), false);
  assert.equal(h.users.length, 1);
  const pending = h.events.find((event) => event.operation === "record_audit_event" && event.parameters.p_event_type === "core.user_invitation.access_pending");
  assert.equal(pending.parameters.p_payload_redacted.reason_code, "STEP_UP_REQUIRED");
});

test("success requires exact user, organization, role and membership-state readback", async () => {
  const base = { organizationId, userId: targetId, role: "member", status: "active", created: true };
  for (const membershipResult of [null, { ...base, organizationId: otherId }, { ...base, userId: otherId },
    { ...base, role: "owner" }, { ...base, status: "unknown" }]) {
    const h = harness({ users: [{ id: targetId, email: "new-user@example.test", email_confirmed_at: "2026-10-03T05:00:00Z" }], membershipResult });
    const result = await h.request();
    assert.equal(result.status, 503);
    assert.equal(result.body.code, "MEMBERSHIP_RESULT_UNCONFIRMED");
    assert.equal(result.body.membership, undefined);
    assert.equal(h.events.some((event) => event.operation === "auth.invite"), false);
  }
  const update = harness({ membershipResult: { ...base, status: "active" } });
  const result = await update.request("PATCH", { userId: targetId, status: "suspended" });
  assert.equal(result.status, 503);
  assert.equal(result.body.code, "MEMBERSHIP_RESULT_UNCONFIRMED");
});

test("explicit operators can inspect exactly authorized client users without granting themselves membership", async () => {
  const h = harness({ authority: "explicit_operator_grant", users: [
    { id: targetId, email: "client-user@example.test" }, { id: otherId, email: "unrelated@example.test" },
  ], memberships: [{ user_id: targetId, role: "owner", status: "active" }] });
  const result = await h.request("GET");
  assert.equal(result.status, 200);
  assert.equal(result.body.members.length, 1);
  assert.equal(result.body.members[0].email, "client-user@example.test");
  assert.doesNotMatch(JSON.stringify(result.body), /unrelated@example/);
  const query = h.events.find((event) => event.operation === "memberships.select");
  assert.equal(query.filters.organization_id, organizationId);
  assert.equal(h.events.find((event) => event.operation === "authorize").parameters.p_write, false);
});

test("member updates retain the authenticated actor and exact target organization", async () => {
  const h = harness({ role: "admin" });
  const result = await h.request("PATCH", { userId: targetId, role: "member", actorUserId: otherId, organizationId: otherId });
  assert.equal(result.status, 200);
  const operation = h.events.find((event) => event.operation === "pandora_admin_update_organization_member");
  assert.equal(operation.parameters.p_actor_user_id, actorId);
  assert.equal(operation.parameters.p_organization_id, organizationId);
  assert.equal(operation.parameters.p_target_user_id, targetId);
});

test("signed-out and anonymous callers cannot use the administrator service client", async () => {
  for (const options of [{ signedOut: true }, { anonymous: true }]) {
    const h = harness(options);
    assert.equal((await h.request()).status, 401);
    assert.equal(h.serviceCreated, false);
    assert.equal(h.events.some((event) => event.operation === "authorize"), false);
  }
});
