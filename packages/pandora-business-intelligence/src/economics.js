'use strict';

const COST_CATEGORIES = Object.freeze([
  'model', 'build_compute', 'verification', 'deployment', 'runtime',
  'storage', 'network', 'provider_api', 'other',
]);
const COST_CONFIDENCE = Object.freeze(['unknown', 'estimated', 'actual']);
const DEFAULT_VERIFIED_RESULT_CATEGORIES = Object.freeze(['model', 'build_compute', 'verification']);

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function read(value, camel, snake) { return value?.[camel] ?? value?.[snake] ?? null; }
function requireString(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} is required`);
  return value;
}
function optionalString(value, name) {
  if (value == null) return null;
  if (typeof value !== 'string' || value.trim() === '') throw new TypeError(`${name} must be a non-empty string`);
  return value;
}
function nonNegativeInteger(value, name, { nullable = false } = {}) {
  if (value == null && nullable) return null;
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`${name} must be a non-negative safe integer`);
  return value;
}
function finiteNumber(value, name, { nullable = false } = {}) {
  if (value == null && nullable) return null;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError(`${name} must be finite`);
  return value;
}
function assertCurrency(value) {
  const currency = value ?? 'USD';
  if (typeof currency !== 'string' || !/^[A-Z]{3}$/.test(currency)) throw new TypeError('currency must be a three-letter ISO code');
  return currency;
}
function freezeArray(values) { return Object.freeze(values.map((value) => Object.freeze(value))); }

function costConfidence({ billedCostMicros, estimatedCostMicros }) {
  if (billedCostMicros > 0) return 'actual';
  if (estimatedCostMicros > 0) return 'estimated';
  return 'unknown';
}

function normalizeCostEntry(input) {
  if (!isObject(input)) throw new TypeError('cost entry must be an object');
  const category = requireString(read(input, 'costCategory', 'cost_category'), 'costCategory');
  if (!COST_CATEGORIES.includes(category)) throw new TypeError(`unsupported cost category: ${category}`);
  const metadata = isObject(read(input, 'metadataRedacted', 'metadata_redacted')) ? read(input, 'metadataRedacted', 'metadata_redacted') : {};
  const estimatedCostMicros = nonNegativeInteger(read(input, 'estimatedCostMicros', 'estimated_cost_micros') ?? 0, 'estimatedCostMicros');
  const billedCostMicros = nonNegativeInteger(read(input, 'billedCostMicros', 'billed_cost_micros') ?? 0, 'billedCostMicros');
  const chargedCostMicros = nonNegativeInteger(read(input, 'chargedCostMicros', 'charged_cost_micros') ?? 0, 'chargedCostMicros');
  const creditMicros = nonNegativeInteger(read(input, 'creditMicros', 'credit_micros') ?? 0, 'creditMicros');
  const confidence = costConfidence({ billedCostMicros, estimatedCostMicros });
  const internalCostMicros = confidence === 'actual' ? billedCostMicros : confidence === 'estimated' ? estimatedCostMicros : null;

  return Object.freeze({
    id: optionalString(input.id, 'id'),
    organizationId: requireString(read(input, 'organizationId', 'organization_id'), 'organizationId'),
    projectId: requireString(read(input, 'projectId', 'project_id'), 'projectId'),
    projectSpecId: optionalString(read(input, 'projectSpecId', 'project_spec_id'), 'projectSpecId'),
    buildJobId: optionalString(read(input, 'buildJobId', 'build_job_id'), 'buildJobId'),
    modelRunId: optionalString(read(input, 'modelRunId', 'model_run_id'), 'modelRunId'),
    toolCallId: optionalString(read(input, 'toolCallId', 'tool_call_id'), 'toolCallId'),
    projectVersionId: optionalString(read(input, 'projectVersionId', 'project_version_id'), 'projectVersionId'),
    budgetLimitId: optionalString(read(input, 'budgetLimitId', 'budget_limit_id'), 'budgetLimitId'),
    costCategory: category,
    provider: optionalString(input.provider, 'provider'),
    environment: optionalString(input.environment, 'environment'),
    quantity: finiteNumber(input.quantity ?? 0, 'quantity'),
    unit: requireString(input.unit ?? 'unit', 'unit'),
    estimatedCostMicros,
    billedCostMicros,
    chargedCostMicros,
    creditMicros,
    internalCostMicros,
    confidence,
    currency: assertCurrency(input.currency),
    idempotencyKey: optionalString(read(input, 'idempotencyKey', 'idempotency_key'), 'idempotencyKey'),
    pricingVersion: optionalString(metadata.pricing_version ?? metadata.pricingVersion ?? null, 'pricingVersion'),
    pricingSource: optionalString(metadata.pricing_source ?? metadata.pricingSource ?? null, 'pricingSource'),
    retry: metadata.retry === true || metadata.is_retry === true,
    repairAttempt: metadata.repair_attempt === true || metadata.repairAttempt === true,
    metadataRedacted: Object.freeze({ ...metadata }),
    occurredAt: optionalString(read(input, 'occurredAt', 'occurred_at'), 'occurredAt'),
  });
}

function assertScope(record, scope, { allowUnattributedVersion = false } = {}) {
  if (!isObject(scope)) throw new TypeError('scope is required');
  const organizationId = requireString(scope.organizationId, 'scope.organizationId');
  const projectId = requireString(scope.projectId, 'scope.projectId');
  if (record.organizationId !== organizationId) throw new Error('CROSS_ORG_ACCESS');
  if (record.projectId !== projectId) throw new Error('CROSS_PROJECT_ACCESS');
  if (scope.projectVersionId) {
    if (record.projectVersionId == null && !allowUnattributedVersion) throw new Error('UNATTRIBUTED_VERSION_COST');
    if (record.projectVersionId != null && record.projectVersionId !== scope.projectVersionId) throw new Error('CROSS_VERSION_COST');
  }
  return true;
}

function normalizeScopedEntries(entries, scope, options = {}) {
  if (!Array.isArray(entries)) throw new TypeError('entries must be an array');
  return entries.map(normalizeCostEntry).filter((entry) => {
    assertScope(entry, scope, options);
    return true;
  });
}

function summarizeCostEntries(entries, scope, options = {}) {
  const normalized = normalizeScopedEntries(entries, scope, options);
  const currency = normalized[0]?.currency ?? options.currency ?? 'USD';
  if (normalized.some((entry) => entry.currency !== currency)) throw new Error('MIXED_CURRENCY_COSTS');
  const knownCostMicros = normalized.reduce((sum, entry) => sum + (entry.internalCostMicros ?? 0), 0);
  const chargedMicros = normalized.reduce((sum, entry) => sum + entry.chargedCostMicros, 0);
  const creditsMicros = normalized.reduce((sum, entry) => sum + entry.creditMicros, 0);
  const unknownEntries = normalized.filter((entry) => entry.internalCostMicros == null);
  const estimatedEntries = normalized.filter((entry) => entry.confidence === 'estimated');
  const actualEntries = normalized.filter((entry) => entry.confidence === 'actual');
  const byCategory = {};
  for (const entry of normalized) {
    const bucket = byCategory[entry.costCategory] ?? { knownCostMicros: 0, entryCount: 0, unknownCount: 0, estimatedCount: 0, actualCount: 0 };
    bucket.entryCount += 1;
    if (entry.internalCostMicros == null) bucket.unknownCount += 1;
    else bucket.knownCostMicros += entry.internalCostMicros;
    if (entry.confidence === 'estimated') bucket.estimatedCount += 1;
    if (entry.confidence === 'actual') bucket.actualCount += 1;
    byCategory[entry.costCategory] = bucket;
  }
  return Object.freeze({
    currency,
    entryCount: normalized.length,
    knownCostMicros,
    totalInternalCostMicros: unknownEntries.length === 0 ? knownCostMicros : null,
    chargedMicros,
    creditsMicros,
    netCustomerChargeMicros: Math.max(0, chargedMicros - creditsMicros),
    unknownCount: unknownEntries.length,
    estimatedCount: estimatedEntries.length,
    actualCount: actualEntries.length,
    confidence: unknownEntries.length > 0 ? 'unknown' : estimatedEntries.length > 0 ? 'estimated' : actualEntries.length > 0 ? 'actual' : 'unknown',
    byCategory: Object.freeze(Object.fromEntries(Object.entries(byCategory).map(([key, value]) => [key, Object.freeze({ ...value })]))),
  });
}

function totalCostToVerifiedResult(entries, scope, options = {}) {
  const requiredCategories = options.requiredCategories ?? DEFAULT_VERIFIED_RESULT_CATEGORIES;
  if (!Array.isArray(requiredCategories) || requiredCategories.length === 0) throw new TypeError('requiredCategories must be a non-empty array');
  const normalized = normalizeScopedEntries(entries, scope, options);
  const summary = summarizeCostEntries(normalized, scope, options);
  const present = new Set(normalized.map((entry) => entry.costCategory));
  const missingCategories = requiredCategories.filter((category) => !present.has(category));
  const unknownRequiredEntries = normalized.filter((entry) => requiredCategories.includes(entry.costCategory) && entry.internalCostMicros == null);
  const requiredKnownCostMicros = normalized
    .filter((entry) => requiredCategories.includes(entry.costCategory))
    .reduce((sum, entry) => sum + (entry.internalCostMicros ?? 0), 0);
  const complete = missingCategories.length === 0 && unknownRequiredEntries.length === 0;
  return Object.freeze({
    scope: Object.freeze({ ...scope }),
    currency: summary.currency,
    requiredCategories: Object.freeze([...requiredCategories]),
    missingCategories: Object.freeze(missingCategories),
    unknownRequiredEntries: unknownRequiredEntries.length,
    totalCostMicros: complete ? requiredKnownCostMicros : null,
    knownCostMicros: requiredKnownCostMicros,
    complete,
    confidence: complete ? summary.confidence : 'unknown',
    includesRetries: normalized.some((entry) => entry.retry),
    includesRepairs: normalized.some((entry) => entry.repairAttempt),
  });
}

function summarizeRepairSpend(entries, scope, { capMicros = null, ...options } = {}) {
  const normalized = normalizeScopedEntries(entries, scope, options).filter((entry) => entry.retry || entry.repairAttempt);
  const unknownCount = normalized.filter((entry) => entry.internalCostMicros == null).length;
  const knownSpendMicros = normalized.reduce((sum, entry) => sum + (entry.internalCostMicros ?? 0), 0);
  const cap = capMicros == null ? null : nonNegativeInteger(capMicros, 'capMicros');
  return Object.freeze({
    attemptCount: normalized.length,
    knownSpendMicros,
    totalSpendMicros: unknownCount === 0 ? knownSpendMicros : null,
    unknownCount,
    capMicros: cap,
    remainingMicros: cap == null ? null : Math.max(0, cap - knownSpendMicros),
    exhausted: cap == null ? false : knownSpendMicros >= cap,
  });
}

function normalizeBudgetLimit(input) {
  if (!isObject(input)) throw new TypeError('budget limit must be an object');
  const hardLimitMicros = nonNegativeInteger(read(input, 'hardLimitMicros', 'hard_limit_micros'), 'hardLimitMicros');
  const warningLimitMicros = nonNegativeInteger(read(input, 'warningLimitMicros', 'warning_limit_micros') ?? 0, 'warningLimitMicros');
  const reservedMicros = nonNegativeInteger(read(input, 'reservedMicros', 'reserved_micros') ?? 0, 'reservedMicros');
  const spentMicros = nonNegativeInteger(read(input, 'spentMicros', 'spent_micros') ?? 0, 'spentMicros');
  if (warningLimitMicros > hardLimitMicros) throw new TypeError('warningLimitMicros cannot exceed hardLimitMicros');
  if (reservedMicros + spentMicros > hardLimitMicros) throw new TypeError('committed budget usage cannot exceed hardLimitMicros');
  return Object.freeze({
    id: optionalString(input.id, 'id'),
    organizationId: requireString(read(input, 'organizationId', 'organization_id'), 'organizationId'),
    projectId: requireString(read(input, 'projectId', 'project_id'), 'projectId'),
    budgetKind: requireString(read(input, 'budgetKind', 'budget_kind'), 'budgetKind'),
    scopeKey: requireString(read(input, 'scopeKey', 'scope_key'), 'scopeKey'),
    currency: assertCurrency(input.currency),
    warningLimitMicros,
    hardLimitMicros,
    reservedMicros,
    spentMicros,
    status: input.status ?? 'active',
  });
}

function budgetPolicySignal(limitInput, { requestedAdditionalMicros = 0 } = {}) {
  const limit = normalizeBudgetLimit(limitInput);
  const requested = nonNegativeInteger(requestedAdditionalMicros, 'requestedAdditionalMicros');
  const committed = limit.spentMicros + limit.reservedMicros;
  const remaining = Math.max(0, limit.hardLimitMicros - committed);
  const exhausted = limit.status === 'exhausted' || remaining <= 0;
  const warningCrossed = limit.warningLimitMicros > 0 && committed + requested >= limit.warningLimitMicros;
  const exceedsRemaining = requested > remaining;
  return Object.freeze({
    exhausted,
    remaining_units: remaining,
    requires_approval_for_extra_spend: !exhausted && (warningCrossed || exceedsRemaining),
    budget_kind: limit.budgetKind,
    scope_key: limit.scopeKey,
    currency: limit.currency,
    requested_additional_micros: requested,
    hard_limit_micros: limit.hardLimitMicros,
    spent_micros: limit.spentMicros,
    reserved_micros: limit.reservedMicros,
  });
}

function grossMargin({ customerChargeMicros = null, creditsMicros = 0, internalCostMicros = null, currency = 'USD' }) {
  const charge = nonNegativeInteger(customerChargeMicros, 'customerChargeMicros', { nullable: true });
  const credits = nonNegativeInteger(creditsMicros, 'creditsMicros');
  const cost = nonNegativeInteger(internalCostMicros, 'internalCostMicros', { nullable: true });
  const normalizedCurrency = assertCurrency(currency);
  if (charge == null || cost == null) return Object.freeze({ marginMicros: null, marginRate: null, complete: false, currency: normalizedCurrency });
  const netRevenueMicros = Math.max(0, charge - credits);
  const marginMicros = netRevenueMicros - cost;
  return Object.freeze({
    netRevenueMicros,
    marginMicros,
    marginRate: netRevenueMicros === 0 ? null : marginMicros / netRevenueMicros,
    complete: true,
    currency: normalizedCurrency,
  });
}

function priceModelUsage(input) {
  if (!isObject(input)) throw new TypeError('model usage is required');
  const inputTokens = nonNegativeInteger(input.inputTokens ?? 0, 'inputTokens');
  const outputTokens = nonNegativeInteger(input.outputTokens ?? 0, 'outputTokens');
  const cachedInputTokens = nonNegativeInteger(input.cachedInputTokens ?? 0, 'cachedInputTokens');
  const pricingVersion = requireString(input.pricingVersion, 'pricingVersion');
  const pricingSource = requireString(input.pricingSource, 'pricingSource');
  if (!isObject(input.rates)) throw new TypeError('rates are required');
  const inputRate = nonNegativeInteger(input.rates.inputMicrosPerMillionTokens ?? 0, 'inputMicrosPerMillionTokens');
  const outputRate = nonNegativeInteger(input.rates.outputMicrosPerMillionTokens ?? 0, 'outputMicrosPerMillionTokens');
  const cachedRate = nonNegativeInteger(input.rates.cachedInputMicrosPerMillionTokens ?? inputRate, 'cachedInputMicrosPerMillionTokens');
  if (cachedInputTokens > inputTokens) throw new TypeError('cachedInputTokens cannot exceed inputTokens');
  const uncachedInputTokens = inputTokens - cachedInputTokens;
  const estimatedCostMicros = Math.round((uncachedInputTokens * inputRate + cachedInputTokens * cachedRate + outputTokens * outputRate) / 1_000_000);
  return Object.freeze({
    inputTokens,
    cachedInputTokens,
    uncachedInputTokens,
    outputTokens,
    estimatedCostMicros,
    confidence: 'estimated',
    pricingVersion,
    pricingSource,
  });
}

function qualityPerDollar(candidates) {
  if (!Array.isArray(candidates)) throw new TypeError('candidates must be an array');
  const evaluated = candidates.map((candidate, index) => {
    if (!isObject(candidate)) throw new TypeError(`candidate[${index}] must be an object`);
    const id = requireString(candidate.id ?? candidate.model, `candidate[${index}].id`);
    const qualityScore = finiteNumber(candidate.qualityScore, `candidate[${index}].qualityScore`);
    if (qualityScore < 0 || qualityScore > 1) throw new TypeError('qualityScore must be between 0 and 1');
    const costMicros = nonNegativeInteger(candidate.costMicros, `candidate[${index}].costMicros`, { nullable: true });
    const verified = candidate.verified === true;
    const score = costMicros == null || costMicros === 0 ? null : (qualityScore * (verified ? 1 : 0.5)) / costMicros;
    return Object.freeze({ id, qualityScore, costMicros, verified, score });
  });
  const comparable = evaluated.filter((row) => row.score != null).sort((a, b) => b.score - a.score);
  return Object.freeze({
    ranked: freezeArray(comparable),
    unknownCost: freezeArray(evaluated.filter((row) => row.costMicros == null)),
    recommendedId: comparable[0]?.id ?? null,
    recommendationBasis: comparable.length > 0 ? 'verified_quality_per_cost' : 'insufficient_cost_data',
  });
}

function modelEconomics(runs) {
  if (!Array.isArray(runs)) throw new TypeError('runs must be an array');
  const groups = new Map();
  for (const [index, run] of runs.entries()) {
    if (!isObject(run)) throw new TypeError(`run[${index}] must be an object`);
    const model = requireString(run.model, `run[${index}].model`);
    const bucket = groups.get(model) ?? { model, runs: 0, verifiedPasses: 0, knownCostMicros: 0, unknownCostCount: 0, qualityTotal: 0, qualityCount: 0 };
    bucket.runs += 1;
    if (run.verified === true) bucket.verifiedPasses += 1;
    if (run.costMicros == null) bucket.unknownCostCount += 1;
    else bucket.knownCostMicros += nonNegativeInteger(run.costMicros, `run[${index}].costMicros`);
    if (run.qualityScore != null) {
      const quality = finiteNumber(run.qualityScore, `run[${index}].qualityScore`);
      if (quality < 0 || quality > 1) throw new TypeError('qualityScore must be between 0 and 1');
      bucket.qualityTotal += quality;
      bucket.qualityCount += 1;
    }
    groups.set(model, bucket);
  }
  const rows = [...groups.values()].map((bucket) => Object.freeze({
    model: bucket.model,
    runs: bucket.runs,
    verifiedPasses: bucket.verifiedPasses,
    verifiedPassRate: bucket.runs === 0 ? null : bucket.verifiedPasses / bucket.runs,
    totalCostMicros: bucket.unknownCostCount === 0 ? bucket.knownCostMicros : null,
    knownCostMicros: bucket.knownCostMicros,
    unknownCostCount: bucket.unknownCostCount,
    costPerVerifiedResultMicros: bucket.unknownCostCount === 0 && bucket.verifiedPasses > 0 ? bucket.knownCostMicros / bucket.verifiedPasses : null,
    averageQuality: bucket.qualityCount > 0 ? bucket.qualityTotal / bucket.qualityCount : null,
  }));
  return freezeArray(rows);
}

function roiAssessment({ benefitMicros = null, costMicros = null, benefitConfidence = 'unknown', costConfidence = 'unknown', assumptions = [] }) {
  if (!COST_CONFIDENCE.includes(benefitConfidence) || !COST_CONFIDENCE.includes(costConfidence)) throw new TypeError('invalid ROI confidence');
  const benefit = nonNegativeInteger(benefitMicros, 'benefitMicros', { nullable: true });
  const cost = nonNegativeInteger(costMicros, 'costMicros', { nullable: true });
  if (!Array.isArray(assumptions)) throw new TypeError('assumptions must be an array');
  const complete = benefit != null && cost != null && cost > 0;
  return Object.freeze({
    benefitMicros: benefit,
    costMicros: cost,
    roi: complete ? (benefit - cost) / cost : null,
    complete,
    benefitConfidence,
    costConfidence,
    assumptions: Object.freeze(assumptions.map(String)),
    causal: false,
    label: complete ? (benefitConfidence === 'actual' && costConfidence === 'actual' ? 'observed_noncausal' : 'estimate') : 'unknown',
  });
}

function primitiveSavings({ baselineCostMicros = null, composedCostMicros = null, baselineConfidence = 'unknown', composedConfidence = 'unknown', evidence = [] }) {
  const baseline = nonNegativeInteger(baselineCostMicros, 'baselineCostMicros', { nullable: true });
  const composed = nonNegativeInteger(composedCostMicros, 'composedCostMicros', { nullable: true });
  if (!COST_CONFIDENCE.includes(baselineConfidence) || !COST_CONFIDENCE.includes(composedConfidence)) throw new TypeError('invalid savings confidence');
  if (!Array.isArray(evidence)) throw new TypeError('evidence must be an array');
  const complete = baseline != null && composed != null;
  return Object.freeze({
    baselineCostMicros: baseline,
    composedCostMicros: composed,
    savingsMicros: complete ? baseline - composed : null,
    savingsRate: complete && baseline > 0 ? (baseline - composed) / baseline : null,
    complete,
    baselineConfidence,
    composedConfidence,
    evidence: Object.freeze(evidence.map(String)),
    causal: false,
  });
}

module.exports = {
  COST_CATEGORIES,
  COST_CONFIDENCE,
  DEFAULT_VERIFIED_RESULT_CATEGORIES,
  assertScope,
  budgetPolicySignal,
  grossMargin,
  modelEconomics,
  normalizeBudgetLimit,
  normalizeCostEntry,
  priceModelUsage,
  primitiveSavings,
  qualityPerDollar,
  roiAssessment,
  summarizeCostEntries,
  summarizeRepairSpend,
  totalCostToVerifiedResult,
};
