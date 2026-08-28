"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const T = require("../src");
const base = { project_id: "project_alpha", environment: "preview" };
const p = (tool, arguments_, version = 1) => ({ tool, version, arguments: arguments_, reason: "R-14" });
const code = (fn, expected) => assert.throws(fn, (e) => e?.code === expected);

test("registry is explicit, versioned, complete and shell-free", () => {
  const tools = T.listToolDefinitions();
  assert.ok(tools.length >= 20);
  for (const x of tools) {
    assert.equal(x.key, `${x.name}@1`); assert.equal(x.version, 1);
    for (const field of ["description", "inputSchema", "outputSchema", "capabilityRequirements", "allowedEnvironments", "defaultRisk", "idempotency", "approval", "timeoutMs", "maxPayloadBytes", "sideEffect", "retry", "executor"]) assert.ok(x[field] !== undefined, `${x.name}.${field}`);
    assert.match(x.executor, /Executor$/);
  }
  for (const name of ["shell", "exec", "github.write-repository-api"]) assert.equal(T.getToolDefinition(name), undefined);
});

test("unknown tools, versions, fields and malformed reads fail closed", () => {
  code(() => T.validateToolProposal(p("not_a_tool", base)), "UNKNOWN_TOOL");
  code(() => T.validateToolProposal(p("read_file", { ...base, path: "src/a.js" }, 2)), "UNKNOWN_TOOL");
  code(() => T.validateToolProposal({ ...p("read_file", { ...base, path: "src/a.js" }), injected: true }), "UNKNOWN_FIELD");
  code(() => T.validateToolProposal(p("read_file", { ...base, path: "src/a.js", extra: 1 })), "UNKNOWN_FIELD");
  code(() => T.validateToolProposal(p("read_file", { environment: "preview", path: "src/a.js" })), "FIELD_REQUIRED");
  code(() => T.validateToolProposal(p("query_schema", { ...base, query: { operation: "delete", table: "users", columns: ["id"] } })), "ENUM_INVALID");
});

test("payload, path, secret and symlink boundaries are deterministic", () => {
  code(() => T.validateToolProposal(p("read_file", { ...base, path: `src/${"x".repeat(17 * 1024)}` })), "PAYLOAD_TOO_LARGE");
  for (const value of ["../x", "src/../x", "src/%2e%2e/x", "src/%252e%252e/x", "C:\\Windows\\x", "src%5c..%5cx", "%2fetc/passwd", "src/%00x", ".git/config", ".env", "src/.env.prod", "a/.ssh/id_rsa", "src/／etc"]) assert.throws(() => T.normalizeProjectPath(value), value);
  assert.equal(T.validateProjectPath("src/pages/a.tsx", ["src"]), "src/pages/a.tsx");
  code(() => T.validateProjectPath("tests/a.test.ts", ["src"]), "PATH_OUTSIDE_SCOPE");
  const root = path.resolve("/tmp/pandora/project-alpha");
  assert.equal(T.assertResolvedPathInsideWorkspace(root, path.join(root, "src/a.js")), true);
  code(() => T.assertResolvedPathInsideWorkspace(root, "/etc/passwd"), "SYMLINK_ESCAPE");
});

test("domain normalization is canonical and restrictive", () => {
  assert.equal(T.normalizeDomain("EXAMPLE.COM."), "example.com");
  assert.equal(T.normalizeDomain("münich.example"), "xn--mnich-kva.example");
  for (const value of ["https://example.com", "example.com:443", "*.example.com", "localhost", "u@example.com", "example.com/x"]) code(() => T.normalizeDomain(value), "DOMAIN_INVALID");
});

test("action hash binds exact action and immutable scope", () => {
  const x = { tool: "write_file", version: 1, arguments: { ...base, path: "src/a.js" }, organization_id: "org_alpha", project_id: "project_alpha", environment: "preview", target_resource: "workspace", project_version: "v18", policy_version: T.POLICY_VERSION };
  assert.equal(T.computeActionHash(x), T.computeActionHash({ ...x, arguments: { ...x.arguments } }));
  assert.notEqual(T.computeActionHash(x), T.computeActionHash({ ...x, project_version: "v19" }));
  assert.notEqual(T.computeActionHash(x), T.computeActionHash({ ...x, arguments: { ...x.arguments, path: "src/b.js" } }));
});
