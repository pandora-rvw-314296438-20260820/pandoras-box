import { createHash } from 'node:crypto';

export const MEMORY_PROJECT_REF = 'ivmvufhcsezyhczzondn';
export const BRIDGE_RPC = 'memory_operations_bridge_v1';
export const OUTCOME_CONTRACT = 'pandora-operations-model-outcome-v1';
export const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
export const SHA256 = /^[a-f0-9]{64}$/;
const IDENTITY = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,179}$/;
const REF = /^[A-Za-z0-9][A-Za-z0-9:./_?#=&%-]{0,499}$/;
const TIME = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$/;
const SECRET = /github_pat_|gh[pousr]_[A-Za-z0-9_]{16,}|sb_secret_|AIza[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._~+/-]{12,}|-----BEGIN [^-]*PRIVATE KEY/i;
export class MemoryIntegrationError extends Error {
  constructor(code, { outcomeUnknown = false } = {}) {
    super(code); this.name = 'MemoryIntegrationError'; this.code = code; this.outcomeUnknown = outcomeUnknown;
  }
}
export function requireThat(condition, code) {
  if (!condition) throw new MemoryIntegrationError(code);
}
export const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
export function exact(value, keys, required = keys) {
  requireThat(isRecord(value) && Object.keys(value).every(k => keys.includes(k))
    && required.every(k => Object.hasOwn(value, k)), 'OPS_MEMORY_FIELDS_INVALID');
}
export function immutable(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(immutable); Object.freeze(value);
  }
  return value;
}
export function serialized(value, maxBytes = 32768) {
  let text;
  try { text = JSON.stringify(value); } catch { throw new MemoryIntegrationError('OPS_MEMORY_JSON_INVALID'); }
  requireThat(typeof text === 'string' && Buffer.byteLength(text) <= maxBytes, 'OPS_MEMORY_PAYLOAD_LIMIT');
  requireThat(!SECRET.test(text), 'OPS_MEMORY_CREDENTIAL_REJECTED');
  return text;
}
export function stableDigest(value) {
  const sort = v => Array.isArray(v) ? v.map(sort) : isRecord(v)
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, sort(v[k])])) : v;
  return createHash('sha256').update(serialized(sort(value), 65536)).digest('hex');
}
function nullableCount(value, code) {
  requireThat(value === null || (Number.isSafeInteger(value) && value >= 0), code);
}
export function normalizeMapping(raw) {
  exact(raw, ['organizationId','projectId','memoryProjectRef','memoryProjectId','memoryUserId','namespace','principalKey','environment']);
  for (const k of ['organizationId','projectId','memoryProjectId','memoryUserId']) requireThat(UUID.test(raw[k]), 'OPS_MEMORY_MAPPING_ID_INVALID');
  requireThat(raw.memoryProjectRef === MEMORY_PROJECT_REF && raw.namespace === 'real_life', 'OPS_MEMORY_MAPPING_TARGET_DENIED');
  requireThat(typeof raw.principalKey === 'string' && IDENTITY.test(raw.principalKey), 'OPS_MEMORY_PRINCIPAL_INVALID');
  requireThat(['production','preview','development','test'].includes(raw.environment), 'OPS_MEMORY_ENVIRONMENT_INVALID');
  serialized(raw); return immutable(structuredClone(raw));
}
export function normalizeScope(raw, mapping) {
  exact(raw, ['organizationId','projectId']);
  requireThat(raw.organizationId === mapping.organizationId && raw.projectId === mapping.projectId, 'OPS_MEMORY_SOURCE_SCOPE_DENIED');
  return immutable(structuredClone(raw));
}
export function normalizeContextRequest(raw) {
  exact(raw, ['intent','actionMode','consequential','terms','requiredCapabilities','maxBytes'], ['intent','actionMode']);
  const value = {consequential:false,terms:[],requiredCapabilities:[],maxBytes:12288,...structuredClone(raw)};
  requireThat(['communication','research','coding_building','files','device_operations','business','travel','scheduling','future_capability','general_assistance'].includes(value.intent), 'OPS_MEMORY_INTENT_INVALID');
  requireThat(['no_action','read_only','state_change'].includes(value.actionMode) && typeof value.consequential === 'boolean', 'OPS_MEMORY_ACTION_MODE_INVALID');
  requireThat(Number.isSafeInteger(value.maxBytes) && value.maxBytes >= 4096 && value.maxBytes <= 16384, 'OPS_MEMORY_CONTEXT_BUDGET_INVALID');
  requireThat(Array.isArray(value.terms) && value.terms.length <= 12 && value.terms.every(x => typeof x === 'string' && /^[A-Za-z0-9_.:/+-]{3,64}$/.test(x)), 'OPS_MEMORY_TERMS_INVALID');
  requireThat(Array.isArray(value.requiredCapabilities) && value.requiredCapabilities.length <= 16 && value.requiredCapabilities.every(x => typeof x === 'string' && x.length <= 96 && /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/.test(x)), 'OPS_MEMORY_CAPABILITIES_INVALID');
  value.terms = [...new Set(value.terms)].sort();
  value.requiredCapabilities = [...new Set(value.requiredCapabilities)].sort();
  serialized(value); return immutable(value);
}
export const OUTCOME_FIELDS = Object.freeze([
  'contractVersion','sourceRunId','provider','model','modelRevision','taskClass','routingPolicyVersion',
  'executionStatus','verificationStatus','downstreamOutcomeStatus','qualitySignal','latencyMs',
  'estimatedCostMicros','billedCostMicros','occurredAt','evidenceRefs','sourceCommit','sourceDeploymentRef',
  'reviewDueAt','usage','retryCount','configurationDigest',
]);
export function normalizeOutcome(raw, now = Date.now()) {
  exact(raw, OUTCOME_FIELDS); serialized(raw);
  requireThat(raw.contractVersion === OUTCOME_CONTRACT && UUID.test(raw.sourceRunId), 'OPS_MEMORY_OUTCOME_IDENTITY_INVALID');
  for (const key of ['provider','model','taskClass','routingPolicyVersion']) {
    requireThat(typeof raw[key] === 'string' && IDENTITY.test(raw[key]), 'OPS_MEMORY_IDENTITY_INVALID');
  }
  requireThat(raw.provider === raw.provider.toLowerCase() && raw.provider.length <= 120, 'OPS_MEMORY_PROVIDER_INVALID');
  requireThat(raw.modelRevision === null || (typeof raw.modelRevision === 'string' && IDENTITY.test(raw.modelRevision)), 'OPS_MEMORY_MODEL_REVISION_INVALID');
  requireThat(typeof raw.sourceCommit === 'string' && /^[a-f0-9]{40}$/.test(raw.sourceCommit), 'OPS_MEMORY_SOURCE_SHA_REQUIRED');
  requireThat(raw.configurationDigest === null || (typeof raw.configurationDigest === 'string' && SHA256.test(raw.configurationDigest)), 'OPS_MEMORY_CONFIGURATION_INVALID');
  requireThat(raw.sourceDeploymentRef === null || (typeof raw.sourceDeploymentRef === 'string' && REF.test(raw.sourceDeploymentRef)), 'OPS_MEMORY_DEPLOYMENT_REF_INVALID');
  requireThat(['succeeded','failed','cancelled'].includes(raw.executionStatus), 'OPS_MEMORY_EXECUTION_STATUS_INVALID');
  requireThat(['pass','fail','disagree','remediated'].includes(raw.verificationStatus), 'OPS_MEMORY_VERIFICATION_REQUIRED');
  requireThat(['succeeded','failed','accepted','rejected','regressed','unknown'].includes(raw.downstreamOutcomeStatus), 'OPS_MEMORY_DOWNSTREAM_INVALID');
  requireThat(raw.qualitySignal === null || (typeof raw.qualitySignal === 'number' && Number.isFinite(raw.qualitySignal) && raw.qualitySignal >= 0 && raw.qualitySignal <= 1), 'OPS_MEMORY_QUALITY_INVALID');
  for (const key of ['latencyMs','estimatedCostMicros','billedCostMicros']) nullableCount(raw[key], 'OPS_MEMORY_METRIC_INVALID');
  exact(raw.usage, ['inputTokens','outputTokens','totalTokens']);
  for (const count of Object.values(raw.usage)) nullableCount(count, 'OPS_MEMORY_USAGE_INVALID');
  requireThat(Number.isSafeInteger(raw.retryCount) && raw.retryCount >= 0 && raw.retryCount <= 16, 'OPS_MEMORY_RETRY_INVALID');
  requireThat(Array.isArray(raw.evidenceRefs) && raw.evidenceRefs.length >= 1 && raw.evidenceRefs.length <= 31
    && new Set(raw.evidenceRefs).size === raw.evidenceRefs.length
    && raw.evidenceRefs.every(x => typeof x === 'string' && REF.test(x)), 'OPS_MEMORY_EVIDENCE_INVALID');
  requireThat(typeof raw.occurredAt === 'string' && TIME.test(raw.occurredAt) && typeof raw.reviewDueAt === 'string' && TIME.test(raw.reviewDueAt), 'OPS_MEMORY_TIME_INVALID');
  const observed = Date.parse(raw.occurredAt), due = Date.parse(raw.reviewDueAt);
  requireThat(Number.isFinite(observed) && Number.isFinite(due) && observed <= now && due > observed && due - observed <= 366 * 86400000, 'OPS_MEMORY_TIME_INVALID');
  return immutable(structuredClone(raw));
}
