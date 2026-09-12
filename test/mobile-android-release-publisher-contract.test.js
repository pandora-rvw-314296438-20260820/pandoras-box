"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const publisher = fs.readFileSync(
  path.join(root, ".github/workflows/pandora-mobile-release.yml"),
  "utf8",
);
const validation = fs.readFileSync(
  path.join(root, ".github/workflows/pandora-mobile-integration.yml"),
  "utf8",
);
const deploymentTarget = fs.readFileSync(
  path.join(root, "DEPLOYMENT_TARGET.md"),
  "utf8",
);

test("Android prerelease publisher is manual, exact-source, and evidence-bound", () => {
  assert.match(publisher, /workflow_dispatch:/);
  assert.doesNotMatch(publisher, /^\s{2}(?:push|pull_request|workflow_run):/m);
  assert.match(publisher, /contents: write/);
  assert.match(publisher, /actions: read/);
  assert.match(publisher, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(publisher, /git\/ref\/heads\/main/);
  assert.match(publisher, /test \"\$main_sha\" = \"\$SOURCE_SHA\"/);
  assert.match(publisher, /\.head_branch.*main/);
  assert.match(publisher, /\.event.*push/);
  assert.match(publisher, /\.conclusion.*success/);
  assert.match(publisher, /pandora-mobile-integration\.yml/);
  assert.match(publisher, /pandora-mobile-android-validation-\$\{SOURCE_SHA\}/);
  assert.match(publisher, /artifact_class=.*validation-candidate/);
  assert.match(publisher, /production_release=.*false/);
  assert.match(publisher, /physical_device_verified=.*false/);
  assert.match(publisher, /--target \"\$SOURCE_SHA\"/);
  assert.match(publisher, /--prerelease/);
  assert.match(publisher, /Physical-device verification: not yet asserted/);
  assert.doesNotMatch(publisher, /secrets\./);
  assert.doesNotMatch(publisher, /(?:VERCEL|SUPABASE)_(?:PAT|TOKEN)/);
  assert.doesNotMatch(publisher, /GITHUB_PAT/);
  assert.doesNotMatch(publisher, /BEGIN [A-Z ]+PRIVATE KEY/);
});

test("read-only mobile validation lane remains unable to publish releases", () => {
  assert.match(validation, /^permissions:\s*\n\s{2}contents: read\s*$/m);
  assert.match(validation, /contents:\[\[:space:\]\]\+write/);
  assert.match(validation, /gh\[\[:space:\]\]\+release/);
  assert.doesNotMatch(validation, /^\s{2}contents: write\s*$/m);
});

test("canonical deployment target uses live Vercel team identity", () => {
  assert.match(deploymentTarget, /team_3yw1CN59ce4pj5SwyQGCAqN3/);
  assert.match(deploymentTarget, /Team slug: `mbanatao`/);
  assert.doesNotMatch(deploymentTarget, /team_IcdJUnzLi5wUN1GD8ALHyjF7/);
});
