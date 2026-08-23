"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.memoryTools = exports.PandoraMemoryMCPServer = exports.PandoraMemoryError = void 0;
exports.executeMemoryTool = executeMemoryTool;
const zod_1 = require("zod");
const memory_response_1 = require("./memory-response");
const memory_governance_1 = require("./memory-governance");
const memory_evidence_intake_1 = require("./memory-evidence-intake");
const DEFAULT_TIMEOUT_MS = 8000;
const DEFAULT_MAX_RESPONSE_BYTES = 500000;
const DEFAULT_CANONICAL_MAX_AGE_MS = 86_400_000;
const NamespaceSchema = zod_1.z.enum(['real_life', 'au']);
const RuntimeConfigurationSchema = zod_1.z.object({
    baseUrl: zod_1.z.string().min(1),
    oidcToken: zod_1.z.string().min(64),
    allowedNamespaces: zod_1.z.array(NamespaceSchema).min(1),
    grantedScopes: zod_1.z.array(zod_1.z.string().trim().min(1)).min(1),
    timeoutMs: zod_1.z.number().int().min(250).max(30000).default(DEFAULT_TIMEOUT_MS),
    maxResponseBytes: zod_1.z.number().int().min(1024).max(2000000).default(DEFAULT_MAX_RESPONSE_BYTES),
});
const SearchArgsSchema = zod_1.z.object({
    namespace: NamespaceSchema,
    query: zod_1.z.string().trim().min(1).max(4000),
    currentTask: zod_1.z.string().trim().min(1).max(2000).optional(),
    maxItems: zod_1.z.number().int().min(1).max(50).default(12),
    includeSemantic: zod_1.z.boolean().default(true),
    includeProfiles: zod_1.z.boolean().default(true),
    includeRecent: zod_1.z.boolean().default(true),
    includeOpenLoops: zod_1.z.boolean().default(true),
});
const CanonicalContextArgsSchema = zod_1.z.object({
    namespace: NamespaceSchema,
    query: zod_1.z.string().trim().min(1).max(4000),
    currentTask: zod_1.z.string().trim().min(1).max(2000).optional(),
    maxItems: zod_1.z.number().int().min(1).max(50).default(25),
    /** Approved records older than this force a degraded result. */
    maxAgeMs: zod_1.z.number().int().min(60000).default(DEFAULT_CANONICAL_MAX_AGE_MS),
    /** Include unreviewed drafts in the response for reviewer inspection. */
    includeProposed: zod_1.z.boolean().default(false),
});
function normalizeHttpsOrigin(value) {
    let url;
    try {
        url = new URL(value);
    }
    catch {
        throw new PandoraMemoryError('Pandora Memory origin is invalid');
    }
    if (url.protocol !== 'https:'
        || url.username
        || url.password
        || url.search
        || url.hash
        || (url.pathname !== '/' && url.pathname !== '')) {
        throw new PandoraMemoryError('Pandora Memory origin must be an HTTPS origin without credentials, path, query, or fragment');
    }
    return url.origin;
}
function declaredResponseLength(response) {
    const raw = response.headers?.get('content-length')?.trim();
    if (!raw || !/^\d+$/.test(raw))
        return undefined;
    const value = Number(raw);
    return Number.isSafeInteger(value) ? value : undefined;
}
async function readBoundedResponseBody(response, maxResponseBytes) {
    const declaredLength = declaredResponseLength(response);
    if (declaredLength !== undefined && declaredLength > maxResponseBytes) {
        throw new PandoraMemoryError('Pandora Memory response exceeded size limit');
    }
    if (!response.body?.getReader) {
        const text = await response.text();
        if (Buffer.byteLength(text, 'utf8') > maxResponseBytes) {
            throw new PandoraMemoryError('Pandora Memory response exceeded size limit');
        }
        return text;
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let bytesRead = 0;
    let text = '';
    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done)
                break;
            if (!value)
                continue;
            bytesRead += value.byteLength;
            if (bytesRead > maxResponseBytes) {
                await reader.cancel?.('Pandora Memory response exceeded size limit');
                throw new PandoraMemoryError('Pandora Memory response exceeded size limit');
            }
            text += decoder.decode(value, { stream: true });
        }
        text += decoder.decode();
        return text;
    }
    finally {
        reader.releaseLock?.();
    }
}
class PandoraMemoryError extends Error {
    constructor(message, status) {
        super(message);
        this.name = 'PandoraMemoryError';
        this.status = status;
    }
}
exports.PandoraMemoryError = PandoraMemoryError;
class PandoraMemoryMCPServer {
    constructor(configuration, fetchFn = globalThis.fetch) {
        const parsed = RuntimeConfigurationSchema.parse(configuration);
        this.config = { ...parsed, baseUrl: normalizeHttpsOrigin(parsed.baseUrl) };
        this.fetchFn = fetchFn;
    }
    async health() {
        const raw = (0, memory_response_1.sanitizeMemoryHealthResponse)(await this.request('/api/projectos/health', 'GET'));
        return {
            ok: raw.ok,
            project: raw.project,
            status: raw.status,
            origin: this.config.baseUrl,
            authentication: 'vercel_oidc',
        };
    }
    async search(input) {
        if (!this.config.allowedNamespaces.includes(input.namespace)) {
            throw new PandoraMemoryError(`Pandora Memory namespace is not allowed: ${input.namespace}`, 403);
        }
        return (0, memory_response_1.sanitizeMemorySearchResponse)(await this.request('/api/projectos/memory/search', 'POST', {
            namespace: input.namespace,
            query: input.query,
            current_task: input.currentTask,
            max_items: input.maxItems,
            include_semantic: input.includeSemantic,
            include_profiles: input.includeProfiles,
            include_recent: input.includeRecent,
            include_open_loops: input.includeOpenLoops,
        }));
    }
    /**
     * Recover governed project context in one operation.
     *
     * Pandora's-Box must not rebuild project state from a raw relevance list, so
     * this returns an explicitly governed package: approved records only, with
     * conflicts surfaced and a degraded flag that tells the caller to fall back
     * to GitHub and Supabase instead of executing on weak memory.
     */
    async canonicalContext(input) {
        const search = await this.search(SearchArgsSchema.parse({
            namespace: input.namespace,
            query: input.query,
            currentTask: input.currentTask,
            maxItems: input.maxItems,
        }));
        const context = (0, memory_governance_1.evaluateCanonicalContext)(search, {
            maxAgeMs: input.maxAgeMs,
        });
        // Drafts are only disclosed on request, and never as canonical context.
        return input.includeProposed ? context : { ...context, proposed: [] };
    }
    async request(path, method, body) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), this.config.timeoutMs);
        try {
            const response = await this.fetchFn(`${this.config.baseUrl}${path}`, {
                method,
                headers: {
                    'X-Pandora-Vercel-OIDC': this.config.oidcToken,
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'User-Agent': 'MCPMaster-Pandora-Memory/2.1',
                },
                body: body ? JSON.stringify(body) : undefined,
                signal: controller.signal,
                redirect: 'error',
            });
            const text = await readBoundedResponseBody(response, this.config.maxResponseBytes);
            if (!response.ok) {
                throw new PandoraMemoryError(`Pandora Memory request failed with ${response.status}`, response.status);
            }
            if (!text.trim()) {
                throw new PandoraMemoryError('Pandora Memory returned an empty response');
            }
            try {
                return JSON.parse(text);
            }
            catch {
                throw new PandoraMemoryError('Pandora Memory returned invalid JSON');
            }
        }
        catch (error) {
            if (error instanceof PandoraMemoryError)
                throw error;
            if (error instanceof Error && error.name === 'AbortError') {
                throw new PandoraMemoryError('Pandora Memory request timed out');
            }
            throw new PandoraMemoryError(`Pandora Memory request failed: ${error instanceof Error ? error.message : 'unknown error'}`);
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
exports.PandoraMemoryMCPServer = PandoraMemoryMCPServer;
exports.memoryTools = {
    'memory.health': {
        description: 'Verify the OIDC-authenticated ProjectOS connection to Pandora Memory without exposing credentials or database access',
        parameters: {
            type: 'object',
            properties: {},
        },
    },
    'memory.search': {
        description: 'Retrieve namespace-isolated context from Pandora Memory through the allowlisted ProjectOS workload identity',
        parameters: {
            type: 'object',
            properties: {
                namespace: {
                    type: 'string',
                    enum: ['real_life', 'au'],
                    description: 'Exact Pandora Memory namespace',
                },
                query: {
                    type: 'string',
                    minLength: 1,
                    maxLength: 4000,
                    description: 'Bounded retrieval query',
                },
                currentTask: {
                    type: 'string',
                    minLength: 1,
                    maxLength: 2000,
                    description: 'Optional current task context',
                },
                maxItems: {
                    type: 'integer',
                    minimum: 1,
                    maximum: 50,
                    default: 12,
                },
                includeSemantic: { type: 'boolean', default: true },
                includeProfiles: { type: 'boolean', default: true },
                includeRecent: { type: 'boolean', default: true },
                includeOpenLoops: { type: 'boolean', default: true },
            },
            required: ['namespace', 'query'],
        },
    },
    'memory.submitEvidenceCandidate': {
        description: 'Submit a sanitized, project-scoped evidence candidate to Pandora Memory for human review. This never promotes canonical Memory automatically',
        parameters: {
            type: 'object',
            properties: {
                namespace: { type: 'string', enum: ['real_life', 'au'] },
                projectId: { type: 'string', description: 'Exact ProjectOS project UUID when known' },
                projectKey: { type: 'string', description: 'Exact ProjectOS project key when known' },
                title: { type: 'string' },
                summary: { type: 'string', maxLength: 1800 },
                proofStage: { type: 'string', enum: ['documented', 'implemented', 'tested', 'deployed', 'production_verified'] },
                claim: { type: 'string' },
                evidenceRefs: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            type: { type: 'string' },
                            ref: { type: 'string' },
                            sha256: { type: 'string' },
                            artifact_class: { type: 'string' },
                            observed_at: { type: 'string' },
                        },
                        required: ['type', 'ref'],
                    },
                },
                provenance: {
                    type: 'object',
                    properties: {
                        source_type: { type: 'string' },
                        source_locator: { type: 'string' },
                        source_sha: { type: 'string' },
                        parent_sha: { type: 'string' },
                        observed_at: { type: 'string' },
                    },
                    required: ['source_type', 'source_locator', 'observed_at'],
                },
                idempotencyKey: { type: 'string' },
            },
            required: ['namespace', 'title', 'summary', 'proofStage', 'claim', 'evidenceRefs', 'provenance', 'idempotencyKey'],
            additionalProperties: false,
        },
    },
    'memory.canonicalContext': {
        description: 'Recover governed canonical project context from Pandora Memory. Defaults to a 24-hour freshness gate, returns approved records only, surfaces unresolved conflicts, and fails closed to GitHub and Supabase when approved memory is unavailable or stale',
        parameters: {
            type: 'object',
            properties: {
                namespace: {
                    type: 'string',
                    enum: ['real_life', 'au'],
                    description: 'Exact Pandora Memory namespace',
                },
                query: {
                    type: 'string',
                    minLength: 1,
                    maxLength: 4000,
                    description: 'Project context recovery query',
                },
                currentTask: {
                    type: 'string',
                    minLength: 1,
                    maxLength: 2000,
                    description: 'Optional current task context',
                },
                maxItems: { type: 'integer', minimum: 1, maximum: 50, default: 25 },
                maxAgeMs: {
                    type: 'integer',
                    minimum: 60000,
                    default: DEFAULT_CANONICAL_MAX_AGE_MS,
                    description: 'Approved records older than this force a degraded result; defaults to 24 hours',
                },
                includeProposed: {
                    type: 'boolean',
                    default: false,
                    description: 'Disclose unreviewed drafts for reviewer inspection. Drafts are never canonical',
                },
            },
            required: ['namespace', 'query'],
        },
    },
};
async function executeMemoryTool(tool, args, configuration, fetchFn) {
    const memory = new PandoraMemoryMCPServer(configuration, fetchFn);
    switch (tool) {
        case 'memory.health':
            return memory.health();
        case 'memory.search':
            return memory.search(SearchArgsSchema.parse(args));
        case 'memory.submitEvidenceCandidate':
            return (0, memory_evidence_intake_1.submitEvidenceCandidate)(args, configuration, fetchFn);
        case 'memory.canonicalContext':
            return memory.canonicalContext(CanonicalContextArgsSchema.parse(args));
        default:
            throw new PandoraMemoryError(`Unknown Pandora Memory tool: ${tool}`, 404);
    }
}
//# sourceMappingURL=memory.js.map
