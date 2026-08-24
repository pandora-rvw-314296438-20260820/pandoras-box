"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.supabaseProviderApiTools = exports.githubProviderApiTools = void 0;
exports.executeGitHubProviderApiTool = executeGitHubProviderApiTool;
exports.executeSupabaseProviderApiTool = executeSupabaseProviderApiTool;
const zod_1 = require("zod");
const crypto_1 = require("node:crypto");
const GITHUB_API_ORIGIN = 'https://api.github.com';
const SUPABASE_API_ORIGIN = 'https://api.supabase.com/v1';
const DEFAULT_TIMEOUT_MS = 15000;
const DEFAULT_MAX_RESPONSE_BYTES = 2000000;
const CHILD_DATABASE_QUERY_MAX_BYTES = 240000;
const CHILD_DATABASE_PARAMETERS_MAX_BYTES = 65536;
const CHILD_DATABASE_RESPONSE_MAX_BYTES = 1000000;
const CHILD_DELETE_RECONCILIATION_ATTEMPTS = 4;
const CHILD_DELETE_RECONCILIATION_DELAY_MS = 250;
const ReadMethodSchema = zod_1.z.enum(['GET', 'HEAD']).default('GET');
const WriteMethodSchema = zod_1.z.enum(['POST', 'PUT', 'PATCH']);
const PathSegmentsSchema = zod_1.z.array(zod_1.z.string().min(1).max(512)
    .refine((value) => !value.includes('\0'), 'Path segment contains a null byte')
    .refine((value) => value !== '.' && value !== '..', 'Path traversal segments are not allowed')).max(32).default([]);
const QueryValueSchema = zod_1.z.union([
    zod_1.z.string(),
    zod_1.z.number().finite(),
    zod_1.z.boolean(),
    zod_1.z.array(zod_1.z.union([zod_1.z.string(), zod_1.z.number().finite(), zod_1.z.boolean()])).max(100),
]);
const QuerySchema = zod_1.z.record(QueryValueSchema).default({});
const GitHubBaseArgsSchema = zod_1.z.object({
    owner: zod_1.z.string().min(1),
    repo: zod_1.z.string().min(1),
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
});
const GitHubReadArgsSchema = GitHubBaseArgsSchema.extend({ method: ReadMethodSchema });
const GitHubWriteArgsSchema = GitHubBaseArgsSchema.extend({
    method: WriteMethodSchema,
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const GitHubDeleteArgsSchema = GitHubBaseArgsSchema.extend({
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseAccountArgsSchema = zod_1.z.object({ accountId: zod_1.z.string().min(1) });
const SupabaseProjectRefSchema = zod_1.z.string().regex(/^[a-z0-9]{20}$/);
const SupabaseBranchUuidSchema = zod_1.z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
const SupabaseProjectArgsSchema = SupabaseAccountArgsSchema.extend({
    projectRef: SupabaseProjectRefSchema,
});
const SupabaseProjectReadArgsSchema = SupabaseProjectArgsSchema.extend({
    method: ReadMethodSchema,
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
});
const SupabaseProjectWriteArgsSchema = SupabaseProjectArgsSchema.extend({
    method: WriteMethodSchema,
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseProjectDeleteArgsSchema = SupabaseProjectArgsSchema.extend({
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseOrganizationBaseArgsSchema = SupabaseAccountArgsSchema.extend({
    organizationSlug: zod_1.z.string().min(1),
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
});
const SupabaseOrganizationReadArgsSchema = SupabaseOrganizationBaseArgsSchema.extend({
    method: ReadMethodSchema,
});
const SupabaseOrganizationWriteArgsSchema = SupabaseOrganizationBaseArgsSchema.extend({
    method: WriteMethodSchema,
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseOrganizationDeleteArgsSchema = SupabaseOrganizationBaseArgsSchema.extend({
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseBranchBaseArgsSchema = SupabaseProjectArgsSchema.extend({
    branchIdOrRef: zod_1.z.string().min(1).max(160),
    pathSegments: PathSegmentsSchema,
    query: QuerySchema,
});
const SupabaseBranchReadArgsSchema = SupabaseBranchBaseArgsSchema.extend({ method: ReadMethodSchema });
const SupabaseBranchWriteArgsSchema = SupabaseBranchBaseArgsSchema.extend({
    method: WriteMethodSchema,
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
const SupabaseBranchDeleteArgsSchema = SupabaseBranchBaseArgsSchema.extend({
    body: zod_1.z.unknown().optional(),
    confirmation: zod_1.z.string().min(1),
});
function isBoundedJsonParameter(value, depth = 0) {
    if (depth > 8)
        return false;
    if (value === null || typeof value === 'boolean')
        return true;
    if (typeof value === 'number')
        return Number.isFinite(value);
    if (typeof value === 'string')
        return Buffer.byteLength(value, 'utf8') <= 10000;
    if (Array.isArray(value)) {
        return value.length <= 100
            && value.every((entry) => isBoundedJsonParameter(entry, depth + 1));
    }
    if (!value || typeof value !== 'object' || Object.getPrototypeOf(value) !== Object.prototype)
        return false;
    const entries = Object.entries(value);
    return entries.length <= 100
        && entries.every(([key, entry]) => (key.length > 0
            && key.length <= 256
            && !['__proto__', 'constructor', 'prototype'].includes(key)
            && isBoundedJsonParameter(entry, depth + 1)));
}
function serializedByteLength(value) {
    try {
        return Buffer.byteLength(JSON.stringify(value), 'utf8');
    }
    catch {
        return Number.POSITIVE_INFINITY;
    }
}
const SupabaseChildDatabaseQueryArgsSchema = SupabaseAccountArgsSchema.extend({
    parentProjectRef: SupabaseProjectRefSchema,
    branchId: SupabaseBranchUuidSchema,
    childProjectRef: SupabaseProjectRefSchema,
    sql: zod_1.z.string().min(1).max(CHILD_DATABASE_QUERY_MAX_BYTES)
        .refine((value) => Buffer.byteLength(value, 'utf8') <= CHILD_DATABASE_QUERY_MAX_BYTES, 'SQL query exceeds the UTF-8 byte limit'),
    parameters: zod_1.z.array(zod_1.z.unknown().refine((value) => isBoundedJsonParameter(value), 'SQL parameter must be bounded JSON')).max(100)
        .refine((value) => serializedByteLength(value) <= CHILD_DATABASE_PARAMETERS_MAX_BYTES, 'SQL parameters exceed the serialized byte limit'),
    bodySha256: zod_1.z.string().regex(/^[a-f0-9]{64}$/),
    confirmation: zod_1.z.string().min(1),
}).strict();
const SupabaseChildBranchDeleteArgsSchema = SupabaseAccountArgsSchema.extend({
    parentProjectRef: SupabaseProjectRefSchema,
    branchId: SupabaseBranchUuidSchema,
    childProjectRef: SupabaseProjectRefSchema,
    confirmation: zod_1.z.string().min(1),
}).strict();
const SupabaseChildDeletionReconciliationArgsSchema = SupabaseAccountArgsSchema.extend({
    parentProjectRef: SupabaseProjectRefSchema,
    branchId: SupabaseBranchUuidSchema,
    childProjectRef: SupabaseProjectRefSchema,
    expectedParentOrganizationSlug: zod_1.z.string().min(1).max(160),
    expectedParentStatus: zod_1.z.string().min(1).max(80),
    reconciliationProof: zod_1.z.string().regex(/^[a-f0-9]{64}$/),
}).strict();
function encodeSegments(segments) {
    return segments.map((segment) => encodeURIComponent(segment)).join('/');
}
function encodedSuffix(segments) {
    return segments.length > 0 ? `/${encodeSegments(segments)}` : '';
}
function rawSuffix(segments) {
    return segments.length > 0 ? `/${segments.join('/')}` : '';
}
function normalizedSupabasePath(segments) {
    return segments.map((segment) => {
        let normalized = segment.normalize('NFKC').trim().toLowerCase();
        for (let attempt = 0; attempt <= segment.length; attempt += 1) {
            try {
                const decoded = decodeURIComponent(normalized);
                if (decoded === normalized)
                    break;
                normalized = decoded.normalize('NFKC').trim().toLowerCase();
            }
            catch {
                throw new Error('Supabase Management API path contains invalid encoding');
            }
        }
        return normalized;
    }).join('/').replace(/\/{2,}/g, '/');
}
function assertProjectMutationPathAllowed(pathSegments) {
    const normalizedPath = normalizedSupabasePath(pathSegments);
    const normalizedSegments = normalizedPath.split('/');
    if (normalizedSegments.some((segment) => segment === '.' || segment === '..')) {
        throw new Error('Path traversal segments are not allowed');
    }
    if (normalizedPath === 'config/auth' || normalizedPath.startsWith('config/auth/')) {
        throw new Error('Supabase Auth configuration is reserved for dedicated security tools');
    }
}
function buildQuery(query) {
    const params = new URLSearchParams();
    for (const [key, rawValue] of Object.entries(query)) {
        if (rawValue === undefined)
            continue;
        const values = Array.isArray(rawValue) ? rawValue : [rawValue];
        for (const value of values)
            params.append(key, String(value));
    }
    const rendered = params.toString();
    return rendered ? `?${rendered}` : '';
}
function selectedHeaders(headers) {
    if (!headers)
        return {};
    const names = [
        'content-type', 'content-length', 'etag', 'last-modified', 'link', 'location',
        'content-range', 'x-total-count', 'x-ratelimit-limit', 'x-ratelimit-remaining', 'x-ratelimit-reset',
    ];
    return Object.fromEntries(names
        .map((name) => [name, headers.get(name)])
        .filter((entry) => typeof entry[1] === 'string'));
}
async function parseResponse(response, method, maxResponseBytes, providerName) {
    const declaredLength = Number(response.headers?.get('content-length') || '0');
    if (Number.isFinite(declaredLength) && declaredLength > maxResponseBytes) {
        throw new Error(`${providerName} response exceeded size limit`);
    }
    if (!response.ok)
        throw new Error(`${providerName} request failed with ${response.status}`);
    if (method === 'HEAD')
        return { status: response.status, headers: selectedHeaders(response.headers) };
    if (response.text) {
        const text = await response.text();
        if (Buffer.byteLength(text, 'utf8') > maxResponseBytes) {
            throw new Error(`${providerName} response exceeded size limit`);
        }
        if (!text.trim())
            return { status: response.status, headers: selectedHeaders(response.headers) };
        try {
            return JSON.parse(text);
        }
        catch {
            return { status: response.status, headers: selectedHeaders(response.headers), body: text };
        }
    }
    if (response.json)
        return response.json();
    return { status: response.status, headers: selectedHeaders(response.headers) };
}
async function providerRequest(fetchFn, url, method, headers, query, body, timeoutMs, maxResponseBytes, providerName) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetchFn(`${url}${buildQuery(query)}`, {
            method,
            headers,
            body: body === undefined || method === 'GET' || method === 'HEAD' ? undefined : JSON.stringify(body),
            signal: controller.signal,
            redirect: 'error',
        });
        return await parseResponse(response, method, maxResponseBytes, providerName);
    }
    catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
            throw new Error(`${providerName} request timed out`);
        }
        throw error;
    }
    finally {
        clearTimeout(timeout);
    }
}
function githubHeaders(token) {
    return {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'MCPMaster-GitHub-Control/2.0',
        'X-GitHub-Api-Version': '2022-11-28',
    };
}
async function githubRepositoryRequest(configuration, method, owner, repo, pathSegments, query, body, fetchFn = globalThis.fetch) {
    if (configuration.baseUrl !== GITHUB_API_ORIGIN)
        throw new Error('GitHub API origin is not trusted');
    const url = `${GITHUB_API_ORIGIN}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}${encodedSuffix(pathSegments)}`;
    return providerRequest(fetchFn, url, method, githubHeaders(configuration.token), query, body, DEFAULT_TIMEOUT_MS, DEFAULT_MAX_RESPONSE_BYTES, 'GitHub API');
}
async function executeGitHubProviderApiTool(tool, args, configuration, fetchFn) {
    switch (tool) {
        case 'github.read-repository-api': {
            const input = GitHubReadArgsSchema.parse(args);
            return githubRepositoryRequest(configuration, input.method, input.owner, input.repo, input.pathSegments, input.query, undefined, fetchFn);
        }
        case 'github.write-repository-api': {
            const input = GitHubWriteArgsSchema.parse(args);
            const expected = `${input.method} ${input.owner}/${input.repo}${rawSuffix(input.pathSegments)}`;
            if (input.confirmation !== expected)
                throw new Error(`Confirmation must exactly equal "${expected}"`);
            return githubRepositoryRequest(configuration, input.method, input.owner, input.repo, input.pathSegments, input.query, input.body, fetchFn);
        }
        case 'github.delete-repository-api': {
            const input = GitHubDeleteArgsSchema.parse(args);
            const expected = `DELETE ${input.owner}/${input.repo}${rawSuffix(input.pathSegments)}`;
            if (input.confirmation !== expected)
                throw new Error(`Confirmation must exactly equal "${expected}"`);
            return githubRepositoryRequest(configuration, 'DELETE', input.owner, input.repo, input.pathSegments, input.query, input.body, fetchFn);
        }
        default:
            throw new Error(`Unknown GitHub provider API tool: ${tool}`);
    }
}
function supabaseAccount(configuration, accountId) {
    const account = configuration.accounts.find((candidate) => candidate.id === accountId);
    if (!account)
        throw new Error(`Unknown Supabase account: ${accountId}`);
    return account;
}
function assertSupabaseMutationAllowed(account) {
    if (!account.allowMutations)
        throw new Error(`Mutations are disabled for Supabase account ${account.id}`);
}
function assertOrganizationAllowed(account, organizationSlug) {
    if (account.allowedOrganizationSlugs.length === 0
        || !account.allowedOrganizationSlugs.includes(organizationSlug))
        throw new Error(`Supabase account ${account.id} is not allowed to access organization ${organizationSlug}`);
}
function assertProjectRefAllowed(account, projectRef) {
    if ((account.allowedProjectRefs.length === 0 && account.allowedOrganizationSlugs.length === 0)
        || (account.allowedProjectRefs.length > 0 && !account.allowedProjectRefs.includes(projectRef))) {
        throw new Error(`Supabase account ${account.id} is not allowed to access project ${projectRef}`);
    }
}
function supabaseHeaders(token) {
    return {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'MCPMaster-Supabase-Control/2.0',
    };
}
async function supabaseRequest(account, configuration, path, method, query, body, fetchFn = globalThis.fetch) {
    if (!path.startsWith('/') || path.includes('://'))
        throw new Error('Supabase Management API path is not trusted');
    return providerRequest(fetchFn, `${SUPABASE_API_ORIGIN}${path}`, method, supabaseHeaders(account.token), query, body, configuration.timeoutMs || DEFAULT_TIMEOUT_MS, configuration.maxResponseBytes || DEFAULT_MAX_RESPONSE_BYTES, 'Supabase Management API');
}
async function ensureProjectAllowed(account, configuration, projectRef, fetchFn) {
    assertProjectRefAllowed(account, projectRef);
    if (account.allowedOrganizationSlugs.length === 0)
        return;
    const project = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(projectRef)}`, 'GET', {}, undefined, fetchFn);
    const organizationSlug = project && typeof project === 'object'
        ? project.organization_slug
        : undefined;
    if (typeof organizationSlug !== 'string' || !account.allowedOrganizationSlugs.includes(organizationSlug)) {
        throw new Error(`Supabase account ${account.id} is not allowed to access project ${projectRef}`);
    }
}
async function ensureBranchAllowed(account, configuration, projectRef, branchIdOrRef, fetchFn) {
    await ensureProjectAllowed(account, configuration, projectRef, fetchFn);
    const data = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(projectRef)}/branches`, 'GET', {}, undefined, fetchFn);
    const branches = Array.isArray(data)
        ? data
        : data && typeof data === 'object' && Array.isArray(data.branches)
            ? data.branches
            : [];
    const match = branches.some((candidate) => {
        if (!candidate || typeof candidate !== 'object')
            return false;
        const branch = candidate;
        return [branch.id, branch.ref, branch.name].some((value) => value === branchIdOrRef);
    });
    if (!match)
        throw new Error(`Branch ${branchIdOrRef} is not visible under allowed project ${projectRef}`);
}
function childBranchRecords(data) {
    if (Array.isArray(data))
        return data;
    if (data && typeof data === 'object' && Array.isArray(data.branches))
        return data.branches;
    return [];
}
function childBranchCollides(candidate, branchId, childProjectRef) {
    if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate))
        return false;
    return candidate.id === branchId
        || candidate.project_ref === childProjectRef
        || candidate.ref === childProjectRef;
}
function exactChildBranchMatch(candidate, parentProjectRef, branchId, childProjectRef) {
    if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate))
        return false;
    const branch = candidate;
    if (branch.id !== branchId
        || branch.project_ref !== childProjectRef
        || (branch.ref !== undefined && branch.ref !== childProjectRef)
        || branch.parent_project_ref !== parentProjectRef
        || branch.is_default !== false
        || branch.persistent !== false
        || branch.with_data !== false
        || branch.status !== 'FUNCTIONS_DEPLOYED'
        || branch.preview_project_status !== 'ACTIVE_HEALTHY'
        || (branch.deletion_scheduled_at !== undefined && branch.deletion_scheduled_at !== null)) {
        return false;
    }
    return true;
}
function exactDeletableChildBranchMatch(candidate, parentProjectRef, branchId, childProjectRef) {
    if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate))
        return false;
    const branch = candidate;
    return branch.id === branchId
        && branch.project_ref === childProjectRef
        && (branch.ref === undefined || branch.ref === childProjectRef)
        && branch.parent_project_ref === parentProjectRef
        && branch.is_default === false
        && branch.persistent === false
        && branch.with_data === false;
}
function sameProjectSnapshot(left, right) {
    return left.ref === right.ref
        && left.organizationSlug === right.organizationSlug
        && left.status === right.status;
}
async function readAllowedParentProject(account, configuration, parentProjectRef, phase, fetchFn, expectedSnapshot, requireHealthy = false) {
    if (!account.allowedProjectRefs.includes(parentProjectRef)) {
        throw new Error(`Supabase account ${account.id} is not statically allowed to access parent project ${parentProjectRef}`);
    }
    const project = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(parentProjectRef)}`, 'GET', {}, undefined, fetchFn);
    const ref = project && typeof project === 'object' && !Array.isArray(project)
        ? project.ref
        : undefined;
    const organizationSlug = project && typeof project === 'object' && !Array.isArray(project)
        ? project.organization_slug
        : undefined;
    const status = project && typeof project === 'object' && !Array.isArray(project)
        ? project.status
        : undefined;
    if (ref !== parentProjectRef
        || typeof organizationSlug !== 'string'
        || typeof status !== 'string'
        || (account.allowedOrganizationSlugs.length > 0
            && !account.allowedOrganizationSlugs.includes(organizationSlug))) {
        throw new Error(`Allowed parent project ${parentProjectRef} identity drifted during ${phase}`);
    }
    const snapshot = { ref, organizationSlug, status };
    if (requireHealthy && snapshot.status !== 'ACTIVE_HEALTHY') {
        throw new Error(`Allowed parent project ${parentProjectRef} is not ACTIVE_HEALTHY during ${phase}`);
    }
    if (expectedSnapshot && !sameProjectSnapshot(snapshot, expectedSnapshot)) {
        throw new Error(`Allowed parent project ${parentProjectRef} changed after its bound snapshot during ${phase}`);
    }
    return snapshot;
}
async function readBoundChildProject(account, configuration, childProjectRef, organizationSlug, phase, fetchFn, expectedSnapshot, requireHealthy = true) {
    const project = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(childProjectRef)}`, 'GET', {}, undefined, fetchFn);
    const ref = project && typeof project === 'object' && !Array.isArray(project)
        ? project.ref
        : undefined;
    const observedOrganization = project && typeof project === 'object' && !Array.isArray(project)
        ? project.organization_slug
        : undefined;
    const status = project && typeof project === 'object' && !Array.isArray(project)
        ? project.status
        : undefined;
    if (ref !== childProjectRef
        || observedOrganization !== organizationSlug
        || typeof status !== 'string'
        || (account.allowedOrganizationSlugs.length > 0
            && !account.allowedOrganizationSlugs.includes(observedOrganization))) {
        throw new Error(`Child project ${childProjectRef} identity drifted during ${phase}`);
    }
    const snapshot = { ref, organizationSlug: observedOrganization, status };
    if (requireHealthy && snapshot.status !== 'ACTIVE_HEALTHY') {
        throw new Error(`Child project ${childProjectRef} is not ACTIVE_HEALTHY during ${phase}`);
    }
    if (expectedSnapshot && !sameProjectSnapshot(snapshot, expectedSnapshot)) {
        throw new Error(`Child project ${childProjectRef} changed after its bound snapshot during ${phase}`);
    }
    return snapshot;
}
async function ensureChildBranchBinding(account, configuration, parentProjectRef, branchId, childProjectRef, phase, fetchFn, expectedBinding) {
    const parent = await readAllowedParentProject(account, configuration, parentProjectRef, phase, fetchFn, expectedBinding?.parent, true);
    const data = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(parentProjectRef)}/branches`, 'GET', {}, undefined, fetchFn);
    const collisions = childBranchRecords(data).filter((candidate) => childBranchCollides(candidate, branchId, childProjectRef));
    if (collisions.length !== 1
        || !exactChildBranchMatch(collisions[0], parentProjectRef, branchId, childProjectRef)) {
        throw new Error(`Child project ${childProjectRef} is not uniquely bound to branch ${branchId} under allowed parent ${parentProjectRef} during ${phase}`);
    }
    const child = await readBoundChildProject(account, configuration, childProjectRef, parent.organizationSlug, phase, fetchFn, expectedBinding?.child, true);
    return { parent, child };
}
async function ensureDeletableChildBranchBinding(account, configuration, parentProjectRef, branchId, childProjectRef, fetchFn) {
    const parent = await readAllowedParentProject(account, configuration, parentProjectRef, 'delete preflight', fetchFn);
    const data = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(parentProjectRef)}/branches`, 'GET', {}, undefined, fetchFn);
    const collisions = childBranchRecords(data).filter((candidate) => childBranchCollides(candidate, branchId, childProjectRef));
    if (collisions.length !== 1
        || !exactDeletableChildBranchMatch(collisions[0], parentProjectRef, branchId, childProjectRef)) {
        throw new Error(`Child project ${childProjectRef} is not uniquely bound to deletable branch ${branchId} under allowed parent ${parentProjectRef} during delete preflight`);
    }
    const child = await readBoundChildProjectIfPresent(account, configuration, childProjectRef, parent.organizationSlug, 'delete preflight', fetchFn);
    return { parent, child };
}
function childDatabaseProviderBody(input) {
    return {
        query: input.sql,
        parameters: input.parameters,
        read_only: false,
    };
}
function childDatabaseBodySha256(body) {
    return (0, crypto_1.createHash)('sha256')
        .update(JSON.stringify(body), 'utf8')
        .digest('hex');
}
function childDeletionReconciliationProof(account, parentProjectRef, branchId, childProjectRef, parentSnapshot) {
    const canonical = JSON.stringify({
        schemaVersion: 'supabase-child-deletion-reconciliation-v1',
        accountId: account.id,
        parentProjectRef,
        branchId,
        childProjectRef,
        parentOrganizationSlug: parentSnapshot.organizationSlug,
        parentStatus: parentSnapshot.status,
    });
    return (0, crypto_1.createHmac)('sha256', account.token)
        .update(canonical, 'utf8')
        .digest('hex');
}
function assertChildDeletionReconciliationProof(actual, expected) {
    const actualBytes = Buffer.from(actual, 'hex');
    const expectedBytes = Buffer.from(expected, 'hex');
    if (actualBytes.length !== expectedBytes.length
        || !(0, crypto_1.timingSafeEqual)(actualBytes, expectedBytes)) {
        throw new Error('Child deletion reconciliation proof is invalid');
    }
}
function childQueryConfiguration(configuration) {
    const configuredLimit = Number.isFinite(configuration.maxResponseBytes)
        ? configuration.maxResponseBytes
        : DEFAULT_MAX_RESPONSE_BYTES;
    return {
        ...configuration,
        maxResponseBytes: Math.min(configuredLimit, CHILD_DATABASE_RESPONSE_MAX_BYTES),
    };
}
async function readSupabaseProjectIfPresent(account, configuration, childProjectRef, fetchFn) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), configuration.timeoutMs || DEFAULT_TIMEOUT_MS);
    try {
        const response = await fetchFn(`${SUPABASE_API_ORIGIN}/projects/${encodeURIComponent(childProjectRef)}`, {
            method: 'GET',
            headers: supabaseHeaders(account.token),
            signal: controller.signal,
            redirect: 'error',
        });
        if (response.status === 404) {
            const declaredLength = Number(response.headers?.get('content-length') || '0');
            const limit = configuration.maxResponseBytes || DEFAULT_MAX_RESPONSE_BYTES;
            if (Number.isFinite(declaredLength) && declaredLength > limit) {
                throw new Error('Supabase Management API response exceeded size limit');
            }
            if (response.text) {
                const text = await response.text();
                if (Buffer.byteLength(text, 'utf8') > limit) {
                    throw new Error('Supabase Management API response exceeded size limit');
                }
            }
            return undefined;
        }
        return parseResponse(response, 'GET', configuration.maxResponseBytes || DEFAULT_MAX_RESPONSE_BYTES, 'Supabase Management API');
    }
    catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
            throw new Error('Supabase Management API request timed out');
        }
        throw error;
    }
    finally {
        clearTimeout(timeout);
    }
}
async function readBoundChildProjectIfPresent(account, configuration, childProjectRef, organizationSlug, phase, fetchFn) {
    const project = await readSupabaseProjectIfPresent(account, configuration, childProjectRef, fetchFn);
    if (project === undefined)
        return undefined;
    const ref = project && typeof project === 'object' && !Array.isArray(project)
        ? project.ref
        : undefined;
    const observedOrganization = project && typeof project === 'object' && !Array.isArray(project)
        ? project.organization_slug
        : undefined;
    const status = project && typeof project === 'object' && !Array.isArray(project) && typeof project.status === 'string'
        ? project.status
        : undefined;
    if (ref !== childProjectRef || observedOrganization !== organizationSlug) {
        throw new Error(`Child project ${childProjectRef} identity drifted during ${phase}`);
    }
    return { ref, organizationSlug: observedOrganization, status };
}
async function readChildDeletionState(account, configuration, parentProjectRef, branchId, childProjectRef, expectedParentSnapshot, fetchFn) {
    const parent = await readAllowedParentProject(account, configuration, parentProjectRef, 'delete reconciliation', fetchFn, expectedParentSnapshot);
    const data = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(parentProjectRef)}/branches`, 'GET', {}, undefined, fetchFn);
    const collisions = childBranchRecords(data).filter((candidate) => childBranchCollides(candidate, branchId, childProjectRef));
    if (collisions.length > 0
        && (collisions.length !== 1
            || !exactDeletableChildBranchMatch(collisions[0], parentProjectRef, branchId, childProjectRef))) {
        throw new Error(`Child deletion reconciliation identity conflict for ${childProjectRef} under ${parentProjectRef}`);
    }
    const branchPresent = collisions.length === 1;
    const child = await readBoundChildProjectIfPresent(account, configuration, childProjectRef, parent.organizationSlug, 'delete reconciliation', fetchFn);
    const childProjectPresent = child !== undefined;
    return {
        complete: !branchPresent && !childProjectPresent,
        branchPresent,
        childProjectPresent,
    };
}
async function reconcileDeletedChild(account, configuration, parentProjectRef, branchId, childProjectRef, expectedParentSnapshot, fetchFn) {
    let state = { complete: false, branchPresent: true, childProjectPresent: true };
    for (let attempt = 1; attempt <= CHILD_DELETE_RECONCILIATION_ATTEMPTS; attempt += 1) {
        state = await readChildDeletionState(account, configuration, parentProjectRef, branchId, childProjectRef, expectedParentSnapshot, fetchFn);
        if (state.complete)
            return { ...state, attempts: attempt };
        if (attempt < CHILD_DELETE_RECONCILIATION_ATTEMPTS) {
            await new Promise((resolve) => setTimeout(resolve, CHILD_DELETE_RECONCILIATION_DELAY_MS));
        }
    }
    return { ...state, attempts: CHILD_DELETE_RECONCILIATION_ATTEMPTS };
}
function assertConfirmation(actual, expected) {
    if (actual !== expected)
        throw new Error(`Confirmation must exactly equal "${expected}"`);
}
async function executeSupabaseProviderApiTool(tool, args, configuration, fetchFn) {
    const providerFetch = fetchFn ?? globalThis.fetch;
    switch (tool) {
        case 'supabase.read-project-api': {
            const input = SupabaseProjectReadArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            await ensureProjectAllowed(account, configuration, input.projectRef, providerFetch);
            return supabaseRequest(account, configuration, `/projects/${encodeURIComponent(input.projectRef)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, undefined, providerFetch);
        }
        case 'supabase.write-project-api': {
            const input = SupabaseProjectWriteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            assertProjectMutationPathAllowed(input.pathSegments);
            await ensureProjectAllowed(account, configuration, input.projectRef, providerFetch);
            assertConfirmation(input.confirmation, `${input.method} PROJECT ${input.projectRef}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/projects/${encodeURIComponent(input.projectRef)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, input.body, providerFetch);
        }
        case 'supabase.write-child-database-query': {
            const input = SupabaseChildDatabaseQueryArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            if (input.parentProjectRef === input.childProjectRef) {
                throw new Error('Child project ref must differ from its allowlisted parent project ref');
            }
            const body = childDatabaseProviderBody(input);
            const computedBodySha256 = childDatabaseBodySha256(body);
            if (input.bodySha256 !== computedBodySha256) {
                throw new Error(`Child database bodySha256 must exactly equal ${computedBodySha256}`);
            }
            const expected = `POST CHILD DATABASE ${input.parentProjectRef}:${input.branchId}:${input.childProjectRef} BODY_SHA256 ${computedBodySha256}`;
            assertConfirmation(input.confirmation, expected);
            const binding = await ensureChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, 'query preflight', providerFetch);
            const result = await supabaseRequest(account, childQueryConfiguration(configuration), `/projects/${encodeURIComponent(input.childProjectRef)}/database/query`, 'POST', {}, body, providerFetch);
            await ensureChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, 'query postflight', providerFetch, binding);
            return result;
        }
        case 'supabase.delete-child-branch': {
            const input = SupabaseChildBranchDeleteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            if (input.parentProjectRef === input.childProjectRef) {
                throw new Error('Child project ref must differ from its allowlisted parent project ref');
            }
            const expected = `DELETE CHILD BRANCH ${input.parentProjectRef}:${input.branchId}:${input.childProjectRef}`;
            assertConfirmation(input.confirmation, expected);
            const binding = await ensureDeletableChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, providerFetch);
            const reconciliationProof = childDeletionReconciliationProof(account, input.parentProjectRef, input.branchId, input.childProjectRef, binding.parent);
            const deleteReceipt = await supabaseRequest(account, configuration, `/branches/${encodeURIComponent(input.branchId)}`, 'DELETE', { force: 'true' }, undefined, providerFetch);
            let reconciliation;
            try {
                reconciliation = await reconcileDeletedChild(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, binding.parent, providerFetch);
            }
            catch (error) {
                reconciliation = {
                    complete: false,
                    attempts: 0,
                    error: error instanceof Error ? error.message : 'Unknown child deletion reconciliation error',
                };
            }
            return {
                deleteReceipt,
                reconciliation: {
                    ...reconciliation,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                },
                parentSnapshot: binding.parent,
                reconciliationArgs: {
                    accountId: input.accountId,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                    expectedParentOrganizationSlug: binding.parent.organizationSlug,
                    expectedParentStatus: binding.parent.status,
                    reconciliationProof,
                },
            };
        }
        case 'supabase.read-child-deletion-reconciliation': {
            const input = SupabaseChildDeletionReconciliationArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            const expectedParentSnapshot = {
                ref: input.parentProjectRef,
                organizationSlug: input.expectedParentOrganizationSlug,
                status: input.expectedParentStatus,
            };
            const expectedProof = childDeletionReconciliationProof(account, input.parentProjectRef, input.branchId, input.childProjectRef, expectedParentSnapshot);
            assertChildDeletionReconciliationProof(input.reconciliationProof, expectedProof);
            const state = await readChildDeletionState(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, expectedParentSnapshot, providerFetch);
            return {
                ...state,
                parentProjectRef: input.parentProjectRef,
                branchId: input.branchId,
                childProjectRef: input.childProjectRef,
            };
        }
        case 'supabase.delete-project-api': {
            const input = SupabaseProjectDeleteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            assertProjectMutationPathAllowed(input.pathSegments);
            await ensureProjectAllowed(account, configuration, input.projectRef, providerFetch);
            assertConfirmation(input.confirmation, `DELETE PROJECT ${input.projectRef}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/projects/${encodeURIComponent(input.projectRef)}${encodedSuffix(input.pathSegments)}`, 'DELETE', input.query, input.body, providerFetch);
        }
        case 'supabase.read-organization-api': {
            const input = SupabaseOrganizationReadArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertOrganizationAllowed(account, input.organizationSlug);
            return supabaseRequest(account, configuration, `/organizations/${encodeURIComponent(input.organizationSlug)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, undefined, providerFetch);
        }
        case 'supabase.write-organization-api': {
            const input = SupabaseOrganizationWriteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            assertOrganizationAllowed(account, input.organizationSlug);
            assertConfirmation(input.confirmation, `${input.method} ORGANIZATION ${input.organizationSlug}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/organizations/${encodeURIComponent(input.organizationSlug)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, input.body, providerFetch);
        }
        case 'supabase.delete-organization-api': {
            const input = SupabaseOrganizationDeleteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            assertOrganizationAllowed(account, input.organizationSlug);
            assertConfirmation(input.confirmation, `DELETE ORGANIZATION ${input.organizationSlug}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/organizations/${encodeURIComponent(input.organizationSlug)}${encodedSuffix(input.pathSegments)}`, 'DELETE', input.query, input.body, providerFetch);
        }
        case 'supabase.read-branch-api': {
            const input = SupabaseBranchReadArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            await ensureBranchAllowed(account, configuration, input.projectRef, input.branchIdOrRef, providerFetch);
            return supabaseRequest(account, configuration, `/branches/${encodeURIComponent(input.branchIdOrRef)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, undefined, providerFetch);
        }
        case 'supabase.write-branch-api': {
            const input = SupabaseBranchWriteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            await ensureBranchAllowed(account, configuration, input.projectRef, input.branchIdOrRef, providerFetch);
            assertConfirmation(input.confirmation, `${input.method} BRANCH ${input.projectRef}:${input.branchIdOrRef}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/branches/${encodeURIComponent(input.branchIdOrRef)}${encodedSuffix(input.pathSegments)}`, input.method, input.query, input.body, providerFetch);
        }
        case 'supabase.delete-branch-api': {
            const input = SupabaseBranchDeleteArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertSupabaseMutationAllowed(account);
            await ensureBranchAllowed(account, configuration, input.projectRef, input.branchIdOrRef, providerFetch);
            assertConfirmation(input.confirmation, `DELETE BRANCH ${input.projectRef}:${input.branchIdOrRef}${rawSuffix(input.pathSegments)}`);
            return supabaseRequest(account, configuration, `/branches/${encodeURIComponent(input.branchIdOrRef)}${encodedSuffix(input.pathSegments)}`, 'DELETE', input.query, input.body, providerFetch);
        }
        default:
            throw new Error(`Unknown Supabase provider API tool: ${tool}`);
    }
}
const repositoryProperties = {
    owner: { type: 'string', description: 'Repository owner' },
    repo: { type: 'string', description: 'Repository name' },
};
const accountProperty = { accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' } };
const projectProperties = {
    ...accountProperty,
    projectRef: { type: 'string', description: 'Exact 20-character Supabase project ref' },
};
const genericProperties = {
    pathSegments: {
        type: 'array', items: { type: 'string' },
        description: 'Provider path segments after the selected repository/project/organization/branch',
    },
    query: { type: 'object', additionalProperties: true, description: 'Query parameters' },
};
exports.githubProviderApiTools = {
    'github.read-repository-api': {
        description: 'Call any GET or HEAD GitHub REST endpoint under one allowlisted repository',
        parameters: {
            type: 'object',
            properties: { ...repositoryProperties, ...genericProperties, method: { type: 'string', enum: ['GET', 'HEAD'] } },
            required: ['owner', 'repo'],
        },
    },
    'github.write-repository-api': {
        description: 'Call any POST, PUT, or PATCH GitHub REST endpoint under one allowlisted repository',
        parameters: {
            type: 'object',
            properties: {
                ...repositoryProperties, ...genericProperties,
                method: { type: 'string', enum: ['POST', 'PUT', 'PATCH'] },
                body: { description: 'JSON request body' },
                confirmation: { type: 'string', description: 'METHOD owner/repo/path' },
            },
            required: ['owner', 'repo', 'method', 'confirmation'],
        },
    },
    'github.delete-repository-api': {
        description: 'Call any DELETE GitHub REST endpoint under one allowlisted repository; classified as destructive',
        parameters: {
            type: 'object',
            properties: {
                ...repositoryProperties, ...genericProperties,
                body: { description: 'Optional JSON request body' },
                confirmation: { type: 'string', description: 'DELETE owner/repo/path' },
            },
            required: ['owner', 'repo', 'confirmation'],
        },
    },
};
exports.supabaseProviderApiTools = {
    'supabase.read-project-api': {
        description: 'Call any GET or HEAD Management API endpoint under one allowlisted Supabase project',
        parameters: {
            type: 'object', properties: { ...projectProperties, ...genericProperties, method: { type: 'string', enum: ['GET', 'HEAD'] } },
            required: ['accountId', 'projectRef'],
        },
    },
    'supabase.write-project-api': {
        description: 'Call any POST, PUT, or PATCH Management API endpoint under one allowlisted Supabase project',
        parameters: {
            type: 'object',
            properties: {
                ...projectProperties, ...genericProperties, method: { type: 'string', enum: ['POST', 'PUT', 'PATCH'] },
                body: { description: 'JSON request body' }, confirmation: { type: 'string', description: 'METHOD PROJECT projectRef/path' },
            },
            required: ['accountId', 'projectRef', 'method', 'confirmation'],
        },
    },
    'supabase.write-child-database-query': {
        description: 'Run one approved SQL mutation plan with read_only=false against an exact healthy disposable child project only after proving its UUID branch and project binding to an allowlisted parent before and after dispatch; logical scope gating uses projects:read and projects:write while the downstream provider still enforces its own database permission',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the verified parent branch inventory' },
                sql: { type: 'string', minLength: 1, maxLength: CHILD_DATABASE_QUERY_MAX_BYTES, description: 'Exact SQL bytes to send as the provider body query field' },
                parameters: {
                    type: 'array',
                    maxItems: 100,
                    items: {},
                    description: `Bounded JSON parameters; serialized array must not exceed ${CHILD_DATABASE_PARAMETERS_MAX_BYTES} UTF-8 bytes`,
                },
                bodySha256: { type: 'string', pattern: '^[a-f0-9]{64}$', description: 'SHA-256 of the exact UTF-8 JSON provider body {"query":sql,"parameters":parameters,"read_only":false}' },
                confirmation: {
                    type: 'string',
                    description: 'POST CHILD DATABASE parentProjectRef:branchId:childProjectRef BODY_SHA256 bodySha256',
                },
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef', 'sql', 'parameters', 'bodySha256', 'confirmation'],
        },
    },
    'supabase.delete-child-branch': {
        description: 'Force-delete one exact disposable child branch by provider UUID using only DELETE /branches/{uuid}?force=true after proving its allowlisted-parent binding; returns the exact delete receipt plus bounded read-only reconciliation and never retries DELETE',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the verified parent branch inventory' },
                confirmation: { type: 'string', description: 'DELETE CHILD BRANCH parentProjectRef:branchId:childProjectRef' },
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef', 'confirmation'],
        },
    },
    'supabase.read-child-deletion-reconciliation': {
        description: 'Reconcile terminal deletion for one exact parent/UUID/child binding without mutating or returning provider records; returns only bounded presence booleans and exact requested identities and can be called repeatedly after one DELETE receipt',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact statically allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID from the delete receipt chain' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the delete receipt chain' },
                expectedParentOrganizationSlug: { type: 'string', minLength: 1, maxLength: 160, description: 'Exact parent organization snapshot captured before DELETE' },
                expectedParentStatus: { type: 'string', minLength: 1, maxLength: 80, description: 'Exact parent status snapshot captured before DELETE' },
                reconciliationProof: { type: 'string', pattern: '^[a-f0-9]{64}$', description: 'Server-generated HMAC capability returned only by the bound delete operation; prevents arbitrary child-ref probing' },
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef', 'expectedParentOrganizationSlug', 'expectedParentStatus', 'reconciliationProof'],
        },
    },
    'supabase.delete-project-api': {
        description: 'Call any DELETE Management API endpoint under one allowlisted Supabase project; classified as destructive',
        parameters: {
            type: 'object',
            properties: { ...projectProperties, ...genericProperties, body: {}, confirmation: { type: 'string' } },
            required: ['accountId', 'projectRef', 'confirmation'],
        },
    },
    'supabase.read-organization-api': {
        description: 'Call any GET or HEAD Management API endpoint under one allowlisted Supabase organization',
        parameters: {
            type: 'object',
            properties: { ...accountProperty, organizationSlug: { type: 'string' }, ...genericProperties, method: { type: 'string', enum: ['GET', 'HEAD'] } },
            required: ['accountId', 'organizationSlug'],
        },
    },
    'supabase.write-organization-api': {
        description: 'Call any POST, PUT, or PATCH Management API endpoint under one allowlisted Supabase organization',
        parameters: {
            type: 'object',
            properties: {
                ...accountProperty, organizationSlug: { type: 'string' }, ...genericProperties,
                method: { type: 'string', enum: ['POST', 'PUT', 'PATCH'] }, body: {}, confirmation: { type: 'string' },
            },
            required: ['accountId', 'organizationSlug', 'method', 'confirmation'],
        },
    },
    'supabase.delete-organization-api': {
        description: 'Call any DELETE Management API endpoint under one allowlisted Supabase organization; classified as destructive',
        parameters: {
            type: 'object',
            properties: { ...accountProperty, organizationSlug: { type: 'string' }, ...genericProperties, body: {}, confirmation: { type: 'string' } },
            required: ['accountId', 'organizationSlug', 'confirmation'],
        },
    },
    'supabase.read-branch-api': {
        description: 'Call any GET or HEAD Management API endpoint under a branch verified against an allowlisted project',
        parameters: {
            type: 'object',
            properties: { ...projectProperties, branchIdOrRef: { type: 'string' }, ...genericProperties, method: { type: 'string', enum: ['GET', 'HEAD'] } },
            required: ['accountId', 'projectRef', 'branchIdOrRef'],
        },
    },
    'supabase.write-branch-api': {
        description: 'Call any POST, PUT, or PATCH Management API endpoint under a branch verified against an allowlisted project',
        parameters: {
            type: 'object',
            properties: {
                ...projectProperties, branchIdOrRef: { type: 'string' }, ...genericProperties,
                method: { type: 'string', enum: ['POST', 'PUT', 'PATCH'] }, body: {}, confirmation: { type: 'string' },
            },
            required: ['accountId', 'projectRef', 'branchIdOrRef', 'method', 'confirmation'],
        },
    },
    'supabase.delete-branch-api': {
        description: 'Call any DELETE Management API endpoint under a branch verified against an allowlisted project; classified as destructive',
        parameters: {
            type: 'object',
            properties: { ...projectProperties, branchIdOrRef: { type: 'string' }, ...genericProperties, body: {}, confirmation: { type: 'string' } },
            required: ['accountId', 'projectRef', 'branchIdOrRef', 'confirmation'],
        },
    },
};
//# sourceMappingURL=provider-api.js.map
