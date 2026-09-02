
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  memoryProjectKeyForControlProject,
} = require("../dist/runtime/memory-project-scope.js");

test("ProjectOS control workspace maps to canonical Memory project only for hydration", () => {
  assert.equal(memoryProjectKeyForControlProject("mcpmaster"), "mcpmaster-pandoras-box");
});

test("explicit Memory scope stays exact and missing scope stays unscoped", () => {
  assert.equal(memoryProjectKeyForControlProject("mcpmaster-pandoras-box"), "mcpmaster-pandoras-box");
  assert.equal(memoryProjectKeyForControlProject("another-legitimate-scope"), "another-legitimate-scope");
  assert.equal(memoryProjectKeyForControlProject(undefined), undefined);
});

test("Memory project mapping fails closed when source authority identity is invalid", () => {
  assert.throws(
    () => memoryProjectKeyForControlProject("mcpmaster", {
      mode: "fail_closed",
      project_key: "INVALID KEY",
      canonical: { vercel_project_name: "mcpmaster" },
    }),
    /source authority project_key is missing or invalid/,
  );
});
