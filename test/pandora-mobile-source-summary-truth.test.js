"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const source = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/live_build_theatre/live_build_file_activity.dart"),
  "utf8",
);

test("complete reconstructed source metrics are authoritative and contradictions fail closed", () => {
  const completeBranch = source.indexOf("if (state.locallyCompleteSourceMetrics)");
  const reportedTriple = source.indexOf("reportedFiles != null && reportedLines != null && reportedBytes != null");
  assert.ok(completeBranch >= 0, "complete local metrics branch must exist");
  assert.ok(reportedTriple > completeBranch, "complete local metrics must be evaluated before reported totals");
  assert.match(source, /bool metricAgrees\(int\? reported, int actual\)/);
  assert.match(source, /reported == null \|\| reported == actual/);
  assert.match(source, /!metricAgrees\(reportedFiles, state\.uniqueFileCount\)/);
  assert.match(source, /!metricAgrees\(reportedLines, state\.sourceLineCount\)/);
  assert.match(source, /!metricAgrees\(reportedBytes, state\.sourceByteCount\)[\s\S]*return 'Source summary unavailable';/);
});

test("incomplete and retention-gap fallbacks remain available", () => {
  assert.match(source, /return '\$reportedFiles files';/);
  assert.match(source, /if \(state\.historyGapDueToRetention\) \{[\s\S]*Build continued while you were away/);
  assert.match(source, /return 'Source summary ready';/);
});
