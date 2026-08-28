"use strict";

const { sha256, requireDigest } = require("./contracts");
const { CHECK_REGISTRY } = require("./registry");

function secretPatterns() {
  return [
    ["github_token", new RegExp("\\b(?:" + "gh" + "[pousr]_[A-Za-z0-9_]{20,255}|github" + "_pat_[A-Za-z0-9_]{20,255})\\b", "g")],
    ["jwt_like_secret", /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/g],
    ["provider_api_key", /\b(?:sk-|AIza|vc_)[A-Za-z0-9_-]{20,}\b/g],
    ["private_key_marker", new RegExp("-".repeat(5) + "BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY" + "-".repeat(5), "g")],
    ["connection_string", /\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s]+/gi],
    ["authorization_header", /\bAuthorization\s*:\s*(?:Bearer|Basic)\s+[^\s"']+/gi],
    ["pandora_canary", /\bPANDORA_CANARY_SECRET_[A-Za-z0-9_-]{8,}\b/g],
  ];
}

function scanSecrets(input) {
  const text = Buffer.isBuffer(input) ? input.toString("utf8") : String(input ?? "");
  const findings = [];
  for (const [kind, pattern] of secretPatterns()) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      findings.push(Object.freeze({
        kind,
        severity: kind === "authorization_header" ? "HIGH" : "CRITICAL",
        index: match.index,
        length: match[0].length,
        fingerprint: sha256(match[0]).slice(0, 16),
        redacted: "[REDACTED]",
      }));
      if (!match[0].length) pattern.lastIndex += 1;
    }
  }
  return Object.freeze({ status: findings.length ? "FAIL" : "PASS", findings: Object.freeze(findings) });
}

function analyzeMigrationSql(sql, options = {}) {
  const source = String(sql ?? "");
  const findings = [];
  const add = (code, severity, summary) => findings.push(Object.freeze({ code, severity, summary }));
  if (/\bdrop\s+(?:table|column|schema|type)\b/i.test(source)) add("destructive_drop", "HIGH", "Migration contains a destructive DROP operation.");
  if (/\btruncate\b/i.test(source)) add("destructive_truncate", "CRITICAL", "Migration contains TRUNCATE.");
  if (/\balter\s+table\b[\s\S]*?\balter\s+column\b[\s\S]*?\btype\b/i.test(source)) add("incompatible_type_change", "HIGH", "Migration changes a column type and requires compatibility review.");
  if (/\bdisable\s+row\s+level\s+security\b/i.test(source)) add("rls_disabled", "CRITICAL", "Migration disables row-level security.");
  if (/\bdrop\s+policy\b/i.test(source)) add("policy_removed", "HIGH", "Migration removes an RLS policy.");
  if (/\bcreate\s+unique\s+index\b|\bunique\s*\(/i.test(source)) add("uniqueness_change", "MEDIUM", "Migration introduces uniqueness; existing data requires preflight.");
  if (!options.rollbackPlan && findings.some((finding) => ["HIGH", "CRITICAL"].includes(finding.severity))) {
    add("rollback_plan_missing", "HIGH", "High-risk migration lacks a rollback or recovery plan reference.");
  }
  return Object.freeze({
    status: findings.some((finding) => ["HIGH", "CRITICAL"].includes(finding.severity)) ? "FAIL" : "PASS",
    findings: Object.freeze(findings),
  });
}

function verifyArtifactIdentity({ built, verified, preview = null, production = null, lineage = [] }) {
  requireDigest("built_artifact_digest", built);
  requireDigest("verified_artifact_digest", verified);
  if (preview != null) requireDigest("preview_artifact_digest", preview);
  if (production != null) requireDigest("production_artifact_digest", production);
  const values = [built, verified, preview, production].filter(Boolean).map((value) => value.toLowerCase());
  const exact = values.every((value) => value === values[0]);
  if (exact) return Object.freeze({ status: "PASS", exact: true, lineage: Object.freeze([...lineage]) });
  if (lineage.length) return Object.freeze({ status: "INCONCLUSIVE", exact: false, lineage: Object.freeze([...lineage]) });
  return Object.freeze({ status: "FAIL", exact: false, lineage: Object.freeze([]) });
}

function compareReproducibleBuilds(firstDigest, secondDigest, normalizedDifferences = []) {
  requireDigest("first_build_digest", firstDigest);
  requireDigest("second_build_digest", secondDigest);
  if (firstDigest.toLowerCase() === secondDigest.toLowerCase()) return { status: "PASS", deterministic: true, normalizedDifferences: [] };
  if (normalizedDifferences.length) return { status: "INCONCLUSIVE", deterministic: false, normalizedDifferences: [...normalizedDifferences] };
  return { status: "FAIL", deterministic: false, normalizedDifferences: [] };
}

function classifyVisualDiff({ changedPixelRatio = 0, brokenLayout = false, approvedChange = false, threshold = 0.005 }) {
  if (brokenLayout) return "BROKEN LAYOUT";
  if (approvedChange || changedPixelRatio <= threshold) return "EXPECTED CHANGE";
  if (changedPixelRatio <= Math.max(threshold * 4, 0.02)) return "REVIEW REQUIRED";
  return "UNEXPECTED CHANGE";
}

function verifyRuntimeProbe(probe) {
  if (!probe || typeof probe !== "object" || probe.infrastructure_error) {
    return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: probe?.summary ?? "Runtime verifier unavailable." };
  }
  if (probe.statusCode == null) return { status: "INCONCLUSIVE", failure_class: "runtime", summary: "No runtime response status observed." };
  const allowed = probe.expectedStatuses ?? [200];
  if (allowed.includes(probe.statusCode)) return { status: "PASS", failure_class: null, summary: "Runtime probe matched expected response." };
  return { status: "FAIL", failure_class: "runtime", summary: `Runtime returned HTTP ${probe.statusCode}.` };
}

function securityPolicySignal(findings, policy = {}) {
  const blockAt = new Set(policy.block_severities ?? ["HIGH", "CRITICAL"]);
  const reviewAt = new Set(policy.review_severities ?? ["MEDIUM"]);
  return {
    blocking: findings.filter((finding) => blockAt.has(finding.severity)),
    review: findings.filter((finding) => reviewAt.has(finding.severity)),
    informational: findings.filter((finding) => !blockAt.has(finding.severity) && !reviewAt.has(finding.severity)),
  };
}

function cacheKeyForCheck(checkId, request, identityDigest) {
  const definition = CHECK_REGISTRY[checkId];
  if (!definition) throw new Error(`unknown verification check: ${checkId}`);
  return sha256(`${checkId}:${definition.freshnessScope}:${identityDigest}`);
}

function canReuseCheck(cached, cacheKey, now = Date.now()) {
  if (!cached || cached.status !== "PASS" || cached.cache_key !== cacheKey) return false;
  return !cached.expires_at || new Date(cached.expires_at).getTime() > now;
}

function detectProductionDrift({ verifiedDeploymentId, currentDeploymentId, verifiedArtifactDigest, currentArtifactDigest, evidenceExpiresAt, now = Date.now(), domainMatches = true, runtimeHealthy = true }) {
  if (!verifiedDeploymentId || !currentDeploymentId || !verifiedArtifactDigest || !currentArtifactDigest) return "unknown";
  if (evidenceExpiresAt && new Date(evidenceExpiresAt).getTime() <= now) return "verification_expired";
  if (verifiedDeploymentId !== currentDeploymentId || verifiedArtifactDigest.toLowerCase() !== currentArtifactDigest.toLowerCase() || !domainMatches || !runtimeHealthy) return "drift_detected";
  return "verified_current";
}

module.exports = {
  scanSecrets, analyzeMigrationSql, verifyArtifactIdentity, compareReproducibleBuilds, classifyVisualDiff,
  verifyRuntimeProbe, securityPolicySignal, cacheKeyForCheck, canReuseCheck, detectProductionDrift,
};
