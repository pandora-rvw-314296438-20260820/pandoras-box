const CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const REPOSITORY_ID = 1345495177;
const RULESET_ID = 21532267;
const RULE_CONTEXT = "Pandora coordinator / integration";
const INTEGRATION_APP_ID = 4785021;
const SPREADSHEET_ID = "1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0";
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const TOKEN = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{2,191}$/;
const RFC3339_MILLIS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const MAX_LIFETIME_MS = 15 * 60 * 1000;

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected) {
  if (!isRecord(value)) return false;
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length && actual.every((key, index) => key === wanted[index]);
}
const ENVELOPE_KEYS = Object.freeze([
  "schemaVersion", "repositoryId", "repository", "pullRequestNumber",
  "headSha", "baseRef", "baseSha", "rulesetId", "ruleContext",
  "integrationAppId", "spreadsheetId", "authoritativeSnapshotGeneration",
  "authoritativeSnapshotRevision", "authoritativeSnapshotSha256", "criticalHighHoldDispositions", "policyVersion",
  "decisionGeneration", "priorGeneration", "priorCheckRunId", "decision",
  "reasons", "reviewId", "reviewerVendor", "reviewCandidateSha",
  "decisionNonce", "evaluatedAt", "expiresAt",
]);

const DISPOSITION_KEYS = Object.freeze([
  "id", "severity", "scope", "status", "evidenceRef",
]);

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
function validDisposition(value) {
  if (!exactKeys(value, DISPOSITION_KEYS)) return false;
  return TOKEN.test(String(value.id || "")) &&
    ["CRITICAL", "HIGH"].includes(value.severity) &&
    ["GLOBAL", "MERGE", "BACKEND_ROLLOUT", "PHYSICAL_ACCEPTANCE", "PRODUCTION_RELEASE"].includes(value.scope) &&
    ["CLEARED", "NOT_APPLICABLE", "HOLD", "UNKNOWN"].includes(value.status) &&
    TOKEN.test(String(value.evidenceRef || ""));
}

function parseTime(value) {
  if (typeof value !== "string" || !RFC3339_MILLIS.test(value)) return Number.NaN;
  return Date.parse(value);
}

function validatesPassDispositions(rows) {
  return rows.every((row) =>
    !["GLOBAL", "MERGE"].includes(row.scope) ||
    ["CLEARED", "NOT_APPLICABLE"].includes(row.status)
  );
}

function validateEnvelope(value, now = new Date()) {
  if (!exactKeys(value, ENVELOPE_KEYS)) throw new Error("INVALID_COORDINATOR_ENVELOPE");
  const evaluatedAt = parseTime(value.evaluatedAt);
  const expiresAt = parseTime(value.expiresAt);
  const nowMs = now.getTime();
  const dispositions = Array.isArray(value.criticalHighHoldDispositions)
    ? value.criticalHighHoldDispositions
    : [];
  const reasons = Array.isArray(value.reasons) ? value.reasons : [];
  const snapshotGeneration = Number(value.authoritativeSnapshotGeneration);
  const generation = Number(value.decisionGeneration);
  const priorGeneration = value.priorGeneration === null ? null : Number(value.priorGeneration);
  const priorCheckRunId = value.priorCheckRunId === null ? null : Number(value.priorCheckRunId);
  if (
    value.schemaVersion !== 1 || value.repositoryId !== REPOSITORY_ID ||
    value.repository !== CANONICAL_REPOSITORY || !Number.isSafeInteger(value.pullRequestNumber) || value.pullRequestNumber < 1 ||
    !SHA40.test(String(value.headSha || "")) || value.baseRef !== "main" || !SHA40.test(String(value.baseSha || "")) ||
    value.rulesetId !== RULESET_ID || value.ruleContext !== RULE_CONTEXT || value.integrationAppId !== INTEGRATION_APP_ID ||
    value.spreadsheetId !== SPREADSHEET_ID || !Number.isSafeInteger(snapshotGeneration) || snapshotGeneration < 1 ||
    !TOKEN.test(String(value.authoritativeSnapshotRevision || "")) ||
    !SHA256.test(String(value.authoritativeSnapshotSha256 || "")) || !TOKEN.test(String(value.policyVersion || "")) ||
    !Number.isSafeInteger(generation) || generation < 1 ||
    (priorGeneration !== null && (!Number.isSafeInteger(priorGeneration) || priorGeneration < 1 || priorGeneration >= generation)) ||
    (priorCheckRunId !== null && (!Number.isSafeInteger(priorCheckRunId) || priorCheckRunId < 1))
  ) throw new Error("INVALID_COORDINATOR_ENVELOPE");
  if (
    !["PASS", "HOLD"].includes(value.decision) ||
    dispositions.length > 64 || !dispositions.every(validDisposition) ||
    reasons.length < 1 || reasons.length > 16 ||
    !reasons.every((reason) => typeof reason === "string" && reason.length >= 2 && reason.length <= 240) ||
    !TOKEN.test(String(value.reviewId || "")) || !TOKEN.test(String(value.reviewerVendor || "")) ||
    value.reviewCandidateSha !== value.headSha || !TOKEN.test(String(value.decisionNonce || "")) ||
    !Number.isFinite(evaluatedAt) || !Number.isFinite(expiresAt) ||
    Math.abs(evaluatedAt - nowMs) > 5 * 60 * 1000 || expiresAt <= nowMs ||
    expiresAt <= evaluatedAt || expiresAt - evaluatedAt > MAX_LIFETIME_MS ||
    (value.decision === "PASS" && !validatesPassDispositions(dispositions))
  ) throw new Error("INVALID_COORDINATOR_ENVELOPE");
  return value;
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function bindEnvelope(value, now = new Date()) {
  validateEnvelope(value, now);
  const envelopeHash = await sha256Hex(canonicalJson(value));
  const idempotencyKey = await sha256Hex(canonicalJson({
    repository: value.repository,
    pullRequestNumber: value.pullRequestNumber,
    headSha: value.headSha,
    ruleContext: value.ruleContext,
    decisionGeneration: value.decisionGeneration,
    authoritativeSnapshotGeneration: value.authoritativeSnapshotGeneration,
    authoritativeSnapshotSha256: value.authoritativeSnapshotSha256,
    decision: value.decision,
    decisionNonce: value.decisionNonce,
  }));
  return { envelope: value, envelopeHash, idempotencyKey };
}

function checkExternalId(binding) {
  const { envelope, envelopeHash, idempotencyKey } = binding;
  return [
    "pandora-r058-v1",
    `g=${envelope.decisionGeneration}`,
    `e=${envelopeHash}`,
    `i=${idempotencyKey}`,
    `x=${encodeURIComponent(envelope.expiresAt)}`,
  ].join(";");
}

function parseCheckExternalId(value) {
  if (typeof value !== "string" || !value.startsWith("pandora-r058-v1;")) return null;
  const parts = Object.fromEntries(value.split(";").slice(1).map((part) => {
    const index = part.indexOf("=");
    return index > 0 ? [part.slice(0, index), part.slice(index + 1)] : ["", ""];
  }));
  const generation = Number(parts.g);
  if (
    !Number.isSafeInteger(generation) || generation < 1 ||
    !SHA256.test(parts.e || "") || !SHA256.test(parts.i || "") || !parts.x
  ) return null;
  let expiresAt = "";
  try { expiresAt = decodeURIComponent(parts.x); } catch { return null; }
  if (!Number.isFinite(parseTime(expiresAt))) return null;
  return { generation, envelopeHash: parts.e, idempotencyKey: parts.i, expiresAt };
}

function desiredCheckState(binding) {
  const { envelope, envelopeHash } = binding;
  const summary = [
    `Decision: ${envelope.decision}`,
    `Generation: ${envelope.decisionGeneration}`,
    `Snapshot generation: ${envelope.authoritativeSnapshotGeneration}`,
    `Expires: ${envelope.expiresAt}`,
    `Envelope: ${envelopeHash.slice(0, 16)}`,
    ...envelope.reasons.map((reason) => `- ${reason}`),
  ].join("\n");
  return {
    name: RULE_CONTEXT,
    head_sha: envelope.headSha,
    external_id: checkExternalId(binding),
    status: "completed",
    conclusion: envelope.decision === "PASS" ? "success" : "action_required",
    completed_at: envelope.evaluatedAt,
    output: {
      title: envelope.decision === "PASS" ? "Pandora coordinator PASS" : "Pandora coordinator HOLD",
      summary,
    },
  };
}

export {
  CANONICAL_REPOSITORY,
  ENVELOPE_KEYS,
  INTEGRATION_APP_ID,
  REPOSITORY_ID,
  RULESET_ID,
  RULE_CONTEXT,
  SPREADSHEET_ID,
  bindEnvelope,
  canonicalJson,
  checkExternalId,
  desiredCheckState,
  parseCheckExternalId,
  validateEnvelope,
};
