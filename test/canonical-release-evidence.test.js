"use strict";

const assert = require("node:assert/strict");
const Ajv2020 = require("ajv/dist/2020").default;
const { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");
const { before, test } = require("node:test");

const ROOT = resolve(__dirname, "..");
const CONTRACT_FILE = join(ROOT, "docs/releases/canonical/release-evidence.source.json");
const SCHEMA_FILE = join(ROOT, "docs/releases/canonical/release-evidence.schema.json");
const WORKFLOW_FILE = join(ROOT, ".github/workflows/canonical-release-evidence.yml");

let releaseEvidence;
let validateSourceSchema;

before(async () => {
  releaseEvidence = await import("../scripts/verify-canonical-release-evidence.mjs");
  const schema = JSON.parse(readFileSync(SCHEMA_FILE, "utf8"));
  validateSourceSchema = new Ajv2020({ strict: true, strictTuples: false }).compile(schema);
});

function contractFixture() {
  return JSON.parse(readFileSync(CONTRACT_FILE, "utf8"));
}

function everyReceipt(value, receipts = []) {
  if (Array.isArray(value)) {
    value.forEach((item) => everyReceipt(item, receipts));
    return receipts;
  }
  if (value === null || typeof value !== "object") return receipts;
  for (const [key, child] of Object.entries(value)) {
    if (/receipt$/i.test(key)) receipts.push(child);
    everyReceipt(child, receipts);
  }
  return receipts;
}

function withMigrationFixture(files, callback) {
  const root = mkdtempSync(join(tmpdir(), "canonical-release-evidence-"));
  const migrations = join(root, "supabase", "migrations");
  mkdirSync(migrations, { recursive: true });
  for (const [name, contents] of Object.entries(files)) {
    writeFileSync(join(migrations, name), contents, "utf8");
  }
  try {
    return callback(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("repository release-evidence files satisfy the fail-closed contract", () => {
  const verified = releaseEvidence.verifyRepositoryFiles(ROOT);
  assert.equal(verified.contract.releaseDecision, "not_ready");
  assert.equal(verified.schema.properties.releaseDecision.const, "not_ready");
  assert.equal(validateSourceSchema(verified.contract), true, JSON.stringify(validateSourceSchema.errors));
});

test("source template has no candidate branch, pull request, SHA, or external receipt", () => {
  const contract = contractFixture();
  const serialized = JSON.stringify(contract);
  assert.equal(contract.sourceBinding.sourceSha, null);
  assert.equal(contract.sourceBinding.treeSha, null);
  assert.equal(contract.releaseDecision, "not_ready");
  assert.ok(everyReceipt(contract).length > 0);
  assert.ok(everyReceipt(contract).every((receipt) => receipt === null));
  assert.doesNotMatch(serialized, /\b[0-9a-f]{40}\b/i);
  assert.doesNotMatch(serialized, /refs\/heads\/|"(?:candidate)?branch(?:Name)?"|"pullRequest/i);
});

test("source control cannot self-author provider, reviewer, or owner proof", () => {
  const mutations = [
    (value) => {
      value.vercel.productionDeployment.status = "verified";
    },
    (value) => {
      value.vercel.productionDeployment.receipt = { deploymentId: "dpl_forged" };
    },
    (value) => {
      value.supabase.appliedMigrationChain.receipt = { status: "passed" };
    },
    (value) => {
      value.independentReview.receipt = { verdict: "approved" };
    },
    (value) => {
      value.ownerAuthorization.receipt = { decision: "authorized" };
    },
    (value) => {
      value.releaseDecision = "ready";
    },
    (value) => {
      value.sourceAuthority.mayAuthorizeRelease = true;
    },
  ];

  for (const mutate of mutations) {
    const contract = contractFixture();
    mutate(contract);
    assert.throws(() => releaseEvidence.validateSourceContract(contract), /canonical release evidence:/);
  }
});

test("production and rollback identities are exact, distinct, and provider-read", () => {
  const mutations = [
    (value) => {
      value.vercel.productionDeployment.requiredCount = 2;
    },
    (value) => {
      value.vercel.productionDeployment.bindToSourceSha = false;
    },
    (value) => {
      value.vercel.rollbackDeployment.mustDifferFromProduction = false;
    },
    (value) => {
      value.vercel.rollbackDeployment.providerReadRequired = false;
    },
    (value) => {
      value.vercel.rollbackDeployment.authority = "SOURCE_CONTROLLED";
    },
  ];

  for (const mutate of mutations) {
    const contract = contractFixture();
    mutate(contract);
    assert.throws(() => releaseEvidence.validateSourceContract(contract), /canonical release evidence:/);
  }
});

test("rollback rehearsal requires the transition, probes, and candidate restoration in order", () => {
  const contract = contractFixture();
  contract.rollbackRehearsal.requiredSequence = [
    "record_candidate_deployment",
    "verify_rollback_routes",
    "restore_candidate_deployment",
  ];
  assert.throws(
    () => releaseEvidence.validateSourceContract(contract),
    /rollbackRehearsal\.requiredSequence/,
  );

  const noRestoration = contractFixture();
  noRestoration.rollbackRehearsal.restorationRequired = false;
  assert.throws(() => releaseEvidence.validateSourceContract(noRestoration), /restoration/);

  const weakenedProbe = contractFixture();
  weakenedProbe.rollbackRehearsal.requiredRouteProbes[1].expectedStatuses = [200, 401];
  assert.throws(() => releaseEvidence.validateSourceContract(weakenedProbe), /requiredRouteProbes\[1\]/);
});

test("physical journey binds one Android build to both Wi-Fi and mobile-data runs", () => {
  const wrongNetwork = contractFixture();
  wrongNetwork.physicalJourney.runs[1].network = "wifi";
  assert.throws(() => releaseEvidence.validateSourceContract(wrongNetwork), /mobile_data/);

  const differentBuilds = contractFixture();
  differentBuilds.physicalJourney.sameBuildAcrossNetworks = false;
  assert.throws(() => releaseEvidence.validateSourceContract(differentBuilds), /same build/);

  const missingDeploymentBinding = contractFixture();
  missingDeploymentBinding.physicalJourney.bindTo = ["source_sha", "android_artifact_sha256"];
  assert.throws(() => releaseEvidence.validateSourceContract(missingDeploymentBinding), /physicalJourney\.bindTo/);
  assert.equal(validateSourceSchema(missingDeploymentBinding), false);

  const emptyBinding = contractFixture();
  emptyBinding.physicalJourney.bindTo = [];
  assert.equal(validateSourceSchema(emptyBinding), false);

  const missingRestorationIdentity = contractFixture();
  missingRestorationIdentity.physicalJourney.bindTo =
    missingRestorationIdentity.physicalJourney.bindTo.filter(
      (binding) => !binding.startsWith("rollback_restoration_"),
    );
  assert.throws(
    () => releaseEvidence.validateSourceContract(missingRestorationIdentity),
    /physicalJourney\.bindTo/,
  );
  assert.equal(validateSourceSchema(missingRestorationIdentity), false);

  const beforeRestorationAllowed = contractFixture();
  beforeRestorationAllowed.physicalJourney.mustFollowRollbackRestoration = false;
  assert.throws(
    () => releaseEvidence.validateSourceContract(beforeRestorationAllowed),
    /follow rollback restoration/,
  );
  assert.equal(validateSourceSchema(beforeRestorationAllowed), false);
});

test("migration binding is ordered, byte-exact, and separates source bytes from applied versions", () => {
  withMigrationFixture(
    {
      "20260101000000_first.sql": "select 1;\n",
      "20260102000000_second.sql": "select 2;\n",
    },
    (root) => {
      const first = releaseEvidence.computeMigrationChain(root);
      assert.deepEqual(
        first.orderedMigrations.map((migration) => migration.version),
        ["20260101000000", "20260102000000"],
      );
      assert.match(first.sourceChainSha256, /^[0-9a-f]{64}$/);
      assert.match(first.expectedAppliedChainSha256, /^[0-9a-f]{64}$/);

      writeFileSync(
        join(root, "supabase/migrations/20260102000000_second.sql"),
        "select 200;\n",
        "utf8",
      );
      const changedBytes = releaseEvidence.computeMigrationChain(root);
      assert.notEqual(changedBytes.sourceChainSha256, first.sourceChainSha256);
      assert.equal(changedBytes.expectedAppliedChainSha256, first.expectedAppliedChainSha256);
    },
  );
});

test("migration binding rejects duplicate timestamps", () => {
  withMigrationFixture(
    {
      "20260101000000_first.sql": "select 1;\n",
      "20260101000000_second.sql": "select 2;\n",
    },
    (root) => {
      assert.throws(() => releaseEvidence.computeMigrationChain(root), /duplicate migration version/);
    },
  );
});

test("source binding captures exact SHA, tree, and migrations but remains non-authoritative", () => {
  const migrationChain = releaseEvidence.computeMigrationChain(ROOT);
  const sourceSha = "1".repeat(40);
  const treeSha = "2".repeat(40);
  const binding = releaseEvidence.createSourceBinding({
    contract: contractFixture(),
    sourceSha,
    treeSha,
    generatedAt: "2026-08-23T00:00:00.000Z",
    migrationChain,
  });

  assert.equal(binding.sourceSha, sourceSha);
  assert.equal(binding.treeSha, treeSha);
  assert.deepEqual(binding.supabaseMigrationChain, migrationChain);
  assert.equal(binding.trustEffect, "describes_candidate_only");
  assert.equal(binding.externalEvidenceStatus, "pending_external_receipts");
  assert.equal(binding.externalReceiptsCopied, false);
  assert.equal(binding.sourceCanAuthorizeRelease, false);
  assert.equal(binding.releaseDecision, "not_ready");
  assert.equal("providerReceipt" in binding, false);
  assert.equal("ownerAuthorization" in binding, false);
});

test("source binding rejects abbreviated or malformed commit and tree identities", () => {
  const migrationChain = releaseEvidence.computeMigrationChain(ROOT);
  const base = {
    contract: contractFixture(),
    sourceSha: "1".repeat(40),
    treeSha: "2".repeat(40),
    generatedAt: "2026-08-23T00:00:00.000Z",
    migrationChain,
  };
  assert.throws(
    () => releaseEvidence.createSourceBinding({ ...base, sourceSha: "abc123" }),
    /source SHA/,
  );
  assert.throws(
    () => releaseEvidence.createSourceBinding({ ...base, treeSha: "A".repeat(40) }),
    /tree SHA/,
  );
});

test("candidate workflow is immutable, integration-SHA-bound, secretless, and read-only", () => {
  const workflow = readFileSync(WORKFLOW_FILE, "utf8");
  assert.equal(releaseEvidence.validateWorkflowText(workflow), workflow);

  const mutations = [
    workflow.replace(
      "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683",
      "actions/checkout@v4",
    ),
    workflow.replace("contents: read", "contents: write"),
    workflow.replace("workflow_dispatch:\n", "workflow_dispatch:\n    secrets: inherit\n"),
    workflow.replace("pull_request:\n", "pull_request:\n    paths:\n      - scripts/**\n"),
    workflow.replace("      - main\n", "      - develop\n"),
    workflow.replace("  merge_group:\n", ""),
    `${workflow}\n# forbidden mutation\n# vercel deploy --prod\n`,
    workflow.replace(
      "ref: ${{ github.sha }}",
      "ref: main",
    ),
  ];

  for (const mutatedWorkflow of mutations) {
    assert.throws(() => releaseEvidence.validateWorkflowText(mutatedWorkflow), /canonical release evidence:/);
  }
});

test("required checks are an exact ordered set and cannot be marked passed in source", () => {
  const missing = contractFixture();
  missing.requiredChecks.pop();
  assert.throws(() => releaseEvidence.validateSourceContract(missing), /exact required set/);

  const reordered = contractFixture();
  [reordered.requiredChecks[0], reordered.requiredChecks[1]] = [
    reordered.requiredChecks[1],
    reordered.requiredChecks[0],
  ];
  assert.throws(() => releaseEvidence.validateSourceContract(reordered), /requiredChecks\[0\]\.name/);

  const passed = contractFixture();
  passed.requiredChecks[0].status = "passed";
  assert.throws(() => releaseEvidence.validateSourceContract(passed), /must remain pending/);

  const duplicateName = contractFixture();
  duplicateName.requiredChecks[2] = {
    ...duplicateName.requiredChecks[0],
    command: "npm run check",
  };
  assert.equal(validateSourceSchema(duplicateName), false);

  const weakenedCommand = contractFixture();
  weakenedCommand.requiredChecks[0].command = "npm test";
  assert.equal(validateSourceSchema(weakenedCommand), false);
});
