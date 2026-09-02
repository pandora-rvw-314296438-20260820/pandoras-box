"use strict";

const { readFileSync } = require("node:fs");
const { createHash } = require("node:crypto");

const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DEPLOYMENT_BINDING = /^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$/;
const OPAQUE_EVIDENCE_REF = /^(?:sha256:[0-9a-f]{64}|provider-evidence:[0-9a-f]{64}|approved-store:[A-Za-z0-9][A-Za-z0-9._-]{0,127})$/;
const PROVIDER_BACKED_EVIDENCE_REF = /^provider-evidence:[0-9a-f]{64}$/;
const CANONICAL_RECEIPT_AUTHORITY = "AUTHENTICATED_CANONICAL_STATUS";
const GITHUB_ACTIONS_APP_ID = 15368;
const REQUIRED_CHECKS = Object.freeze([
  Object.freeze({ name: "node24", providerContext: "node24", authority: "GITHUB_ACTIONS_PROVIDER", appId: GITHUB_ACTIONS_APP_ID }),
  Object.freeze({ name: "external-review", providerContext: "external-review", authority: "TRUSTED_EXTERNAL_REVIEW_PROVIDER", appId: 4658204 }),
  Object.freeze({ name: "canonical-release-source-contract", providerContext: "canonical-release-source-contract", authority: "GITHUB_ACTIONS_PROVIDER", appId: GITHUB_ACTIONS_APP_ID }),
  Object.freeze({ name: "Windows worker contract", providerContext: "Windows worker contract", authority: "GITHUB_ACTIONS_PROVIDER", appId: GITHUB_ACTIONS_APP_ID }),
  Object.freeze({ name: "Exact source / Flutter / Android", providerContext: "Exact source / Flutter / Android", authority: "GITHUB_ACTIONS_PROVIDER", appId: GITHUB_ACTIONS_APP_ID }),
  Object.freeze({ name: "Exact source / Flutter / iOS", providerContext: "Exact source / Flutter / iOS", authority: "GITHUB_ACTIONS_PROVIDER", appId: GITHUB_ACTIONS_APP_ID }),
]);
const PAID_PILOT_STATES = new Set(["paid", "active", "completed"]);
const OWNER_GATED_STATES = new Set([
  "owner_authorized_offer",
  "offered",
  "accepted",
  ...PAID_PILOT_STATES,
]);

class BusinessValidationEvidenceError extends Error {
  constructor(issues) {
    super(`business-validation evidence rejected: ${issues.join("; ")}`);
    this.name = "BusinessValidationEvidenceError";
    this.code = "BUSINESS_VALIDATION_EVIDENCE_REJECTED";
    this.issues = issues;
  }
}

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function canonicalJson(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
}

function canonicalReceiptPayloadSha256(payload) {
  return createHash("sha256").update(canonicalJson(payload), "utf8").digest("hex");
}

function parseTimestamp(value) {
  const timestamp = typeof value === "string" ? Date.parse(value) : Number.NaN;
  return Number.isFinite(timestamp) ? timestamp : Number.NaN;
}

function walk(value, visit, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => walk(entry, visit, `${path}[${index}]`));
    return;
  }
  if (!isRecord(value)) return;
  for (const [key, entry] of Object.entries(value)) {
    const entryPath = `${path}.${key}`;
    visit(key, entry, entryPath);
    walk(entry, visit, entryPath);
  }
}

function findEvidencePrivacyLeaks(record) {
  const issues = [];
  const prohibitedField = /(?:rawtranscript|messagebody|contactdetails?|personalidentifiers?|customerrecords?|financialdocuments?|credentials?|secret|sourceurl|publicbusinessname|mailbox|(?:name|email|phone|address)$)/i;
  const email = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;
  const url = /\b(?:https?:\/\/|www\.)\S+/i;
  const phone = /(?:\+\d{1,3}[ .-]?)?(?:\(?\d{2,4}\)?[ .-])\d{3,4}[ .-]\d{4}\b|\b\d{10,15}\b/;
  const secret = /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bBearer\s+[A-Za-z0-9._~+\/-]+=*/i;

  walk(record, (key, value, path) => {
    const allowedFalsePrivacyFlag = key.startsWith("contains") && value === false;
    const allowedCanonicalTechnicalName = path.startsWith("$.technicalGate.canonicalReceipt.payload.")
      && ["name", "artifactName", "packageName"].includes(key);
    if (!allowedFalsePrivacyFlag && !allowedCanonicalTechnicalName && prohibitedField.test(key)) {
      issues.push(`${path}: prohibited privacy-bearing field`);
    }
    if (typeof value !== "string") return;
    const allowedCanonicalReceiptUuid = path.startsWith("$.technicalGate.canonicalReceipt.")
      && UUID.test(value);
    if (email.test(value)) issues.push(`${path}: email address detected`);
    if (url.test(value)) issues.push(`${path}: URL detected; commit an opaque evidence reference`);
    if (!allowedCanonicalReceiptUuid && phone.test(value)) issues.push(`${path}: phone number detected`);
    if (secret.test(value)) issues.push(`${path}: credential or secret detected`);
  });
  return [...new Set(issues)];
}

function validateOpaqueReferences(record, issues) {
  walk(record, (key, value, path) => {
    if (key.endsWith("EvidenceRef") && value !== null) {
      if (typeof value !== "string" || !OPAQUE_EVIDENCE_REF.test(value)) {
        issues.push(`${path}: must be an opaque evidence reference`);
      }
    }
    if (key === "evidenceRefs") {
      if (!Array.isArray(value)) {
        issues.push(`${path}: must be an array of opaque evidence references`);
        return;
      }
      value.forEach((entry, index) => {
        if (typeof entry !== "string" || !OPAQUE_EVIDENCE_REF.test(entry)) {
          issues.push(`${path}[${index}]: must be an opaque evidence reference`);
        }
      });
    }
  });
}

function validatePrivacyFlags(record, issues) {
  if (!isRecord(record.privacy)) {
    issues.push("$.privacy: privacy flags are required");
    return;
  }
  const flags = [
    "containsRawTranscript",
    "containsContactDetails",
    "containsPersonalIdentifiers",
    "containsSecrets",
    "containsCustomerRecords",
    "containsFinancialDocuments",
  ];
  for (const flag of flags) {
    if (record.privacy[flag] !== false) {
      issues.push(`$.privacy.${flag}: must be explicitly false`);
    }
  }
}

function validateTechnicalGate(gate, recordObservedAt, verifyCanonicalStatusReceipt, issues) {
  if (!isRecord(gate) || gate.passed !== true) {
    issues.push("$.technicalGate.passed: must be true");
    return;
  }
  const receipt = gate.canonicalReceipt;
  if (!isRecord(receipt) || !isRecord(receipt.payload)) {
    issues.push("$.technicalGate.canonicalReceipt: canonical status/release receipt required");
    return;
  }
  const payload = receipt.payload;
  if (receipt.authority !== CANONICAL_RECEIPT_AUTHORITY) {
    issues.push("$.technicalGate.canonicalReceipt.authority: authenticated canonical status authority required");
  }
  if (!UUID.test(receipt.receiptId || "")) {
    issues.push("$.technicalGate.canonicalReceipt.receiptId: provider-issued receipt UUID required");
  }
  if (!SHA256.test(receipt.receiptSha256 || "")) {
    issues.push("$.technicalGate.canonicalReceipt.receiptSha256: canonical payload digest required");
  }
  if (receipt.providerEvidenceRef !== `provider-evidence:${receipt.receiptSha256}`) {
    issues.push("$.technicalGate.canonicalReceipt.providerEvidenceRef: must bind the exact canonical payload digest");
  }
  const computedDigest = canonicalReceiptPayloadSha256(payload);
  if (computedDigest !== receipt.receiptSha256) {
    issues.push("$.technicalGate.canonicalReceipt.receiptSha256: does not match the canonical payload bytes");
  }

  if (payload.kind !== "canonical_status_release_receipt"
    || payload.schemaVersion !== "1.0.0"
    || payload.authoritative !== true
    || payload.status !== "current") {
    issues.push("$.technicalGate.canonicalReceipt.payload: authoritative current canonical status required");
  }
  const source = payload.source;
  if (!isRecord(source)
    || source.repository !== "banataosystems/Pandoras-box"
    || source.branch !== "main"
    || !SHA40.test(source.sha || "")
    || !SHA40.test(source.treeSha || "")) {
    issues.push("$.technicalGate.canonicalReceipt.payload.source: exact protected main SHA/tree binding required");
  }

  const checks = payload.requiredChecks;
  if (!Array.isArray(checks) || checks.length !== REQUIRED_CHECKS.length) {
    issues.push("$.technicalGate.canonicalReceipt.payload.requiredChecks: exact ordered five-check receipt set required");
  } else {
    const checkRunIds = new Set();
    const checkEvidenceRefs = new Set();
    checks.forEach((check, index) => {
      const required = REQUIRED_CHECKS[index];
      if (!isRecord(check)
        || check.name !== required.name
        || check.providerContext !== required.providerContext
        || check.authority !== required.authority
        || check.conclusion !== "success"
        || check.sourceSha !== source?.sha
        || !Number.isSafeInteger(check.checkRunId)
        || check.checkRunId <= 0
        || !Number.isSafeInteger(check.checkSuiteId)
        || check.checkSuiteId <= 0
        || check.appId !== required.appId
        || !PROVIDER_BACKED_EVIDENCE_REF.test(check.providerEvidenceRef || "")) {
        issues.push(`$.technicalGate.canonicalReceipt.payload.requiredChecks[${index}]: exact successful provider check binding required`);
      }
      if (checkRunIds.has(check?.checkRunId) || checkEvidenceRefs.has(check?.providerEvidenceRef)) {
        issues.push("$.technicalGate.canonicalReceipt.payload.requiredChecks: check receipts must be distinct");
      }
      checkRunIds.add(check?.checkRunId);
      checkEvidenceRefs.add(check?.providerEvidenceRef);
    });
  }

  const production = payload.productionDeployment;
  const rollback = payload.rollbackRehearsal;
  if (!isRecord(production)
    || production.authority !== "VERCEL_PROVIDER"
    || !DEPLOYMENT_BINDING.test(production.deploymentId || "")
    || production.sourceSha !== source?.sha) {
    issues.push("$.technicalGate.canonicalReceipt.payload.productionDeployment: exact source/deployment provider binding required");
  }
  if (!isRecord(rollback)
    || rollback.authority !== "VERCEL_PROVIDER"
    || rollback.candidateDeploymentId !== production?.deploymentId
    || rollback.candidateSourceSha !== source?.sha
    || !DEPLOYMENT_BINDING.test(rollback.rollbackDeploymentId || "")
    || rollback.rollbackDeploymentId === production?.deploymentId
    || !SHA40.test(rollback.rollbackSourceSha || "")
    || rollback.rollbackSourceSha === source?.sha
    || !UUID.test(rollback.transitionReceiptId || "")
    || !SHA256.test(rollback.transitionReceiptSha256 || "")
    || !UUID.test(rollback.restorationReceiptId || "")
    || !SHA256.test(rollback.restorationReceiptSha256 || "")
    || rollback.transitionReceiptId === rollback.restorationReceiptId
    || rollback.restoredDeploymentId !== production?.deploymentId
    || rollback.restoredSourceSha !== source?.sha) {
    issues.push("$.technicalGate.canonicalReceipt.payload.rollbackRehearsal: distinct rollback and exact candidate restoration receipt required");
  }

  const migration = payload.supabaseMigrationChain;
  if (!isRecord(migration)
    || migration.authority !== "SUPABASE_PROVIDER"
    || !UUID.test(migration.receiptId || "")
    || !SHA256.test(migration.receiptSha256 || "")
    || migration.sourceSha !== source?.sha
    || migration.sourceTreeSha !== source?.treeSha
    || !SHA256.test(migration.sourceChainSha256 || "")
    || !SHA256.test(migration.expectedAppliedVersionChainSha256 || "")
    || migration.expectedAppliedVersionChainSha256 !== migration.appliedVersionChainSha256) {
    issues.push("$.technicalGate.canonicalReceipt.payload.supabaseMigrationChain: exact source-byte chain and matching expected/provider-applied version-chain receipt required");
  }

  const android = payload.androidArtifact;
  const androidCheck = Array.isArray(checks) ? checks[4] : null;
  if (!isRecord(android)
    || android.authority !== "GITHUB_ACTIONS_PROVIDER"
    || android.artifactName !== "pandora-android-apk"
    || android.packageName !== "com.banataosystems.pandora_mobile"
    || !Number.isSafeInteger(android.artifactId)
    || android.artifactId <= 0
    || !SHA256.test(android.apkSha256 || "")
    || !SHA256.test(android.githubArtifactDigestSha256 || "")
    || android.sourceSha !== source?.sha
    || android.sourceTreeSha !== source?.treeSha
    || android.checkRunId !== androidCheck?.checkRunId
    || android.checkSuiteId !== androidCheck?.checkSuiteId
    || !PROVIDER_BACKED_EVIDENCE_REF.test(android.providerEvidenceRef || "")) {
    issues.push("$.technicalGate.canonicalReceipt.payload.androidArtifact: exact CI APK/artifact receipt binding required");
  }

  const physical = payload.physicalJourney;
  if (!isRecord(physical)
    || physical.authority !== "PHYSICAL_ANDROID_OBSERVER"
    || physical.storageAuthority !== "IMMUTABLE_PHYSICAL_ANDROID_RECEIPT"
    || physical.sourceSha !== source?.sha
    || physical.sourceTreeSha !== source?.treeSha
    || physical.productionDeploymentId !== production?.deploymentId
    || physical.restorationReceiptId !== rollback?.restorationReceiptId
    || physical.apkSha256 !== android?.apkSha256) {
    issues.push("$.technicalGate.canonicalReceipt.payload.physicalJourney: journey must bind restored production, source/tree, and one CI APK");
  }
  for (const [key, network] of [["wifi", "wifi"], ["mobileData", "mobile_data"]]) {
    const run = physical?.[key];
    if (!isRecord(run)
      || run.network !== network
      || !UUID.test(run.receiptId || "")
      || !SHA256.test(run.receiptSha256 || "")
      || run.sourceSha !== source?.sha
      || run.sourceTreeSha !== source?.treeSha
      || run.productionDeploymentId !== production?.deploymentId
      || run.restorationReceiptId !== rollback?.restorationReceiptId
      || run.apkSha256 !== android?.apkSha256) {
      issues.push(`$.technicalGate.canonicalReceipt.payload.physicalJourney.${key}: exact physical ${network} receipt binding required`);
    }
  }
  if (physical?.wifi?.receiptId === physical?.mobileData?.receiptId) {
    issues.push("$.technicalGate.canonicalReceipt.payload.physicalJourney: Wi-Fi and mobile-data receipts must be distinct");
  }

  const review = payload.independentReview;
  if (!isRecord(review)
    || review.authority !== "INDEPENDENT_REVIEWER"
    || !UUID.test(review.receiptId || "")
    || !SHA256.test(review.receiptSha256 || "")
    || !SHA256.test(review.reviewerKeyFingerprint || "")
    || review.sourceSha !== source?.sha
    || review.sourceTreeSha !== source?.treeSha
    || review.productionDeploymentId !== production?.deploymentId
    || review.rollbackDeploymentId !== rollback?.rollbackDeploymentId
    || review.supabaseMigrationChainSha256 !== migration?.sourceChainSha256) {
    issues.push("$.technicalGate.canonicalReceipt.payload.independentReview: exact independent-review receipt binding required");
  }

  const times = {
    production: parseTimestamp(production?.observedAt),
    transition: parseTimestamp(rollback?.transitionObservedAt),
    restoration: parseTimestamp(rollback?.restorationObservedAt),
    migration: parseTimestamp(migration?.observedAt),
    wifiObserved: parseTimestamp(physical?.wifi?.observedAt),
    wifiCaptured: parseTimestamp(physical?.wifi?.capturedAt),
    mobileObserved: parseTimestamp(physical?.mobileData?.observedAt),
    mobileCaptured: parseTimestamp(physical?.mobileData?.capturedAt),
    review: parseTimestamp(review?.reviewedAt),
    verified: parseTimestamp(payload.verifiedAt),
    captured: parseTimestamp(payload.capturedAt),
    expires: parseTimestamp(payload.expiresAt),
    record: parseTimestamp(recordObservedAt),
  };
  if (Object.values(times).some((value) => !Number.isFinite(value))) {
    issues.push("$.technicalGate.canonicalReceipt.payload: valid receipt chronology timestamps required");
  } else if (!(times.production < times.transition
    && times.transition < times.restoration
    && times.production < times.migration
    && times.restoration < times.wifiObserved
    && times.wifiObserved <= times.wifiCaptured
    && times.wifiCaptured < times.mobileCaptured
    && times.wifiObserved < times.mobileObserved
    && times.mobileObserved <= times.mobileCaptured
    && times.mobileObserved < times.review
    && times.review <= times.verified
    && times.verified <= times.captured
    && times.captured < times.expires
    && times.verified <= times.record
    && times.record <= times.expires)) {
    issues.push("$.technicalGate.canonicalReceipt.payload: stale or out-of-order deployment, restoration, Android, review, or verification evidence");
  }

  if (typeof verifyCanonicalStatusReceipt !== "function") {
    issues.push("$.technicalGate.canonicalReceipt: trusted authenticated canonical-status verifier required; receipt-shaped strings cannot self-verify");
    return;
  }
  try {
    const verified = verifyCanonicalStatusReceipt(receipt);
    if (!isRecord(verified)
      || verified.verified !== true
      || verified.authority !== CANONICAL_RECEIPT_AUTHORITY
      || verified.receiptId !== receipt.receiptId
      || verified.receiptSha256 !== receipt.receiptSha256
      || verified.providerEvidenceRef !== receipt.providerEvidenceRef
      || verified.verifiedAt !== payload.verifiedAt) {
      issues.push("$.technicalGate.canonicalReceipt: authenticated authority did not verify this exact receipt identity and digest");
    }
  } catch {
    issues.push("$.technicalGate.canonicalReceipt: authenticated authority verification failed closed");
  }
}

function validateOwnerAuthorization(authorization, issues) {
  if (!isRecord(authorization) || authorization.ownerAuthorized !== true) {
    issues.push("$.commercialAuthorization.ownerAuthorized: must be true");
    return;
  }
  if (!OPAQUE_EVIDENCE_REF.test(authorization.termsEvidenceRef || "")) {
    issues.push("$.commercialAuthorization.termsEvidenceRef: accepted owner terms proof required");
  }
}

function validatePaidCommercialProof(record, issues) {
  const price = record.price;
  if (!isRecord(price) || price.status !== "accepted") {
    issues.push("$.price.status: paid pilot price must be accepted");
  }
  if (!isRecord(price) || !Number.isFinite(price.amount) || price.amount <= 0) {
    issues.push("$.price.amount: paid pilot price must be positive");
  }

  const payment = record.payment;
  if (!isRecord(payment) || payment.state !== "paid") {
    issues.push("$.payment.state: paid, active, or completed pilot requires paid state");
  }
  if (!isRecord(payment) || !Number.isFinite(payment.amount) || payment.amount <= 0) {
    issues.push("$.payment.amount: positive paid amount required");
  }
  if (!PROVIDER_BACKED_EVIDENCE_REF.test(payment?.providerEvidenceRef || "")) {
    issues.push("$.payment.providerEvidenceRef: provider-backed paid receipt required");
  }
}

function validateBusinessValidationEvidence(record, options = {}) {
  const issues = [];
  if (!isRecord(record)) {
    throw new BusinessValidationEvidenceError(["$: evidence must be an object"]);
  }

  validateOpaqueReferences(record, issues);
  validatePrivacyFlags(record, issues);
  issues.push(...findEvidencePrivacyLeaks(record));

  if (record.recordType === "pilot") {
    const paidClaimed = record.payment?.state === "paid" || PAID_PILOT_STATES.has(record.state);
    if (OWNER_GATED_STATES.has(record.state) || paidClaimed) {
      validateTechnicalGate(
        record.technicalGate,
        record.observedAt,
        options.verifyCanonicalStatusReceipt,
        issues,
      );
      validateOwnerAuthorization(record.commercialAuthorization, issues);
    } else if (record.technicalGate?.passed === true) {
      validateTechnicalGate(
        record.technicalGate,
        record.observedAt,
        options.verifyCanonicalStatusReceipt,
        issues,
      );
    }

    if (paidClaimed) {
      validatePaidCommercialProof(record, issues);
    }
  } else if (record.recordType !== "interview") {
    issues.push("$.recordType: must be interview or pilot");
  }

  if (issues.length) throw new BusinessValidationEvidenceError([...new Set(issues)]);
  return record;
}

module.exports = {
  BusinessValidationEvidenceError,
  CANONICAL_RECEIPT_AUTHORITY,
  OPAQUE_EVIDENCE_REF,
  PROVIDER_BACKED_EVIDENCE_REF,
  REQUIRED_CHECKS,
  canonicalReceiptPayloadSha256,
  findEvidencePrivacyLeaks,
  validateBusinessValidationEvidence,
};

if (require.main === module) {
  const inputPath = process.argv[2];
  if (!inputPath) throw new Error("usage: node business-validation-evidence.js <evidence.json>");
  validateBusinessValidationEvidence(JSON.parse(readFileSync(inputPath, "utf8")));
  process.stdout.write("business-validation evidence: valid\n");
}
