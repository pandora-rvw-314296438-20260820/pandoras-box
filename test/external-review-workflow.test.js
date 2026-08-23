"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const workflowPath = join(root, ".github/workflows/projectos-security.yml");
const verifierPath = join(root, "scripts/verify-projectos-external-review.mjs");
const workflow = readFileSync(workflowPath, "utf8");
const verifier = readFileSync(verifierPath, "utf8");
const releaseContract = JSON.parse(readFileSync(
  join(root, "docs/releases/canonical/release-evidence.source.json"),
  "utf8",
));

test("candidate-controlled workflows cannot produce the trusted external-review context", () => {
  assert.doesNotMatch(workflow, /^\s{2}external-review:\s*$/m);
  assert.doesNotMatch(workflow, /^\s{4}name: external-review\s*$/m);
  assert.doesNotMatch(workflow, /verify-projectos-external-review\.mjs/);

  const requirement = releaseContract.requiredChecks.find(
    (check) => check.name === "external-review",
  );
  assert.deepEqual(requirement, {
    name: "external-review",
    authority: "TRUSTED_EXTERNAL_REVIEW_PROVIDER",
    producer: "unconfigured",
    command: null,
    status: "pending_external_receipt",
    receipt: null,
  });
});

test("the non-authoritative review inspector still binds evidence to an exact PR head", () => {
  execFileSync(process.execPath, ["--check", verifierPath], { cwd: root, stdio: "pipe" });
  assert.match(verifier, /target\.head\.sha === eventSha/);
  assert.match(verifier, /TRUSTED_REVIEWER = "google-labs-jules"/);
  assert.match(verifier, /normalizeLogin\(reportCommit\.author\?\.login\) === TRUSTED_REVIEWER/);
  assert.match(verifier, /normalizeLogin\(reportCommit\.committer\?\.login\) === TRUSTED_REVIEWER/);
  assert.match(verifier, /content\.includes\(target\.head\.sha\)/);
  assert.match(verifier, /content\.includes\(targetTree\)/);
  assert.match(verifier, /verdicts\[0\]\[1\]\.toLowerCase\(\) === "pass"/);
  assert.match(verifier, /eventName === "pull_request" && reportOnly/);
});

test("all repository-owned required checks test the synthetic integration SHA", () => {
  const workflowPaths = [
    ".github/workflows/projectos-security.yml",
    ".github/workflows/canonical-release-evidence.yml",
    ".github/workflows/windows-worker-contract.yml",
    ".github/workflows/pandora-mobile-integration.yml",
  ];
  for (const relativePath of workflowPaths) {
    const source = readFileSync(join(root, relativePath), "utf8");
    assert.doesNotMatch(source, /github\.event\.pull_request\.head\.sha/, relativePath);
    assert.match(source, /\$\{\{ github\.sha \}\}/, relativePath);
    assert.match(
      source,
      /^\s{2}merge_group:\s*\r?\n\s{4}types: \[checks_requested\]\s*$/m,
      relativePath,
    );
  }
});
