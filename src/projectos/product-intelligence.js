"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PRODUCT_KEYS = exports.CONTROL_TOWER_PRODUCT_KEY = void 0;
exports.canonicalProductKey = canonicalProductKey;
exports.sanitizeProductProperties = sanitizeProductProperties;
exports.normalizeProductSignal = normalizeProductSignal;
exports.verifySharedSecret = verifySharedSecret;
const crypto_1 = require("crypto");
exports.CONTROL_TOWER_PRODUCT_KEY = 'pandoras_box';
exports.PRODUCT_KEYS = [
    'battle',
    'callgate',
    'realmatch',
    'fxpass',
    exports.CONTROL_TOWER_PRODUCT_KEY,
    'tessie',
];
const PRODUCT_KEY_SET = new Set(exports.PRODUCT_KEYS);
const PRODUCT_ALIASES = {
    battle: 'battle',
    'battle-prototype': 'battle',
    'batalla-law-office-os': 'battle',
    callgate: 'callgate',
    'callgate-platform': 'callgate',
    realmatch: 'realmatch',
    'real-match': 'realmatch',
    fxpass: 'fxpass',
    fong: 'fxpass',
    'fxpass-prototype': 'fxpass',
    'fong-europay-prototype': 'fxpass',
    'pandoras-box': exports.CONTROL_TOWER_PRODUCT_KEY,
    pandoras_box: exports.CONTROL_TOWER_PRODUCT_KEY,
    projectos: exports.CONTROL_TOWER_PRODUCT_KEY,
    project_os: exports.CONTROL_TOWER_PRODUCT_KEY,
    mcpmaster: exports.CONTROL_TOWER_PRODUCT_KEY,
    mcp_master: exports.CONTROL_TOWER_PRODUCT_KEY,
    'mcp-master': exports.CONTROL_TOWER_PRODUCT_KEY,
    tessie: 'tessie',
};
const ALLOWED_PROPERTY_KEYS = new Set([
    'product_key', 'app', 'environment', 'source_sha', 'release_sha', 'release_id',
    'app_version', 'product_version', 'deployment_id', 'rollback_of_deployment_id',
    'schema_version', 'event_schema_version', 'source_repo', 'privacy_tier', 'privacy_mode',
    'proof_stage', 'organization_key', 'project_key', 'execution_id', 'failure_class',
    'tool_class', 'model_provider', 'model_name', 'outcome_type', 'result', 'retry_count',
    'input_tokens', 'output_tokens', 'total_cost_usd', 'evaluation_score', 'evidence_count',
    'route_group', 'screen', 'feature_key', 'experiment_key', 'variant', 'outcome', 'status',
    'success', 'error_code', 'duration_ms', 'latency_ms', 'metric_name', 'metric_value',
    'funnel_step', 'entrypoint', 'channel', 'device_type', 'browser', 'os', 'action_key',
    'target_section', 'source_path', '$device_type', '$browser', '$os', '$pathname',
    '$current_url', '$referrer', '$lib', '$lib_version', '$web_vitals_INP_value',
    '$web_vitals_LCP_value', '$web_vitals_CLS_value', '$web_vitals_FCP_value',
    '$web_vitals_TTFB_value', '$exception_type', '$exception_fingerprint', '$exception_level',
    '$mcp_tool_name', '$mcp_server_name', '$mcp_client_name', '$mcp_duration_ms', '$mcp_is_error',
]);
const FORBIDDEN_KEY_EXCEPTIONS = new Set(['input_tokens', 'output_tokens']);
const FORBIDDEN_KEY_PATTERN = /(^|_)(email|phone|full_?name|first_?name|last_?name|address|message|prompt|input|output|transcript|recording|audio|document|content|password|secret|token|authorization|cookie|card|account|beneficiary|client_?matter|case_?details|legal_?narrative)($|_)/i;
const DIRECT_IDENTIFIER_PATTERN = /(?:[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|\+?\d[\d\s().-]{7,}\d)/i;
const PANDORA_PSEUDONYM_PATTERN = /^(?:actor|org|project)_[A-Za-z0-9_-]{32}$/;
function isCanonicalUtcTimestamp(value) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) && new Date(parsed).toISOString() === value;
}
function isSafeStructuralMetadata(value) {
    return PANDORA_PSEUDONYM_PATTERN.test(value) || isCanonicalUtcTimestamp(value);
}
const ENVIRONMENTS = new Set(['production', 'preview', 'staging', 'development', 'unknown']);
const PRIVACY_TIERS = new Set(['aggregate_only', 'anonymous_technical', 'pseudonymous_product']);
function record(value) {
    return value && typeof value === 'object' && !Array.isArray(value)
        ? value
        : {};
}
function normalizeString(value, maxLength = 256) {
    if (typeof value !== 'string')
        return null;
    const normalized = value.trim();
    if (!normalized)
        return null;
    if (!isSafeStructuralMetadata(normalized) && DIRECT_IDENTIFIER_PATTERN.test(normalized))
        return null;
    return normalized.slice(0, maxLength);
}
function normalizeUrl(value) {
    const stringValue = normalizeString(value, 2048);
    if (!stringValue)
        return null;
    try {
        const parsed = new URL(stringValue, 'https://invalid.local');
        if (parsed.hostname === 'invalid.local')
            return parsed.pathname.slice(0, 512);
        return `${parsed.origin}${parsed.pathname}`.slice(0, 512);
    }
    catch {
        return stringValue.split(/[?#]/, 1)[0]?.slice(0, 512) ?? null;
    }
}
function sanitizePrimitive(value, key) {
    if (typeof value === 'boolean')
        return value;
    if (typeof value === 'number' && Number.isFinite(value))
        return value;
    if (typeof value !== 'string')
        return null;
    if (key === 'source_repo' && value === 'pandora-rvw-314296438-20260820/pandoras-box')
        return value;
    if (key === '$current_url' || key === '$referrer')
        return normalizeUrl(value);
    return normalizeString(value);
}
function canonicalProductKey(value) {
    const normalized = normalizeString(value, 128)?.toLowerCase();
    if (!normalized)
        return null;
    if (PRODUCT_KEY_SET.has(normalized))
        return normalized;
    return PRODUCT_ALIASES[normalized] ?? null;
}
function sanitizeProductProperties(input) {
    const output = {};
    for (const [key, rawValue] of Object.entries(input)) {
        if (!ALLOWED_PROPERTY_KEYS.has(key)
            || (FORBIDDEN_KEY_PATTERN.test(key) && !FORBIDDEN_KEY_EXCEPTIONS.has(key)))
            continue;
        if (Array.isArray(rawValue)) {
            const sanitized = rawValue.slice(0, 20)
                .map((value) => sanitizePrimitive(value, key))
                .filter((value) => value !== null);
            if (sanitized.length)
                output[key] = sanitized;
            continue;
        }
        const sanitized = sanitizePrimitive(rawValue, key);
        if (sanitized !== null)
            output[key] = sanitized;
    }
    return output;
}
function stableSerialize(value) {
    if (Array.isArray(value))
        return `[${value.map(stableSerialize).join(',')}]`;
    if (value && typeof value === 'object') {
        return `{${Object.entries(value)
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([key, child]) => `${JSON.stringify(key)}:${stableSerialize(child)}`)
            .join(',')}}`;
    }
    return JSON.stringify(value);
}
function hashValue(value, salt) {
    return (0, crypto_1.createHash)('sha256').update(`${salt}:${value}`, 'utf8').digest('hex');
}
function normalizeProductSignal(rawBody, hashSalt) {
    const body = record(rawBody);
    const nested = record(body.event);
    const envelope = Object.keys(nested).length ? nested : body;
    const properties = record(envelope.properties ?? body.properties);
    const productKey = canonicalProductKey(properties.product_key ?? properties.app);
    if (!productKey)
        throw new Error('unrecognized_product');
    const eventName = normalizeString(envelope.event ?? envelope.event_name ?? body.event_name, 160);
    if (!eventName)
        throw new Error('invalid_event_name');
    const occurredAtText = normalizeString(envelope.timestamp ?? body.timestamp, 64);
    if (!occurredAtText)
        throw new Error('invalid_timestamp');
    const occurredAtDate = new Date(occurredAtText);
    if (Number.isNaN(occurredAtDate.getTime()))
        throw new Error('invalid_timestamp');
    const sanitizedProperties = sanitizeProductProperties(properties);
    sanitizedProperties.product_key = productKey;
    const environmentCandidate = normalizeString(properties.environment, 32)?.toLowerCase();
    const environment = environmentCandidate && ENVIRONMENTS.has(environmentCandidate) ? environmentCandidate : 'unknown';
    const privacyCandidate = normalizeString(properties.privacy_tier, 64)?.toLowerCase();
    const privacyTier = privacyCandidate && PRIVACY_TIERS.has(privacyCandidate) ? privacyCandidate : 'aggregate_only';
    const releaseSha = normalizeString(properties.release_sha, 128);
    const appVersion = normalizeString(properties.app_version ?? properties.product_version, 128);
    const deploymentId = normalizeString(properties.deployment_id, 256);
    const rawDistinctId = normalizeString(envelope.distinct_id ?? body.distinct_id, 512);
    const anonymousActorHash = rawDistinctId ? hashValue(rawDistinctId, hashSalt) : null;
    const schemaCandidate = Number(properties.event_schema_version ?? 1);
    const schemaVersion = Number.isInteger(schemaCandidate) && schemaCandidate > 0 && schemaCandidate <= 1000 ? schemaCandidate : 1;
    const sourceUuid = normalizeString(envelope.uuid ?? body.uuid, 256);
    const dedupeMaterial = sourceUuid ?? stableSerialize({
        productKey,
        eventName,
        occurredAt: occurredAtDate.toISOString(),
        anonymousActorHash,
        sanitizedProperties,
    });
    return {
        productKey,
        eventName,
        occurredAt: occurredAtDate.toISOString(),
        environment,
        privacyTier,
        releaseSha,
        appVersion,
        deploymentId,
        anonymousActorHash,
        properties: sanitizedProperties,
        schemaVersion,
        dedupeKey: hashValue(dedupeMaterial, hashSalt),
    };
}
function verifySharedSecret(provided, expected) {
    if (!provided || !expected)
        return false;
    const providedBuffer = Buffer.from(provided, 'utf8');
    const expectedBuffer = Buffer.from(expected, 'utf8');
    return providedBuffer.length === expectedBuffer.length && (0, crypto_1.timingSafeEqual)(providedBuffer, expectedBuffer);
}
//# sourceMappingURL=product-intelligence.js.map