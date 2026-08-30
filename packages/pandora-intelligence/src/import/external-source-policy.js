
'use strict';

const EXTERNAL_SOURCE_MODES = Object.freeze([
  'SKILL_SEED',
  'KNOWLEDGE_SEED',
  'BENCHMARK_REFERENCE',
]);

const EXACT_COMMIT = /^[0-9a-f]{40}$/;
const EXACT_SHA256 = /^sha256:[0-9a-f]{64}$/;
const SAFE_PATH = /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/-]+$/;

/**
 * @typedef {{
 *   sourceId:string,
 *   repository:string,
 *   upstreamRepository:string,
 *   commit:string,
 *   mode:string,
 *   license:string,
 *   licenseStatus:string,
 *   contentImportAllowed:boolean,
 *   referenceOnly:boolean
 * }} ExternalSourcePolicy
 */
/** @type {Readonly<Record<string, Readonly<ExternalSourcePolicy>>>} */
const EXTERNAL_SOURCE_CATALOG = Object.freeze({
  awesome_claude_skills: Object.freeze({
    sourceId: 'awesome_claude_skills',
    repository: 'pandora-rvw-314296438-20260820/awesome-claude-skills',
    upstreamRepository: 'ComposioHQ/awesome-claude-skills',
    commit: 'be2a406907dbc61b73e6827ded415c96139d13a2',
    mode: 'SKILL_SEED',
    license: 'Apache-2.0',
    licenseStatus: 'PER_ENTRY_REVIEW_REQUIRED',
    contentImportAllowed: false,
    referenceOnly: false,
  }),
  router: Object.freeze({
    sourceId: 'router',
    repository: 'pandora-rvw-314296438-20260820/router',
    upstreamRepository: 'workweave/router',
    commit: '16b1480edf5d012f544516df514b1b28ee4ea83e',
    mode: 'BENCHMARK_REFERENCE',
    license: 'Elastic-2.0',
    licenseStatus: 'REFERENCE_ONLY',
    contentImportAllowed: false,
    referenceOnly: true,
  }),
  secret_knowledge: Object.freeze({
    sourceId: 'secret_knowledge',
    repository: 'pandora-rvw-314296438-20260820/the-book-of-secret-knowledge',
    upstreamRepository: 'trimstray/the-book-of-secret-knowledge',
    commit: '7d37069a361d3fd9f214480755f7969744e866fa',
    mode: 'KNOWLEDGE_SEED',
    license: 'MIT',
    licenseStatus: 'APPROVED',
    contentImportAllowed: true,
    referenceOnly: false,
  }),
});

/**
 * A per-entry review never approves an entire external repository. Each record
 * binds one reviewed path to one exact SHA-256 source identity and its own
 * license evidence. Raw upstream instructions may remain non-materializable
 * even when metadata adoption is approved.
 */
const EXTERNAL_SOURCE_ENTRY_CATALOG = Object.freeze({
  'awesome_claude_skills:mcp-builder/SKILL.md': Object.freeze({
    sourceId: 'awesome_claude_skills',
    path: 'mcp-builder/SKILL.md',
    sourceDigest: 'sha256:b1010e90adcb8fd6bf57640df34ab6454fbf7e4216e150a4620f7caccadc4e63',
    gitBlobSha: 'c9ef8a261f80e0c37dc73300ce90679e946c4407',
    license: 'Apache-2.0',
    licenseStatus: 'APPROVED',
    contentImportAllowed: false,
    reviewMode: 'METADATA_ONLY',
    reviewedAt: '2026-08-30',
    licenseEvidencePath: 'mcp-builder/LICENSE.txt',
    licenseEvidenceGitBlobSha: '7a4a3ea2424c09fbe48d455aed1eaa94d9124835',
  }),
});

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function exactCommit(value, field) {
  const text = requiredText(value, field).toLowerCase();
  if (!EXACT_COMMIT.test(text)) throw new TypeError(`${field} must be an exact 40-character commit SHA`);
  return text;
}

/** @param {unknown} value */
function exactSourceDigest(value) {
  const text = requiredText(value, 'sourceDigest').toLowerCase();
  const normalized = text.startsWith('sha256:') ? text : `sha256:${text}`;
  if (!EXACT_SHA256.test(normalized)) throw new TypeError('sourceDigest must be an exact sha256 digest');
  return normalized;
}

/** @param {unknown} value */
function safeSourcePath(value) {
  const path = requiredText(value, 'path');
  if (!SAFE_PATH.test(path) || path.includes('//')) throw new TypeError('path must be a safe repository-relative path');
  return path;
}

/** @param {string} sourceId */
function getExternalSourcePolicy(sourceId) {
  const policy = EXTERNAL_SOURCE_CATALOG[sourceId];
  if (!policy) throw new Error(`external source is not allowlisted: ${sourceId}`);
  return policy;
}

/** @param {string} sourceId @param {string} path */
function getExternalSourceEntryPolicy(sourceId, path) {
  const normalizedSourceId = requiredText(sourceId, 'sourceId');
  const normalizedPath = safeSourcePath(path);
  return EXTERNAL_SOURCE_ENTRY_CATALOG[`${normalizedSourceId}:${normalizedPath}`] ?? null;
}

/**
 * Binds an import/reference request to a reviewed fork, exact commit, exact path,
 * and exact SHA-256 content identity. Source policy never grants execution authority.
 * @param {{sourceId:string, repository:string, commit:string, path:string, sourceDigest:string, purpose:string, materializeContent?:boolean}} input
 */
function authorizeExternalSourceReference(input) {
  if (!input || typeof input !== 'object') throw new TypeError('external source reference is required');
  const sourceId = requiredText(input.sourceId, 'sourceId');
  const policy = getExternalSourcePolicy(sourceId);
  const repository = requiredText(input.repository, 'repository');
  const commit = exactCommit(input.commit, 'commit');
  const purpose = requiredText(input.purpose, 'purpose');
  const path = safeSourcePath(input.path);
  const sourceDigest = exactSourceDigest(input.sourceDigest);
  if (!EXTERNAL_SOURCE_MODES.includes(purpose)) throw new TypeError('unsupported external source purpose');
  if (repository !== policy.repository) throw new Error('external source repository drift');
  if (commit !== policy.commit) throw new Error('external source commit drift');
  if (purpose !== policy.mode) throw new Error(`external source purpose mismatch: ${sourceId}`);

  const entryReview = getExternalSourceEntryPolicy(sourceId, path);
  if (entryReview && sourceDigest !== entryReview.sourceDigest) {
    throw new Error('external source entry digest drift');
  }
  const license = entryReview?.license ?? policy.license;
  const licenseStatus = entryReview?.licenseStatus ?? policy.licenseStatus;
  const contentImportAllowed = entryReview?.contentImportAllowed ?? policy.contentImportAllowed;
  if (input.materializeContent === true && contentImportAllowed !== true) {
    throw new Error(`external source content import is not licensed/approved: ${sourceId}`);
  }
  return Object.freeze({
    sourceId,
    repository,
    upstreamRepository: policy.upstreamRepository,
    commit,
    path,
    sourceDigest,
    purpose,
    license,
    licenseStatus,
    contentImportAllowed,
    referenceOnly: policy.referenceOnly,
    executionAuthority: false,
    runtimeDependency: false,
    entryReview: entryReview
      ? Object.freeze({
        gitBlobSha: entryReview.gitBlobSha,
        reviewMode: entryReview.reviewMode,
        reviewedAt: entryReview.reviewedAt,
        licenseEvidencePath: entryReview.licenseEvidencePath,
        licenseEvidenceGitBlobSha: entryReview.licenseEvidenceGitBlobSha,
      })
      : null,
  });
}

module.exports = {
  EXACT_COMMIT,
  EXACT_SHA256,
  EXTERNAL_SOURCE_CATALOG,
  EXTERNAL_SOURCE_ENTRY_CATALOG,
  EXTERNAL_SOURCE_MODES,
  authorizeExternalSourceReference,
  exactSourceDigest,
  getExternalSourceEntryPolicy,
  getExternalSourcePolicy,
  safeSourcePath,
};
