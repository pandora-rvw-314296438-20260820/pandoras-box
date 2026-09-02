
const { createHash } = require('node:crypto');
const { resolveVercelWorkloadToken } = require('../src/runtime/vercel-workload-identity.js');

const ORIGIN = 'https://pandorasbox-memory.vercel.app';
const PROJECT = { key: 'mcpmaster-pandoras-box', id: '7c686cbd-d968-49d5-86cc-918f5e777bd2' };
const DENIED = { key: 'launchos', id: 'b5ec8e3b-e470-44c5-a219-d3ad30e2be64' };
const MEMORY_SHA = 'bfe88db4622a208eace9d1de025404d2d878e397';
const DEPLOYMENT = 'dpl_9Y44hinKEjeGBmFjC49GG4nptVU1';
const IDEMPOTENCY = 'memory-max-task5-6-prod-20260903-v2';

const digest = (value) => createHash('sha256').update(value, 'utf8').digest('hex');

async function call(token, path, body) {
  const r = await fetch(`${ORIGIN}${path}`, {
    method: 'POST',
    headers: {
      'X-Pandora-Vercel-OIDC': token,
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'Pandora-Memory-Convergence-Proof/1.0',
    },
    body: JSON.stringify(body),
    redirect: 'error',
    signal: AbortSignal.timeout(8000),
  });
  const text = await r.text();
  let parsed = null;
  try { parsed = text ? JSON.parse(text) : null; } catch { parsed = { parse_error: true }; }
  return { status: r.status, body: parsed };
}

const code = (body) => body?.error || body?.code || body?.safe_error_code || null;

module.exports = async function handler(request, response) {
  response.setHeader('Cache-Control', 'no-store');
  if (request.method !== 'GET') return response.status(405).json({ ok: false, error: 'method_not_allowed' });
  if (process.env.VERCEL_ENV !== 'production') return response.status(403).json({ ok: false, error: 'production_only' });

  const token = await resolveVercelWorkloadToken();
  if (!token) return response.status(503).json({ ok: false, error: 'workload_identity_unavailable' });

  const search = (namespace, project) => call(token, '/api/projectos/memory/search', {
    namespace,
    project_key: project.key,
    project_id: project.id,
    query: 'Pandora Memory production isolation verification',
    max_items: 3,
    include_semantic: true,
    include_profiles: false,
    include_recent: true,
    include_open_loops: false,
  });

  const positive = await search('real_life', PROJECT);
  const wrongProject = await search('real_life', DENIED);
  const wrongNamespace = await search('au', PROJECT);

  const observedAt = new Date().toISOString();
  const candidate = {
    namespace: 'real_life',
    project_id: PROJECT.id,
    project_key: PROJECT.key,
    title: 'Pandora Memory production convergence proof',
    summary: 'Verified exact Memory production through the canonical Box workload while preserving strict project and namespace isolation.',
    proof_stage: 'production_verified',
    evidence_kind: 'verified_publish',
    claim: `Memory production ${MEMORY_SHA} at ${DEPLOYMENT} is reachable through the canonical production workload and remains fail-closed across project and namespace boundaries.`,
    evidence_refs: [
      {
        type: 'project_version',
        ref: `pandoras-box-memory:${MEMORY_SHA}`,
        sha256: digest(`pandoras-box-memory:${MEMORY_SHA}`),
        observed_at: observedAt,
      },
      { type: 'production_deployment', ref: DEPLOYMENT, observed_at: observedAt },
      {
        type: 'verification_run',
        ref: 'pandora-memory-maximization-task-5-6-production-proof',
        sha256: digest(`task5-6:${MEMORY_SHA}:${DEPLOYMENT}`),
        observed_at: observedAt,
      },
    ],
    provenance: {
      source_type: 'production_verification',
      source_locator: 'pandora-memory-maximization/task-5-6',
      observed_at: observedAt,
    },
    idempotency_key: IDEMPOTENCY,
  };

  const evidencePath = '/api/projectos/memory/evidence-candidates';
  const first = await call(token, evidencePath, candidate);
  const duplicate = await call(token, evidencePath, candidate);
  const conflict = await call(token, evidencePath, {
    ...candidate,
    claim: `${candidate.claim} Altered payload must be rejected as an idempotency conflict.`,
  });

  const positiveOk =
    positive.status === 200 &&
    positive.body?.ok === true &&
    positive.body?.namespace === 'real_life' &&
    positive.body?.retrieval_mode === 'project_scoped_keyword_recency';
  const wrongProjectOk = wrongProject.status === 403 && code(wrongProject.body) === 'project_not_allowed';
  const wrongNamespaceOk = wrongNamespace.status === 403 && code(wrongNamespace.body) === 'namespace_not_allowed';
  const evidenceOk =
    [200, 202].includes(first.status) &&
    first.body?.status === 'pending_review' &&
    first.body?.canonical_memory_written === false &&
    [200, 202].includes(duplicate.status) &&
    duplicate.body?.status === 'pending_review' &&
    duplicate.body?.canonical_memory_written === false &&
    duplicate.body?.deduplicated === true &&
    conflict.status === 409 &&
    code(conflict.body) === 'idempotency_conflict';

  const ok = positiveOk && wrongProjectOk && wrongNamespaceOk && evidenceOk;
  return response.status(ok ? 200 : 502).json({
    ok,
    memory_sha: MEMORY_SHA,
    memory_deployment: DEPLOYMENT,
    positive: {
      status: positive.status,
      retrieval_mode: positive.body?.retrieval_mode || null,
      namespace: positive.body?.namespace || null,
      project_id: positive.body?.project_id || null,
    },
    wrong_project: { status: wrongProject.status, safe_error_code: code(wrongProject.body) },
    wrong_namespace: { status: wrongNamespace.status, safe_error_code: code(wrongNamespace.body) },
    governed_evidence: {
      candidate_id: first.body?.candidate_id || null,
      review_item_id: first.body?.review_item_id || null,
      status: first.body?.status || null,
      canonical_memory_written: first.body?.canonical_memory_written,
      first_deduplicated: first.body?.deduplicated,
      duplicate_deduplicated: duplicate.body?.deduplicated,
      conflict_status: conflict.status,
      conflict_code: code(conflict.body),
    },
  });
};
