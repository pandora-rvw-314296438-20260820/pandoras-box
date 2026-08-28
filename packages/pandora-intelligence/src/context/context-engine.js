'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

/** @type {Readonly<Record<string, number>>} */
const SOURCE_PRIORITY = Object.freeze({
  project_spec: 100,
  current_task: 95,
  acceptance_criteria: 92,
  exact_error: 90,
  relevant_artifact: 85,
  dependency_metadata: 80,
  durable_decision: 75,
  project_memory: 65,
  prior_attempt: 60,
  conversation: 35,
});

/** @type {Readonly<Record<string, readonly string[]>>} */
const TASK_SOURCE_ALLOWLIST = Object.freeze({
  repair_code: Object.freeze(['project_spec','current_task','acceptance_criteria','exact_error','relevant_artifact','dependency_metadata','durable_decision','project_memory','prior_attempt']),
  inspect_error: Object.freeze(['project_spec','current_task','acceptance_criteria','exact_error','relevant_artifact','dependency_metadata','prior_attempt']),
  compile_project_spec: Object.freeze(['project_spec','current_task','durable_decision','project_memory','conversation']),
  plan_build: Object.freeze(['project_spec','current_task','acceptance_criteria','durable_decision','project_memory','dependency_metadata']),
  derive_acceptance_tests: Object.freeze(['project_spec','current_task','acceptance_criteria','durable_decision']),
});

/** @param {string} value */
function utf8ByteLength(value) {
  let bytes = 0;
  for (const char of value) {
    const code = char.codePointAt(0) ?? 0;
    bytes += code <= 0x7f ? 1 : code <= 0x7ff ? 2 : code <= 0xffff ? 3 : 4;
  }
  return bytes;
}

/** @param {unknown} value */
function estimateTokens(value) {
  const serialized = typeof value === 'string' ? value : JSON.stringify(value ?? null);
  return Math.max(1, Math.ceil(utf8ByteLength(serialized) / 4));
}

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }

/**
 * @param {{task:string,sources:unknown[],maxTokens:number,nowMs?:number}} input
 */
function assembleContext(input) {
  if (!Number.isInteger(input.maxTokens) || input.maxTokens <= 0) throw new TypeError('maxTokens must be positive');
  const nowMs = Number.isFinite(input.nowMs) ? Number(input.nowMs) : Date.now();
  const allowed = TASK_SOURCE_ALLOWLIST[input.task] ?? Object.keys(SOURCE_PRIORITY);
  /** @type {Array<Record<string, unknown>>} */
  const candidates = [];

  for (const sourceValue of Array.isArray(input.sources) ? input.sources : []) {
    if (!isRecord(sourceValue)) continue;
    const source = /** @type {Record<string, unknown>} */ (sourceValue);
    const kind = typeof source.kind === 'string' ? source.kind : '';
    if (!allowed.includes(kind) || !(kind in SOURCE_PRIORITY)) continue;
    assertNoCredentialMaterial(source.content);
    const freshnessMs = typeof source.updatedAt === 'string' ? Date.parse(source.updatedAt) : Number(source.updatedAt ?? 0);
    const ageDays = Number.isFinite(freshnessMs) && freshnessMs > 0 ? Math.max(0, (nowMs - freshnessMs) / 86400000) : 3650;
    const relevance = typeof source.relevance === 'number' && Number.isFinite(source.relevance) ? Math.max(0, Math.min(1, source.relevance)) : 0.5;
    const score = Number(SOURCE_PRIORITY[kind] ?? 0) + relevance * 20 - Math.min(20, ageDays / 30);
    const fullTokens = estimateTokens(source.content);
    const summaryTokens = source.summary !== undefined ? estimateTokens(source.summary) : null;
    candidates.push({
      id: typeof source.id === 'string' ? source.id : `${kind}:${candidates.length}`,
      kind,
      authoritative: source.authoritative === true || kind === 'project_spec',
      content: source.content,
      summary: source.summary,
      fullTokens,
      summaryTokens,
      score,
      updatedAt: source.updatedAt ?? null,
    });
  }

  candidates.sort((a, b) => Number(b.score) - Number(a.score));
  /** @type {Readonly<Record<string, unknown>>[]} */
  const selected = [];
  /** @type {Readonly<Record<string, unknown>>[]} */
  const omitted = [];
  let usedTokens = 0;
  let summarizedCount = 0;

  for (const source of candidates) {
    const fullTokens = Number(source.fullTokens);
    if (usedTokens + fullTokens <= input.maxTokens) {
      selected.push(Object.freeze({ id: source.id, kind: source.kind, content: source.content, authoritative: source.authoritative, summarized: false, estimatedTokens: fullTokens }));
      usedTokens += fullTokens;
      continue;
    }
    const summaryTokens = source.summaryTokens === null ? null : Number(source.summaryTokens);
    if (source.summary !== undefined && summaryTokens !== null && usedTokens + summaryTokens <= input.maxTokens) {
      assertNoCredentialMaterial(source.summary);
      selected.push(Object.freeze({ id: source.id, kind: source.kind, content: source.summary, authoritative: source.authoritative, summarized: true, estimatedTokens: summaryTokens }));
      usedTokens += summaryTokens;
      summarizedCount += 1;
      continue;
    }
    omitted.push(Object.freeze({ id: source.id, kind: source.kind, reason: 'context_budget' }));
  }

  return Object.freeze({
    task: input.task,
    maxTokens: input.maxTokens,
    estimatedTokens: usedTokens,
    selected: Object.freeze(selected),
    omitted: Object.freeze(omitted),
    summarizedCount,
    truncated: omitted.length > 0,
  });
}

module.exports = { SOURCE_PRIORITY, TASK_SOURCE_ALLOWLIST, assembleContext, estimateTokens };
