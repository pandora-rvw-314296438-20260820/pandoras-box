"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOperatorApiApp = createOperatorApiApp;
const node_crypto_1 = require("node:crypto");
const node_path_1 = __importDefault(require("node:path"));
const express_1 = __importDefault(require("express"));
const OPERATOR_ROLES = new Set(['owner', 'admin', 'operator']);
const APPROVER_ROLES = new Set(['owner', 'admin']);
const EXECUTOR_ROLES = new Set(['owner', 'admin']);
const OPERATOR_RATE_WINDOW_MS = 60000;
const MAX_OPERATOR_RATE_BUCKETS = 10000;
function defaultRuntimeFactory(config) {
    const modulePath = process.env.MCPMASTER_RUNTIME_MODULE
        ?? node_path_1.default.resolve(process.cwd(), 'dist/http-app.js');
    const runtimeModule = require(modulePath);
    if (typeof runtimeModule.createHttpApp !== 'function') {
        throw new Error('The embedded MCPMaster runtime is unavailable');
    }
    return runtimeModule.createHttpApp(config);
}
function processLocalCredential() {
    return (0, node_crypto_1.randomBytes)(48).toString('base64url');
}
function actor(response) {
    return response.locals.operatorActor;
}
function noStore(response) {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
}
function operatorOriginAllowed(request, allowedOrigins) {
    const origin = request.header('origin');
    if (!origin)
        return true;
    try {
        const parsed = new URL(origin);
        const requestHost = request.header('host')?.toLowerCase();
        const sameHost = Boolean(requestHost && parsed.host.toLowerCase() === requestHost);
        const localHttp = parsed.protocol === 'http:'
            && ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname);
        const secureSameOrigin = sameHost && (parsed.protocol === 'https:' || localHttp);
        return secureSameOrigin || allowedOrigins.includes(parsed.origin);
    }
    catch {
        return false;
    }
}
function createOperatorRateLimiter(limit) {
    const buckets = new Map();
    const safeLimit = Math.max(5, Math.min(limit, 300));
    return (request, response, next) => {
        const now = Date.now();
        const key = request.ip || request.socket.remoteAddress || 'unknown';
        const existing = buckets.get(key);
        const state = !existing || existing.resetAt <= now
            ? { count: 0, resetAt: now + OPERATOR_RATE_WINDOW_MS }
            : existing;
        state.count += 1;
        buckets.set(key, state);
        response.setHeader('RateLimit-Limit', safeLimit.toString());
        response.setHeader('RateLimit-Remaining', Math.max(0, safeLimit - state.count).toString());
        response.setHeader('RateLimit-Reset', Math.ceil(state.resetAt / 1000).toString());
        if (state.count > safeLimit) {
            noStore(response);
            response.setHeader('Retry-After', Math.max(1, Math.ceil((state.resetAt - now) / 1000)).toString());
            response.status(429).json({
                ok: false,
                error: {
                    code: 'OPERATOR_RATE_LIMITED',
                    message: 'Too many operator authentication requests. Try again after the current window resets.',
                },
            });
            return;
        }
        if (buckets.size > MAX_OPERATOR_RATE_BUCKETS) {
            for (const [bucketKey, bucket] of buckets.entries()) {
                if (bucket.resetAt <= now)
                    buckets.delete(bucketKey);
            }
        }
        next();
    };
}
function clearPrivilegedCallerHeaders(request) {
    delete request.headers['x-approval-token'];
    delete request.headers['x-approver-id'];
    delete request.headers['x-vercel-oidc-token'];
    delete request.headers['x-vercel-sc-headers'];
}
function requiredOperatorScope(request) {
    if (request.method === 'POST' && request.path === '/project-memory-context')
        return 'projectos:plan';
    if (request.method === 'POST'
        && /^\/worker-plans\/[0-9a-f-]+\/context$/i.test(request.path))
        return 'projectos:plan';
    if (request.method === 'POST' && request.path === '/tools/plan')
        return 'projectos:plan';
    if (request.method === 'POST' && request.path === '/tools/approve')
        return 'projectos:approve';
    if (request.method === 'POST'
        && (request.path === '/tools/execute' || request.path === '/tools'))
        return 'projectos:execute';
    if (request.method === 'GET')
        return 'projectos:read';
    return undefined;
}
function oauthScopeAllowed(current, requiredScope) {
    if (!current.identity.scopeClaimsPresent)
        return true;
    const granted = new Set(Array.isArray(current.identity.scopes) ? current.identity.scopes : []);
    return Boolean(requiredScope
        && granted.has('openid')
        && (granted.has(requiredScope) || granted.has('projectos:*')));
}
function operatorAuthentication(options) {
    return async (request, response, next) => {
        if (!operatorOriginAllowed(request, options.allowedOrigins)) {
            noStore(response);
            response.status(403).json({
                ok: false,
                error: {
                    code: 'OPERATOR_ORIGIN_FORBIDDEN',
                    message: 'The operator API accepts only the same origin or an explicitly allowed origin.',
                },
            });
            return;
        }
        const authorization = request.header('authorization');
        clearPrivilegedCallerHeaders(request);
        try {
            const identity = await options.authenticator.authenticate(authorization);
            const membership = await options.membershipResolver.resolve(options.organizationId, identity.userId, identity.accessToken);
            if (!membership || !OPERATOR_ROLES.has(membership.role)) {
                noStore(response);
                response.status(403).json({
                    ok: false,
                    error: {
                        code: 'OPERATOR_MEMBERSHIP_REQUIRED',
                        message: 'An active owner, admin, or operator membership is required.',
                    },
                });
                return;
            }
            if (membership.organizationId !== options.organizationId || membership.userId !== identity.userId) {
                noStore(response);
                response.status(403).json({
                    ok: false,
                    error: {
                        code: 'OPERATOR_MEMBERSHIP_REQUIRED',
                        message: 'The active membership must match the authenticated user and organization.',
                    },
                });
                return;
            }
            response.locals.operatorActor = { identity, membership };
            next();
        }
        catch (error) {
            const status = typeof error === 'object' && error !== null && 'status' in error
                && (error.status === 401 || error.status === 503)
                ? error.status
                : 503;
            noStore(response);
            if (status === 401)
                response.setHeader('WWW-Authenticate', 'Bearer');
            response.status(status).json({
                ok: false,
                error: {
                    code: status === 401 ? 'OPERATOR_UNAUTHORIZED' : 'OPERATOR_AUTH_UNAVAILABLE',
                    message: error instanceof Error ? error.message : 'Operator authentication failed.',
                },
            });
        }
    };
}
function createOperatorApiApp(options) {
    const router = express_1.default.Router();
    const runtimeFactory = options.runtimeFactory ?? defaultRuntimeFactory;
    const internalAdminToken = processLocalCredential();
    const internalApprovalToken = processLocalCredential();
    const embeddedRuntime = runtimeFactory({
        port: 3000,
        adminToken: internalAdminToken,
        approvalToken: internalApprovalToken,
        allowedOrigins: options.allowedOrigins.join(','),
        rateLimitRequests: options.requestsPerMinute,
        rateLimitWindowMs: 60000,
    });
    router.use(createOperatorRateLimiter(options.requestsPerMinute));
    router.get('/auth/config', (request, response) => {
        if (!operatorOriginAllowed(request, options.allowedOrigins)) {
            noStore(response);
            response.status(403).json({
                ok: false,
                error: {
                    code: 'OPERATOR_ORIGIN_FORBIDDEN',
                    message: 'The operator API accepts only the same origin or an explicitly allowed origin.',
                },
            });
            return;
        }
        noStore(response);
        response.json({
            supabaseUrl: options.supabaseUrl,
            supabasePublishableKey: options.supabasePublishableKey,
            organizationId: options.organizationId,
            sessionStorage: 'memory-only',
            mfaRequiredForApproval: false,
        });
    });
    router.use(operatorAuthentication(options));
    router.get('/session', (_request, response) => {
        const current = actor(response);
        noStore(response);
        response.json({
            ok: true,
            user: {
                id: current?.identity.userId,
                email: current?.identity.email,
                role: current?.membership.role,
            },
        });
    });
    router.use((request, response, next) => {
        const current = actor(response);
        if (!current) {
            noStore(response);
            response.status(401).json({
                ok: false,
                error: { code: 'OPERATOR_UNAUTHORIZED', message: 'Operator session is unavailable.' },
            });
            return;
        }
        const requiredScope = requiredOperatorScope(request);
        if (!oauthScopeAllowed(current, requiredScope)) {
            noStore(response);
            response.setHeader('WWW-Authenticate', `Bearer error="insufficient_scope", scope="${requiredScope || 'projectos'}"`);
            response.status(403).json({
                ok: false,
                error: {
                    code: 'OPERATOR_SCOPE_REQUIRED',
                    message: `OAuth scope ${requiredScope || 'projectos'} is required for this operator action.`,
                },
            });
            return;
        }
        if (request.method === 'POST' && request.path === '/tools/approve') {
            if (!APPROVER_ROLES.has(current.membership.role)) {
                noStore(response);
                response.status(403).json({
                    ok: false,
                    error: {
                        code: 'APPROVER_ROLE_REQUIRED',
                        message: 'Plan approval requires a ProjectOS owner or admin session.',
                    },
                });
                return;
            }
            request.headers['x-approval-token'] = internalApprovalToken;
            request.headers['x-approver-id'] = `supabase:${current.identity.userId}`;
        }
        if (request.method === 'POST'
            && request.path === '/tools/execute'
            && !EXECUTOR_ROLES.has(current.membership.role)) {
            noStore(response);
            response.status(403).json({
                ok: false,
                error: {
                    code: 'EXECUTOR_ROLE_REQUIRED',
                    message: 'Only an owner or admin may execute a provider operation.',
                },
            });
            return;
        }
        request.headers.authorization = `Bearer ${internalAdminToken}`;
        delete request.headers.origin;
        next();
    });
    router.get('/status', async (request, response) => {
        noStore(response);
        try {
            const pack = await options.statusProvider?.refresh?.({
                vercelOidcToken: request.__canonicalVercelOidcToken,
            });
            if (!pack || typeof pack !== 'object' || pack.schemaVersion !== '1.0.0') {
                response.status(503).json({
                    schemaVersion: '1.0.0',
                    authoritative: false,
                    status: 'unavailable',
                    blockers: ['canonical-status-provider-unavailable'],
                    error: {
                        code: 'CANONICAL_STATUS_UNAVAILABLE',
                        message: 'The canonical status providers did not return a valid pack.',
                    },
                });
                return;
            }
            response.status(pack.authoritative === true ? 200 : 503).json(pack);
        }
        catch {
            response.status(503).json({
                schemaVersion: '1.0.0',
                authoritative: false,
                status: 'unavailable',
                blockers: ['canonical-status-provider-unavailable'],
                error: {
                    code: 'CANONICAL_STATUS_UNAVAILABLE',
                    message: 'The canonical status pack could not be refreshed.',
                },
            });
        }
    });
    router.post('/project-memory-context', async (request, response) => {
        noStore(response);
        const current = actor(response);
        const body = request.body && typeof request.body === 'object' && !Array.isArray(request.body)
            ? request.body
            : {};
        const keys = Object.keys(body).sort();
        if (!current || keys.length !== 2 || keys[0] !== 'decisionType' || keys[1] !== 'intentId'
            || typeof body.intentId !== 'string'
            || !['project_spec', 'build', 'repair'].includes(body.decisionType)) {
            response.status(400).json({
                ok: false,
                error: { code: 'MEMORY_CONTEXT_REQUEST_INVALID', message: 'Exact intentId and decisionType are required.' },
            });
            return;
        }
        try {
            const context = await options.projectMemoryContextProvider?.prepareIntent?.({
                intentId: body.intentId,
                decisionType: body.decisionType,
                accessToken: current.identity.accessToken,
                vercelOidcToken: request.__canonicalVercelOidcToken,
            });
            if (!context || context.sourceIntentId !== body.intentId || context.decisionType !== body.decisionType) {
                throw new Error('MEMORY_CONTEXT_PROVIDER_UNAVAILABLE');
            }
            response.json({ ok: true, context });
        }
        catch (error) {
            const candidate = typeof error === 'object' && error !== null && 'status' in error
                ? Number(error.status)
                : 503;
            const status = [400, 401, 403, 404].includes(candidate) ? candidate : 503;
            response.status(status).json({
                ok: false,
                error: {
                    code: error instanceof Error ? error.message : 'MEMORY_CONTEXT_PROVIDER_UNAVAILABLE',
                    message: status === 503
                        ? 'Fresh project-scoped Pandora Memory context could not be prepared.'
                        : 'The requested project Memory context is not available to this session.',
                },
            });
        }
    });
    router.post('/worker-plans/:planId/context', async (request, response) => {
        noStore(response);
        const current = actor(response);
        if (!current || !APPROVER_ROLES.has(current.membership.role)) {
            response.status(403).json({
                ok: false,
                error: {
                    code: 'OWNER_ROLE_REQUIRED',
                    message: 'Only an owner or admin may prepare an exact worker plan for approval.',
                },
            });
            return;
        }
        if (request.body && typeof request.body === 'object'
            && Object.keys(request.body).length > 0) {
            response.status(400).json({
                ok: false,
                error: {
                    code: 'WORKER_CONTEXT_BODY_NOT_ALLOWED',
                    message: 'The plan identity is read from the durable ledger, not request fields.',
                },
            });
            return;
        }
        try {
            const context = await options.workerContextProvider?.attachExactPlan?.(request.params.planId);
            if (!context || context.planId !== request.params.planId) {
                throw new Error('WORKER_CONTEXT_PROVIDER_UNAVAILABLE');
            }
            response.json({ ok: true, context });
        }
        catch (error) {
            const code = error instanceof Error ? error.message : 'WORKER_CONTEXT_UNAVAILABLE';
            const notFound = code === 'WORKER_PLAN_NOT_FOUND';
            const invalid = code === 'WORKER_PLAN_ID_INVALID' || code === 'WORKER_PLAN_IDENTITY_MISMATCH';
            response.status(notFound ? 404 : invalid ? 409 : 503).json({
                ok: false,
                error: {
                    code: notFound ? code : invalid ? code : 'WORKER_CONTEXT_UNAVAILABLE',
                    message: notFound
                        ? 'That exact worker plan was not found.'
                        : invalid
                            ? 'The worker plan identity did not match the governed contract.'
                            : 'Fresh Pandora Memory context could not be attached to this plan.',
                },
            });
        }
    });
    router.use(embeddedRuntime);
    return router;
}
