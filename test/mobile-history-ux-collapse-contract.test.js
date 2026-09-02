"use strict";

// Release-sync marker: package-context formatter applied; force owner-authored exact-head CI.
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const root = join(__dirname, "..");
const history = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "features", "simple", "project_history_screen.dart"),
  "utf8",
);
const model = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "models", "project_conversation_history.dart"),
  "utf8",
);

test("old proposals collapse to a bounded plan summary", () => {
  assert.match(model, /bool get isProposal => kind == 'PANDORA_PROPOSAL'/);
  assert.match(history, /item\.payloadText\('businessSummary'\)/);
  assert.match(history, /'View plan'/);
  assert.match(history, /'Hide plan'/);
  assert.match(history, /collapsedLines = item\.isProposal \|\| item\.isBuild \? 2 : 5/);
});

test("completed build history uses exact durable source and verification facts", () => {
  assert.match(history, /api\.loadExactPreviewFiles\(/);
  assert.match(history, /versionId: versionId/);
  assert.match(history, /file\['content'\]/);
  assert.match(history, /'checksTotal'/);
  assert.match(history, /'checksPassed'/);
  assert.match(history, /_matchingVerification\(items, buildJobId\)/);
  assert.match(history, /candidate\.isVerification && candidate\.buildJobId == buildJobId/);
  assert.match(history, /'View build evidence'/);
  assert.match(history, /Fail closed: never infer source counts from expired transport events/);
  assert.doesNotMatch(history, /content_chunk/);
});

test("history preserves a one-tap route back to the live conversation", () => {
  assert.match(history, /bottomNavigationBar:/);
  assert.match(history, /'Back to live'/);
  assert.match(history, /Navigator\.of\(context\)\.maybePop\(\)/);
  assert.doesNotMatch(history, /pushReplacement/);
});
