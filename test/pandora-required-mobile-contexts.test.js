"use strict";
const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const workflow = fs.readFileSync(".github/workflows/pandora-mobile-integration.yml", "utf8");

test("required Flutter contexts always report a real result", () => {
  assert.match(workflow, /verify_android_heavy:\n[\s\S]*?if: \$\{\{ needs\.mobile-impact\.outputs\.mobile == 'true' \}\}/);
  assert.match(workflow, /verify_ios_heavy:\n[\s\S]*?if: \$\{\{ needs\.mobile-impact\.outputs\.mobile == 'true' \}\}/);
  assert.match(workflow, /\n  verify:\n[\s\S]*?if: \$\{\{ always\(\) \}\}[\s\S]*?name: Exact source \/ Flutter \/ Android/);
  assert.match(workflow, /\n  verify-ios:\n[\s\S]*?if: \$\{\{ always\(\) \}\}[\s\S]*?name: Exact source \/ Flutter \/ iOS/);
  assert.match(workflow, /needs\.verify_android_heavy\.result/);
  assert.match(workflow, /needs\.verify_ios_heavy\.result/);
});

test("required wrappers bind exact source and fail closed on heavy validation", () => {
  const androidName = (workflow.match(/name: Exact source \/ Flutter \/ Android/g) || []).length;
  const iosName = (workflow.match(/name: Exact source \/ Flutter \/ iOS/g) || []).length;
  assert.equal(androidName, 1);
  assert.equal(iosName, 1);
  assert.match(workflow, /test "\$\(git rev-parse HEAD\)" = "\$SOURCE_SHA"/);
  assert.match(workflow, /test "\$HEAVY_RESULT" = "success"/);
  assert.match(workflow, /test "\$HEAVY_RESULT" = "skipped"/);
});
