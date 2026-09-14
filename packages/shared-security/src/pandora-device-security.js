"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PROTECTED_APP_CLASSES = exports.FINANCIAL_RISK_TIERS = void 0;
exports.classifyFinancialAction = classifyFinancialAction;
exports.evaluateProtectedAppAction = evaluateProtectedAppAction;
exports.evaluateDeviceIntegrityBaseline = evaluateDeviceIntegrityBaseline;
exports.canStartDestructiveProvisioning = canStartDestructiveProvisioning;
exports.buildConsequentialActionAuditRecord = buildConsequentialActionAuditRecord;

const { createHash } = require("crypto");

exports.PROTECTED_APP_CLASSES = Object.freeze([
  "financial",
  "authenticator",
  "password_manager",
  "identity_security",
  "security_sensitive"
]);

exports.FINANCIAL_RISK_TIERS = Object.freeze({
  F0: "information_only",
  F1: "protected_app_handoff",
  F2: "account_or_payee_change",
  F3: "money_movement_or_purchase",
  F4: "security_bypass_forbidden"
});

const FORBIDDEN_OPERATIONS = new Set([
  "credential_extract", "credential_scrape", "otp_read", "otp_bypass",
  "authenticator_secret_export", "biometric_bypass", "device_integrity_bypass",
  "protected_screen_scrape", "silent_financial_transfer"
]);

const SAFE_HANDOFF_OPERATIONS = new Set([
  "launch", "open_supported_deep_link", "show_instructions"
]);

const INFORMATION_OPERATIONS = new Set([
  "check_app_availability", "show_public_information"
]);

const USER_PRESENCE_OPERATIONS = new Set([
  "read_sensitive_account_data", "account_security_change", "add_or_change_payee",
  "financial_transfer", "purchase", "authenticator_migration", "password_export"
]);

const SUPPORTED_API_OPERATIONS = new Set(["supported_api_action"]);

function normalize(value) {
  return String(value ?? "").trim().toLowerCase();
}
function hasAuthority(input) {
  const basis = normalize(input.authorityBasis);
  if (basis === "explicit_current_user_instruction") return true;
  if (basis !== "active_explicit_standing_policy") return false;
  return input.standingPolicyMatches === true &&
    input.standingPolicyBoundsVerified === true;
}

function classifyFinancialAction(action) {
  const operation = normalize(action);
  if (FORBIDDEN_OPERATIONS.has(operation)) return "F4";
  if (["financial_transfer", "purchase", "withdraw", "deposit"].includes(operation)) return "F3";
  if (["add_or_change_payee", "account_security_change", "link_account"].includes(operation)) return "F2";
  if (SAFE_HANDOFF_OPERATIONS.has(operation)) return "F1";
  return "F0";
}

function isKnownOperation(operation) {
  return FORBIDDEN_OPERATIONS.has(operation) || SAFE_HANDOFF_OPERATIONS.has(operation) ||
    INFORMATION_OPERATIONS.has(operation) || USER_PRESENCE_OPERATIONS.has(operation) ||
    SUPPORTED_API_OPERATIONS.has(operation);
}

function evaluateProtectedAppAction(input) {
  const appClass = normalize(input.appClass);
  const operation = normalize(input.operation);
  if (!exports.PROTECTED_APP_CLASSES.includes(appClass)) {
    return { decision: "deny", reasonCode: "unknown_protected_app_class" };
  }
  if (FORBIDDEN_OPERATIONS.has(operation)) {
    return { decision: "deny", reasonCode: "protected_app_security_bypass_forbidden" };
  }
  if (!isKnownOperation(operation)) {
    return { decision: "deny", reasonCode: "unsupported_protected_operation" };
  }
  if (SAFE_HANDOFF_OPERATIONS.has(operation)) {
    return { decision: "allow_handoff", reasonCode: "protected_app_safe_handoff" };
  }
  if (INFORMATION_OPERATIONS.has(operation)) {
    return { decision: "allow", reasonCode: "protected_app_information_only" };
  }
  if (!hasAuthority(input)) {
    return { decision: "needs_approval", reasonCode: "protected_app_authority_required" };
  }
  if (USER_PRESENCE_OPERATIONS.has(operation) && input.userPresenceVerified !== true) {
    return { decision: "needs_user_presence", reasonCode: "protected_app_user_presence_required" };
  }
  if (SUPPORTED_API_OPERATIONS.has(operation) && input.providerControlsVerified !== true) {
    return { decision: "deny", reasonCode: "protected_app_provider_controls_not_verified" };
  }
  if (SUPPORTED_API_OPERATIONS.has(operation) && input.postVerificationPlanned !== true) {
    return { decision: "deny", reasonCode: "protected_app_post_verification_required" };
  }
  return { decision: "allow", reasonCode: "protected_app_policy_satisfied" };
}

function evaluateDeviceIntegrityBaseline(input) {
  const failures = [];
  const unknown = [];
  const checks = [
    ["stockFirmware", true, "stock_firmware_required"],
    ["bootloaderLocked", true, "locked_bootloader_required"],
    ["rooted", false, "non_root_required"],
    ["customRom", false, "stock_rom_required"],
    ["verifiedBootTrusted", true, "trusted_verified_boot_required"],
    ["googleSystemServicesPreserved", true, "system_services_required"],
    ["biometricsPreserved", true, "biometrics_required"],
    ["simTelephonyPreserved", true, "sim_telephony_required"],
    ["imsDependenciesPreserved", true, "ims_dependencies_required"]
  ];

  for (const [key, expected, code] of checks) {
    if (input[key] === undefined || input[key] === null) unknown.push(key);
    else if (input[key] !== expected) failures.push(code);
  }
  let status = "meets_policy_baseline";
  if (failures.length > 0) status = "blocked";
  else if (unknown.length > 0 || input.physicalEvidenceVerified !== true) {
    status = "needs_physical_verification";
  }

  return {
    status,
    acceptable: status === "meets_policy_baseline",
    failures,
    unknown,
    physicalVerificationRequired: input.physicalEvidenceVerified !== true
  };
}

function canStartDestructiveProvisioning(input) {
  const missing = [];
  const required = [
    ["authenticatorRecoveryVerified", "authenticator_recovery_not_verified"],
    ["passwordManagerRecoveryVerified", "password_manager_recovery_not_verified"],
    ["protectedAppRecoveryVerified", "protected_app_recovery_not_verified"],
    ["backupExportVerified", "backup_export_not_verified"],
    ["simEsimRecoveryVerified", "sim_esim_recovery_not_verified"],
    ["knownGoodRollbackAvailable", "known_good_rollback_not_available"],
    ["userExplicitlyAuthorizedDestructiveAction", "explicit_destructive_authority_required"]
  ];
  for (const [key, code] of required) {
    if (input[key] !== true) missing.push(code);
  }

  return {
    allowed: missing.length === 0,
    missing,
    destructiveActionExecuted: false,
    physicalAcceptanceStillRequired: true
  };
}

const SECRET_KEY_PATTERN = /(?:authorization|cookie|password|passphrase|secret|token|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|private[_-]?key|credential|otp)/i;
const PERSONAL_KEY_PATTERN = /(?:email|phone|mobile|address|full[_-]?name|first[_-]?name|last[_-]?name|message|body|content)/i;

function redactAuditValue(value, keyHint = "") {
  if (SECRET_KEY_PATTERN.test(keyHint)) return "[REDACTED_SECRET]";
  if (PERSONAL_KEY_PATTERN.test(keyHint)) return "[REDACTED_PERSONAL]";
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value.slice(0, 20).map((item) => redactAuditValue(item));
  if (typeof value === "object") {
    const output = {};
    for (const [key, child] of Object.entries(value)) output[key] = redactAuditValue(child, key);
    return output;
  }
  if (typeof value === "string") {
    return value.length <= 500 ? value : `${value.slice(0, 500)}…[TRUNCATED]`;
  }
  if (typeof value === "number") return Number.isFinite(value) ? value : "[NON_FINITE_NUMBER]";
  if (typeof value === "boolean") return value;
  return `[UNSUPPORTED_${typeof value}]`;
}

function hashValue(value) {
  if (value === undefined || value === null || String(value).length === 0) return null;
  return createHash("sha256").update(String(value), "utf8").digest("hex");
}

function buildConsequentialActionAuditRecord(input) {
  const actionId = String(input.actionId ?? "").trim();
  const actor = String(input.actor ?? input.principal ?? "").trim();
  const authorityBasis = String(input.authorityBasis ?? "").trim();
  if (!actionId || !actor || !authorityBasis) {
    throw new Error("actionId, actor/principal and authorityBasis are required");
  }

  const recordedAt = String(input.recordedAt ?? new Date().toISOString());
  return {
    schemaVersion: "pandora-consequential-device-action-audit-v1",
    actionId,
    jobId: String(input.jobId ?? "").trim() || null,
    actor,
    authorityBasis,
    authorityPolicyId: String(input.authorityPolicyId ?? "").trim() || null,
    authorityPolicyFingerprint: hashValue(input.authorityPolicyFingerprint),
    capability: String(input.capability ?? "").trim(),
    operation: String(input.operation ?? "").trim(),
    actionClass: String(input.actionClass ?? "").trim() || null,
    protectedAppClass: String(input.protectedAppClass ?? "").trim() || null,
    financialRiskTier: classifyFinancialAction(input.operation),
    redactedInputScope: redactAuditValue(input.inputScope ?? {}),
    idempotencyKeyHash: hashValue(input.idempotencyKey),
    outcome: String(input.outcome ?? "unknown").trim(),
    verificationState: String(input.verificationState ?? "unverified").trim(),
    providerReadback: redactAuditValue(input.providerReadback ?? null),
    evidenceIds: Array.isArray(input.evidenceIds)
      ? input.evidenceIds.map((value) => String(value)).slice(0, 50)
      : [],
    startedAt: String(input.startedAt ?? recordedAt),
    completedAt: input.completedAt ? String(input.completedAt) : null,
    recordedAt,
    containsSecrets: false
  };
}
