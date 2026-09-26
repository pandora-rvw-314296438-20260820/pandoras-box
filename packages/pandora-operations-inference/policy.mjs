import {Buffer} from 'node:buffer';
import {createHash} from 'node:crypto';
import {PERFORMANCE_CLASSES} from '../pandora-operations-memory/performance-client.mjs';

export const CAPABILITY_CLASSES = PERFORMANCE_CLASSES;
export class InferenceError extends Error {
  constructor(code, {outcomeUnknown = false} = {}) { super(code); this.name = 'InferenceError'; this.code = code; this.outcomeUnknown = outcomeUnknown; }
}
export function demand(value, code) { if (!value) throw new InferenceError(code); }
export const record = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
export const sha256 = value => createHash('sha256').update(typeof value === 'string' ? value : stable(value)).digest('hex');
export function stable(value) {
  const visit = v => Array.isArray(v) ? v.map(visit) : record(v) ? Object.fromEntries(Object.keys(v).sort().map(k => [k, visit(v[k])])) : v;
  return JSON.stringify(visit(value));
}
const typed = pattern => Object.freeze({test:value=>typeof value === "string" && pattern.test(value)});
export const ID = typed(/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,179}$/);
export const SHA = typed(/^[a-f0-9]{40}$/);
export const DIGEST = typed(/^[a-f0-9]{64}$/);
export const UUID = typed(/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
export function immutable(value) { if(value && typeof value === "object") { for(const item of Object.values(value)) immutable(item); Object.freeze(value); } return value; }
const SECRET = /github_pat_|gh[pousr]_[A-Za-z0-9_]{16,}|sb_secret_|AIza[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._~+/-]{12,}|-----BEGIN [^-]*PRIVATE KEY/i;
export function bounded(value, limit = 1048576) {
  let text; try { text = JSON.stringify(value); } catch { throw new InferenceError('INFERENCE_JSON_INVALID'); }
  demand(typeof text === 'string' && Buffer.byteLength(text) <= limit, 'INFERENCE_PAYLOAD_LIMIT');
  demand(!SECRET.test(text), 'INFERENCE_CREDENTIAL_REJECTED'); return text;
}
export function exact(value, allowed, required = allowed) {
  demand(record(value) && Object.keys(value).every(k => allowed.includes(k)) && required.every(k => Object.hasOwn(value, k)), 'INFERENCE_FIELDS_INVALID');
}
export const integer = (v, lo, hi) => Number.isSafeInteger(v) && v >= lo && v <= hi;
export function normalizeRequest(raw) {
  exact(raw, ['requestId','taskId','leaseId','generation','sourceSha','taskClass','parts','maxOutputTokens','maxCostMicros','deadlineMs']);
  demand(UUID.test(raw.requestId) && UUID.test(raw.leaseId) && ID.test(raw.taskId) && SHA.test(raw.sourceSha), 'INFERENCE_IDENTITY_INVALID');
  demand(integer(raw.generation, 1, Number.MAX_SAFE_INTEGER) && CAPABILITY_CLASSES.includes(raw.taskClass), 'INFERENCE_CLASS_INVALID');
  demand(integer(raw.maxOutputTokens, 1, 65536) && integer(raw.maxCostMicros, 0, 1000000000000)
    && integer(raw.deadlineMs, 100, 60000), 'INFERENCE_BUDGET_INVALID');
  demand(Array.isArray(raw.parts) && raw.parts.length >= 1 && raw.parts.length <= 16, 'INFERENCE_INPUT_INVALID');
  let textBytes = 0, imageCount = 0, imageBytes = 0; const modalities = new Set();
  for (const part of raw.parts) {
    if (part?.type === 'text') {
      exact(part, ['type','text']); demand(typeof part.text === 'string' && part.text.length > 0, 'INFERENCE_INPUT_INVALID');
      textBytes += Buffer.byteLength(part.text); modalities.add('text');
    } else if (part?.type === 'image') {
      exact(part, ['type','mimeType','data']);
      demand(['image/png','image/jpeg','image/webp'].includes(part.mimeType)
        && typeof part.data === 'string' && part.data.length >= 4 && part.data.length <= 262144
        && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(part.data), 'INFERENCE_IMAGE_INVALID');
      imageCount++; imageBytes += part.data.length; modalities.add('image');
    } else throw new InferenceError('INFERENCE_MODALITY_UNSUPPORTED');
  }
  bounded(raw); demand(textBytes > 0 || imageCount > 0, 'INFERENCE_INPUT_INVALID');
  const normalized = structuredClone(raw);
  return immutable({...normalized, textBytes, inputBytes:textBytes+imageBytes, imageCount, modalities:[...modalities].sort(), requestDigest:sha256(normalized)});
}
const finite = v => typeof v === 'number' && Number.isFinite(v);
const optionalMetric = value => value === null || (finite(value) && value >= 0);
const keyOf = m => `${m.provider}:${m.model}`;
function validateModel(m) {
  exact(m, ['provider','model','modelRevision','configurationDigest','classes','modalities','executionBoundary','riskTier',
    'contextTokens','maxInputBytes','maxOutputTokens','imageTokenUpperBound','transport','approved','approvalRef','approvalExpiresAt',
    'available','healthObservedAt','estimatedLatencyMs','maxCostMicros','maxConcurrency']);
  demand(ID.test(m.provider) && m.provider === m.provider.toLowerCase() && ID.test(m.model), 'INFERENCE_CATALOG_ID_INVALID');
  demand(m.modelRevision === null || ID.test(m.modelRevision), 'INFERENCE_CATALOG_REVISION_INVALID');
  demand(DIGEST.test(m.configurationDigest) && ['cloud','phone'].includes(m.executionBoundary), 'INFERENCE_CATALOG_INVALID');
  demand(Array.isArray(m.classes) && m.classes.length > 0 && m.classes.every(c => CAPABILITY_CLASSES.includes(c))
    && new Set(m.classes).size === m.classes.length, 'INFERENCE_CATALOG_CLASS_INVALID');
  demand(Array.isArray(m.modalities) && m.modalities.length > 0 && m.modalities.every(c => ['text','image'].includes(c)), 'INFERENCE_CATALOG_MODALITY_INVALID');
  demand(integer(m.riskTier, 0, 3) && integer(m.contextTokens, 1, 10000000)
    && integer(m.maxInputBytes, 1, 1048576) && integer(m.maxOutputTokens, 1, 65536)
    && integer(m.imageTokenUpperBound, 0, 1000000) && integer(m.maxConcurrency, 1, 128), 'INFERENCE_CATALOG_LIMIT_INVALID');
  demand(m.approved === true && typeof m.approvalRef === 'string' && m.approvalRef.length >= 8 && m.approvalRef.length <= 500
    && Number.isFinite(Date.parse(m.approvalExpiresAt)) && Number.isFinite(Date.parse(m.healthObservedAt)), 'INFERENCE_CATALOG_APPROVAL_INVALID');
  demand(typeof m.available === 'boolean' && ID.test(m.transport) && optionalMetric(m.estimatedLatencyMs)
    && (m.maxCostMicros === null || integer(m.maxCostMicros, 0, 1000000000000)), 'INFERENCE_CATALOG_METRIC_INVALID');
  if (m.modalities.includes('image')) demand(m.imageTokenUpperBound > 0, 'INFERENCE_IMAGE_BUDGET_REQUIRED');
}
export function validatePolicy(raw) {
  exact(raw, ['version','models','maxAttempts','maxHealthAgeMs','minHistorySamples','maxHistoryAgeMs','minimumRiskTier',
    'allowedBoundaries','allowedProviders','allowedFallbackCodes','override','requireMemoryContext']);
  demand(ID.test(raw.version) && Array.isArray(raw.models) && raw.models.length <= 64, 'INFERENCE_POLICY_INVALID');
  demand(integer(raw.maxAttempts, 1, 3) && integer(raw.maxHealthAgeMs, 1000, 3600000)
    && integer(raw.minHistorySamples, 1, 1000000) && integer(raw.maxHistoryAgeMs, 1000, 31536000000), 'INFERENCE_POLICY_LIMIT_INVALID');
  exact(raw.minimumRiskTier, ['read','source','preview','production','destructive']);
  demand(Object.values(raw.minimumRiskTier).every(v => integer(v, 0, 3)), 'INFERENCE_RISK_POLICY_INVALID');
  demand(Array.isArray(raw.allowedBoundaries) && raw.allowedBoundaries.length > 0 && raw.allowedBoundaries.every(x => ['phone','cloud'].includes(x))
    && Array.isArray(raw.allowedProviders) && raw.allowedProviders.length > 0 && raw.allowedProviders.every(x => ID.test(x)), 'INFERENCE_POLICY_SCOPE_INVALID');
  demand(Array.isArray(raw.allowedFallbackCodes) && raw.allowedFallbackCodes.every(x => ['rate_limit','unavailable','invalid_output','verification_failed'].includes(x))
    && typeof raw.requireMemoryContext === 'boolean', 'INFERENCE_FALLBACK_POLICY_INVALID');
  if (raw.override !== null) {
    exact(raw.override, ['provider','model','principalKey','taskId','expiresAt','evidenceRef','allowFallback']);
    demand(ID.test(raw.override.provider) && ID.test(raw.override.model) && ID.test(raw.override.principalKey)
      && ID.test(raw.override.taskId) && Number.isFinite(Date.parse(raw.override.expiresAt))
      && typeof raw.override.evidenceRef === 'string' && raw.override.evidenceRef.length >= 8
      && raw.override.evidenceRef.length <= 500 && typeof raw.override.allowFallback === 'boolean', 'INFERENCE_OVERRIDE_INVALID');
  }
  const keys = new Set();
  for (const m of raw.models) { validateModel(m); demand(!keys.has(keyOf(m)), 'INFERENCE_CATALOG_DUPLICATE'); keys.add(keyOf(m)); }
  bounded(raw, 131072); return immutable(structuredClone(raw));
}
function performanceFor(model, taskClass, evidence, policy, now) {
  if (!evidence || evidence.state !== 'available') return null;
  demand(evidence.authorizationGranted === false && evidence.providerApprovalGranted === false
    && evidence.summingSamplesAllowed === false && Array.isArray(evidence.records), 'INFERENCE_HISTORY_AUTHORITY_INVALID');
  const matches = evidence.records.filter(r => r.provider === model.provider && r.model === model.model
    && r.modelRevision === model.modelRevision && r.configurationDigest === model.configurationDigest && r.taskClass === taskClass
    && r.canonStatus === 'hard_canon' && r.recordType === 'provider_performance' && DIGEST.test(r.recordDigest)
    && integer(r.sampleCount, policy.minHistorySamples, Number.MAX_SAFE_INTEGER)
    && integer(r.verificationPassCount, 0, r.sampleCount) && integer(r.negativeOutcomeCount, 0, r.sampleCount)
    && Date.parse(r.approvedAt) <= now && Date.parse(r.reviewDueAt) > now
    && Date.parse(r.evidenceWindowEnd) <= now && now - Date.parse(r.evidenceWindowEnd) <= policy.maxHistoryAgeMs);
  demand(matches.length <= 1, 'INFERENCE_OVERLAPPING_HISTORY');
  if (!matches.length) return null;
  const r = matches[0];
  return {passRate:r.verificationPassCount/r.sampleCount, negativeRate:r.negativeOutcomeCount/r.sampleCount,
    sampleCount:r.sampleCount, evidenceRef:`memory-record:${r.memoryItemId}`, digest:r.recordDigest};
}
/** Pure deterministic selection. Scope/policy/evidence must come from the authenticated service, never the model. */
export function selectCandidates(request, rawPolicy, scope, evidence, {now = Date.now(), transports = [], executionBoundary = 'cloud', excluded = []} = {}) {
  const policy = validatePolicy(rawPolicy);
  demand(record(scope) && ID.test(scope.principalKey) && scope.taskId === request.taskId
    && Object.hasOwn(policy.minimumRiskTier, scope.risk), 'INFERENCE_SCOPE_INVALID');
  if (request.taskClass === 'local_private' && executionBoundary !== 'phone') throw new InferenceError('INFERENCE_PHONE_LOCAL_REQUIRED');
  const override = policy.override;
  if (override) demand(override.principalKey === scope.principalKey && override.taskId === scope.taskId
    && Date.parse(override.expiresAt) > now, 'INFERENCE_OVERRIDE_SCOPE_INVALID');
  const rejected = [], candidates = [];
  for (const model of policy.models) {
    const key = keyOf(model), reasons = [];
    if (!policy.allowedProviders.includes(model.provider) || !policy.allowedBoundaries.includes(model.executionBoundary)) reasons.push('security_policy');
    if (request.taskClass === 'local_private' && model.executionBoundary !== 'phone') reasons.push('local_private');
    if (!model.classes.includes(request.taskClass)) reasons.push('capability');
    if (model.riskTier < policy.minimumRiskTier[scope.risk]) reasons.push('risk');
    if (!request.modalities.every(x => model.modalities.includes(x))) reasons.push('modality');
    // A byte-per-token ceiling for text plus an approved per-image ceiling is deliberately conservative.
    const tokenCeiling = request.textBytes + request.imageCount * model.imageTokenUpperBound + request.maxOutputTokens;
    if (request.inputBytes > model.maxInputBytes || tokenCeiling > model.contextTokens || request.maxOutputTokens > model.maxOutputTokens) reasons.push('context');
    if (!model.available || Date.parse(model.healthObservedAt) > now + 5000 || now - Date.parse(model.healthObservedAt) > policy.maxHealthAgeMs
      || Date.parse(model.approvalExpiresAt) <= now) reasons.push('unavailable_or_stale');
    if (!transports.includes(model.transport) || excluded.includes(key)) reasons.push('transport_or_attempted');
    if (model.maxCostMicros === null || model.maxCostMicros > request.maxCostMicros) reasons.push('budget_or_unknown_ceiling');
    if (reasons.length) { rejected.push({key,reasons}); continue; }
    candidates.push({...model,key,history:performanceFor(model,request.taskClass,evidence,policy,now)});
  }
  if (override && !candidates.some(m => m.provider === override.provider && m.model === override.model)
    && !override.allowFallback) throw new InferenceError('INFERENCE_FORCED_MODEL_UNAVAILABLE');
  candidates.sort((a,b) => {
    const forced = m => override && m.provider === override.provider && m.model === override.model ? 1 : 0;
    if (forced(a) !== forced(b)) return forced(b)-forced(a);
    if (['source','production','destructive'].includes(scope.risk) && a.riskTier !== b.riskTier) return b.riskTier-a.riskTier;
    // Missing history is unknown, not a fabricated zero score. Compare only compatible known records.
    // Known compatible evidence is its own ordered tier; unknown is not a numeric zero.
    if (Boolean(a.history) !== Boolean(b.history)) return a.history ? -1 : 1;
    if (a.history && b.history) {
      const delta = b.history.passRate-a.history.passRate || a.history.negativeRate-b.history.negativeRate;
      if (delta) return delta;
    }
    if (a.estimatedLatencyMs !== null && b.estimatedLatencyMs !== null && a.estimatedLatencyMs !== b.estimatedLatencyMs) return a.estimatedLatencyMs-b.estimatedLatencyMs;
    return a.maxCostMicros-b.maxCostMicros || a.key.localeCompare(b.key);
  });
  const limited = override && !override.allowFallback ? candidates.filter(m => forcedMatch(m, override)).slice(0,1) : candidates;
  return {policyVersion:policy.version,policyDigest:sha256(policy),candidates:limited.slice(0,policy.maxAttempts),rejected,
    historyState:evidence?.state || 'unavailable',authorizationGranted:false};
}
function forcedMatch(m,o) {return m.provider===o.provider && m.model===o.model;}
