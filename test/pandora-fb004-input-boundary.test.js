"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const vm = require("node:vm");
const { spawnSync } = require("node:child_process");
const auditor = path.resolve(__dirname, "../scripts/audit-fb004-identity.cjs");
const inputError = "FB004_INPUT_ERROR: supply one bounded, secret-free JSON snapshot file\n";
const fifoSupported = process.platform !== "win32" && Number.isInteger(fs.constants.O_NONBLOCK);

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fb004-input-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function cli(args) {
  return spawnSync(process.execPath, [auditor, ...args], {
    encoding: "utf8", timeout: 5000, killSignal: "SIGKILL", maxBuffer: 65536,
  });
}
function refused(result) {
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 2);
  assert.equal(result.stdout, "");
  assert.equal(result.stderr, inputError);
}
function consistent() {
  const repository = "pandora-rvw-314296438-20260820/pandoras-box";
  const expected = {
    organizationId: "synthetic-org", primaryProjectId: "synthetic-primary",
    trackingTenantId: "synthetic-tenant", campaignSlug: "synthetic-campaign",
    memoryProjectId: "synthetic-memory", memoryProjectKey: "synthetic-key",
    principalKey: "synthetic-principal", environment: "production", namespace: "real_life",
    repository, readRecordType: "integration_state", proposalRecordType: "outcome",
  };
  const observedAt = new Date().toISOString();
  return {
    schemaVersion: 1, expected,
    primary: {
      observedAt,
      projects: [{ id: expected.primaryProjectId, organization_id: expected.organizationId, repository, status: "active" }],
      registries: [{ project_id: expected.primaryProjectId, organization_id: expected.organizationId, canonical_repository: repository }],
      tenants: [{ id: expected.trackingTenantId, organization_id: expected.organizationId, project_id: expected.primaryProjectId, status: "active" }],
      campaigns: [{ slug: expected.campaignSlug, tenant_id: expected.trackingTenantId, provider: "meta", provider_campaign_bound: true }],
      metaConnections: [{ organization_id: expected.organizationId, credential_reference_present: true }],
    },
    memory: {
      observedAt,
      projects: [{ id: expected.memoryProjectId, project_key: expected.memoryProjectKey, memory_namespace: expected.namespace,
        github_owner: repository.split("/")[0], github_repository: "pandoras-box", lifecycle_status: "active" }],
      principals: [{ principal_key: expected.principalKey, is_active: true, environment: expected.environment,
        allowed_namespaces: [expected.namespace], scopes: ["memory:read", "memory:write"] }],
      grants: [{ project_id: expected.memoryProjectId, principal_key: expected.principalKey, environment: expected.environment,
        is_active: true, revoked: false, can_read: true, can_propose: true, can_approve: false,
        allowed_record_types: ["integration_state", "outcome"] }],
    },
  };
}
function assertReport(result, raw, status) {
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, status, result.stderr);
  assert.equal(result.stderr, "");
  const report = JSON.parse(result.stdout);
  assert.equal(report.inputSha256, crypto.createHash("sha256").update(raw).digest("hex"));
  assert.equal(report.authorizationEffect, "none");
  assert.equal(report.productionVerified, false);
  assert.equal(report.snapshotOnly, true);
}
function makeFifo(target) {
  const result = spawnSync("mkfifo", [target], { encoding: "utf8", timeout: 5000, killSignal: "SIGKILL" });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.lstatSync(target).isFIFO(), true);
}

test("FB004 input: no argument and extra arguments are rejected safely", () => {
  refused(cli([]));
  refused(cli(["synthetic-private-name", "synthetic-private-extra"]));
});
test("FB004 input: missing file is rejected without disclosing its path", (t) => {
  refused(cli([path.join(fixture(t), "synthetic-private-name")]));
});
for (const [name, raw] of [["empty file", ""], ["invalid JSON", "synthetic-private-payload"]]) {
  test(`FB004 input: ${name} is rejected without echoing input`, (t) => {
    const target = path.join(fixture(t), "synthetic-private-name.json");
    fs.writeFileSync(target, raw);
    refused(cli([target]));
  });
}
test("FB004 input: directory is rejected safely", (t) => {
  refused(cli([fixture(t)]));
});
test("FB004 input: regular consistent snapshot retains exit code and exact content hash", (t) => {
  const target = path.join(fixture(t), "snapshot.json");
  const raw = JSON.stringify(consistent());
  fs.writeFileSync(target, raw);
  assertReport(cli([target]), raw, 0);
});
test("FB004 input: ordinary blocked snapshot retains exit code and hash", (t) => {
  const target = path.join(fixture(t), "snapshot.json");
  const raw = "{}";
  fs.writeFileSync(target, raw);
  assertReport(cli([target]), raw, 1);
});
test("FB004 input: exact one-MiB regular file remains admitted", (t) => {
  const target = path.join(fixture(t), "snapshot.json");
  const raw = "{}" + " ".repeat(1048574);
  fs.writeFileSync(target, raw);
  assertReport(cli([target]), raw, 1);
});
test("FB004 input: oversized regular file is rejected safely", (t) => {
  const target = path.join(fixture(t), "synthetic-private-name.json");
  fs.writeFileSync(target, " ".repeat(1048577));
  refused(cli([target]));
});
test("FB004 input: symlink to regular file retains existing behavior", (t) => {
  const dir = fixture(t);
  const target = path.join(dir, "snapshot.json");
  const link = path.join(dir, "link.json");
  const raw = "{}";
  fs.writeFileSync(target, raw);
  try { fs.symlinkSync(target, link, "file"); }
  catch (error) {
    if (process.platform === "win32" && ["EPERM", "EACCES"].includes(error.code)) {
      t.skip("Windows test runner cannot create symlinks"); return;
    }
    throw error;
  }
  assertReport(cli([link]), raw, 1);
});
test("FB004 input: unconnected FIFO is rejected instead of blocking at open", { skip: !fifoSupported }, (t) => {
  const target = path.join(fixture(t), "synthetic-private-fifo");
  makeFifo(target);
  refused(cli([target]));
});
test("FB004 input: symlink to an unconnected FIFO is rejected without blocking", { skip: !fifoSupported }, (t) => {
  const dir = fixture(t);
  const target = path.join(dir, "synthetic-private-fifo");
  const link = path.join(dir, "synthetic-private-link");
  makeFifo(target);
  fs.symlinkSync(target, link);
  refused(cli([link]));
});

// Execute the unchanged CLI entry point with an injected filesystem only. These
// tests cover descriptor lifetime and a missing optional POSIX flag; they are
// not evidence of native Windows named-pipe or filesystem behavior.
function instrumented(overrides = {}) {
  const calls = [];
  const raw = "{}";
  const fakeFs = {
    constants: { O_RDONLY: 0, O_NONBLOCK: 2048 },
    openSync(target, flags) { calls.push(["open", target, flags]); return 7; },
    fstatSync(fd) { calls.push(["stat", fd]); return { isFile: () => true, size: raw.length }; },
    readFileSync(fd, encoding) { calls.push(["read", fd, encoding]); return raw; },
    closeSync(fd) { calls.push(["close", fd]); },
    ...overrides,
  };
  const moduleObject = { exports: {} };
  const processObject = { argv: [process.execPath, auditor, "synthetic-private-input"] };
  const output = { stdout: "", stderr: "" };
  function injectedRequire(name) { return name === "node:fs" ? fakeFs : require(name); }
  injectedRequire.main = moduleObject;
  vm.runInNewContext(fs.readFileSync(auditor, "utf8"), {
    require: injectedRequire, module: moduleObject, process: processObject, Buffer,
    console: {
      log(value) { output.stdout += `${value}\n`; },
      error(value) { output.stderr += `${value}\n`; },
    },
  }, { filename: auditor, timeout: 1000 });
  return { calls, ...output, status: processObject.exitCode, signal: null };
}
test("FB004 input: verifies and reads the same nonblocking read-only descriptor, then closes once", () => {
  const result = instrumented();
  assertReport(result, "{}", 1);
  assert.deepEqual(result.calls, [
    ["open", "synthetic-private-input", 2048], ["stat", 7], ["read", 7, "utf8"], ["close", 7],
  ]);
});
test("FB004 input: missing optional O_NONBLOCK preserves ordinary read-only flag", () => {
  const result = instrumented({ constants: { O_RDONLY: 0 } });
  assertReport(result, "{}", 1);
  assert.equal(result.calls[0][2], 0);
  assert.deepEqual(result.calls.at(-1), ["close", 7]);
});
test("FB004 input: non-regular opened descriptor is closed without any read", () => {
  const result = instrumented({ fstatSync: () => ({ isFile: () => false, size: 0 }) });
  refused(result);
  assert.deepEqual(result.calls, [["open", "synthetic-private-input", 2048], ["close", 7]]);
});
for (const operation of ["fstatSync", "readFileSync"]) {
  test(`FB004 input: ${operation} failure closes the opened descriptor and redacts diagnostics`, () => {
    const result = instrumented({ [operation]() { throw new Error("synthetic-private-error"); } });
    refused(result);
    assert.deepEqual(result.calls.at(-1), ["close", 7]);
    assert.equal(result.calls.filter(([name]) => name === "close").length, 1);
  });
}
