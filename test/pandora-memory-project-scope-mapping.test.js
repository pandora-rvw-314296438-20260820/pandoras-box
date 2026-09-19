
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  canonicalMemoryProjectKey,
  memoryProjectKeyForPandoraIntake,
  sourceAuthorityPolicy,
} = require("../dist/runtime/source-authority.js");

test("Pandora control identity maps only to canonical Memory project scope", () => {
  const controlProjectKey = sourceAuthorityPolicy.canonical.vercel_project_name;
  assert.equal(controlProjectKey, "mcpmaster");
  assert.equal(canonicalMemoryProjectKey(), "mcpmaster-pandoras-box");
  assert.equal(memoryProjectKeyForPandoraIntake(controlProjectKey), "mcpmaster-pandoras-box");

  const repositoryProjectKey = sourceAuthorityPolicy.canonical.source_repository.split("/").at(-1);
  assert.equal(repositoryProjectKey, "pandoras-box");
  assert.equal(memoryProjectKeyForPandoraIntake(repositoryProjectKey), "mcpmaster-pandoras-box");
});

test("explicit legitimate Memory scopes remain exact", () => {
  assert.equal(memoryProjectKeyForPandoraIntake("mcpmaster-pandoras-box"), "mcpmaster-pandoras-box");
  assert.equal(memoryProjectKeyForPandoraIntake("another-legitimate-scope"), "another-legitimate-scope");
});

test("unscoped or invalid Pandora identity fails closed before Memory hydration", () => {
  assert.throws(() => memoryProjectKeyForPandoraIntake(undefined), /project key is required/i);
  assert.throws(() => memoryProjectKeyForPandoraIntake("INVALID KEY"), /project key is invalid/i);
});
