"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GitHubControlResolver = exports.GitHubControlResolverError = void 0;
const zod_1 = require("zod");
const DEFAULT_CONTROL_URL = 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control';
const DEFAULT_TIMEOUT_MS = 10000;
const DEFAULT_MAX_RESPONSE_BYTES = 1000000;
const GitHubAccountSchema = zod_1.z.object({
    id: zod_1.z.string().regex(/^[a-z][a-z0-9_-]{1,63}$/),
    label: zod_1.z.string().min(1).max(160),
    authMode: zod_1.z.enum(['pat', 'oauth', 'github_app']).default('pat'),
    token: zod_1.z.string().min(1),
    allowMutations: zod_1.z.boolean().default(false),
    baseUrl: zod_1.z.literal('https://api.github.com').default('https://api.github.com'),
    login: zod_1.z.string().min(1).optional(),
    allowedRepositories: zod_1.z.array(zod_1.z.string().regex(/^[^/\s]+\/[^/\s]+$/)).default([]),
    grantedScopes: zod_1.z.array(zod_1.z.string().min(1)).default([]),
});
const CatalogResponseSchema = zod_1.z.object({
    ok: zod_1.z.literal(true),
    accounts: zod_1.z.array(GitHubAccountSchema).min(1),
});
class GitHubControlResolverError extends Error {
    constructor(message, status) {
        super(message);
        this.name = 'GitHubControlResolverError';
        this.status = status;
    }
}
exports.GitHubControlResolverError = GitHubControlResolverError;
function validatedEndpoint(raw) {
    const endpoint = new URL(raw);
    if (endpoint.protocol !== 'https:'
        || endpoint.hostname !== 'jcyqixttuebxqqfkjonq.supabase.co'
        || endpoint.pathname !== '/functions/v1/mcpmaster-supabase-control'
        || endpoint.username
        || endpoint.password
        || endpoint.search
        || endpoint.hash) {
        throw new GitHubControlResolverError('GitHub control endpoint is not trusted');
    }
    return endpoint.toString();
}
class GitHubControlResolver {
    constructor(options = {}) {
        this.endpoint = validatedEndpoint(options.endpoint || DEFAULT_CONTROL_URL);
        this.timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
        this.maxResponseBytes = options.maxResponseBytes || DEFAULT_MAX_RESPONSE_BYTES;
        this.fetchFn = options.fetchFn || globalThis.fetch;
    }
    async resolve(vercelOidcToken, requestedAccountId) {
        const token = vercelOidcToken?.trim();
        if (!token || token.length < 20) {
            throw new GitHubControlResolverError('Vercel OIDC runtime token is required');
        }
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
        try {
            const response = await this.fetchFn(this.endpoint, {
                method: 'POST',
                headers: {
                    authorization: `Bearer ${token}`,
                    'content-type': 'application/json',
                    accept: 'application/json',
                },
                body: JSON.stringify({ action: 'github_catalog' }),
                signal: controller.signal,
                redirect: 'error',
            });
            const declaredLength = Number(response.headers?.get('content-length') || '0');
            if (Number.isFinite(declaredLength) && declaredLength > this.maxResponseBytes) {
                throw new GitHubControlResolverError('GitHub control response is too large');
            }
            const body = await response.text();
            if (Buffer.byteLength(body, 'utf8') > this.maxResponseBytes) {
                throw new GitHubControlResolverError('GitHub control response is too large');
            }
            if (!response.ok) {
                throw new GitHubControlResolverError(`GitHub control request failed with status ${response.status}`, response.status);
            }
            let parsed;
            try {
                parsed = JSON.parse(body);
            }
            catch {
                throw new GitHubControlResolverError('GitHub control returned invalid JSON');
            }
            const catalog = CatalogResponseSchema.parse(parsed);
            const accountId = requestedAccountId?.trim() || process.env.MCPMASTER_GITHUB_ACCOUNT_ID?.trim();
            const selected = accountId
                ? catalog.accounts.find((account) => account.id === accountId)
                : catalog.accounts.length === 1
                    ? catalog.accounts[0]
                    : undefined;
            if (!selected) {
                throw new GitHubControlResolverError(accountId
                    ? `GitHub account ${accountId} is not available`
                    : 'Multiple GitHub accounts are available; MCPMASTER_GITHUB_ACCOUNT_ID is required');
            }
            return selected;
        }
        catch (error) {
            if (error instanceof GitHubControlResolverError)
                throw error;
            if (error instanceof zod_1.z.ZodError) {
                throw new GitHubControlResolverError('GitHub control returned an invalid account catalog');
            }
            if (error instanceof Error && error.name === 'AbortError') {
                throw new GitHubControlResolverError('GitHub control request timed out');
            }
            throw new GitHubControlResolverError('GitHub control request failed');
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
exports.GitHubControlResolver = GitHubControlResolver;
//# sourceMappingURL=github-control-resolver.js.map