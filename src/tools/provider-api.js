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
const CHILD_DELETE_AUTHORIZATION_TTL_MS = 10 * 60 * 1000;
const CHILD_DELETE_RECONCILIATION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const CHILD_DELETE_MINIMUM_RESERVATION_WINDOW_MS = 120 * 1000;
const CHILD_DELETE_CAPABILITY_SCHEMA_VERSION = 'supabase-child-deletion-capability-v3';
const CHILD_DELETE_CAPABILITY_ACTION = 'delete-and-reconcile-child-branch';
const CHILD_DELETE_RESERVATION_INTENT_SCHEMA_VERSION = 'projectos-destructive-capability-reservation-intent-v1';
const CHILD_DELETE_RESERVATION_RECEIPT_SCHEMA_VERSION = 'projectos-destructive-capability-reservation-receipt-v2';
const CHILD_DELETE_RESERVATION_PROVIDER = 'projectos_capability_reservation';
const CHILD_DELETE_RESERVATION_EVENT_TYPE = 'supabase_child_branch_delete_reserved';
const CONTROL_PROJECT_REF = 'jcyqixttuebxqqfkjonq';
const CONTROL_ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
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
    deletionCapability: zod_1.z.object({
        schemaVersion: zod_1.z.literal(CHILD_DELETE_CAPABILITY_SCHEMA_VERSION),
        action: zod_1.z.literal(CHILD_DELETE_CAPABILITY_ACTION),
        signingKeyId: zod_1.z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/),
        reservationKeyId: zod_1.z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/),
        accountId: zod_1.z.string().min(1),
        organizationSlug: zod_1.z.string().regex(/^[a-z0-9]{20}$/),
        parentProjectRef: SupabaseProjectRefSchema,
        parentStatus: zod_1.z.string().min(1).max(80),
        branchId: SupabaseBranchUuidSchema,
        childProjectRef: SupabaseProjectRefSchema,
        operationNonce: zod_1.z.string().regex(/^[a-f0-9]{64}$/),
        issuedAt: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/),
        deleteAuthorizationExpiresAt: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/),
        reconciliationExpiresAt: zod_1.z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/),
        membershipSnapshotSha256: zod_1.z.string().regex(/^[a-f0-9]{64}$/),
        proof: zod_1.z.string().regex(/^[a-f0-9]{64}$/),
    }).strict(),
    confirmation: zod_1.z.string().min(1),
}).strict();
const SupabaseChildDeletionPreparationArgsSchema = SupabaseAccountArgsSchema.extend({
    parentProjectRef: SupabaseProjectRefSchema,
    branchId: SupabaseBranchUuidSchema,
    childProjectRef: SupabaseProjectRefSchema,
}).strict();
const SupabaseChildDeletionReconciliationArgsSchema = SupabaseChildDeletionPreparationArgsSchema.extend({
    deletionCapability: SupabaseChildBranchDeleteArgsSchema.shape.deletionCapability,
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
    const records = Array.isArray(data)
        ? data
        : data
            && typeof data === 'object'
            && !Array.isArray(data)
            && Object.keys(data).length === 1
            && Array.isArray(data.branches)
            ? data.branches
            : undefined;
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    const projectRef = /^[a-z0-9]{20}$/;
    if (!records
        || records.some((candidate) => !candidate
            || typeof candidate !== 'object'
            || Array.isArray(candidate)
            || !uuid.test(candidate.id || '')
            || !projectRef.test(candidate.project_ref || '')
            || !projectRef.test(candidate.parent_project_ref || '')
            || (candidate.ref !== undefined
                && (typeof candidate.ref !== 'string' || !projectRef.test(candidate.ref)))
            || (candidate.name !== undefined && typeof candidate.name !== 'string')
            || (candidate.is_default !== undefined && typeof candidate.is_default !== 'boolean')
            || (candidate.persistent !== undefined && typeof candidate.persistent !== 'boolean')
            || (candidate.with_data !== undefined && typeof candidate.with_data !== 'boolean')
            || (candidate.status !== undefined && typeof candidate.status !== 'string')
            || (candidate.preview_project_status !== undefined && typeof candidate.preview_project_status !== 'string')
            || (candidate.deletion_scheduled_at !== undefined
                && candidate.deletion_scheduled_at !== null
                && typeof candidate.deletion_scheduled_at !== 'string')
            || (candidate.created_at !== undefined && typeof candidate.created_at !== 'string'))) {
        throw new Error('Supabase child branch inventory is malformed');
    }
    return records;
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
        && typeof branch.name === 'string'
        && branch.name.length > 0
        && branch.is_default === false
        && branch.persistent === false
        && branch.with_data === false
        && typeof branch.status === 'string'
        && branch.status.length > 0
        && typeof branch.preview_project_status === 'string'
        && branch.preview_project_status.length > 0
        && typeof branch.created_at === 'string'
        && Number.isFinite(Date.parse(branch.created_at));
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
        || !/^[a-z0-9]{20}$/.test(organizationSlug)
        || typeof status !== 'string'
        || status.length === 0
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
        || !/^[a-z0-9]{20}$/.test(observedOrganization)
        || typeof status !== 'string'
        || status.length === 0
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
async function ensureDeletableChildBranchBinding(account, configuration, parentProjectRef, branchId, childProjectRef, fetchFn, phase = 'delete preflight', expectedParentSnapshot) {
    const parent = await readAllowedParentProject(account, configuration, parentProjectRef, phase, fetchFn, expectedParentSnapshot);
    const data = await supabaseRequest(account, configuration, `/projects/${encodeURIComponent(parentProjectRef)}/branches`, 'GET', {}, undefined, fetchFn);
    const collisions = childBranchRecords(data).filter((candidate) => childBranchCollides(candidate, branchId, childProjectRef));
    if (collisions.length !== 1
        || !exactDeletableChildBranchMatch(collisions[0], parentProjectRef, branchId, childProjectRef)) {
        throw new Error(`Child project ${childProjectRef} is not uniquely bound to deletable branch ${branchId} under allowed parent ${parentProjectRef} during ${phase}`);
    }
    const child = await readBoundChildProjectIfPresent(account, configuration, childProjectRef, parent.organizationSlug, phase, fetchFn);
    return { parent, branch: collisions[0], child };
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
function childDeletionMembershipSnapshot(binding) {
    const branch = binding.branch;
    return {
        parent: {
            ref: binding.parent.ref,
            organizationSlug: binding.parent.organizationSlug,
            status: binding.parent.status,
        },
        branch: {
            id: branch.id,
            name: typeof branch.name === 'string' ? branch.name : null,
            projectRef: branch.project_ref,
            parentProjectRef: branch.parent_project_ref,
            ref: typeof branch.ref === 'string' ? branch.ref : null,
            isDefault: branch.is_default,
            persistent: branch.persistent,
            withData: branch.with_data,
            status: typeof branch.status === 'string' ? branch.status : null,
            previewProjectStatus: typeof branch.preview_project_status === 'string'
                ? branch.preview_project_status
                : null,
            deletionScheduledAt: typeof branch.deletion_scheduled_at === 'string'
                ? branch.deletion_scheduled_at
                : null,
            createdAt: typeof branch.created_at === 'string' ? branch.created_at : null,
        },
        child: binding.child
            ? {
                ref: binding.child.ref,
                organizationSlug: binding.child.organizationSlug,
                status: binding.child.status,
            }
            : null,
    };
}
function childDeletionMembershipSnapshotSha256(binding) {
    return (0, crypto_1.createHash)('sha256')
        .update(JSON.stringify(childDeletionMembershipSnapshot(binding)), 'utf8')
        .digest('hex');
}
function childDeletionCapabilityPayload(capability) {
    return {
        schemaVersion: capability.schemaVersion,
        action: capability.action,
        signingKeyId: capability.signingKeyId,
        reservationKeyId: capability.reservationKeyId,
        accountId: capability.accountId,
        organizationSlug: capability.organizationSlug,
        parentProjectRef: capability.parentProjectRef,
        parentStatus: capability.parentStatus,
        branchId: capability.branchId,
        childProjectRef: capability.childProjectRef,
        operationNonce: capability.operationNonce,
        issuedAt: capability.issuedAt,
        deleteAuthorizationExpiresAt: capability.deleteAuthorizationExpiresAt,
        reconciliationExpiresAt: capability.reconciliationExpiresAt,
        membershipSnapshotSha256: capability.membershipSnapshotSha256,
    };
}
function childDeletionSigningKey(configuration, keyId) {
    const keyring = configuration.childDeletionCapabilityKeyring;
    if (!keyring
        || typeof keyring !== 'object'
        || typeof keyring.activeKeyId !== 'string'
        || !keyring.keys
        || typeof keyring.keys !== 'object'
        || Array.isArray(keyring.keys)) {
        throw new Error('Child deletion capability signing keyring is not configured');
    }
    const encoded = keyring.keys[keyId];
    if (typeof encoded !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(encoded)) {
        throw new Error(`Child deletion capability signing key ${keyId} is unavailable`);
    }
    const decoded = Buffer.from(encoded, 'base64url');
    if (decoded.length !== 32 || decoded.toString('base64url') !== encoded) {
        throw new Error(`Child deletion capability signing key ${keyId} is invalid`);
    }
    return decoded;
}
function childDeletionOperationNonce(account, configuration, reservationKeyId, organizationSlug, parentProjectRef, branchId, childProjectRef) {
    return (0, crypto_1.createHmac)('sha256', childDeletionSigningKey(configuration, reservationKeyId))
        .update(JSON.stringify({
        schemaVersion: 'supabase-child-deletion-target-v1',
        action: CHILD_DELETE_CAPABILITY_ACTION,
        accountId: account.id,
        organizationSlug,
        parentProjectRef,
        branchId,
        childProjectRef,
    }), 'utf8')
        .digest('hex');
}
function childDeletionCapabilityProof(configuration, capability) {
    const canonical = JSON.stringify(childDeletionCapabilityPayload(capability));
    return (0, crypto_1.createHmac)('sha256', childDeletionSigningKey(configuration, capability.signingKeyId))
        .update(canonical, 'utf8')
        .digest('hex');
}
function assertChildDeletionCapabilityProof(actual, expected) {
    const actualBytes = Buffer.from(actual, 'hex');
    const expectedBytes = Buffer.from(expected, 'hex');
    if (actualBytes.length !== expectedBytes.length
        || !(0, crypto_1.timingSafeEqual)(actualBytes, expectedBytes)) {
        throw new Error('Child deletion capability proof is invalid');
    }
}
function issueChildDeletionCapability(account, configuration, parentProjectRef, branchId, childProjectRef, binding) {
    const issuedAtMs = Date.now();
    const signingKeyId = configuration.childDeletionCapabilityKeyring?.activeKeyId;
    const reservationKeyId = configuration.childDeletionCapabilityKeyring?.reservationKeyId;
    if (typeof signingKeyId !== 'string'
        || typeof reservationKeyId !== 'string'
        || signingKeyId === reservationKeyId) {
        throw new Error('Child deletion capability signing keyring is not configured');
    }
    const capability = {
        schemaVersion: CHILD_DELETE_CAPABILITY_SCHEMA_VERSION,
        action: CHILD_DELETE_CAPABILITY_ACTION,
        signingKeyId,
        reservationKeyId,
        accountId: account.id,
        organizationSlug: binding.parent.organizationSlug,
        parentProjectRef,
        parentStatus: binding.parent.status,
        branchId,
        childProjectRef,
        operationNonce: childDeletionOperationNonce(account, configuration, reservationKeyId, binding.parent.organizationSlug, parentProjectRef, branchId, childProjectRef),
        issuedAt: new Date(issuedAtMs).toISOString(),
        deleteAuthorizationExpiresAt: new Date(issuedAtMs + CHILD_DELETE_AUTHORIZATION_TTL_MS).toISOString(),
        reconciliationExpiresAt: new Date(issuedAtMs + CHILD_DELETE_RECONCILIATION_TTL_MS).toISOString(),
        membershipSnapshotSha256: childDeletionMembershipSnapshotSha256(binding),
    };
    return {
        ...capability,
        proof: childDeletionCapabilityProof(configuration, capability),
    };
}
function assertChildDeletionCapability(account, configuration, capability, input, purpose) {
    if (capability.accountId !== account.id
        || capability.parentProjectRef !== input.parentProjectRef
        || capability.branchId !== input.branchId
        || capability.childProjectRef !== input.childProjectRef) {
        throw new Error('Child deletion capability target is invalid');
    }
    if (capability.signingKeyId === capability.reservationKeyId) {
        throw new Error('Child deletion capability proof and reservation keys must be role-separated');
    }
    if (purpose === 'delete'
        && capability.reservationKeyId !== configuration.childDeletionCapabilityKeyring?.reservationKeyId) {
        throw new Error('Child deletion capability reservation key is no longer authoritative');
    }
    if (purpose === 'delete'
        && capability.signingKeyId !== configuration.childDeletionCapabilityKeyring?.activeKeyId) {
        throw new Error('Child deletion capability signing key is no longer active for DELETE authorization');
    }
    const expectedNonce = childDeletionOperationNonce(account, configuration, capability.reservationKeyId, capability.organizationSlug, input.parentProjectRef, input.branchId, input.childProjectRef);
    if (capability.operationNonce !== expectedNonce) {
        throw new Error('Child deletion capability operation nonce is invalid');
    }
    assertChildDeletionCapabilityProof(capability.proof, childDeletionCapabilityProof(configuration, capability));
    const issuedAtMs = Date.parse(capability.issuedAt);
    const deleteExpiresAtMs = Date.parse(capability.deleteAuthorizationExpiresAt);
    const reconcileExpiresAtMs = Date.parse(capability.reconciliationExpiresAt);
    if (!Number.isFinite(issuedAtMs)
        || !Number.isFinite(deleteExpiresAtMs)
        || !Number.isFinite(reconcileExpiresAtMs)
        || deleteExpiresAtMs - issuedAtMs !== CHILD_DELETE_AUTHORIZATION_TTL_MS
        || reconcileExpiresAtMs - issuedAtMs !== CHILD_DELETE_RECONCILIATION_TTL_MS
        || issuedAtMs > Date.now() + 30000) {
        throw new Error('Child deletion capability time bounds are invalid');
    }
    const expiresAtMs = purpose === 'delete' ? deleteExpiresAtMs : reconcileExpiresAtMs;
    if (Date.now() >= expiresAtMs) {
        throw new Error(`Child deletion capability is expired for ${purpose}`);
    }
}
function stableReservationValue(value) {
    if (Array.isArray(value))
        return value.map(stableReservationValue);
    if (value && typeof value === 'object') {
        return Object.fromEntries(Object.entries(value)
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([key, nested]) => [key, stableReservationValue(nested)]));
    }
    return value;
}
function childDeletionReservationDeliveryId(input) {
    return (0, crypto_1.createHash)('sha256')
        .update(JSON.stringify({
        reservationDomain: 'projectos-supabase-child-branch-delete-v1',
        parentProjectRef: input.parentProjectRef,
        branchId: input.branchId,
        childProjectRef: input.childProjectRef,
    }), 'utf8')
        .digest('hex');
}
function assertChildDeletionReservationIntent(intent, input) {
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    const binding = intent && typeof intent === 'object' && !Array.isArray(intent)
        ? intent.payloadBinding
        : undefined;
    const redacted = intent && typeof intent === 'object' && !Array.isArray(intent)
        ? intent.payloadRedacted
        : undefined;
    const exactIntentKeys = ['deliveryId', 'eventType', 'payloadBinding', 'payloadHash', 'payloadRedacted', 'provider', 'schemaVersion'];
    const exactBindingKeys = [
        'accountId', 'action', 'branchId', 'capabilitySchemaVersion', 'childProjectRef',
        'deleteAuthorizationExpiresAt', 'issuedAt', 'membershipSnapshotSha256', 'operationNonce',
        'organizationSlug', 'parentProjectRef', 'parentStatus', 'reconciliationExpiresAt',
        'reservationKeyId', 'schemaVersion',
        'signingKeyId', 'sourceIntakeId', 'sourcePayloadHash', 'sourcePlanId', 'sourceRequestId',
    ];
    const exactRedactedKeys = [
        'reservationDomain', 'schemaVersion', 'sourcePayloadHash',
        'sourcePlanId', 'sourceRequestId', 'targetDigest',
    ];
    if (!intent
        || typeof intent !== 'object'
        || Array.isArray(intent)
        || JSON.stringify(Object.keys(intent).sort()) !== JSON.stringify(exactIntentKeys)
        || intent.schemaVersion !== CHILD_DELETE_RESERVATION_INTENT_SCHEMA_VERSION
        || intent.provider !== CHILD_DELETE_RESERVATION_PROVIDER
        || intent.eventType !== CHILD_DELETE_RESERVATION_EVENT_TYPE
        || intent.deliveryId !== childDeletionReservationDeliveryId(input)
        || !/^[a-f0-9]{64}$/.test(intent.payloadHash || '')
        || !binding
        || typeof binding !== 'object'
        || Array.isArray(binding)
        || JSON.stringify(Object.keys(binding).sort()) !== JSON.stringify(exactBindingKeys)
        || binding.schemaVersion !== 'projectos-destructive-capability-reservation-v1'
        || binding.action !== input.deletionCapability.action
        || binding.capabilitySchemaVersion !== input.deletionCapability.schemaVersion
        || binding.signingKeyId !== input.deletionCapability.signingKeyId
        || binding.reservationKeyId !== input.deletionCapability.reservationKeyId
        || binding.accountId !== input.accountId
        || binding.organizationSlug !== input.deletionCapability.organizationSlug
        || binding.parentProjectRef !== input.parentProjectRef
        || binding.parentStatus !== input.deletionCapability.parentStatus
        || binding.branchId !== input.branchId
        || binding.childProjectRef !== input.childProjectRef
        || binding.operationNonce !== input.deletionCapability.operationNonce
        || binding.membershipSnapshotSha256 !== input.deletionCapability.membershipSnapshotSha256
        || binding.issuedAt !== input.deletionCapability.issuedAt
        || binding.deleteAuthorizationExpiresAt !== input.deletionCapability.deleteAuthorizationExpiresAt
        || binding.reconciliationExpiresAt !== input.deletionCapability.reconciliationExpiresAt
        || !uuid.test(binding.sourcePlanId || '')
        || !uuid.test(binding.sourceRequestId || '')
        || !uuid.test(binding.sourceIntakeId || '')
        || binding.sourcePayloadHash !== (0, crypto_1.createHash)('sha256')
            .update(JSON.stringify({ tool: 'supabase.delete-child-branch', args: stableReservationValue(input) }), 'utf8')
            .digest('hex')
        || !redacted
        || typeof redacted !== 'object'
        || Array.isArray(redacted)
        || JSON.stringify(Object.keys(redacted).sort()) !== JSON.stringify(exactRedactedKeys)
        || redacted.schemaVersion !== 'projectos-destructive-capability-reservation-redacted-v1'
        || redacted.reservationDomain !== 'projectos-supabase-child-branch-delete-v1'
        || redacted.targetDigest !== intent.deliveryId
        || redacted.sourcePlanId !== binding.sourcePlanId
        || redacted.sourceRequestId !== binding.sourceRequestId
        || redacted.sourcePayloadHash !== binding.sourcePayloadHash
        || intent.payloadHash !== (0, crypto_1.createHash)('sha256')
            .update(JSON.stringify(stableReservationValue(binding)), 'utf8')
            .digest('hex')) {
        throw new Error('Durable child deletion capability reservation intent is missing or invalid');
    }
    return intent;
}
function exactExternalReservationRow(row, intent) {
    const exactKeys = [
        'delivery_id', 'event_type', 'external_created_at', 'id', 'organization_id',
        'payload_hash', 'payload_redacted', 'process_error', 'process_status', 'processed_at',
        'project_id', 'provider', 'received_at', 'repository',
    ];
    return row
        && typeof row === 'object'
        && !Array.isArray(row)
        && JSON.stringify(Object.keys(row).sort()) === JSON.stringify(exactKeys)
        && ((Number.isSafeInteger(row.id) && row.id > 0) || (typeof row.id === 'string' && /^[1-9][0-9]*$/.test(row.id)))
        && row.organization_id === CONTROL_ORGANIZATION_ID
        && row.project_id === null
        && row.provider === intent.provider
        && row.delivery_id === intent.deliveryId
        && row.event_type === intent.eventType
        && row.repository === null
        && row.external_created_at === null
        && row.payload_hash === intent.payloadHash
        && JSON.stringify(stableReservationValue(row.payload_redacted)) === JSON.stringify(stableReservationValue(intent.payloadRedacted))
        && row.process_status === 'processed'
        && row.process_error === null
        && typeof row.received_at === 'string'
        && Number.isFinite(Date.parse(row.received_at))
        && typeof row.processed_at === 'string'
        && Number.isFinite(Date.parse(row.processed_at))
        && Date.parse(row.processed_at) >= Date.parse(row.received_at);
}
async function reserveChildDeletionCapability(account, configuration, intent, input, fetchFn) {
    assertChildDeletionReservationIntent(intent, input);
    const controlProject = await supabaseRequest(account, configuration, `/projects/${CONTROL_PROJECT_REF}`, 'GET', {}, undefined, fetchFn);
    if (!controlProject
        || typeof controlProject !== 'object'
        || Array.isArray(controlProject)
        || controlProject.ref !== CONTROL_PROJECT_REF
        || controlProject.organization_slug !== input.deletionCapability.organizationSlug
        || controlProject.status !== 'ACTIVE_HEALTHY') {
        throw new Error('ProjectOS control project identity or health drifted before durable reservation');
    }
    const body = {
        query: "insert into public.projectos_external_events (organization_id,project_id,provider,delivery_id,event_type,repository,external_created_at,payload_hash,payload_redacted,process_status,processed_at) values ($1::uuid,null,$2::text,$3::text,$4::text,null,null,$5::text,$6::jsonb,'processed',clock_timestamp()) on conflict (organization_id,provider,delivery_id) do nothing returning jsonb_build_object('id',id,'organization_id',organization_id,'project_id',project_id,'provider',provider,'delivery_id',delivery_id,'event_type',event_type,'repository',repository,'external_created_at',external_created_at,'payload_hash',payload_hash,'payload_redacted',payload_redacted,'process_status',process_status,'process_error',process_error,'received_at',received_at,'processed_at',processed_at) as reservation",
        parameters: [
            CONTROL_ORGANIZATION_ID,
            intent.provider,
            intent.deliveryId,
            intent.eventType,
            intent.payloadHash,
            intent.payloadRedacted,
        ],
        read_only: false,
    };
    const result = await supabaseRequest(account, childQueryConfiguration(configuration), `/projects/${CONTROL_PROJECT_REF}/database/query`, 'POST', {}, body, fetchFn);
    const row = Array.isArray(result) && result.length === 1
        && result[0]
        && typeof result[0] === 'object'
        && !Array.isArray(result[0])
        && Object.keys(result[0]).length === 1
        ? result[0].reservation
        : undefined;
    if (!exactExternalReservationRow(row, intent)) {
        throw new Error('Durable child deletion capability reservation was not proven');
    }
    return {
        schemaVersion: CHILD_DELETE_RESERVATION_RECEIPT_SCHEMA_VERSION,
        controlProjectRef: CONTROL_PROJECT_REF,
        eventId: row.id,
        provider: row.provider,
        deliveryId: row.delivery_id,
        eventType: row.event_type,
        payloadHash: row.payload_hash,
        receivedAt: new Date(row.received_at).toISOString(),
        processedAt: new Date(row.processed_at).toISOString(),
    };
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
    if (ref !== childProjectRef
        || observedOrganization !== organizationSlug
        || !/^[a-z0-9]{20}$/.test(observedOrganization)
        || typeof status !== 'string'
        || status.length === 0) {
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
        case 'supabase.prepare-child-deletion-reconciliation': {
            const input = SupabaseChildDeletionPreparationArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            const activeSigningKeyId = configuration.childDeletionCapabilityKeyring?.activeKeyId;
            const reservationKeyId = configuration.childDeletionCapabilityKeyring?.reservationKeyId;
            if (typeof activeSigningKeyId !== 'string'
                || typeof reservationKeyId !== 'string'
                || activeSigningKeyId === reservationKeyId) {
                throw new Error('Child deletion capability signing keyring is not configured');
            }
            childDeletionSigningKey(configuration, activeSigningKeyId);
            childDeletionSigningKey(configuration, reservationKeyId);
            if (input.parentProjectRef === input.childProjectRef) {
                throw new Error('Child project ref must differ from its allowlisted parent project ref');
            }
            const binding = await ensureDeletableChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, providerFetch, 'deletion capability preparation');
            if (!binding.child) {
                throw new Error(`Child project ${input.childProjectRef} is absent during deletion capability preparation`);
            }
            const deletionCapability = issueChildDeletionCapability(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, binding);
            return {
                parentSnapshot: binding.parent,
                membershipSnapshotSha256: deletionCapability.membershipSnapshotSha256,
                deletionCapability,
                deleteArgs: {
                    accountId: input.accountId,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                    deletionCapability,
                    confirmation: `DELETE CHILD BRANCH ${input.parentProjectRef}:${input.branchId}:${input.childProjectRef}`,
                },
                reconciliationArgs: {
                    accountId: input.accountId,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                    deletionCapability,
                },
            };
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
            assertChildDeletionCapability(account, configuration, input.deletionCapability, input, 'delete');
            if (typeof configuration.destructiveCapabilityReservation !== 'function') {
                throw new Error('Durable child deletion capability reservation authority is missing');
            }
            const expectedParentSnapshot = {
                ref: input.parentProjectRef,
                organizationSlug: input.deletionCapability.organizationSlug,
                status: input.deletionCapability.parentStatus,
            };
            const binding = await ensureDeletableChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, providerFetch, 'delete preflight', expectedParentSnapshot);
            if (!binding.child
                || childDeletionMembershipSnapshotSha256(binding) !== input.deletionCapability.membershipSnapshotSha256) {
                throw new Error('Child deletion target drifted after capability preparation');
            }
            // Provider reads can consume the entire authorization window. Recheck
            // the signed deadline before reserving the one permitted DELETE.
            assertChildDeletionCapability(account, configuration, input.deletionCapability, input, 'delete');
            // Reserve enough signed lifetime for the bounded control-project
            // read/write, three post-reservation target reads, and the one
            // DELETE. A later timeout still burns the target and fails closed.
            if (Date.parse(input.deletionCapability.deleteAuthorizationExpiresAt) - Date.now() < CHILD_DELETE_MINIMUM_RESERVATION_WINDOW_MS) {
                throw new Error('Child deletion capability has insufficient time remaining for durable reservation');
            }
            const reservationIntent = await configuration.destructiveCapabilityReservation(input);
            const reservationReceipt = await reserveChildDeletionCapability(account, configuration, reservationIntent, input, providerFetch);
            // The durable reservation burns this exact target even if any
            // subsequent check fails. Re-read the complete provider binding so
            // drift during reservation can never reach DELETE.
            const postReservationBinding = await ensureDeletableChildBranchBinding(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, providerFetch, 'delete post-reservation preflight', expectedParentSnapshot);
            if (!postReservationBinding.child
                || childDeletionMembershipSnapshotSha256(postReservationBinding) !== input.deletionCapability.membershipSnapshotSha256) {
                throw new Error('Child deletion target drifted after durable reservation');
            }
            // The post-reservation reads can consume time. No provider DELETE
            // is allowed without this final signed-deadline check.
            assertChildDeletionCapability(account, configuration, input.deletionCapability, input, 'delete');
            const deleteReceipt = await supabaseRequest(account, configuration, `/branches/${encodeURIComponent(input.branchId)}`, 'DELETE', { force: 'true' }, undefined, providerFetch);
            let reconciliation;
            try {
                reconciliation = await reconcileDeletedChild(account, configuration, input.parentProjectRef, input.branchId, input.childProjectRef, postReservationBinding.parent, providerFetch);
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
                reservationReceipt,
                reconciliation: {
                    ...reconciliation,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                },
                parentSnapshot: postReservationBinding.parent,
                reconciliationArgs: {
                    accountId: input.accountId,
                    parentProjectRef: input.parentProjectRef,
                    branchId: input.branchId,
                    childProjectRef: input.childProjectRef,
                    deletionCapability: input.deletionCapability,
                },
            };
        }
        case 'supabase.read-child-deletion-reconciliation': {
            const input = SupabaseChildDeletionReconciliationArgsSchema.parse(args);
            const account = supabaseAccount(configuration, input.accountId);
            assertChildDeletionCapability(account, configuration, input.deletionCapability, input, 'reconciliation');
            const expectedParentSnapshot = {
                ref: input.parentProjectRef,
                organizationSlug: input.deletionCapability.organizationSlug,
                status: input.deletionCapability.parentStatus,
            };
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
            throw new Error('Generic Supabase branch deletion is disabled; use the exact prepare, delete-child, and reconciliation capability flow');
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
const childDeletionCapabilitySchema = {
    type: 'object',
    additionalProperties: false,
    properties: {
        schemaVersion: { type: 'string', const: CHILD_DELETE_CAPABILITY_SCHEMA_VERSION },
        action: { type: 'string', const: CHILD_DELETE_CAPABILITY_ACTION },
        signingKeyId: { type: 'string', pattern: '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' },
        reservationKeyId: { type: 'string', pattern: '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' },
        accountId: { type: 'string' },
        organizationSlug: { type: 'string', pattern: '^[a-z0-9]{20}$' },
        parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$' },
        parentStatus: { type: 'string', minLength: 1, maxLength: 80 },
        branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' },
        childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$' },
        operationNonce: { type: 'string', pattern: '^[a-f0-9]{64}$' },
        issuedAt: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$' },
        deleteAuthorizationExpiresAt: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$' },
        reconciliationExpiresAt: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$' },
        membershipSnapshotSha256: { type: 'string', pattern: '^[a-f0-9]{64}$' },
        proof: { type: 'string', pattern: '^[a-f0-9]{64}$' },
    },
    required: [
        'schemaVersion', 'action', 'signingKeyId', 'reservationKeyId', 'accountId', 'organizationSlug',
        'parentProjectRef', 'parentStatus', 'branchId', 'childProjectRef',
        'operationNonce', 'issuedAt', 'deleteAuthorizationExpiresAt',
        'reconciliationExpiresAt', 'membershipSnapshotSha256', 'proof',
    ],
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
    'supabase.prepare-child-deletion-reconciliation': {
        description: 'Issue a signed, time-bounded deletion/reconciliation capability before any DELETE by proving the exact allowlisted parent, branch UUID, child project, organization, and membership snapshot; performs provider reads only',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the verified parent branch inventory' },
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef'],
        },
    },
    'supabase.delete-child-branch': {
        description: 'Force-delete one exact disposable child branch by provider UUID using only DELETE /branches/{uuid}?force=true after validating a separately pre-issued signed capability, atomically burning its durable one-shot reservation, and revalidating unchanged membership; returns the exact receipt plus bounded reconciliation and never retries DELETE. Once reserved, failure or ambiguity requires read-only reconciliation and separately owner-authorized manual recovery rather than a new automated DELETE plan.',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the verified parent branch inventory' },
                deletionCapability: childDeletionCapabilitySchema,
                confirmation: { type: 'string', description: 'DELETE CHILD BRANCH parentProjectRef:branchId:childProjectRef' },
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef', 'deletionCapability', 'confirmation'],
        },
    },
    'supabase.read-child-deletion-reconciliation': {
        description: 'Reconcile terminal deletion for one exact parent/UUID/child binding using the signed capability issued before DELETE; performs reads only, returns bounded presence booleans, and remains repeatable after an accepted-but-response-lost DELETE',
        parameters: {
            type: 'object',
            additionalProperties: false,
            properties: {
                ...accountProperty,
                parentProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact statically allowlisted parent project ref' },
                branchId: { type: 'string', pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', description: 'Exact provider-returned child branch UUID from the delete receipt chain' },
                childProjectRef: { type: 'string', pattern: '^[a-z0-9]{20}$', description: 'Exact child project ref from the delete receipt chain' },
                deletionCapability: childDeletionCapabilitySchema,
            },
            required: ['accountId', 'parentProjectRef', 'branchId', 'childProjectRef', 'deletionCapability'],
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
        description: 'Disabled legacy generic branch-deletion route; exact child teardown requires the prepare, delete-child, and reconciliation capability flow',
        parameters: {
            type: 'object',
            properties: { ...projectProperties, branchIdOrRef: { type: 'string' }, ...genericProperties, body: {}, confirmation: { type: 'string' } },
            required: ['accountId', 'projectRef', 'branchIdOrRef', 'confirmation'],
        },
    },
};
//# sourceMappingURL=provider-api.js.map
