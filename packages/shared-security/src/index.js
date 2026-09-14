"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.canonicalizeJson = canonicalizeJson;
exports.computeActionHash = computeActionHash;
exports.secureEqualHex = secureEqualHex;
exports.redactForAudit = redactForAudit;
exports.isPageAllowed = isPageAllowed;
exports.evaluateLawOfficeText = evaluateLawOfficeText;
exports.authorizeExternalWrite = authorizeExternalWrite;
const crypto_1 = require("crypto");
function normalizeJson(value) {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') {
        return value;
    }
    if (typeof value === 'number') {
        if (!Number.isFinite(value)) {
            throw new Error('Action envelopes cannot contain non-finite numbers');
        }
        return value;
    }
    if (Array.isArray(value)) {
        return value.map((item) => normalizeJson(item));
    }
    if (typeof value === 'object') {
        const prototype = Object.getPrototypeOf(value);
        if (prototype !== Object.prototype && prototype !== null) {
            throw new Error('Action envelopes may contain only plain JSON objects');
        }
        const output = {};
        for (const key of Object.keys(value).sort()) {
            const child = value[key];
            if (child !== undefined) {
                output[key] = normalizeJson(child);
            }
        }
        return output;
    }
    throw new Error(`Unsupported action-envelope value: ${typeof value}`);
}
function canonicalizeJson(value) {
    return JSON.stringify(normalizeJson(value));
}
function computeActionHash(envelope) {
    return (0, crypto_1.createHash)('sha256').update(canonicalizeJson(envelope), 'utf8').digest('hex');
}
function secureEqualHex(left, right) {
    if (!/^[0-9a-f]{64}$/.test(left) || !/^[0-9a-f]{64}$/.test(right)) {
        return false;
    }
    const leftBuffer = Buffer.from(left, 'hex');
    const rightBuffer = Buffer.from(right, 'hex');
    return leftBuffer.length === rightBuffer.length && (0, crypto_1.timingSafeEqual)(leftBuffer, rightBuffer);
}
const SECRET_KEY_PATTERN = /(?:authorization|cookie|password|passphrase|secret|token|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|private[_-]?key)/i;
const PERSONAL_KEY_PATTERN = /(?:email|phone|mobile|address|full[_-]?name|first[_-]?name|last[_-]?name|message|body|content|case[_-]?facts?)/i;
function redactForAudit(value, options = {}, keyHint = '') {
    const maxStringLength = options.maxStringLength ?? 500;
    const maxArrayLength = options.maxArrayLength ?? 20;
    if (SECRET_KEY_PATTERN.test(keyHint)) {
        return '[REDACTED_SECRET]';
    }
    if (!options.includePersonalData && PERSONAL_KEY_PATTERN.test(keyHint)) {
        return '[REDACTED_PERSONAL]';
    }
    if (value === null || value === undefined) {
        return null;
    }
    if (typeof value === 'string') {
        if (value.length <= maxStringLength) {
            return value;
        }
        return `${value.slice(0, maxStringLength)}…[TRUNCATED]`;
    }
    if (typeof value === 'boolean') {
        return value;
    }
    if (typeof value === 'number') {
        return Number.isFinite(value) ? value : '[NON_FINITE_NUMBER]';
    }
    if (Array.isArray(value)) {
        const redacted = value
            .slice(0, maxArrayLength)
            .map((item) => redactForAudit(item, options));
        if (value.length > maxArrayLength) {
            redacted.push(`[${value.length - maxArrayLength} ITEMS OMITTED]`);
        }
        return redacted;
    }
    if (typeof value === 'object') {
        const output = {};
        for (const [key, child] of Object.entries(value)) {
            output[key] = redactForAudit(child, options, key);
        }
        return output;
    }
    return `[UNSUPPORTED_${typeof value}]`;
}
function isPageAllowed(pageId, allowedPageIds) {
    const normalizedPageId = pageId.trim();
    if (!normalizedPageId || normalizedPageId.includes('*')) {
        return false;
    }
    return new Set(allowedPageIds.map((id) => id.trim()).filter(Boolean)).has(normalizedPageId);
}
const LAW_OFFICE_PATTERNS = [
    {
        reason: 'legal_advice',
        pattern: /\b(?:legal advice|what are my rights|should i sue|am i liable|are they liable|do i have a case)\b/i,
    },
    {
        reason: 'case_merits_or_strategy',
        pattern: /\b(?:merits? of (?:the|my|your) case|legal strategy|case strategy|best argument|defense strategy)\b/i,
    },
    {
        reason: 'deadline_or_limitation_period',
        pattern: /\b(?:deadline|statute of limitations|limitation period|prescriptive period|filing period|appeal period)\b/i,
    },
    {
        reason: 'fees_or_engagement_terms',
        pattern: /\b(?:attorney(?:'s)? fees?|legal fees?|retainer|engagement terms?|representation agreement)\b/i,
    },
    {
        reason: 'conflict_clearance',
        pattern: /\b(?:conflict check|conflict clearance|conflict of interest|opposing party)\b/i,
    },
    {
        reason: 'confidential_case_facts',
        pattern: /\b(?:confidential case facts?|client confession|case evidence|docket number|case number|medical records?)\b/i,
    },
    {
        reason: 'outcome_prediction',
        pattern: /\b(?:will (?:i|we|you|they) win|(?:i|we|you|they) will win|chance of winning|likely outcome|guaranteed result|case is worth)\b/i,
    },
];
function evaluateLawOfficeText(text) {
    const reasons = LAW_OFFICE_PATTERNS
        .filter(({ pattern }) => pattern.test(text))
        .map(({ reason }) => reason);
    return {
        disposition: reasons.length > 0 ? 'legal_review_required' : 'static_information_candidate',
        reasons: [...new Set(reasons)],
    };
}
function authorizeExternalWrite(input) {
    const reasons = [];
    const staffId = input.staffId.trim();
    const idempotencyKey = input.idempotencyKey.trim();
    const textEvaluation = evaluateLawOfficeText(input.outboundText ?? '');
    const requiresLegalReview = textEvaluation.disposition === 'legal_review_required';
    if (!staffId) {
        reasons.push('authenticated_staff_required');
    }
    if (input.killSwitchActive) {
        reasons.push('emergency_kill_switch_active');
    }
    if (!isPageAllowed(input.pageId, input.allowedPageIds)) {
        reasons.push('page_not_allowlisted');
    }
    if (input.approvalDecision !== 'approved') {
        reasons.push('human_approval_required');
    }
    if (!secureEqualHex(input.expectedActionHash, input.approvedActionHash)) {
        reasons.push('approved_action_hash_mismatch');
    }
    if (idempotencyKey.length < 8 || idempotencyKey.length > 200) {
        reasons.push('valid_idempotency_key_required');
    }
    if (requiresLegalReview && !input.legalReviewConfirmed) {
        reasons.push('lawyer_or_secretary_review_required');
    }
    return {
        allowed: reasons.length === 0,
        reasons,
        requiresLegalReview,
    };
}


// Pandora device/protected-app security boundary (M7).
// Kept in a separate module so device security can evolve without coupling to provider-specific policy.
const pandoraDeviceSecurity = require("./pandora-device-security");
exports.PROTECTED_APP_CLASSES = pandoraDeviceSecurity.PROTECTED_APP_CLASSES;
exports.FINANCIAL_RISK_TIERS = pandoraDeviceSecurity.FINANCIAL_RISK_TIERS;
exports.classifyFinancialAction = pandoraDeviceSecurity.classifyFinancialAction;
exports.evaluateProtectedAppAction = pandoraDeviceSecurity.evaluateProtectedAppAction;
exports.evaluateDeviceIntegrityBaseline = pandoraDeviceSecurity.evaluateDeviceIntegrityBaseline;
exports.canStartDestructiveProvisioning = pandoraDeviceSecurity.canStartDestructiveProvisioning;
exports.buildConsequentialActionAuditRecord = pandoraDeviceSecurity.buildConsequentialActionAuditRecord;

// Pandora least-privilege device permission boundary (M7-006).
const pandoraDevicePermissions = require("./pandora-device-permissions");
exports.PERMISSION_GATE_SCHEMA_VERSION = pandoraDevicePermissions.PERMISSION_GATE_SCHEMA_VERSION;
exports.PERMISSION_AUTHORITY_MODES = pandoraDevicePermissions.PERMISSION_AUTHORITY_MODES;
exports.PERMISSION_GATE_DECISIONS = pandoraDevicePermissions.PERMISSION_GATE_DECISIONS;
exports.evaluateDevicePermissionGate = pandoraDevicePermissions.evaluateDevicePermissionGate;
exports.permissionDecisionNeedsYou = pandoraDevicePermissions.permissionDecisionNeedsYou;
