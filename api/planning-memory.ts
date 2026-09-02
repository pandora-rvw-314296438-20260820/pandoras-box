
import { createHash } from 'node:crypto';
import { loadOperatorPublicConfig } from '../src/operator-public-config.js';
import { SupabaseBearerAuthenticator } from '../apps/meta-business-mcp/src/auth/supabase-bearer.js';
import { SupabaseOrganizationMembershipResolver } from '../apps/meta-business-mcp/src/auth/membership.js';
import { SupabaseRestClient } from '../apps/meta-business-mcp/src/supabase/rest-client.js';

export const config = { api: { bodyParser: false }, maxDuration: 30 };

const MEMORY_ORIGIN = 'https://ivmvufhcsezyhczzondn.supabase.co';
const MEMORY_PROJECT_ID = '7c686cbd-d968-49d5-86cc-918f5e777bd2';
const MEMORY_PROJECT_KEY = 'mcpmaster-pandoras-box';
const MAX_BODY_BYTES = 2048;
const MAX_MEMORY_RECORDS = 6;
const MAX_SUMMARY_BYTES = 4000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SECRET = /AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:password|secret|api[_-]?key|access[_-]?token)\s*[:=]/i;

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as JsonRecord : {};
}
function bounded(value: unknown, max: number): string {
  if (typeof value !== 'string') return '';
  const normalized = value.replace(/\s+/g, ' ').trim();
  return normalized && normalized.length <= max ? normalized : '';
}
function send(res: any, status: number, body: unknown) {
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('cache-control', 'no-store, max-age=0');
  res.setHeader('x-content-type-options', 'nosniff');
  return res.status(status).send(JSON.stringify(body));
}
async function body(req: any): Promise<{ organizationId: string; visibleProjectId: string; projectName: string }> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += bytes.length;
    if (total > MAX_BODY_BYTES) throw new Error('INVALID_REQUEST');
    chunks.push(bytes);
  }
  let parsed: unknown;
  try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Error('INVALID_REQUEST'); }
  const value = record(parsed);
  const keys = Object.keys(value).sort();
  if (JSON.stringify(keys) !== JSON.stringify(['organizationId','projectName','visibleProjectId'])) throw new Error('INVALID_REQUEST');
  const organizationId = bounded(value.organizationId, 64);
  const visibleProjectId = bounded(value.visibleProjectId, 64);
  const projectName = bounded(value.projectName, 120);
  if (!UUID.test(organizationId) || !UUID.test(visibleProjectId) || !projectName || SECRET.test(projectName)) throw new Error('INVALID_REQUEST');
  return { organizationId, visibleProjectId, projectName };
}
function sha256(value: string) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}
function safeMemoryRecord(value: unknown, approvedIds: Set<string>) {
  const item = record(value);
  const id = bounded(item.id, 64);
  const canonStatus = bounded(item.canon_status, 32);
  const memoryType = bounded(item.memory_type, 64);
  const title = bounded(item.title, 240);
  const memoryBody = bounded(item.body, 1200);
  const sourceRef = bounded(item.source_summary, 300);
  if (!UUID.test(id) || !approvedIds.has(id) || item.approved !== true || !['hard_canon','soft_canon'].includes(canonStatus) || !memoryType || !title || !memoryBody) return null;
  const summary = `${title}: ${memoryBody}`.replace(/\s+/g, ' ').trim().slice(0, 1400);
  if (!summary || SECRET.test(summary)) return null;
  return { id, memoryType, canonStatus, sourceRef, summary };
}

export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'method_not_allowed' });
  try {
    const input = await body(req);
    const config = loadOperatorPublicConfig(process.env);
    if (input.organizationId !== config.organizationId) return send(res, 403, { ok: false, error: 'organization_not_allowed' });
    const authenticator = new SupabaseBearerAuthenticator({ supabaseUrl: config.supabaseUrl, publishableKey: config.supabasePublishableKey });
    const identity = await authenticator.authenticate(String(req.headers.authorization || ''));
    const membershipResolver = new SupabaseOrganizationMembershipResolver({ supabaseUrl: config.supabaseUrl, publishableKey: config.supabasePublishableKey });
    const membership = await membershipResolver.resolve(input.organizationId, identity.userId, identity.accessToken);
    if (!membership) return send(res, 403, { ok: false, error: 'membership_required' });

    const primary = new SupabaseRestClient({ supabaseUrl: config.supabaseUrl, apiKey: config.supabasePublishableKey, accessToken: identity.accessToken, maxResponseBytes: 64 * 1024 });
    const query = new URLSearchParams({
      select: 'id,organization_id,status',
      id: `eq.${input.visibleProjectId}`,
      organization_id: `eq.${input.organizationId}`,
      status: 'eq.active',
      limit: '1',
    });
    const projects = await primary.requestJson(`/rest/v1/projectos_projects?${query.toString()}`);
    if (!Array.isArray(projects) || projects.length !== 1 || record(projects[0]).id !== input.visibleProjectId) {
      return send(res, 403, { ok: false, error: 'project_not_allowed' });
    }

    const oidc = typeof req.headers['x-vercel-oidc-token'] === 'string' ? req.headers['x-vercel-oidc-token'].trim() : '';
    if (oidc.length < 40 || oidc.length > 16384) return send(res, 503, { ok: false, error: 'workload_identity_unavailable' });
    const memoryResponse = await fetch(`${MEMORY_ORIGIN}/functions/v1/pandora-projectos-bridge`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-pandora-vercel-oidc': oidc },
      redirect: 'error',
      body: JSON.stringify({
        action: 'search',
        namespace: 'real_life',
        project_id: MEMORY_PROJECT_ID,
        project_key: MEMORY_PROJECT_KEY,
        query: `ProjectSpec planning for Visible Creation project ${input.visibleProjectId}; ${input.projectName}`,
        current_task: `Prepare advisory approved planning context for Visible Creation project ${input.visibleProjectId}`,
        max_items: MAX_MEMORY_RECORDS,
        canon_statuses: ['hard_canon','soft_canon'],
      }),
    });
    const raw = Buffer.from(await memoryResponse.arrayBuffer());
    if (raw.length > 512 * 1024) return send(res, 502, { ok: false, error: 'memory_response_too_large' });
    let memory: JsonRecord;
    try { memory = record(JSON.parse(raw.toString('utf8'))); } catch { return send(res, 502, { ok: false, error: 'memory_response_invalid' }); }
    if (!memoryResponse.ok || memory.ok !== true || memory.project_id !== MEMORY_PROJECT_ID || memory.project_key !== MEMORY_PROJECT_KEY) {
      return send(res, 502, { ok: false, error: 'memory_scope_invalid' });
    }
    const retrievalLogId = bounded(memory.retrieval_log_id, 64);
    if (retrievalLogId && !UUID.test(retrievalLogId)) return send(res, 502, { ok: false, error: 'memory_provenance_invalid' });
    const approvedIds = new Set((Array.isArray(memory.approved_memory_item_ids) ? memory.approved_memory_item_ids : [])
      .map((id) => bounded(id, 64)).filter((id) => UUID.test(id)));
    const records = (Array.isArray(memory.canonical_records) ? memory.canonical_records : [])
      .map((item) => safeMemoryRecord(item, approvedIds)).filter(Boolean).slice(0, MAX_MEMORY_RECORDS) as Array<{id:string;memoryType:string;canonStatus:string;sourceRef:string;summary:string}>;
    records.sort((a, b) => a.id.localeCompare(b.id));
    let usedBytes = 0;
    const boundedRecords = records.filter((item) => {
      const bytes = Buffer.byteLength(item.summary, 'utf8');
      if (usedBytes + bytes > MAX_SUMMARY_BYTES) return false;
      usedBytes += bytes;
      return true;
    });
    const contextSha256 = sha256(JSON.stringify(boundedRecords));
    return send(res, 200, {
      ok: true,
      state: boundedRecords.length ? 'available' : 'empty',
      memoryProjectId: MEMORY_PROJECT_ID,
      memoryProjectKey: MEMORY_PROJECT_KEY,
      visibleProjectId: input.visibleProjectId,
      retrievalLogId: retrievalLogId || null,
      contextSha256,
      records: boundedRecords,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    const status = message === 'INVALID_REQUEST' ? 400 : message.includes('bearer') || message.includes('token') ? 401 : 503;
    return send(res, status, { ok: false, error: status === 400 ? 'invalid_request' : status === 401 ? 'authentication_failed' : 'planning_memory_unavailable' });
  }
}
