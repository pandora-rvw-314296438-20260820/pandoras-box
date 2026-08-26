import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const CONTRACT_PATH = "docs/releases/canonical/release-evidence.source.json";
export const SCHEMA_PATH = "docs/releases/canonical/release-evidence.schema.json";
export const WORKFLOW_PATH = ".github/workflows/canonical-release-evidence.yml";

export const REQUIRED_CHECKS = Object.freeze([
  Object.freeze({
    name: "node24",
    authority: "GITHUB_ACTIONS_PROVIDER",
    producer: "repository_workflow",
    command: "npm run check && npm test && npm audit --omit=dev --audit-level=high",
  }),
  Object.freeze({
    name: "external-review",
    authority: "TRUSTED_EXTERNAL_REVIEW_PROVIDER",
    producer: "pandora_main_gate_github_app",
    providerContext: "external-review",
    appId: 4658204,
    command: null,
  }),
  Object.freeze({
    name: "canonical-release-source-contract",
    authority: "GITHUB_ACTIONS_PROVIDER",
    producer: "repository_workflow",
    command:
      "node scripts/verify-canonical-release-evidence.mjs --mode repository && node --test test/canonical-release-evidence.test.js && npm run check && npm test && npm audit --omit=dev --audit-level=high && npx --yes deno-bin@2.2.7 check --node-modules-dir=none --frozen supabase/functions/pandora-owner-api/index.ts supabase/functions/pandora-worker-dispatch/index.ts supabase/functions/pandora-reviewer-attestation/index.ts supabase/functions/pandora-release-review-attestation/index.ts supabase/functions/pandora-release-owner-authorization/index.ts supabase/functions/pandora-physical-android-attestation/index.ts supabase/functions/mcpmaster-supabase-control/index.ts",
  }),
  Object.freeze({
    name: "Windows worker contract",
    authority: "GITHUB_ACTIONS_PROVIDER",
    producer: "repository_workflow",
    command: "npm run test:worker",
  }),
  Object.freeze({
    name: "Exact source / Flutter / Android",
    authority: "GITHUB_ACTIONS_PROVIDER",
    producer: "repository_workflow",
    command:
      "python3 -m unittest discover -s apps/pandora-mobile/tool -p 'test_*.py' && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test --reporter expanded && flutter build web --release && flutter build apk --debug",
  }),
]);

const CANONICAL_WORKFLOW_COMMANDS = Object.freeze([
  "node scripts/verify-canonical-release-evidence.mjs --mode repository",
  "node --test test/canonical-release-evidence.test.js",
  "npm run check",
  "npm test",
  "npm audit --omit=dev --audit-level=high",
  "npx --yes deno-bin@2.2.7 check --node-modules-dir=none --frozen supabase/functions/pandora-owner-api/index.ts supabase/functions/pandora-worker-dispatch/index.ts supabase/functions/pandora-reviewer-attestation/index.ts supabase/functions/pandora-release-review-attestation/index.ts supabase/functions/pandora-release-owner-authorization/index.ts supabase/functions/pandora-physical-android-attestation/index.ts supabase/functions/mcpmaster-supabase-control/index.ts",
]);

export const ROLLBACK_SEQUENCE = Object.freeze([
  "record_candidate_deployment",
  "transition_to_rollback_deployment",
  "verify_rollback_routes",
  "restore_candidate_deployment",
  "verify_restored_routes",
]);

export const REQUIRED_ROUTE_PROBES = Object.freeze([
  {
    route: "/health",
    methods: ["GET"],
    expectedStatuses: [200],
    semanticContract: "healthy_json",
  },
  {
    route: "/mcp",
    methods: ["GET", "POST"],
    expectedStatuses: [401],
    semanticContract: "unauthenticated_bearer_boundary",
  },
  {
    route: "/.well-known/oauth-protected-resource/mcp",
    methods: ["GET"],
    expectedStatuses: [200],
    semanticContract: "oauth_resource_metadata",
  },
]);

export const PHYSICAL_JOURNEY_STEPS = Object.freeze([
  "owner_authenticate",
  "submit_owner_command",
  "observe_durable_dispatch",
  "observe_worker_01_claim",
  "observe_exact_provider_result",
  "observe_proof_in_owner_read",
]);

const ROOT_KEYS = [
  "schemaVersion",
  "kind",
  "repository",
  "releaseDecision",
  "sourceAuthority",
  "sourceBinding",
  "vercel",
  "supabase",
  "requiredChecks",
  "rollbackRehearsal",
  "physicalJourney",
  "independentReview",
  "ownerAuthorization",
];

const SHA_PATTERN = /^[0-9a-f]{40}$/;
const MIGRATION_PATTERN = /^(\d{14})_([a-z0-9_]+)\.sql$/;
const PENDING_EXTERNAL = "pending_external_receipt";

function fail(message) {
  throw new Error(`canonical release evidence: ${message}`);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function assertObject(value, path) {
  assert(
    value !== null && typeof value === "object" && !Array.isArray(value),
    `${path} must be an object`,
  );
}

function assertExactKeys(value, expectedKeys, path) {
  assertObject(value, path);
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${path} keys must be exactly ${expected.join(", ")}`,
  );
}

function assertArrayEquals(actual, expected, path) {
  assert(Array.isArray(actual), `${path} must be an array`);
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${path} must be exactly ${JSON.stringify(expected)}`,
  );
}

function assertPendingReceipt(value, authority, path) {
  assert(value.authority === authority, `${path}.authority must be ${authority}`);
  assert(value.status === PENDING_EXTERNAL, `${path}.status must remain pending`);
  assert(value.receipt === null, `${path}.receipt must remain null in source control`);
}

function scanSourceTrustBoundary(value, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanSourceTrustBoundary(item, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== "object") return;

  for (const [key, child] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    if (/receipt$/i.test(key)) {
      assert(child === null, `${childPath} cannot be authored by source control`);
    }
    if (/(status|decision|verdict|result)$/i.test(key) && typeof child === "string") {
      assert(
        ["not_ready", "pending_ci_binding", PENDING_EXTERNAL].includes(child) ||
          !/(?:^|_)(?:pass(?:ed)?|ready|verified|approved|authorized|rehearsed|complete(?:d)?|success)(?:$|_)/i.test(
            child,
          ),
        `${childPath} cannot assert positive external evidence`,
      );
    }
    if (/^(?:token|accessToken|apiKey|secret|password|cookie|privateKey|authorizationHeader)$/i.test(key)) {
      fail(`${childPath} is secret-shaped and forbidden`);
    }
    if (
      typeof child === "string" &&
      /(?:gh[oprsu]_[A-Za-z0-9_]{16,}|sb_(?:secret|publishable)_[A-Za-z0-9_-]+|Bearer\s+[A-Za-z0-9._~-]+|-----BEGIN [A-Z ]+PRIVATE KEY-----)/.test(
        child,
      )
    ) {
      fail(`${childPath} contains secret-shaped material`);
    }
    scanSourceTrustBoundary(child, childPath);
  }
}

function assertNoCandidateRef(value) {
  const forbiddenKeys = new Set([
    "branch",
    "branchName",
    "candidateBranch",
    "pullRequest",
    "pullRequestNumber",
  ]);

  function walk(child, path = "$") {
    if (Array.isArray(child)) {
      child.forEach((item, index) => walk(item, `${path}[${index}]`));
      return;
    }
    if (child === null || typeof child !== "object") return;
    for (const [key, nested] of Object.entries(child)) {
      assert(!forbiddenKeys.has(key), `${path}.${key} must not pin a branch or pull request`);
      if (typeof nested === "string") {
        assert(!/^refs\/heads\//.test(nested), `${path}.${key} must not pin a branch ref`);
        assert(!/^release\//.test(nested), `${path}.${key} must not pin a release branch`);
      }
      walk(nested, `${path}.${key}`);
    }
  }

  walk(value);
}

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function validateSourceContract(contract) {
  assertExactKeys(contract, ROOT_KEYS, "$contract");
  assert(contract.schemaVersion === "1.0.0", "schemaVersion must be 1.0.0");
  assert(contract.kind === "canonical_release_evidence_requirements", "kind is invalid");
  assert(contract.repository === "pandora-rvw-314296438-20260820/pandoras-box", "repository is invalid");
  assert(contract.releaseDecision === "not_ready", "source releaseDecision must be not_ready");

  assertExactKeys(
    contract.sourceAuthority,
    [
      "authority",
      "describesRequirementsOnly",
      "mayIssueProviderProof",
      "mayIssueReviewerProof",
      "mayIssueOwnerAuthorization",
      "mayAuthorizeRelease",
    ],
    "sourceAuthority",
  );
  assert(contract.sourceAuthority.authority === "SOURCE_CONTROLLED", "source authority is invalid");
  assert(contract.sourceAuthority.describesRequirementsOnly === true, "source must describe requirements only");
  for (const key of [
    "mayIssueProviderProof",
    "mayIssueReviewerProof",
    "mayIssueOwnerAuthorization",
    "mayAuthorizeRelease",
  ]) {
    assert(contract.sourceAuthority[key] === false, `sourceAuthority.${key} must be false`);
  }

  assertExactKeys(
    contract.sourceBinding,
    ["mode", "required", "sourceSha", "treeSha", "status"],
    "sourceBinding",
  );
  assert(contract.sourceBinding.mode === "ci_exact_integration_sha", "source binding mode is invalid");
  assert(contract.sourceBinding.required === true, "exact source binding must be required");
  assert(contract.sourceBinding.sourceSha === null, "source SHA must be CI-bound, not committed");
  assert(contract.sourceBinding.treeSha === null, "tree SHA must be CI-bound, not committed");
  assert(contract.sourceBinding.status === "pending_ci_binding", "source binding must remain pending in the template");

  assertExactKeys(
    contract.vercel,
    ["provider", "projectId", "productionAlias", "productionDeployment", "rollbackDeployment"],
    "vercel",
  );
  assert(contract.vercel.provider === "vercel", "Vercel provider is invalid");
  assert(contract.vercel.projectId === "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk", "Vercel project is invalid");
  assert(contract.vercel.productionAlias === "https://mcpmaster.vercel.app", "production alias is invalid");

  assertExactKeys(
    contract.vercel.productionDeployment,
    ["authority", "requiredCount", "target", "bindToSourceSha", "deploymentId", "sourceSha", "status", "receipt"],
    "vercel.productionDeployment",
  );
  const production = contract.vercel.productionDeployment;
  assertPendingReceipt(production, "VERCEL_PROVIDER", "vercel.productionDeployment");
  assert(production.requiredCount === 1, "exactly one production deployment is required");
  assert(production.target === "production", "production target is required");
  assert(production.bindToSourceSha === true, "production deployment must bind to the source SHA");
  assert(production.deploymentId === null && production.sourceSha === null, "production identity must come from Vercel");

  assertExactKeys(
    contract.vercel.rollbackDeployment,
    ["authority", "mustDifferFromProduction", "providerReadRequired", "deploymentId", "sourceSha", "status", "receipt"],
    "vercel.rollbackDeployment",
  );
  const rollback = contract.vercel.rollbackDeployment;
  assertPendingReceipt(rollback, "VERCEL_PROVIDER", "vercel.rollbackDeployment");
  assert(rollback.mustDifferFromProduction === true, "rollback deployment must be distinct");
  assert(rollback.providerReadRequired === true, "rollback identity requires a provider read");
  assert(rollback.deploymentId === null && rollback.sourceSha === null, "rollback identity must come from Vercel");

  assertExactKeys(contract.supabase, ["projectRef", "sourceMigrationChain", "appliedMigrationChain"], "supabase");
  assert(contract.supabase.projectRef === "jcyqixttuebxqqfkjonq", "Supabase project is invalid");
  assertExactKeys(
    contract.supabase.sourceMigrationChain,
    ["mode", "orderedMigrations", "sourceChainSha256", "expectedAppliedChainSha256", "status"],
    "supabase.sourceMigrationChain",
  );
  const sourceMigrations = contract.supabase.sourceMigrationChain;
  assert(sourceMigrations.mode === "computed_in_ci", "source migration mode is invalid");
  assert(sourceMigrations.status === "pending_ci_binding", "source migration chain must remain pending in the template");
  assert(
    sourceMigrations.orderedMigrations === null &&
      sourceMigrations.sourceChainSha256 === null &&
      sourceMigrations.expectedAppliedChainSha256 === null,
    "source migration bytes must be computed from the exact CI tree",
  );

  assertExactKeys(
    contract.supabase.appliedMigrationChain,
    ["authority", "exactOrderedMatchRequired", "orderedVersions", "appliedChainSha256", "status", "receipt"],
    "supabase.appliedMigrationChain",
  );
  const appliedMigrations = contract.supabase.appliedMigrationChain;
  assertPendingReceipt(appliedMigrations, "SUPABASE_PROVIDER", "supabase.appliedMigrationChain");
  assert(appliedMigrations.exactOrderedMatchRequired === true, "applied migrations must exactly match source order");
  assert(
    appliedMigrations.orderedVersions === null && appliedMigrations.appliedChainSha256 === null,
    "applied migration identity must come from Supabase",
  );

  const expectedChecks = REQUIRED_CHECKS;
  assert(Array.isArray(contract.requiredChecks), "requiredChecks must be an array");
  assert(contract.requiredChecks.length === expectedChecks.length, "requiredChecks must contain the exact required set");
  contract.requiredChecks.forEach((check, index) => {
    const expected = expectedChecks[index];
    assert(check?.name === expected.name, `requiredChecks[${index}].name must be ${expected.name}`);
    assertExactKeys(
      check,
      [...Object.keys(expected), "status", "receipt"],
      `requiredChecks[${index}]`,
    );
    for (const [key, value] of Object.entries(expected).filter(([key]) => key !== "name")) {
      assert(check[key] === value, `${check.name} ${key} is not exact`);
    }
    assertPendingReceipt(check, expected.authority, `requiredChecks[${index}]`);
  });

  assertExactKeys(
    contract.rollbackRehearsal,
    [
      "authority",
      "environment",
      "providerReadRequired",
      "candidateDeploymentId",
      "rollbackDeploymentId",
      "distinctDeploymentsRequired",
      "requiredSequence",
      "requiredRouteProbes",
      "restorationRequired",
      "status",
      "receipt",
    ],
    "rollbackRehearsal",
  );
  const rehearsal = contract.rollbackRehearsal;
  assertPendingReceipt(rehearsal, "VERCEL_PROVIDER", "rollbackRehearsal");
  assert(rehearsal.environment === "production_alias", "rollback rehearsal must bind the production alias");
  assert(rehearsal.providerReadRequired === true, "rollback rehearsal requires provider reads");
  assert(rehearsal.candidateDeploymentId === null && rehearsal.rollbackDeploymentId === null, "deployment IDs must be provider-issued");
  assert(rehearsal.distinctDeploymentsRequired === true, "rehearsal deployments must be distinct");
  assertArrayEquals(rehearsal.requiredSequence, ROLLBACK_SEQUENCE, "rollbackRehearsal.requiredSequence");
  assert(Array.isArray(rehearsal.requiredRouteProbes), "rollback route probes must be an array");
  assert(rehearsal.requiredRouteProbes.length === REQUIRED_ROUTE_PROBES.length, "rollback route probes must be exact");
  rehearsal.requiredRouteProbes.forEach((probe, index) => {
    assertExactKeys(
      probe,
      ["route", "methods", "expectedStatuses", "semanticContract"],
      `rollbackRehearsal.requiredRouteProbes[${index}]`,
    );
    assert(
      JSON.stringify(probe) === JSON.stringify(REQUIRED_ROUTE_PROBES[index]),
      `rollbackRehearsal.requiredRouteProbes[${index}] is not exact`,
    );
  });
  assert(rehearsal.restorationRequired === true, "candidate restoration must be rehearsed");

  assertExactKeys(
    contract.physicalJourney,
    ["platform", "sameBuildAcrossNetworks", "mustFollowRollbackRestoration", "bindTo", "requiredSteps", "runs"],
    "physicalJourney",
  );
  const journey = contract.physicalJourney;
  assert(journey.platform === "physical_android", "journey must use a physical Android device");
  assert(journey.sameBuildAcrossNetworks === true, "Wi-Fi and mobile data must use the same build");
  assert(
    journey.mustFollowRollbackRestoration === true,
    "physical journey must follow rollback restoration",
  );
  assertArrayEquals(
    journey.bindTo,
    [
      "source_sha",
      "source_tree_sha",
      "production_deployment_id",
      "rollback_restoration_receipt_sha256",
      "rollback_restoration_completed_at",
      "android_artifact_sha256",
      "github_android_artifact_digest_sha256",
      "production_origin",
    ],
    "physicalJourney.bindTo",
  );
  assertArrayEquals(journey.requiredSteps, PHYSICAL_JOURNEY_STEPS, "physicalJourney.requiredSteps");
  assert(Array.isArray(journey.runs) && journey.runs.length === 2, "journey requires exactly Wi-Fi and mobile-data runs");
  for (const [index, network] of ["wifi", "mobile_data"].entries()) {
    const run = journey.runs[index];
    assertExactKeys(run, ["network", "authority", "status", "receipt"], `physicalJourney.runs[${index}]`);
    assert(run.network === network, `physicalJourney.runs[${index}] must be ${network}`);
    assertPendingReceipt(run, "PHYSICAL_ANDROID_OBSERVER", `physicalJourney.runs[${index}]`);
  }

  assertExactKeys(contract.independentReview, ["authority", "bindTo", "status", "receipt"], "independentReview");
  assertPendingReceipt(contract.independentReview, "INDEPENDENT_REVIEWER", "independentReview");
  assertArrayEquals(
    contract.independentReview.bindTo,
    ["source_sha", "source_tree_sha", "production_deployment_id", "rollback_deployment_id", "supabase_migration_chain_sha256"],
    "independentReview.bindTo",
  );

  assertExactKeys(contract.ownerAuthorization, ["authority", "bindTo", "status", "receipt"], "ownerAuthorization");
  assertPendingReceipt(contract.ownerAuthorization, "OWNER_AUTHORIZATION", "ownerAuthorization");
  assertArrayEquals(
    contract.ownerAuthorization.bindTo,
    ["source_sha", "production_deployment_id", "review_receipt_sha256"],
    "ownerAuthorization.bindTo",
  );

  scanSourceTrustBoundary(contract);
  assertNoCandidateRef(contract);
  return contract;
}

export function validateSchemaContract(schema) {
  assertObject(schema, "$schema");
  assert(schema.$schema === "https://json-schema.org/draft/2020-12/schema", "schema draft must be 2020-12");
  assert(schema.additionalProperties === false, "schema root must reject unknown fields");
  assert(schema.properties?.releaseDecision?.const === "not_ready", "schema must pin the source decision to not_ready");
  assert(schema.$defs?.pendingStatus?.const === PENDING_EXTERNAL, "schema must pin external status to pending");
  assert(schema.$defs?.nullReceipt?.type === "null", "schema must require null source receipts");
  assert(/cannot issue provider/i.test(schema.description ?? ""), "schema must state the provider-proof trust boundary");
  assertArrayEquals(
    schema.properties?.requiredChecks?.prefixItems?.map((item) => item.$ref),
    [
      "#/$defs/node24Check",
      "#/$defs/externalReviewCheck",
      "#/$defs/canonicalReleaseSourceContractCheck",
      "#/$defs/windowsWorkerContractCheck",
      "#/$defs/exactSourceFlutterAndroidCheck",
    ],
    "schema.requiredChecks.prefixItems",
  );
  assert(schema.properties?.requiredChecks?.items === false, "schema required checks must be exact and ordered");
  assertArrayEquals(
    schema.$defs?.externalReviewCheck?.required,
    ["name", "authority", "producer", "providerContext", "appId", "command", "status", "receipt"],
    "schema.externalReviewCheck.required",
  );
  assert(
    schema.$defs?.externalReviewCheck?.properties?.producer?.const === "pandora_main_gate_github_app",
    "schema must pin the external-review producer",
  );
  assert(
    schema.$defs?.externalReviewCheck?.properties?.providerContext?.const === "external-review",
    "schema must pin the external-review provider context",
  );
  assert(
    schema.$defs?.externalReviewCheck?.properties?.appId?.const === 4658204,
    "schema must pin the external-review GitHub App",
  );
  assert(
    schema.$defs?.physicalJourney?.properties?.mustFollowRollbackRestoration?.const === true,
    "schema physical journey must follow rollback restoration",
  );
  return schema;
}

export function validateWorkflowText(text) {
  assert(typeof text === "string" && text.length > 0, "workflow must be text");
  assert(/^name: Canonical release evidence$/m.test(text), "workflow name is invalid");
  assert(/^\s{2}push:\s*\r?\n\s{4}branches:\s*\r?\n\s{6}- main\s*$/m.test(text), "workflow must verify every pushed main SHA");
  assert(/^\s{2}pull_request:\s*$/m.test(text), "workflow must run for every pull request");
  assert(
    /^\s{2}merge_group:\s*\r?\n\s{4}types: \[checks_requested\]\s*$/m.test(text),
    "workflow must verify merge-queue integration SHAs",
  );
  assert(/^\s{2}workflow_dispatch:\s*$/m.test(text), "workflow must support manual dispatch");
  assert(!/^\s*pull_request_target:\s*$/m.test(text), "pull_request_target is forbidden");
  assert(!/^\s+paths(?:-ignore)?:\s*$/m.test(text), "path filters are forbidden");
  assert((text.match(/^permissions:\s*$/gm) ?? []).length === 1, "workflow must have one explicit permissions block");
  assert(/^permissions:\s*\r?\n\s{2}contents: read\s*$/m.test(text), "workflow permissions must be contents: read");
  assert(!/^\s+[^#\s][^:]*:\s*write\s*$/m.test(text), "write permissions are forbidden");
  assert(
    !/(?:^\s+secrets:|secrets\.|github\.token|GITHUB_TOKEN|GH_TOKEN|VERCEL_TOKEN|SUPABASE_ACCESS_TOKEN)/m.test(text),
    "workflow secrets are forbidden",
  );

  const uses = [...text.matchAll(/^\s*-?\s*uses:\s*([^\s#]+)\s*(?:#.*)?$/gm)].map((match) => match[1]);
  assert(uses.length >= 3, "workflow must use pinned checkout, Node setup, and artifact upload actions");
  for (const action of uses) {
    assert(/^[^@\s]+@[0-9a-f]{40}$/.test(action), `workflow action must use an immutable SHA: ${action}`);
  }
  for (const action of [
    "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683",
    "actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020",
    "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
  ]) {
    assert(uses.includes(action), `workflow is missing pinned ${action}`);
  }

  assert(text.includes("ref: ${{ github.sha }}"), "checkout must use the exact integration SHA");
  assert(!text.includes("github.event.pull_request.head.sha"), "workflow must not bypass the synthetic integration SHA");
  assert(text.includes("fetch-depth: 1"), "checkout must be shallow and exact");
  assert(text.includes("persist-credentials: false"), "checkout credentials must not persist");
  assert(text.includes("EXPECTED_SOURCE_SHA: ${{ github.sha }}"), "workflow must independently compare the integration SHA");
  assert(text.includes("node-version: 24"), "workflow must pin the repository Node major");

  for (const command of CANONICAL_WORKFLOW_COMMANDS) {
    assert(text.includes(command), `workflow is missing required command: ${command}`);
  }

  assert(text.includes("--mode source-binding"), "workflow must emit the exact source binding");
  assert(text.includes("${{ runner.temp }}/canonical-release-source-binding.json"), "source binding must be outside the repository");
  assert(text.includes("if-no-files-found: error"), "source binding artifact must be required");

  const mutatingCommand = /\b(?:vercel\s+(?:deploy|promote|alias)|supabase\s+db\s+(?:push|reset)|git\s+push|gh\s+pr\s+merge|npm\s+publish)\b/i;
  assert(!mutatingCommand.test(text), "candidate workflow must not mutate providers or repository refs");
  assert(!/^\s+environment:\s*(?:production|preview)\s*$/mi.test(text), "candidate workflow must not acquire a deployment environment");
  return text;
}

export function computeMigrationChain(root) {
  const migrationDirectory = resolve(root, "supabase/migrations");
  const dirents = readdirSync(migrationDirectory, { withFileTypes: true });
  const migrationNames = dirents
    .filter((entry) => entry.name.endsWith(".sql"))
    .map((entry) => {
      assert(entry.isFile() && !entry.isSymbolicLink(), `migration must be a regular file: ${entry.name}`);
      const match = MIGRATION_PATTERN.exec(entry.name);
      assert(match, `migration filename is invalid: ${entry.name}`);
      return { file: entry.name, version: match[1] };
    })
    .sort((left, right) => left.file.localeCompare(right.file));

  assert(migrationNames.length > 0, "at least one Supabase migration is required");
  const versions = new Set();
  const orderedMigrations = migrationNames.map(({ file, version }) => {
    assert(!versions.has(version), `duplicate migration version: ${version}`);
    versions.add(version);
    const migrationPath = resolve(migrationDirectory, file);
    const stats = lstatSync(migrationPath);
    assert(stats.isFile() && !stats.isSymbolicLink(), `migration must be a regular file: ${file}`);
    return { version, file, sha256: sha256(readFileSync(migrationPath)) };
  });

  const sourceChainBytes = orderedMigrations
    .map(({ file, sha256: fileSha256 }) => `${file}\t${fileSha256}\n`)
    .join("");
  const appliedChainBytes = orderedMigrations.map(({ version }) => `${version}\n`).join("");
  return {
    count: orderedMigrations.length,
    firstVersion: orderedMigrations[0].version,
    lastVersion: orderedMigrations.at(-1).version,
    orderedMigrations,
    sourceChainSha256: sha256(sourceChainBytes),
    expectedAppliedChainSha256: sha256(appliedChainBytes),
  };
}

export function createSourceBinding({
  contract,
  sourceSha,
  treeSha,
  generatedAt,
  migrationChain,
}) {
  validateSourceContract(contract);
  assert(SHA_PATTERN.test(sourceSha), "source SHA must be 40 lowercase hexadecimal characters");
  assert(SHA_PATTERN.test(treeSha), "tree SHA must be 40 lowercase hexadecimal characters");
  assert(
    typeof generatedAt === "string" && !Number.isNaN(Date.parse(generatedAt)),
    "generatedAt must be an ISO timestamp",
  );
  assertObject(migrationChain, "migrationChain");
  assert(Array.isArray(migrationChain.orderedMigrations) && migrationChain.orderedMigrations.length > 0, "migration chain is empty");

  return {
    schemaVersion: "1.0.0",
    kind: "canonical_release_source_binding",
    repository: contract.repository,
    generatedAt,
    authority: "SOURCE_CONTROLLED_WORKFLOW",
    trustEffect: "describes_candidate_only",
    sourceSha,
    treeSha,
    requirementsObjectSha256: sha256(`${JSON.stringify(contract)}\n`),
    supabaseMigrationChain: migrationChain,
    externalEvidenceStatus: "pending_external_receipts",
    externalReceiptsCopied: false,
    sourceCanAuthorizeRelease: false,
    releaseDecision: "not_ready",
  };
}

export function verifyRepositoryFiles(root = process.cwd()) {
  const contract = JSON.parse(readFileSync(resolve(root, CONTRACT_PATH), "utf8"));
  const schema = JSON.parse(readFileSync(resolve(root, SCHEMA_PATH), "utf8"));
  const workflow = readFileSync(resolve(root, WORKFLOW_PATH), "utf8");
  validateSourceContract(contract);
  validateSchemaContract(schema);
  validateWorkflowText(workflow);
  return { contract, schema, workflow };
}

function parseArguments(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    assert(argument.startsWith("--"), `unexpected argument: ${argument}`);
    const key = argument.slice(2);
    const value = argv[index + 1];
    assert(value && !value.startsWith("--"), `missing value for ${argument}`);
    result[key] = value;
    index += 1;
  }
  return result;
}

function git(root, ...args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
}

function pathIsInside(parent, candidate) {
  const candidateRelative = relative(parent, candidate);
  return candidateRelative !== "" && !candidateRelative.startsWith("..") && !isAbsolute(candidateRelative);
}

function runCli() {
  const args = parseArguments(process.argv.slice(2));
  const mode = args.mode;
  const root = resolve(args.root ?? process.cwd());
  assert(mode === "repository" || mode === "source-binding", "--mode must be repository or source-binding");
  const { contract } = verifyRepositoryFiles(root);

  if (mode === "repository") {
    process.stdout.write("canonical release source contract: valid and NOT_READY\n");
    return;
  }

  assert(args["expected-sha"], "--expected-sha is required for source-binding mode");
  assert(args.output, "--output is required for source-binding mode");
  const expectedSha = args["expected-sha"];
  const outputPath = resolve(args.output);
  assert(SHA_PATTERN.test(expectedSha), "--expected-sha must be a full lowercase commit SHA");
  assert(!pathIsInside(root, outputPath) && outputPath !== root, "source binding output must be outside the repository");

  const actualSha = git(root, "rev-parse", "HEAD");
  const treeSha = git(root, "rev-parse", "HEAD^{tree}");
  assert(actualSha === expectedSha, `checked-out HEAD ${actualSha} does not match expected ${expectedSha}`);
  assert(git(root, "status", "--porcelain", "--untracked-files=all") === "", "source-binding mode requires a clean exact checkout");

  const migrationChain = computeMigrationChain(root);
  const binding = createSourceBinding({
    contract,
    sourceSha: actualSha,
    treeSha,
    generatedAt: new Date().toISOString(),
    migrationChain,
  });
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(binding, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`canonical release source binding written outside repository: ${outputPath}\n`);
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  try {
    runCli();
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
