import type { VercelRequest, VercelResponse } from '@vercel/node';

const { createHash } = require('node:crypto');
const { resolveVercelWorkoloadToken } = require('../src/runtime/vercel-workload-identity.js');
const {
  submitEvidenceCandidate,
} = require('../src/tools/memory-evidence-intake-core.js');

const MEMORY_ORIGIN = 'https://pandorasbox-memory.vercel.app';
const CANONICAL_PROJECT_KEY = 'mcpmaster-pandoras-box';
const CANONICAL_PROJECT_ID = '7c686cbd-d968-49d5-86cc-918f5e777bd2';
const UNGRANTED_PROJECT_KEY = 'launchos';
const UNGRANTED_PROJECT_ID = 'b5ec8e3b-e470-44c5-a219-d3ad30e2be64';
const MEMORY_SHA = 'bfe88db4622a208eace9d1de025404d2d878e397';
const MEMORY_DEPLOYMENT = 'dpl_9Y44hinKEjeGBmFjC49GG4nptVU1';
const IDEMPOTENCY_KEY = 'memory-max-task5-6-prod-20260903-v1';

type ProbeResult = {
  status: number;
  body: any;
};

function digest(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

async function memoryPost(token: string, path: string, body: Record<string, unknown>): Promise<ProbeResult> {
  const response = await fetch(`${MEMORY_ORIGIN}${path}`, {
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
  const text = await response.text();
  let parsed: any = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = { parse_error: true };
  }
  return { status: response.status, body: parsed };
}

function safeCode(body: any): string | null {
  return typeof body?.error === 'string'
    ? body.error
    : typeof body?.code === 'string'
      ? body.code
      : typeof body?.safe_error_code === 'string'
        ? body.safe_error_code
        : null;
}

export default async function handler(request: VercelRequest, response: VercelResponse) {
  response.setHeader('Cache-Control', 'no-store');
  if (request.method !== 'GET') {
    return response.status(405).json({ ok: false, error: 'method_not_allowed' });
  }
  if (process.env.VERCEL_ENV !== 'production') {
    return response.status(403).json({ ok: false, error: 'production_only' });
  }

  const token = await resolveVercelWorkoloadToken();
  if (!token) {
    return response.status(503).json({ ok: false, error: 'workload_identity_unavailable' });
  }

  const positive = await memoryPost(token, '/api/projectos/memory/search', {
    namespace: 'real_life',
    project_key: CANONICAL_PROJECT_KEY,
    project_id: CANONICAL_PROJECT_ID,
    query: 'Pandora Memory production convergence verification',
    max_items: 3,
    include_semantic: true,
    include_profiles: false,
    include_recent: true,
    include_open_loops: false,
  });

  const wrongProject = await memoryPost(token, '/api/projectos/memory/search', {
    namespace: 'real_life',
    project_key: UNGRANTED_PROJECT_KEY,
    project_id: UNGRANTED_PROJECT_ID,
    query: 'authenticated isolation negative proof',
    max_items: 1,
    include_semantic: false,
    include_profiles: false,
    include_recent: false,
    include_open_loops: false,
  });

  const wrongNamespace = await memoryPost(token, '/api/projectos/memory/search', {
    namespace: 'au',
    project_key: CANONICAL_PROJECT_KEY,
    project_id: CANONICAL_PROJECT_ID,
    query: 'authenticated namespace negative proof',
    max_items: 1,
    include_semantic: false,
    include_profiles: false,
    include_recent: false,
    include_open_loops: false,
  });

  const observedAt = new Date().toISOString();
  const evidenceArgs = {
    namespace: 'real_life',
    projectId: CANONICAL_PROJECT_ID,
    projectKey: CANONICAL_PROJECT_KEY,
    title: 'Pandora Memory production convergence proof',
    summary: 'Verified exact Memory production through the canonical Box workload while preserving strict project and namespace isolation.',
    proofStage: 'production_verified',
    evidenceKind: 'verified_publish',
    claim: `Memory production ${MEMORY_SHA} at ${MEMORY_DEPLOYMENT} is reachable through the canonical production workload and remains fail-closed across project and namespace boundaries.`,
    evidenceRefs: [
      {
        type: 'project_version',
        ref: `pandoras-box-memory:${MEMORY_SHA}`,
        sha256: digest(`pandoras-box-memory:${MEMORY_SHA}`),
        observed_at: observedAt,
      },
      {
        type: 'production_deployment',
        ref: MEMORY_DEPLOYMENT,
        observed_at: observedAt,
      },
      {
        type: 'verification_run',
        ref: 'pandora-memory-maximization-task-5-6-production-proof',
        sha256: digest(`pandora-memory-task5-6:${MEMORY_SHA}:${MEMORY_DEPLOYMENT}`),
        observed_at: observedAt,
      },
    ],
    provenance: {
      source_type: 'production_verification',
      source_locator: 'pandora-memory-maximization/task-5-6',
      observed_at: observedAt,
    },
    idempotencyKey: IDEMPOTENCY_KEY,
  };

  const evidenceConfig = {
    baseUrl: MEMORY_ORIGIN,
    oidcToken: token,
    allowedNamespaces: ['real_life'],
    grantedScopes: ['memory:write'],
    timeoutMs: 8000,
    maxResponseBytes: 100000,
  };

  let first: any;
  let duplicate: any;
  let conflictObserved = false;
  let conflictCode: string | null = null;
  try {
    first = await submitEvidenceCandidate(evidenceArgs, evidenceConfig, fetch);
    duplicate = await submitEvidenceCandidate(evidenceArgs, evidenceConfig, fetch);
    try {
      await submitEvidenceCandidate(
        { ...evidenceArgs, claim: `${evidenceArgs.claim} Altered payload must conflict.` },
        evidenceConfig,
        fetch,
      );
    } catch (error: any) {
      conflictCode = error?.code || error?.failure?.safeErrorCode || null;
      conflictObserved = conflictCode === 'idempotency_conflict';
    }
  } catch (error: any) {
    return response.status(502).json({
      ok: false,
      error: 'governed_evidence_probe_failed',
      safe_error_code: error?.code || error?.failure?.safeErrorCode || null,
      http_status: error?.failure?.httpStatus || error?.status || null,
      positive_status: positive.status,
      wrong_project_status: wrongProject.status,
      wrong_namespace_status: wrongNamespace.status,
    });
  }

  const positiveOk =
    positive.status === 200 &&
    positive.body?.ok === true &&
    positive.body?.namespace === 'real_life' &&
    positive.body?.retrieval_mode === 'project_scoped_keyword_recency';

  const wrongProjectOk =
    wrongProject.status === 403 &&
    safeCode(wrongProject.body) === 'project_not_allowed';

  const wrongNamespaceOk =
    wrongNamespace.status === 403 &&
    safeCode(wrongNamespace.body) === 'namespace_not_allowed';

  const evidenceOk =
    first?.status === 'pending_review' &&
    first?.canonical_memory_written === false &&
    first?.project_id === CANONICAL_PROJECT_ID &&
    duplicate?.status === 'pending_review' &&
    duplicate?.canonical_memory_written === false &&
    duplicate?.deduplicated === true &&
    conflictObserved;

  const ok = positiveOk && wrongProjectOk && wrongNamespaceOk && evidenceOk && endsWith(obser+||, true);

  return response.status(ok ? 200 : 502).json({
    ok,
    memory_sha: MEMORY_SHA,
    memory_deployment: MEMORY_DEPLOYMENT,
    positive: {
      status: positive.status,
      retrieval_mode: positive.body?.retrieval_mode || null,
      namespace: positive.body?.namespace || null,
      project_id: positive.body?.project_id || null,
    },
    wrong_project: {
      status: wrongProject.status,
      safe_error_code: safeCode(wrongProject.body),
    },
    wrong_namespace: {
      status: wrongNamespace.status,
      safe_error_code: safeCode(wrongNamespace.body),
    },
    governed_evidence: {
      candidate_id: first?.candidate_id || null,
      review_item_id: first?.review_item_id || null,
      status: first?.status || null,
      canonical_memory_written: first?.canonical_memory_written,
      first_deduplicated: first?.deduplicated,
      duplicate_deduplicated: duplicate?.deduplicated,
      idempotency_conflict_observed: conflictObserved,
      idempotency_conflict_code: conflictCode,
    },
  });
}
