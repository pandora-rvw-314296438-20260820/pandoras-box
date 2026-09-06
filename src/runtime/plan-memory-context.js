"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PandoraPlanMemoryContextProvider = void 0;
exports.canonicalPlanMemoryContextJson = canonicalPlanMemoryContextJson;
exports.hashPlanMemoryContextEnvelope = hashPlanMemoryContextEnvelope;
exports.createUnavailablePlanMemoryContext = createUnavailablePlanMemoryContext;
exports.shouldHydratePlanMemoryContext = shouldHydratePlanMemoryContext;
const node_crypto_1 = require("node:crypto");
const memory_js_1 = require("../tools/memory.js");
const DEFAULT_MEMORY_ORIGIN = 'https://pandorasbox-memory.vercel.app';
const CONTEXT_SCHEMA_VERSION = '1.0.0';
const MAX_IDENTIFIER_LENGTH = 240;
const MAX_HIGHLIGHT_LENGTH = 1000;
const MAX_HIGHLIGHTS_PER_KIND = 3;
const MAX_WARNINGS = 10;
const SAFE_IDENTIFIER_KEYS = new Set([
    'owner',
    'org',
    'organization',
    'repo',
    'repository',
    'repository_full_name',
    'projectKey',
    'project_key',
    'projectId',
    'project_id',
    'projectRef',
    'project_ref',
    'branch',
    'issue_number',
    'pr_number',
    'deploymentId',
    'deployment_id',
    'teamId',
    'team_id',
    'domain',
]);
function sha256(value) {
    return (0, node_crypto_1.createHash)('sha256').update(value, 'utf8').digest('hex');
}
// Canonical context JSON is compact JSON with array order preserved and every
// object key recursively sorted. The privileged database boundary implements
// the same byte contract with C-collation key order before accepting the hash.
function canonicalPlanMemoryContextJson(value) {
    if (value === null)
        return 'null';
    if (Array.isArray(value)) {
        return `[${value.map((item) => canonicalPlanMemoryContextJson(item)).join(',')}]`;
    }
    if (typeof value === 'object') {
        return `{${Object.keys(value)
            .sort((left, right) => Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8')))
            .map((key) => `${JSON.stringify(key)}:${canonicalPlanMemoryContextJson(value[key])}`)
            .join(',')}}`;
    }
    if (typeof value === 'string' || typeof value === 'boolean') {
        return JSON.stringify(value);
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
        return JSON.stringify(value);
    }
    throw new TypeError('Plan context contains a non-JSON value');
}
function boundedText(value, maximum = MAX_HIGHLIGHT_LENGTH) {
    if (typeof value !== 'string')
        return undefined;
    const normalized = value.replace(/\s+/g, ' ').trim();
    if (!normalized)
        return undefined;
    return normalized.slice(0, maximum);
}
function safeIdentifiers(args) {
    const identifiers = {};
    for (const [key, value] of Object.entries(args)) {
        if (!SAFE_IDENTIFIER_KEYS.has(key))
            continue;
        if (typeof value !== 'string' && typeof value !== 'number')
            continue;
        const normalized = String(value).replace(/\s+/g, ' ').trim();
        if (!normalized || normalized.length > MAX_IDENTIFIER_LENGTH)
            continue;
        identifiers[key] = normalized;
    }
    return Object.fromEntries(Object.entries(identifiers).sort(([left], [right]) => left.localeCompare(right)));
}
function contextQuery(tool, identifiers) {
    const parts = [`ProjectOS durable plan context for ${tool}`];
    for (const [key, value] of Object.entries(identifiers)) {
        parts.push(`${key} ${value}`);
    }
    return parts.join('; ').slice(0, 4000);
}
function firstText(record, keys) {
    for (const key of keys) {
        const value = boundedText(record[key]);
        if (value)
            return value;
    }
    return undefined;
}
function collectHighlights(values, keys) {
    if (!Array.isArray(values))
        return [];
    const results = [];
    for (const item of values) {
        if (!item || typeof item !== 'object' || Array.isArray(item))
            continue;
        const text = firstText(item, keys);
        if (text && !results.includes(text))
            results.push(text);
        if (results.length >= MAX_HIGHLIGHTS_PER_KIND)
            break;
    }
    return results;
}
function warningList(values) {
    if (!Array.isArray(values))
        return [];
    return values
        .map((value) => boundedText(value, 300))
        .filter((value) => Boolean(value))
        .slice(0, MAX_WARNINGS);
}
function emptyEnvelope(now, tool, identifiers, queryHash, failure) {
    return {
        schemaVersion: CONTEXT_SCHEMA_VERSION,
        status: failure ? 'unavailable' : 'empty',
        source: 'pandora-memory',
        namespace: 'real_life',
        retrievedAt: now.toISOString(),
        queryHash,
        queryBasis: { tool, identifiers },
        counts: {
            projectContext: 0,
            riskWarnings: 0,
            openLoops: 0,
            recentEvents: 0,
            semanticMatches: 0,
        },
        highlights: {
            project: [],
            risks: [],
            openLoops: [],
            recent: [],
            semantic: [],
        },
        warnings: failure ? ['memory_context_unavailable'] : [],
        ...(failure ? { failure } : {}),
    };
}
function hashPlanMemoryContextEnvelope(envelope) {
    return sha256(canonicalPlanMemoryContextJson(envelope));
}
function createUnavailablePlanMemoryContext(input, error, now = new Date()) {
    const identifiers = safeIdentifiers(input.args);
    const queryHash = sha256(contextQuery(input.tool, identifiers));
    const envelope = emptyEnvelope(now, input.tool, identifiers, queryHash, {
        type: error instanceof Error ? error.name : 'unknown',
        ...(error instanceof memory_js_1.PandoraMemoryError && error.status ? { status: error.status } : {}),
    });
    return { envelope, contextHash: hashPlanMemoryContextEnvelope(envelope) };
}
class PandoraPlanMemoryContextProvider {
    constructor(options = {}) {
        this.baseUrl = options.baseUrl || process.env.PANDORA_MEMORY_BASE_URL || DEFAULT_MEMORY_ORIGIN;
        this.timeoutMs = options.timeoutMs || 8000;
        this.maxResponseBytes = options.maxResponseBytes || 500000;
        this.fetchFn = options.fetchFn;
        this.now = options.now || (() => new Date());
    }
    async hydrate(vercelOidcToken, input) {
        const identifiers = safeIdentifiers(input.args);
        const query = contextQuery(input.tool, identifiers);
        const queryHash = sha256(query);
        const now = this.now();
        const projectKey = boundedText(input.args?.projectKey ?? input.args?.project_key, MAX_IDENTIFIER_LENGTH);
        if (!projectKey) {
            return createUnavailablePlanMemoryContext(input, new memory_js_1.PandoraMemoryError('Explicit Pandora Memory project identity is required', 400), now);
        }
        try {
            const memory = new memory_js_1.PandoraMemoryMCPServer({
                baseUrl: this.baseUrl,
                oidcToken: vercelOidcToken,
                allowedNamespaces: ['real_life'],
                grantedScopes: ['memory:health', 'memory:read'],
                timeoutMs: this.timeoutMs,
                maxResponseBytes: this.maxResponseBytes,
            }, this.fetchFn);
            const search = await memory.search({
                namespace: 'real_life',
                projectKey,
                query,
                currentTask: `Prepare a durable ProjectOS plan for ${input.tool}`,
                maxItems: 6,
                includeSemantic: true,
                includeProfiles: true,
                includeRecent: true,
                includeOpenLoops: true,
            });
            const highlights = {
                project: collectHighlights(search.project_context, ['summary', 'title']),
                risks: collectHighlights(search.risk_warnings, ['summary', 'description', 'title']),
                openLoops: collectHighlights(search.open_loops, ['next_action', 'description', 'title']),
                recent: collectHighlights(search.recent_events, ['summary', 'extracted_summary']),
                semantic: collectHighlights(search.semantic_matches, ['summary', 'extracted_summary']),
            };
            const counts = {
                projectContext: search.project_context?.length || 0,
                riskWarnings: search.risk_warnings?.length || 0,
                openLoops: search.open_loops?.length || 0,
                recentEvents: search.recent_events?.length || 0,
                semanticMatches: search.semantic_matches?.length || 0,
            };
            const hasContext = Object.values(counts).some((count) => count > 0)
                || Object.values(highlights).some((items) => items.length > 0);
            const envelope = {
                schemaVersion: CONTEXT_SCHEMA_VERSION,
                status: hasContext ? 'available' : 'empty',
                source: 'pandora-memory',
                namespace: 'real_life',
                retrievedAt: now.toISOString(),
                queryHash,
                queryBasis: { tool: input.tool, identifiers },
                counts,
                highlights,
                warnings: warningList(search.warnings),
            };
            return {
                envelope,
                contextHash: hashPlanMemoryContextEnvelope(envelope),
                memoryProjectId: typeof search.project_id === 'string' ? search.project_id : null,
                memoryProjectKey: typeof search.project_key === 'string' ? search.project_key : projectKey,
                retrievalLogId: typeof search.retrieval_log_id === 'string' ? search.retrieval_log_id : null,
                approvedMemoryItemIds: Array.isArray(search.approved_memory_item_ids)
                    ? search.approved_memory_item_ids.slice(0, 50)
                    : [],
            };
        }
        catch (error) {
            return createUnavailablePlanMemoryContext(input, error, now);
        }
    }
}
exports.PandoraPlanMemoryContextProvider = PandoraPlanMemoryContextProvider;
function shouldHydratePlanMemoryContext() {
    if (process.env.PANDORA_MEMORY_PLAN_CONTEXT_ENABLED === 'false')
        return false;
    return process.env.VERCEL === '1' && process.env.VERCEL_ENV === 'production';
}
//# sourceMappingURL=plan-memory-context.js.map
