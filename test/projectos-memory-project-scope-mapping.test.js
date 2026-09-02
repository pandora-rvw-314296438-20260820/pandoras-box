
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  canonicalMemoryProjectKey,
  memoryProjectKeyForProjectOsIntake,
  sourceAuthorityPolicy,
} = require("../dist/runtime/source-authority.js");

test("ProjectOS control identity maps only to canonical Memory project scope", () => {
  const controlProjectKey = sourceAuthorityPolicy.canonical.vercel_project_name;
  assert.equal(controlProjectKey, "mcpmaster");
  assert.equal(canonicalMemoryProjectKey(), "mcpmaster-pandoras-box");
  assert.equal(memoryProjectKeyForProjectOsIntake(controlProjectKey), "mcpmaster-pandoras-box");
});

test("explicit legitimate Memory scopes remain exact", () => {
  assert.equal(memoryProjectKeyForProjectOsIntake("mcpmaster-pandoras-box"), "mcpmaster-pandoras-box");
  assert.equal(memoryProjectKeyForProjectOsIntake("another-legitimate-scope"), "another-legitimate-scope");
});

test("unscoped or invalid ProjectOS identity fails closed before Memory hydration", () => {
  assert.throws(() => memoryProjectKeyForProjectOsIntake(undefined), /project key is required/i);
  assert.throws(() => memoryProjectKeyForProjectOsIntake("INVALID KEY"), /project key is invalid/i);
});
