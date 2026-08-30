
'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');
const { RISK_CLASSES, riskRank } = require('../skills/registry.js');

const KNOWLEDGE_TRUST_STATES = Object.freeze([
  'DISCOVERED',
  'IMPORTED',
  'EXPERIMENTAL',
  'VERIFIED',
  'TRUSTED',
  'DEPRECATED',
  'BLOCKED',
]);

const EXACT_SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?$/;

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function optionalText(value, field) {
  if (value == null) return null;
  return requiredText(value, field);
}

/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => requiredText(item, `${field}[${index}]`));
}

/** @param {unknown} value @param {readonly string[]} allowed @param {string} field */
function enumValue(value, allowed, field) {
  const parsed = requiredText(value, field);
  if (!allowed.includes(parsed)) throw new TypeError(`${field} must be one of: ${allowed.join(', ')}`);
  return parsed;
}

/** @param {unknown} value @param {string} field */
function isoDateOrNull(value, field) {
  if (value == null) return null;
  const text = requiredText(value, field);
  if (Number.isNaN(Date.parse(text))) throw new TypeError(`${field} must be an ISO date`);
  return new Date(text).toISOString();
}

/** @param {unknown} value */
function sourceMetadata(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('source is required');
  const source = /** @type {Record<string, unknown>} */ (value);
  return Object.freeze({
    repository: optionalText(source.repository, 'source.repository'),
    commit: optionalText(source.commit, 'source.commit'),
    path: optionalText(source.path, 'source.path'),
    url: optionalText(source.url, 'source.url'),
    license: optionalText(source.license, 'source.license'),
    upstreamAuthority: optionalText(source.upstreamAuthority, 'source.upstreamAuthority'),
  });
}

/** @param {Record<string, unknown>} input */
function normalizeKnowledgeEntry(input) {
  assertNoCredentialMaterial(input);
  const knowledgeId = requiredText(input.knowledgeId, 'knowledgeId');
  const version = requiredText(input.version, 'version');
  if (!EXACT_SEMVER.test(version)) throw new TypeError('version must be an exact semantic version; mutable aliases such as latest are forbidden');
  const topics = stringList(input.topics, 'topics');
  if (!topics.length) throw new TypeError('topics must not be empty');
  const summary = requiredText(input.summary, 'summary');
  if (summary.length > 12000) throw new TypeError('summary exceeds the bounded knowledge size');
  const trustState = input.trustState == null ? 'EXPERIMENTAL' : enumValue(input.trustState, KNOWLEDGE_TRUST_STATES, 'trustState');
  const riskClass = input.riskClass == null ? 'INFORMATIONAL' : enumValue(input.riskClass, RISK_CLASSES, 'riskClass');

  return Object.freeze({
    knowledgeId,
    version,
    title: optionalText(input.title, 'title'),
    topics: Object.freeze(topics),
    summary,
    riskClass,
    trustState,
    platforms: Object.freeze(stringList(input.platforms, 'platforms')),
    sourceDigest: optionalText(input.sourceDigest, 'sourceDigest'),
    source: sourceMetadata(input.source),
    verifiedAt: isoDateOrNull(input.verifiedAt, 'verifiedAt'),
    expiresAt: isoDateOrNull(input.expiresAt, 'expiresAt'),
    verification: null,
  });
}

/** @param {Readonly<Record<string, unknown>>} entry @param {number} nowMs */
function isExpired(entry, nowMs = Date.now()) {
  if (typeof entry.expiresAt !== 'string') return false;
  return Date.parse(entry.expiresAt) <= nowMs;
}

/** @param {string} query */
function queryTokens(query) {
  return [...new Set(query.toLowerCase().split(/[^a-z0-9_.-]+/).filter((token) => token.length > 2))];
}

/** @param {Readonly<Record<string, unknown>>} entry @param {string[]} topics @param {string[]} tokens */
function relevanceScore(entry, topics, tokens) {
  const entryTopics = /** @type {readonly string[]} */ (entry.topics);
  let score = topics.reduce((total, topic) => total + (entryTopics.includes(topic) ? 20 : 0), 0);
  const haystack = `${String(entry.title ?? '')} ${String(entry.summary ?? '')} ${entryTopics.join(' ')}`.toLowerCase();
  score += tokens.reduce((total, token) => total + (haystack.includes(token) ? 2 : 0), 0);
  if (entry.trustState === 'TRUSTED') score += 5;
  return score;
}

class PandoraKnowledgeRegistry {
  constructor() {
    /** @type {Map<string, Readonly<Record<string, unknown>>>} */
    this.entries = new Map();
  }

  /** @param {Record<string, unknown>} input */
  register(input) {
    const entry = normalizeKnowledgeEntry(input);
    const key = `${entry.knowledgeId}@${entry.version}`;
    if (this.entries.has(key)) throw new Error(`knowledge already registered: ${key}`);
    this.entries.set(key, entry);
    return entry;
  }

  /** @param {string} knowledgeId @param {string} version */
  get(knowledgeId, version) {
    return this.entries.get(`${knowledgeId}@${version}`) ?? null;
  }

  list() {
    return [...this.entries.values()];
  }

  /**
   * @param {{topics?:string[], query?:string, maxRisk?:string, trustedOnly?:boolean, limit?:number, nowMs?:number}} query
   */
  findRelevant(query = {}) {
    const topics = Array.isArray(query.topics) ? query.topics.map(String) : [];
    const tokens = queryTokens(String(query.query ?? ''));
    const maxRiskRank = riskRank(query.maxRisk ?? 'DESTRUCTIVE');
    const trustedOnly = query.trustedOnly !== false;
    const limit = Number.isInteger(query.limit) && Number(query.limit) > 0 ? Number(query.limit) : 8;
    const nowMs = typeof query.nowMs === 'number' && Number.isFinite(query.nowMs) ? query.nowMs : Date.now();
    return this.list()
      .filter((entry) => {
        if (trustedOnly && entry.trustState !== 'TRUSTED') return false;
        if (entry.trustState === 'BLOCKED' || entry.trustState === 'DEPRECATED') return false;
        if (riskRank(String(entry.riskClass)) > maxRiskRank) return false;
        if (isExpired(entry, nowMs)) return false;
        if (!topics.length && !tokens.length) return true;
        return relevanceScore(entry, topics, tokens) > 0;
      })
      .map((entry) => ({ entry, score: relevanceScore(entry, topics, tokens) }))
      .sort((a, b) => b.score - a.score || String(a.entry.knowledgeId).localeCompare(String(b.entry.knowledgeId)))
      .slice(0, limit)
      .map(({ entry }) => entry);
  }

  /**
   * @param {string} knowledgeId
   * @param {string} version
   * @param {{worker:string, verdict:string, sourceDigest:string, evidenceId:string, verifiedAt?:string, expiresAt?:string}} evidence
   */
  certify(knowledgeId, version, evidence) {
    const key = `${knowledgeId}@${version}`;
    const existing = this.entries.get(key);
    if (!existing) throw new Error(`knowledge not found: ${key}`);
    if (existing.trustState === 'BLOCKED' || existing.trustState === 'DEPRECATED') {
      throw new Error(`knowledge cannot be certified from ${existing.trustState} state`);
    }
    if (evidence.worker !== 'E') throw new Error('only Worker E verification evidence may certify knowledge');
    if (evidence.verdict !== 'PASS') throw new Error('knowledge certification requires PASS evidence');
    const sourceDigest = String(existing.sourceDigest ?? '');
    if (!sourceDigest) throw new Error('knowledge sourceDigest is required before certification');
    if (evidence.sourceDigest !== sourceDigest) throw new Error('knowledge verification source digest mismatch');
    const evidenceId = requiredText(evidence.evidenceId, 'evidence.evidenceId');
    const verifiedAt = isoDateOrNull(evidence.verifiedAt ?? new Date().toISOString(), 'evidence.verifiedAt');
    const expiresAt = isoDateOrNull(evidence.expiresAt ?? existing.expiresAt, 'evidence.expiresAt');
    const trusted = Object.freeze({
      ...existing,
      trustState: 'TRUSTED',
      verifiedAt,
      expiresAt,
      verification: Object.freeze({ worker: 'E', verdict: 'PASS', sourceDigest, evidenceId }),
    });
    this.entries.set(key, trusted);
    return trusted;
  }
}

module.exports = {
  KNOWLEDGE_TRUST_STATES,
  PandoraKnowledgeRegistry,
  isExpired,
  normalizeKnowledgeEntry,
  relevanceScore,
};
