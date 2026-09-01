"use strict";

const { readFileSync, readdirSync } = require("node:fs");
const { resolve } = require("node:path");
const { createHash } = require("node:crypto");
const { GitHubControlResolver } = require("../runtime/github-control-resolver.js");
const { SupabaseControlResolver } = require("../runtime/supabase-control-resolver.js");
const { SupabaseMCPServer } = require("../tools/supabase.js");
const { PandoraMemoryMCPServer } = require("../tools/memory.js");
const {
  CANONICAL_REPOSITORY,
  refreshCanonicalStatusPack,
} = require("./canonical-status-pack.js");

const triage = require("../../docs/status/OPEN_PR_TRIAGE.json");
const DEFAULT_MEMORY_ORIGIN = "https://pandorasbox-memory.vercel.app";
const DEFAULT_SUPABASE_PROJECT_REF = "jcyqixttuebxqqfkjonq";
const DEFAULT_CONTROL_URL = "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 2_000_000;
const GITHUB_ACTIONS_APP_ID = 15368;
const TRUSTED_EXTERNAL_REVIEW_IDENTITY = "external-review";
const TRUSTED_EXTERNAL_REVIEW_PROVIDER_CONTEXT = "external-review";
const TRUSTED_EXTERNAL_REVIEW_APP_ID = 4658204;
const TRUSTED_EXTERNAL_REVIEW_APP_ID_ENV = "PANDORA_TRUSTED_EXTERNAL_REVIEW_APP_ID";
const REQUIRED_CHECK_BINDINGS = Object.freeze([
  Object.freeze({ name: "node24", providerContext: "node24", appId: GITHUB_ACTIONS_APP_ID }),
  Object.freeze({
    name: TRUSTED_EXTERNAL_REVIEW_IDENTITY,
    providerContext: TRUSTED_EXTERNAL_REVIEW_PROVIDER_CONTEXT,
    appId: TRUSTED_EXTERNAL_REVIEW_APP_ID,
  }),
  Object.freeze({
    name: "canonical-release-source-contract",
    providerContext: "canonical-release-source-contract",
    appId: GITHUB_ACTIONS_APP_ID,
  }),
  Object.freeze({
    name: "Windows worker contract",
    providerContext: "Windows worker contract",
    appId: GITHUB_ACTIONS_APP_ID,
  }),
  Object.freeze({
    name: "Exact source / Flutter / Android",
    providerContext: "Exact source / Flutter / Android",
    appId: GITHUB_ACTIONS_APP_ID,
  }),
]);
const REQUIRED_CHECK_IDENTITIES = Object.freeze(REQUIRED_CHECK_BINDINGS.map(({ name }) => name));
const REPOSITORY_CHECK_IDENTITIES = Object.freeze(
  REQUIRED_CHECK_IDENTITIES.filter((name) => name !== TRUSTED_EXTERNAL_REVIEW_IDENTITY),
);
const REQUIRED_CHECK_WORKFLOW_PATHS = Object.freeze({
  node24: ".github/workflows/projectos-security.yml",
  "canonical-release-source-contract": ".github/workflows/canonical-release-evidence.yml",
  "Windows worker contract": ".github/workflows/windows-worker-contract.yml",
  "Exact source / Flutter / Android": ".github/workflows/pandora-mobile-integration.yml",
});
const AUTHORITY_POLICY_PATH = require.resolve("../../SOURCE_AUTHORITY_POLICY.json");
const HISTORICAL_SURFACES_PATH = require.resolve("../../docs/status/HISTORICAL_STATUS_SURFACES.json");
const MIGRATIONS_PATH = resolve(__dirname, "../../supabase/migrations");

function exactMainWorkflowPath(value, expected) {
  return value === expected || value === `${expected}@main`;
}

function trustedExternalReviewAppId(env) {
  return env?.[TRUSTED_EXTERNAL_REVIEW_APP_ID_ENV] === String(TRUSTED_EXTERNAL_REVIEW_APP_ID)
    ? TRUSTED_EXTERNAL_REVIEW_APP_ID
    : null;
}

function fileSha256(filePath) {
  return createHash("sha256")
    .update(readFileSync(filePath))
    .digest("hex");
}

function oidcToken(env) {
  return env.VERCEL_OIDC_TOKEN?.trim();
}

async function boundedJson(url, init, fetchFn, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchFn(url, { ...init, signal: controller.signal, redirect: "error" });
    const declared = Number(response.headers?.get("content-length") || "0");
    if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) throw new Error("oversized");
    const text = await response.text();
    if (Buffer.byteLength(text, "utf8") > MAX_RESPONSE_BYTES) throw new Error("oversized");
    if (!response.ok) throw new Error(`provider status ${response.status}`);
    return JSON.parse(text);
  } finally {
    clearTimeout(timer);
  }
}

async function readAllGitHubPulls({ origin, owner, repo, headers, fetchFn }) {
  const pulls = [];
  const seenNumbers = new Set();
  const perPage = 100;
  const maxPages = 20;
  for (let page = 1; page <= maxPages; page += 1) {
    const pageSuffix = page === 1 ? "" : `&page=${page}`;
    const batch = await boundedJson(
      `${origin}/repos/${owner}/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=${perPage}${pageSuffix}`,
      { headers },
      fetchFn,
    );
    if (!Array.isArray(batch)) throw new Error("invalid GitHub pull response");
    for (const pull of batch) {
      if (!Number.isSafeInteger(pull?.number) || seenNumbers.has(pull.number)) {
        throw new Error("invalid or duplicate GitHub pull identity");
      }
      seenNumbers.add(pull.number);
      pulls.push(pull);
    }
    if (batch.length < perPage) return pulls;
  }
  throw new Error("GitHub pull inventory exceeds bounded pagination");
}

function expectedMigrationManifest() {
  const migrations = readdirSync(MIGRATIONS_PATH, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".sql"))
    .map((entry) => {
      const match = entry.name.match(/^(\d{14})_[a-z0-9_]+\.sql$/);
      if (!match) throw new Error(`invalid migration filename: ${entry.name}`);
      return {
        file: entry.name,
        version: match[1],
        sha256: fileSha256(resolve(MIGRATIONS_PATH, entry.name)),
      };
    })
    .sort((left, right) => left.file.localeCompare(right.file));
  if (migrations.length === 0 || new Set(migrations.map(({ version }) => version)).size !== migrations.length) {
    throw new Error("invalid source migration inventory");
  }
  return migrations;
}

function expectedMigrationVersions() {
  return expectedMigrationManifest().map(({ version }) => version);
}

function migrationVersionChainSha256(versions) {
  return createHash("sha256")
    .update(versions.map((version) => `${version}\n`).join(""), "utf8")
    .digest("hex");
}

function migrationSourceChainSha256(migrations) {
  return createHash("sha256")
    .update(migrations.map(({ file, sha256 }) => `${file}\t${sha256}\n`).join(""), "utf8")
    .digest("hex");
}

function evaluateSupabaseReceiptBinding({
  receipt,
  projectRef,
  sourceSha,
  expectedVersions,
  expectedVersionChainSha256,
  expectedSourceChainSha256,
}) {
  const providerDatabaseReceipt = receipt?.providerDatabaseReceipt;
  const sourceArtifactDatabaseReceipt = receipt?.sourceArtifactDatabaseReceipt;
  const artifactExternalId = String(sourceArtifactDatabaseReceipt?.externalId || "");
  const exactArtifactUrl = `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/${artifactExternalId}`;
  const sourceArtifactDatabaseReceiptPresent = sourceArtifactDatabaseReceipt?.databaseCaptured === true
    && receipt?.projectRef === projectRef
    && /^[0-9a-f]{40}$/i.test(String(sourceSha || ""))
    && sourceArtifactDatabaseReceipt.sourceSha === sourceSha
    && /^[0-9a-f]{40}$/i.test(String(sourceArtifactDatabaseReceipt.sourceTreeSha || ""))
    && /^[0-9a-f]{64}$/i.test(String(sourceArtifactDatabaseReceipt.artifactSha256 || ""))
    && /^[1-9][0-9]{0,19}$/.test(artifactExternalId)
    && sourceArtifactDatabaseReceipt.sourceUrl === exactArtifactUrl
    && sourceArtifactDatabaseReceipt.sourceChainSha256 === expectedSourceChainSha256
    && sourceArtifactDatabaseReceipt.expectedVersionChainSha256 === expectedVersionChainSha256;
  const capturedVersions = providerDatabaseReceipt?.capturedAppliedVersions;
  const providerDatabaseReceiptReadback = providerDatabaseReceipt?.databaseReadback === true
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(String(providerDatabaseReceipt.receiptId || ""))
    && Number.isFinite(Date.parse(providerDatabaseReceipt.capturedAt || ""))
    && Array.isArray(capturedVersions)
    && capturedVersions.length === expectedVersions.length
    && capturedVersions.every((version, index) => version === expectedVersions[index])
    && providerDatabaseReceipt.capturedVersionChainSha256 === expectedVersionChainSha256;
  return {
    sourceArtifactDatabaseReceiptPresent,
    providerDatabaseReceiptReadback,
    sourceArtifactBoundToCapturedVersions: sourceArtifactDatabaseReceiptPresent
      && providerDatabaseReceiptReadback,
  };
}

async function readCanonicalReleaseEvidence({ env, fetchFn }) {
  const token = oidcToken(env);
  if (!token) throw new Error("oidc unavailable");
  const sourceSha = env.VERCEL_GIT_COMMIT_SHA?.trim();
  if (!/^[0-9a-f]{40}$/i.test(String(sourceSha || ""))) throw new Error("runtime source SHA unavailable");
  const payload = await boundedJson(
    env.MCPMASTER_SUPABASE_CONTROL_URL || DEFAULT_CONTROL_URL,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        action: "canonical_release_status",
        repository: CANONICAL_REPOSITORY,
        sourceSha,
      }),
    },
    fetchFn,
  );
  if (payload?.ok !== true || !payload.releaseEvidence || typeof payload.releaseEvidence !== "object") {
    throw new Error("canonical release evidence unavailable");
  }
  return payload.releaseEvidence;
}

function latestCheckByIdentity(checkRuns) {
  const latest = new Map();
  for (const check of checkRuns) {
    if (!check
      || typeof check.name !== "string"
      || !Number.isInteger(check.app?.id)
      || check.app.id <= 0) continue;
    const identity = `${check.name}:${check.app.id}`;
    const current = latest.get(identity);
    const candidateTime = Date.parse(check.completed_at || check.started_at || "") || 0;
    const currentTime = Date.parse(current?.completed_at || current?.started_at || "") || 0;
    if (!current || candidateTime >= currentTime) latest.set(identity, check);
  }
  return latest;
}

function missingSourceArtifactProviderReadback(reason) {
  return {
    verified: false,
    provider: "github",
    reason,
  };
}

function missingMobileArtifactProviderReadback(reason) {
  return {
    verified: false,
    provider: "github",
    reason,
  };
}

async function readSourceArtifactProviderReadback({
  origin,
  headers,
  fetchFn,
  releaseEvidence,
  mainSha,
  mainTreeSha,
  canonicalCheck,
}) {
  const receipt = releaseEvidence?.supabase?.sourceArtifactDatabaseReceipt;
  const databaseReceipt = releaseEvidence?.supabase?.providerDatabaseReceipt;
  const artifactId = String(receipt?.externalId || "");
  const artifactSha256 = String(receipt?.artifactSha256 || "");
  const artifactUrl = `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/${artifactId}`;
  const receiptCapturedAt = Date.parse(databaseReceipt?.capturedAt || "");
  if (receipt?.databaseCaptured !== true
    || databaseReceipt?.databaseReadback !== true
    || !/^[1-9][0-9]{0,19}$/.test(artifactId)
    || !/^[0-9a-f]{64}$/.test(artifactSha256)
    || receipt.sourceUrl !== artifactUrl
    || receipt.sourceSha !== mainSha
    || receipt.sourceTreeSha !== mainTreeSha
    || !Number.isFinite(receiptCapturedAt)
    || !canonicalCheck
    || !Number.isSafeInteger(canonicalCheck.id)
    || canonicalCheck.id <= 0
    || canonicalCheck.name !== "canonical-release-source-contract"
    || canonicalCheck.app?.id !== GITHUB_ACTIONS_APP_ID
    || canonicalCheck.head_sha !== mainSha
    || canonicalCheck.status !== "completed"
    || canonicalCheck.conclusion !== "success") {
    return missingSourceArtifactProviderReadback("receipt_or_exact_check_missing");
  }

  try {
    if (new URL(origin).origin !== "https://api.github.com") {
      return missingSourceArtifactProviderReadback("noncanonical_github_api_origin");
    }
    const artifact = await boundedJson(artifactUrl, { headers }, fetchFn, 3_000);
    const workflowRunId = artifact?.workflow_run?.id;
    const artifactCreatedAt = Date.parse(artifact?.created_at || "");
    const artifactExpiresAt = Date.parse(artifact?.expires_at || "");
    if (String(artifact?.id || "") !== artifactId
      || artifact?.url !== artifactUrl
      || artifact?.name !== `canonical-release-source-${mainSha}`
      || artifact?.expired !== false
      || artifact?.digest !== `sha256:${artifactSha256}`
      || !Number.isFinite(artifactCreatedAt)
      || !Number.isFinite(artifactExpiresAt)
      || artifactCreatedAt >= artifactExpiresAt
      || artifactCreatedAt > receiptCapturedAt
      || artifactExpiresAt <= Date.now()
      || !Number.isSafeInteger(workflowRunId)
      || workflowRunId <= 0
      || artifact.workflow_run.head_sha !== mainSha
      || artifact.workflow_run.head_branch !== "main"
      || !Number.isSafeInteger(artifact.workflow_run.repository_id)
      || artifact.workflow_run.repository_id !== artifact.workflow_run.head_repository_id) {
      return missingSourceArtifactProviderReadback("artifact_identity_mismatch");
    }

    const run = await boundedJson(
      `${origin}/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/${workflowRunId}`,
      { headers },
      fetchFn,
      3_000,
    );
    const runAttempt = run?.run_attempt;
    const runCompletedAt = Date.parse(run?.updated_at || "");
    if (run?.id !== workflowRunId
      || run?.event !== "push"
      || run?.head_branch !== "main"
      || run?.head_sha !== mainSha
      || run?.head_commit?.id !== mainSha
      || run?.head_commit?.tree_id !== mainTreeSha
      || run?.status !== "completed"
      || run?.conclusion !== "success"
      || !exactMainWorkflowPath(run?.path, ".github/workflows/canonical-release-evidence.yml")
      || !Number.isSafeInteger(run?.workflow_id)
      || run.workflow_id <= 0
      || !Number.isSafeInteger(run?.check_suite_id)
      || run.check_suite_id <= 0
      || !Number.isSafeInteger(runAttempt)
      || runAttempt <= 0
      || !Number.isFinite(runCompletedAt)
      || runCompletedAt < artifactCreatedAt
      || runCompletedAt > receiptCapturedAt
      || run?.repository?.full_name?.toLowerCase() !== CANONICAL_REPOSITORY.toLowerCase()
      || run?.head_repository?.full_name?.toLowerCase() !== CANONICAL_REPOSITORY.toLowerCase()
      || run.repository.id !== artifact.workflow_run.repository_id
      || run.head_repository.id !== artifact.workflow_run.head_repository_id) {
      return missingSourceArtifactProviderReadback("workflow_run_identity_mismatch");
    }

    const jobs = await boundedJson(
      `${origin}/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/${workflowRunId}`
        + `/attempts/${runAttempt}/jobs?per_page=100`,
      { headers },
      fetchFn,
      3_000,
    );
    const canonicalJobs = Array.isArray(jobs?.jobs)
      ? jobs.jobs.filter((job) => job?.name === "canonical-release-source-contract")
      : [];
    const job = canonicalJobs[0];
    const expectedCheckUrl = `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/check-runs/${canonicalCheck.id}`;
    if (jobs?.total_count !== 1
      || canonicalJobs.length !== 1
      || !Number.isSafeInteger(job?.id)
      || job.id <= 0
      || job?.run_id !== workflowRunId
      || job?.head_sha !== mainSha
      || job?.status !== "completed"
      || job?.conclusion !== "success"
      || job?.check_run_url !== expectedCheckUrl) {
      return missingSourceArtifactProviderReadback("workflow_job_identity_mismatch");
    }

    const linkedCheck = await boundedJson(job.check_run_url, { headers }, fetchFn, 3_000);
    if (linkedCheck?.id !== canonicalCheck.id
      || linkedCheck?.url !== job.check_run_url
      || linkedCheck?.name !== "canonical-release-source-contract"
      || linkedCheck?.app?.id !== GITHUB_ACTIONS_APP_ID
      || linkedCheck?.head_sha !== mainSha
      || linkedCheck?.status !== "completed"
      || linkedCheck?.conclusion !== "success"
      || linkedCheck?.check_suite?.id !== run.check_suite_id
      || canonicalCheck?.check_suite?.id !== linkedCheck.check_suite.id) {
      return missingSourceArtifactProviderReadback("workflow_job_check_identity_mismatch");
    }

    return {
      verified: true,
      provider: "github",
      observedAt: new Date().toISOString(),
      artifactId,
      artifactUrl,
      artifactName: artifact.name,
      artifactSha256,
      artifactCreatedAt: artifact.created_at,
      artifactExpiresAt: artifact.expires_at,
      runId: workflowRunId,
      runAttempt,
      runCompletedAt: run.updated_at,
      workflowId: run.workflow_id,
      workflowPath: ".github/workflows/canonical-release-evidence.yml",
      workflowRunPath: run.path,
      event: run.event,
      jobId: job.id,
      checkRunId: linkedCheck.id,
      checkSuiteId: run.check_suite_id,
      sourceSha: mainSha,
      sourceTreeSha: mainTreeSha,
      receiptCapturedAt: databaseReceipt.capturedAt,
    };
  } catch {
    return missingSourceArtifactProviderReadback("provider_read_unavailable");
  }
}

async function readMobileArtifactProviderReadback({
  origin,
  headers,
  fetchFn,
  releaseEvidence,
  mainSha,
  mainTreeSha,
  mobileCheck,
}) {
  const receipt = releaseEvidence?.android?.ciArtifactDatabaseReceipt;
  const artifactId = String(receipt?.externalId || "");
  const artifactSha256 = String(receipt?.artifactSha256 || "");
  const apkSha256 = String(receipt?.apkSha256 || "");
  const artifactName = `pandora-mobile-android-validation-${mainSha}`;
  const artifactUrl = `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/${artifactId}`;
  const receiptCapturedAt = Date.parse(receipt?.capturedAt || "");
  if (receipt?.databaseCaptured !== true
    || !/^[1-9][0-9]{0,19}$/.test(artifactId)
    || !/^[0-9a-f]{64}$/.test(artifactSha256)
    || !/^[0-9a-f]{64}$/.test(apkSha256)
    || receipt.sourceUrl !== artifactUrl
    || receipt.artifactName !== artifactName
    || receipt.sourceSha !== mainSha
    || receipt.sourceTreeSha !== mainTreeSha
    || receipt.productionOrigin !== "https://mcpmaster.vercel.app"
    || !Number.isFinite(receiptCapturedAt)
    || !mobileCheck
    || !Number.isSafeInteger(mobileCheck.id)
    || mobileCheck.id <= 0
    || mobileCheck.name !== "Exact source / Flutter / Android"
    || mobileCheck.app?.id !== GITHUB_ACTIONS_APP_ID
    || mobileCheck.head_sha !== mainSha
    || mobileCheck.status !== "completed"
    || mobileCheck.conclusion !== "success") {
    return missingMobileArtifactProviderReadback("receipt_or_exact_check_missing");
  }

  try {
    if (new URL(origin).origin !== "https://api.github.com") {
      return missingMobileArtifactProviderReadback("noncanonical_github_api_origin");
    }
    const artifact = await boundedJson(artifactUrl, { headers }, fetchFn, 3_000);
    const workflowRunId = artifact?.workflow_run?.id;
    const artifactCreatedAt = Date.parse(artifact?.created_at || "");
    const artifactExpiresAt = Date.parse(artifact?.expires_at || "");
    if (String(artifact?.id || "") !== artifactId
      || artifact?.url !== artifactUrl
      || artifact?.name !== artifactName
      || artifact?.expired !== false
      || artifact?.digest !== `sha256:${artifactSha256}`
      || !Number.isFinite(artifactCreatedAt)
      || !Number.isFinite(artifactExpiresAt)
      || artifactCreatedAt >= artifactExpiresAt
      || artifactCreatedAt > receiptCapturedAt
      || artifactExpiresAt <= Date.now()
      || !Number.isSafeInteger(workflowRunId)
      || workflowRunId <= 0
      || artifact.workflow_run.head_sha !== mainSha
      || artifact.workflow_run.head_branch !== "main"
      || !Number.isSafeInteger(artifact.workflow_run.repository_id)
      || artifact.workflow_run.repository_id !== artifact.workflow_run.head_repository_id) {
      return missingMobileArtifactProviderReadback("artifact_identity_mismatch");
    }

    const run = await boundedJson(
      `${origin}/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/${workflowRunId}`,
      { headers },
      fetchFn,
      3_000,
    );
    const runAttempt = run?.run_attempt;
    const runCompletedAt = Date.parse(run?.updated_at || "");
    if (run?.id !== workflowRunId
      || run?.event !== "push"
      || run?.head_branch !== "main"
      || run?.head_sha !== mainSha
      || run?.head_commit?.id !== mainSha
      || run?.head_commit?.tree_id !== mainTreeSha
      || run?.status !== "completed"
      || run?.conclusion !== "success"
      || !exactMainWorkflowPath(run?.path, ".github/workflows/pandora-mobile-integration.yml")
      || !Number.isSafeInteger(run?.workflow_id)
      || run.workflow_id <= 0
      || !Number.isSafeInteger(run?.check_suite_id)
      || run.check_suite_id <= 0
      || !Number.isSafeInteger(runAttempt)
      || runAttempt <= 0
      || !Number.isFinite(runCompletedAt)
      || runCompletedAt < artifactCreatedAt
      || runCompletedAt > receiptCapturedAt
      || run?.repository?.full_name?.toLowerCase() !== CANONICAL_REPOSITORY.toLowerCase()
      || run?.head_repository?.full_name?.toLowerCase() !== CANONICAL_REPOSITORY.toLowerCase()
      || run.repository.id !== artifact.workflow_run.repository_id
      || run.head_repository.id !== artifact.workflow_run.head_repository_id) {
      return missingMobileArtifactProviderReadback("workflow_run_identity_mismatch");
    }

    const jobs = await boundedJson(
      `${origin}/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/${workflowRunId}`
        + `/attempts/${runAttempt}/jobs?per_page=100`,
      { headers },
      fetchFn,
      3_000,
    );
    const mobileJobs = Array.isArray(jobs?.jobs)
      ? jobs.jobs.filter((job) => job?.name === "Exact source / Flutter / Android")
      : [];
    const job = mobileJobs[0];
    const expectedCheckUrl = `https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/check-runs/${mobileCheck.id}`;
    if (jobs?.total_count !== 1
      || mobileJobs.length !== 1
      || !Number.isSafeInteger(job?.id)
      || job.id <= 0
      || job?.run_id !== workflowRunId
      || job?.head_sha !== mainSha
      || job?.status !== "completed"
      || job?.conclusion !== "success"
      || job?.check_run_url !== expectedCheckUrl) {
      return missingMobileArtifactProviderReadback("workflow_job_identity_mismatch");
    }

    const linkedCheck = await boundedJson(job.check_run_url, { headers }, fetchFn, 3_000);
    if (linkedCheck?.id !== mobileCheck.id
      || linkedCheck?.url !== job.check_run_url
      || linkedCheck?.name !== "Exact source / Flutter / Android"
      || linkedCheck?.app?.id !== GITHUB_ACTIONS_APP_ID
      || linkedCheck?.head_sha !== mainSha
      || linkedCheck?.status !== "completed"
      || linkedCheck?.conclusion !== "success"
      || linkedCheck?.check_suite?.id !== run.check_suite_id
      || mobileCheck?.check_suite?.id !== linkedCheck.check_suite.id) {
      return missingMobileArtifactProviderReadback("workflow_job_check_identity_mismatch");
    }

    return {
      verified: true,
      provider: "github",
      observedAt: new Date().toISOString(),
      artifactId,
      artifactUrl,
      artifactName,
      artifactSha256,
      apkSha256,
      artifactCreatedAt: artifact.created_at,
      artifactExpiresAt: artifact.expires_at,
      runId: workflowRunId,
      runAttempt,
      runCompletedAt: run.updated_at,
      workflowId: run.workflow_id,
      workflowPath: ".github/workflows/pandora-mobile-integration.yml",
      workflowRunPath: run.path,
      event: run.event,
      jobId: job.id,
      checkRunId: linkedCheck.id,
      checkSuiteId: run.check_suite_id,
      sourceSha: mainSha,
      sourceTreeSha: mainTreeSha,
      productionOrigin: receipt.productionOrigin,
      receiptCapturedAt: receipt.capturedAt,
    };
  } catch {
    return missingMobileArtifactProviderReadback("provider_read_unavailable");
  }
}

async function readGitHubStatus({ env, fetchFn, resolver, releaseEvidence }) {
  const token = oidcToken(env);
  if (!token) throw new Error("oidc unavailable");
  const account = await resolver.resolve(token, env.MCPMASTER_GITHUB_ACCOUNT_ID);
  if (!account.allowedRepositories.some((value) => value.toLowerCase() === CANONICAL_REPOSITORY.toLowerCase())) {
    throw new Error("canonical repository is not allowlisted");
  }
  const [owner, repo] = CANONICAL_REPOSITORY.split("/");
  const origin = account.baseUrl || "https://api.github.com";
  const headers = {
    authorization: `Bearer ${account.token}`,
    accept: "application/vnd.github+json",
    "x-github-api-version": "2022-11-28",
    "user-agent": "Pandoras-Box-Canonical-Status/1.0",
  };
  const branch = await boundedJson(`${origin}/repos/${owner}/${repo}/branches/main`, { headers }, fetchFn);
  const mainSha = branch?.commit?.sha;
  const mainTreeSha = branch?.commit?.commit?.tree?.sha;
  if (!/^[0-9a-f]{40}$/i.test(String(mainSha || ""))
    || !/^[0-9a-f]{40}$/i.test(String(mainTreeSha || ""))) throw new Error("invalid main source identity");
  const [pulls, checks, protection, workflowRuns] = await Promise.all([
    readAllGitHubPulls({ origin, owner, repo, headers, fetchFn }),
    boundedJson(`${origin}/repos/${owner}/${repo}/commits/${mainSha}/check-runs?per_page=100`, { headers }, fetchFn),
    boundedJson(`${origin}/repos/${owner}/${repo}/branches/main/protection`, { headers }, fetchFn),
    boundedJson(`${origin}/repos/${owner}/${repo}/actions/runs?head_sha=${mainSha}&per_page=100`, { headers }, fetchFn),
  ]);
  if (!Array.isArray(pulls)
    || !Array.isArray(checks?.check_runs)
    || !Array.isArray(workflowRuns?.workflow_runs)) throw new Error("invalid GitHub status response");
  const protectedChecks = protection?.required_status_checks?.checks || [];
  const protectedChecksWellFormed = Array.isArray(protectedChecks)
    && protectedChecks.length > 0
    && protectedChecks.every((entry) => typeof entry?.context === "string"
      && entry.context.length > 0
      && Number.isInteger(entry.app_id)
      && entry.app_id > 0);
  const externalReviewAppId = trustedExternalReviewAppId(env);
  const trustedExternalReviewConfigured = externalReviewAppId !== null;
  const expectedProtectionIdentities = new Map(
    REQUIRED_CHECK_BINDINGS.map(({ providerContext, appId }) => [providerContext, appId]),
  );
  const protectionHasExactIdentities = protectedChecksWellFormed
    && trustedExternalReviewConfigured
    && protectedChecks.length === REQUIRED_CHECK_BINDINGS.length
    && protectedChecks.every((entry) => expectedProtectionIdentities.get(entry.context) === entry.app_id)
    && REQUIRED_CHECK_BINDINGS.every(({ providerContext, appId }) => protectedChecks.some(
      (entry) => entry?.context === providerContext
        && entry?.app_id === appId,
    ));
  const repositoryProtectionIdentitiesPresent = protectedChecksWellFormed
    && REPOSITORY_CHECK_IDENTITIES.every((name) => protectedChecks.some(
      (entry) => entry?.context === name && entry?.app_id === GITHUB_ACTIONS_APP_ID,
    ));
  const reviews = protection?.required_pull_request_reviews;
  const bypass = reviews?.bypass_pull_request_allowances;
  const bypassEmpty = bypass && ["users", "teams", "apps"].every(
    (key) => Array.isArray(bypass[key]) && bypass[key].length === 0,
  );
  const protectedMainPolicyExact = protection?.required_status_checks?.strict === true
    && protectionHasExactIdentities
    && Number.isSafeInteger(reviews?.required_approving_review_count)
    && reviews.required_approving_review_count >= 1
    && reviews.dismiss_stale_reviews === true
    && reviews.require_last_push_approval === true
    && bypassEmpty === true
    && protection?.required_conversation_resolution?.enabled === true
    && protection?.enforce_admins?.enabled === true
    && protection?.allow_force_pushes?.enabled === false
    && protection?.allow_deletions?.enabled === false;
  const latestChecks = latestCheckByIdentity(checks.check_runs);
  const protectedWorkflowBindingsExact = repositoryProtectionIdentitiesPresent
    && REPOSITORY_CHECK_IDENTITIES.every((name) => {
      const expectedPath = REQUIRED_CHECK_WORKFLOW_PATHS[name];
      const check = latestChecks.get(`${name}:${GITHUB_ACTIONS_APP_ID}`);
      if (!expectedPath
        || !Number.isSafeInteger(check?.check_suite?.id)
        || check.check_suite.id <= 0) return false;
      const matchingRuns = workflowRuns.workflow_runs.filter((run) => (
        run?.check_suite_id === check.check_suite.id
        && exactMainWorkflowPath(run?.path, expectedPath)
        && run?.head_sha === mainSha
        && run?.head_branch === "main"
        && run?.event === "push"
        && run?.status === "completed"
        && run?.conclusion === "success"
        && run?.repository?.full_name?.toLowerCase() === CANONICAL_REPOSITORY.toLowerCase()
        && run?.head_repository?.full_name?.toLowerCase() === CANONICAL_REPOSITORY.toLowerCase()
      ));
      return matchingRuns.length === 1;
    });
  const repositoryConclusions = REPOSITORY_CHECK_IDENTITIES.map((name) => {
    const check = latestChecks.get(`${name}:${GITHUB_ACTIONS_APP_ID}`);
    return check?.head_sha === mainSha ? check.conclusion || "missing" : "missing";
  });
  const exactIntegrationChecks = repositoryProtectionIdentitiesPresent
    && protectedWorkflowBindingsExact
    && repositoryConclusions.every((value) => value === "success")
    ? "success"
    : repositoryConclusions.some((value) => value === "failure" || value === "cancelled" || value === "timed_out")
      ? "failure"
      : "pending_or_missing";
  const trustedExternalReviewCheck = trustedExternalReviewConfigured
    ? latestChecks.get(`${TRUSTED_EXTERNAL_REVIEW_PROVIDER_CONTEXT}:${externalReviewAppId}`)
    : null;
  const trustedExternalReviewVerified = protectionHasExactIdentities
    && trustedExternalReviewCheck?.app?.id === externalReviewAppId
    && typeof trustedExternalReviewCheck?.app?.slug === "string"
    && trustedExternalReviewCheck.app.slug.length > 0
    && trustedExternalReviewCheck.app.slug !== "github-actions"
    && trustedExternalReviewCheck.head_sha === mainSha
    && trustedExternalReviewCheck.status === "completed"
    && trustedExternalReviewCheck.conclusion === "success"
    && trustedExternalReviewCheck.output?.title === "Review Complete";
  const [sourceArtifactProviderReadback, mobileArtifactProviderReadback] = await Promise.all([
    readSourceArtifactProviderReadback({
      origin,
      headers,
      fetchFn,
      releaseEvidence,
      mainSha,
      mainTreeSha,
      canonicalCheck: latestChecks.get(`canonical-release-source-contract:${GITHUB_ACTIONS_APP_ID}`),
    }),
    readMobileArtifactProviderReadback({
      origin,
      headers,
      fetchFn,
      releaseEvidence,
      mainSha,
      mainTreeSha,
      mobileCheck: latestChecks.get(`Exact source / Flutter / Android:${GITHUB_ACTIONS_APP_ID}`),
    }),
  ]);
  const observedHeads = new Map(pulls.map((pull) => [pull.number, pull.head?.sha]));
  const triageInventoryCount = triage.decisions
    .filter((decision) => observedHeads.has(decision.number)).length;
  const triageExactHeadMatches = triageInventoryCount === triage.total
    && triage.decisions.every((decision) => observedHeads.get(decision.number) === decision.headSha);
  return {
    ok: true,
    observedAt: new Date().toISOString(),
    repository: CANONICAL_REPOSITORY,
    mainSha,
    mainTreeSha,
    openPullRequestCount: pulls.filter((pull) => pull.state === "open").length,
    triageInventoryCount,
    triageExactHeadMatches,
    requiredChecks: protectedChecks.map((entry) => {
      const binding = REQUIRED_CHECK_BINDINGS.find(
        ({ providerContext, appId }) => providerContext === entry.context && appId === entry.app_id,
      );
      return {
        name: binding?.name || entry.context,
        providerContext: entry.context,
        appId: entry.app_id,
      };
    }),
    protectionHasExactCheckIdentities: protectionHasExactIdentities,
    protectedMainPolicyExact,
    protectedMainPolicy: {
      strictRequiredChecks: protection?.required_status_checks?.strict === true,
      approvingReviewCount: Number.isSafeInteger(reviews?.required_approving_review_count)
        ? reviews.required_approving_review_count
        : null,
      dismissStaleReviews: reviews?.dismiss_stale_reviews === true,
      requireLastPushApproval: reviews?.require_last_push_approval === true,
      bypassAllowancesEmpty: bypassEmpty === true,
      conversationResolution: protection?.required_conversation_resolution?.enabled === true,
      enforceAdmins: protection?.enforce_admins?.enabled === true,
      forcePushesDisabled: protection?.allow_force_pushes?.enabled === false,
      deletionsDisabled: protection?.allow_deletions?.enabled === false,
    },
    protectedWorkflowBindingsExact,
    exactIntegrationChecks,
    trustedExternalReviewConfigured,
    trustedExternalReviewAppId: externalReviewAppId,
    trustedExternalReviewProviderContext: TRUSTED_EXTERNAL_REVIEW_PROVIDER_CONTEXT,
    trustedExternalReviewVerified,
    sourceArtifactProviderReadback,
    mobileArtifactProviderReadback,
  };
}

async function readMemoryStatus({ env, fetchFn }) {
  const token = oidcToken(env);
  if (!token) throw new Error("oidc unavailable");
  const memory = new PandoraMemoryMCPServer({
    baseUrl: env.PANDORA_MEMORY_BASE_URL || DEFAULT_MEMORY_ORIGIN,
    oidcToken: token,
    allowedNamespaces: ["real_life"],
    grantedScopes: ["memory:health", "memory:read"],
  }, fetchFn);
  const [health, context] = await Promise.all([
    memory.health(),
    memory.canonicalContext({
      namespace: "real_life",
      projectKey: "mcpmaster-pandoras-box",
      query: "Pandoras-box current source status deployment rollback blockers and next action",
      currentTask: "Generate the canonical status pack",
      maxItems: 25,
      maxAgeMs: 24 * 60 * 60 * 1000,
      includeProposed: false,
    }),
  ]);
  return {
    ok: true,
    observedAt: new Date().toISOString(),
    healthStatus: health.status,
    authentication: health.authentication,
    contextState: context.degraded ? "degraded" : "healthy",
    fresh: !context.degraded,
    approvedRecordIds: (context.canonical || []).map((record) => record.id),
    freshestRecordAt: context.freshestRecordAt || null,
    conflicts: (context.conflicts || []).map((conflict) => ({
      subject: conflict.subject,
      reason: conflict.reason,
    })),
  };
}

async function readSupabaseStatus({ env, fetchFn, resolver, releaseEvidence }) {
  const token = oidcToken(env);
  if (!token) throw new Error("oidc unavailable");
  const configuration = await resolver.resolve(token);
  const projectRef = env.MCPMASTER_SUPABASE_PROJECT_REF || DEFAULT_SUPABASE_PROJECT_REF;
  const account = configuration.accounts.find((candidate) => candidate.allowedProjectRefs.includes(projectRef));
  if (!account) throw new Error("canonical Supabase project is not allowlisted");
  const server = new SupabaseMCPServer(configuration, fetchFn);
  const [project, applied] = await Promise.all([
    server.getProject(account.id, projectRef),
    server.listMigrations(account.id, projectRef),
  ]);
  const expectedManifest = expectedMigrationManifest();
  const expectedVersions = expectedManifest.map(({ version }) => version);
  const appliedVersions = applied.map((migration) => migration.version);
  const exactOrderedMatch = appliedVersions.length === expectedVersions.length
    && appliedVersions.every((version, index) => version === expectedVersions[index]);
  const expectedVersionChainSha256 = migrationVersionChainSha256(expectedVersions);
  const appliedVersionChainSha256 = migrationVersionChainSha256(appliedVersions);
  const expectedSourceChainSha256 = migrationSourceChainSha256(expectedManifest);
  const receipt = releaseEvidence?.supabase && typeof releaseEvidence.supabase === "object"
    ? releaseEvidence.supabase
    : {};
  const runtimeSourceSha = env.VERCEL_GIT_COMMIT_SHA?.trim() || null;
  const binding = evaluateSupabaseReceiptBinding({
    receipt,
    projectRef,
    sourceSha: runtimeSourceSha,
    expectedVersions,
    expectedVersionChainSha256,
    expectedSourceChainSha256,
  });
  const sourceArtifactBoundToLiveVersions = exactOrderedMatch
    && binding.sourceArtifactBoundToCapturedVersions
    && receipt.providerDatabaseReceipt.capturedVersionChainSha256 === appliedVersionChainSha256;
  return {
    ok: true,
    observedAt: new Date().toISOString(),
    projectRef,
    projectStatus: project.status || "UNKNOWN",
    managementApiVersionReadback: true,
    providerDatabaseReceiptReadback: binding.providerDatabaseReceiptReadback,
    sourceArtifactDatabaseReceiptPresent: binding.sourceArtifactDatabaseReceiptPresent,
    sourceArtifactBoundToLiveVersions,
    exactAppliedBytesProven: false,
    providerReadback: false,
    sourceSha: binding.sourceArtifactDatabaseReceiptPresent ? runtimeSourceSha : null,
    migrationVersionParity: exactOrderedMatch ? "match" : "mismatch",
    migrationByteParity: "not_provider_reconstructable",
    migrationParity: sourceArtifactBoundToLiveVersions
      ? "source_artifact_bound_to_live_versions"
      : exactOrderedMatch
        ? "receipt_missing_or_mismatched"
        : "mismatch",
    expectedMigrationCount: expectedVersions.length,
    appliedMigrationCount: appliedVersions.length,
    expectedAppliedChainSha256: expectedVersionChainSha256,
    appliedChainSha256: appliedVersionChainSha256,
    expectedSourceChainSha256,
    sourceArtifactChainSha256: binding.sourceArtifactDatabaseReceiptPresent
      ? receipt.sourceArtifactDatabaseReceipt.sourceChainSha256
      : null,
    sourceArtifactExternalId: binding.sourceArtifactDatabaseReceiptPresent
      ? String(receipt.sourceArtifactDatabaseReceipt.externalId)
      : null,
    sourceArtifactSha256: binding.sourceArtifactDatabaseReceiptPresent
      ? receipt.sourceArtifactDatabaseReceipt.artifactSha256
      : null,
    sourceArtifactSourceTreeSha: binding.sourceArtifactDatabaseReceiptPresent
      ? receipt.sourceArtifactDatabaseReceipt.sourceTreeSha
      : null,
    providerDatabaseCapturedVersionChainSha256: binding.providerDatabaseReceiptReadback
      ? receipt.providerDatabaseReceipt.capturedVersionChainSha256
      : null,
    providerSourceChainSha256: null,
  };
}

async function readVercelRuntimeStatus({ env, releaseEvidence }) {
  const gitRepository = env.VERCEL_GIT_REPO_OWNER && env.VERCEL_GIT_REPO_SLUG
    ? `${env.VERCEL_GIT_REPO_OWNER}/${env.VERCEL_GIT_REPO_SLUG}`
    : null;
  const receipt = releaseEvidence?.vercel && typeof releaseEvidence.vercel === "object"
    ? releaseEvidence.vercel
    : {};
  const runtimeDeploymentId = env.VERCEL_DEPLOYMENT_ID || null;
  const runtimeSourceSha = env.VERCEL_GIT_COMMIT_SHA || null;
  const runtimeRepository = gitRepository;
  const receiptMatchesRuntime = receipt.deploymentId === runtimeDeploymentId
    && receipt.sourceSha === runtimeSourceSha
    && receipt.gitRepository === runtimeRepository;
  return {
    ok: true,
    observedAt: new Date().toISOString(),
    projectId: env.VERCEL_PROJECT_ID || null,
    deploymentId: runtimeDeploymentId,
    deploymentUrl: env.VERCEL_URL ? `https://${env.VERCEL_URL}` : null,
    productionUrl: env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${env.VERCEL_PROJECT_PRODUCTION_URL}` : null,
    sourceSha: runtimeSourceSha,
    gitRepository,
    gitBranch: env.VERCEL_GIT_COMMIT_REF || null,
    rollbackDeploymentId: receiptMatchesRuntime ? receipt.rollbackDeploymentId || null : null,
    rollbackSourceSha: receiptMatchesRuntime ? receipt.rollbackSourceSha || null : null,
    rollbackVerified: receiptMatchesRuntime && receipt.rollbackVerified === true,
    rollbackVerifiedCandidateDeploymentId: receiptMatchesRuntime
      ? receipt.rollbackVerifiedCandidateDeploymentId || null
      : null,
    rollbackRestoredDeploymentId: receiptMatchesRuntime
      ? receipt.rollbackRestoredDeploymentId || null
      : null,
    productionObservedAt: receiptMatchesRuntime ? receipt.productionObservedAt || null : null,
    rollbackTransitionEvidenceId: receiptMatchesRuntime
      ? receipt.rollbackTransitionEvidenceId || null
      : null,
    rollbackTransitionExternalId: receiptMatchesRuntime
      ? receipt.rollbackTransitionExternalId || null
      : null,
    rollbackTransitionSourceUrl: receiptMatchesRuntime
      ? receipt.rollbackTransitionSourceUrl || null
      : null,
    rollbackTransitionAliasSourceUrl: receiptMatchesRuntime
      ? receipt.rollbackTransitionAliasSourceUrl || null
      : null,
    rollbackTransitionAliasPreResponseSha256: receiptMatchesRuntime
      ? receipt.rollbackTransitionAliasPreResponseSha256 || null
      : null,
    rollbackTransitionAliasPreObservedAt: receiptMatchesRuntime
      ? receipt.rollbackTransitionAliasPreObservedAt || null
      : null,
    rollbackTransitionAliasPostResponseSha256: receiptMatchesRuntime
      ? receipt.rollbackTransitionAliasPostResponseSha256 || null
      : null,
    rollbackTransitionAliasPostObservedAt: receiptMatchesRuntime
      ? receipt.rollbackTransitionAliasPostObservedAt || null
      : null,
    rollbackTransitionRouteProbeContract: receiptMatchesRuntime
      ? receipt.rollbackTransitionRouteProbeContract || null
      : null,
    rollbackTransitionRouteProbeSha256: receiptMatchesRuntime
      ? receipt.rollbackTransitionRouteProbeSha256 || null
      : null,
    rollbackTransitionRouteProbeObservedAt: receiptMatchesRuntime
      ? receipt.rollbackTransitionRouteProbeObservedAt || null
      : null,
    rollbackTransitionObservedAt: receiptMatchesRuntime
      ? receipt.rollbackTransitionObservedAt || null
      : null,
    rollbackRestorationEvidenceId: receiptMatchesRuntime
      ? receipt.rollbackRestorationEvidenceId || null
      : null,
    rollbackRestorationExternalId: receiptMatchesRuntime
      ? receipt.rollbackRestorationExternalId || null
      : null,
    rollbackRestorationSourceUrl: receiptMatchesRuntime
      ? receipt.rollbackRestorationSourceUrl || null
      : null,
    rollbackRestorationAliasSourceUrl: receiptMatchesRuntime
      ? receipt.rollbackRestorationAliasSourceUrl || null
      : null,
    rollbackRestorationAliasPreResponseSha256: receiptMatchesRuntime
      ? receipt.rollbackRestorationAliasPreResponseSha256 || null
      : null,
    rollbackRestorationAliasPreObservedAt: receiptMatchesRuntime
      ? receipt.rollbackRestorationAliasPreObservedAt || null
      : null,
    rollbackRestorationAliasPostResponseSha256: receiptMatchesRuntime
      ? receipt.rollbackRestorationAliasPostResponseSha256 || null
      : null,
    rollbackRestorationAliasPostObservedAt: receiptMatchesRuntime
      ? receipt.rollbackRestorationAliasPostObservedAt || null
      : null,
    rollbackRestorationRouteProbeContract: receiptMatchesRuntime
      ? receipt.rollbackRestorationRouteProbeContract || null
      : null,
    rollbackRestorationRouteProbeSha256: receiptMatchesRuntime
      ? receipt.rollbackRestorationRouteProbeSha256 || null
      : null,
    rollbackRestorationRouteProbeObservedAt: receiptMatchesRuntime
      ? receipt.rollbackRestorationRouteProbeObservedAt || null
      : null,
    rollbackRestorationObservedAt: receiptMatchesRuntime
      ? receipt.rollbackRestorationObservedAt || null
      : null,
    productionAlias: receiptMatchesRuntime ? receipt.productionAlias || null : null,
    productionAliasSourceUrl: receiptMatchesRuntime ? receipt.productionAliasSourceUrl || null : null,
    productionAliasLiveRead: receiptMatchesRuntime && receipt.productionAliasLiveRead === true,
    productionTarget: receiptMatchesRuntime ? receipt.productionTarget || null : null,
    providerReadback: receiptMatchesRuntime && receipt.providerReadback === true,
    productionVerified: receiptMatchesRuntime && receipt.productionVerified === true,
    productionVerifiedDeploymentId: receiptMatchesRuntime
      ? receipt.productionVerifiedDeploymentId || null
      : null,
  };
}

async function readPhysicalAndroidStatus({ releaseEvidence }) {
  const receipt = releaseEvidence?.android;
  if (!receipt || typeof receipt !== "object") throw new Error("physical Android receipt unavailable");
  return { ...receipt, ok: true };
}

async function readIndependentReviewStatus({ releaseEvidence }) {
  const receipt = releaseEvidence?.independentReview;
  if (!receipt || typeof receipt !== "object") throw new Error("independent review receipt unavailable");
  return { ...receipt, ok: true };
}

async function readOwnerAuthorizationStatus({ releaseEvidence }) {
  const receipt = releaseEvidence?.ownerAuthorization;
  if (!receipt || typeof receipt !== "object") throw new Error("owner authorization receipt unavailable");
  return { ...receipt, ok: true };
}

function createCanonicalStatusProviderFromEnvironment(options = {}) {
  const env = options.env || process.env;
  const fetchFn = options.fetchFn || globalThis.fetch;
  const githubResolver = options.githubResolver || new GitHubControlResolver({ fetchFn });
  const supabaseResolver = options.supabaseResolver || new SupabaseControlResolver({ fetchFn });
  const authorityPolicySha256 = fileSha256(AUTHORITY_POLICY_PATH);
  const historicalSurfaceRegistrySha256 = fileSha256(HISTORICAL_SURFACES_PATH);
  return {
    async refresh(context = {}) {
      const refreshEnv = typeof context.vercelOidcToken === "string" && context.vercelOidcToken.trim()
        ? { ...env, VERCEL_OIDC_TOKEN: context.vercelOidcToken.trim() }
        : env;
      let releaseEvidence = null;
      try {
        releaseEvidence = await (options.releaseEvidenceReader
          ? options.releaseEvidenceReader()
          : readCanonicalReleaseEvidence({ env: refreshEnv, fetchFn }));
      } catch {
        releaseEvidence = null;
      }
      return refreshCanonicalStatusPack({
        now: options.now,
        authorityPolicySha256,
        historicalSurfaceRegistrySha256,
        triage,
        readers: {
          github: () => readGitHubStatus({
            env: refreshEnv,
            fetchFn,
            resolver: githubResolver,
            releaseEvidence,
          }),
          memory: () => readMemoryStatus({ env: refreshEnv, fetchFn }),
          supabase: () => readSupabaseStatus({ env: refreshEnv, fetchFn, resolver: supabaseResolver, releaseEvidence }),
          vercel: () => readVercelRuntimeStatus({ env: refreshEnv, releaseEvidence }),
          android: () => readPhysicalAndroidStatus({ releaseEvidence }),
          independentReview: () => readIndependentReviewStatus({ releaseEvidence }),
          ownerAuthorization: () => readOwnerAuthorizationStatus({ releaseEvidence }),
        },
      });
    },
  };
}

module.exports = {
  createCanonicalStatusProviderFromEnvironment,
  readAllGitHubPulls,
  readGitHubStatus,
  readSourceArtifactProviderReadback,
  readMobileArtifactProviderReadback,
  readMemoryStatus,
  readCanonicalReleaseEvidence,
  readPhysicalAndroidStatus,
  readIndependentReviewStatus,
  readOwnerAuthorizationStatus,
  readSupabaseStatus,
  readVercelRuntimeStatus,
  evaluateSupabaseReceiptBinding,
  expectedMigrationManifest,
  expectedMigrationVersions,
  migrationSourceChainSha256,
  migrationVersionChainSha256,
  GITHUB_ACTIONS_APP_ID,
  REQUIRED_CHECK_BINDINGS,
  REQUIRED_CHECK_IDENTITIES,
  REPOSITORY_CHECK_IDENTITIES,
  REQUIRED_CHECK_WORKFLOW_PATHS,
  TRUSTED_EXTERNAL_REVIEW_APP_ID,
  TRUSTED_EXTERNAL_REVIEW_APP_ID_ENV,
  TRUSTED_EXTERNAL_REVIEW_PROVIDER_CONTEXT,
};
