"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOperatorApiApp = createOperatorApiApp;
const node_crypto_1 = require("node:crypto");
const node_path_1 = __importDefault(require("node:path"));
const express_1 = __importDefault(require("express"));
const vercel_connect_user_1 = require("./vercel-connect-user.js");
const project_change_1 = require("./project-change.js");
const preview_focus_1 = require("./preview-focus.js");
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
    if (request.method === 'POST'
        && /^\/worker-plans\/[0-9a-f-]+\/context$/i.test(request.path))
        return 'projectos:plan';
    if (request.method === 'POST' && request.path === '/tools/plan')
        return 'projectos:plan';
    if (request.method === 'POST' && request.path === '/tools/approve')
        return 'projectos:approve';
    if (request.method === 'POST'
        && /^\/projects\/[0-9a-f-]+\/focus-preview$/i.test(request.path))
        return 'projectos:read';
    if (request.method === 'POST'
        && /^\/projects\/[0-9a-f-]+\/change$/i.test(request.path))
        return 'projectos:execute';
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
    const connectUserBroker = options.connectUserBroker ?? new vercel_connect_user_1.VercelConnectUserBroker({
        connector: "mcpmaster.vercel.app/pandoras-box",
        providerUserinfoUrl: new URL("/auth/v1/oauth/userinfo", options.supabaseUrl).toString(),
    });
    const projectChangeExecutor = options.projectChangeExecutor ?? (0, project_change_1.createProjectChangeExecutor)({
        organizationId: options.organizationId,
        supabaseUrl: options.supabaseUrl,
        publishableKey: options.supabasePublishableKey,
    });
    const focusPreviewExecutor = options.focusPreviewExecutor ?? (0, preview_focus_1.createFocusPreviewExecutor)({
        supabaseUrl: options.supabaseUrl,
        publishableKey: options.supabasePublishableKey,
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
    router.use('/connect/pandoras-box', (request, response, next) => {
        const current = actor(response);
        const requiredScope = 'projectos:read';
        if (!current || !oauthScopeAllowed(current, requiredScope)) {
            noStore(response);
            response.setHeader('WWW-Authenticate', 'Bearer error="insufficient_scope", scope="projectos:read"');
            response.status(403).json({
                ok: false,
                connected: false,
                error: {
                    code: 'OPERATOR_SCOPE_REQUIRED',
                    message: 'OAuth scope projectos:read is required for Vercel Connect.',
                },
            });
            return;
        }
        next();
    });
    router.get('/connect/pandoras-box/status', async (request, response) => {
        const current = actor(response);
        noStore(response);
        try {
            const result = await connectUserBroker.probe({
                userId: current.identity.userId,
                vercelOidcToken: request.__canonicalVercelOidcToken,
            });
            response.json({
                ok: true,
                connected: true,
                connector: connectUserBroker.connector,
                subject: { id: result.subjectId },
                provider: { emailVerified: result.emailVerified === true },
            });
        }
        catch (error) {
            const known = error instanceof vercel_connect_user_1.VercelConnectUserError;
            const status = known && Number.isInteger(error.status) ? error.status : 503;
            response.status(status).json({
                ok: false,
                connected: false,
                error: {
                    code: known ? error.code : 'VERCEL_CONNECT_UNAVAILABLE',
                    message: known
                        ? error.message
                        : 'Pandora could not verify the Vercel Connect user token.',
                },
                ...(status === 409
                    ? { authorizationPath: '/api/operator/connect/pandoras-box/authorize' }
                    : {}),
            });
        }
    });
    router.post('/connect/pandoras-box/authorize', async (request, response) => {
        const current = actor(response);
        noStore(response);
        if (request.body && typeof request.body === 'object' && Object.keys(request.body).length > 0) {
            response.status(400).json({
                ok: false,
                error: {
                    code: 'VERCEL_CONNECT_AUTHORIZATION_BODY_NOT_ALLOWED',
                    message: 'Vercel Connect authorization is derived from the authenticated Pandora user.',
                },
            });
            return;
        }
        try {
            const requestOrigin = request.header('origin');
            let returnOrigin = options.allowedOrigins[0];
            if (requestOrigin) {
                const parsedOrigin = new URL(requestOrigin).origin;
                if (options.allowedOrigins.includes(parsedOrigin))
                    returnOrigin = parsedOrigin;
            }
            const authorization = await connectUserBroker.startAuthorization({
                userId: current.identity.userId,
                vercelOidcToken: request.__canonicalVercelOidcToken,
                returnUrl: new URL('/?connect=pandoras-box', returnOrigin).toString(),
            });
            response.json({
                ok: true,
                connector: connectUserBroker.connector,
                authorizationUrl: authorization.url,
            });
        }
        catch (error) {
            const known = error instanceof vercel_connect_user_1.VercelConnectUserError;
            const status = known && Number.isInteger(error.status) ? error.status : 503;
            response.status(status).json({
                ok: false,
                error: {
                    code: known ? error.code : 'VERCEL_CONNECT_AUTHORIZATION_UNAVAILABLE',
                    message: known
                        ? error.message
                        : 'Pandora could not start Vercel Connect authorization.',
                },
            });
        }
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
            && (request.path === '/tools/execute'
                || /^\/projects\/[0-9a-f-]+\/(?:change|focus-preview)$/i.test(request.path))
            && !EXECUTOR_ROLES.has(current.membership.role)) {
            noStore(response);
            response.status(403).json({
                ok: false,
                error: {
                    code: 'EXECUTOR_ROLE_REQUIRED',
                    message: 'Only an owner or admin may execute this operation.',
                },
            });
            return;
        }
        request.headers.authorization = `Bearer ${internalAdminToken}`;
        delete request.headers.origin;
        next();
    });
    router.post('/projects/:projectId/focus-preview', async (request, response) => {
        noStore(response);
        const current = actor(response);
        try {
            const result = await focusPreviewExecutor({
                actor: current,
                projectId: request.params.projectId,
                body: request.body,
            });
            response.json(result);
        }
        catch (error) {
            const status = Number.isInteger(error?.status) && error.status >= 400 && error.status <= 599
                ? error.status
                : 503;
            response.status(status).json({
                ok: false,
                error: {
                    code: typeof error?.code === 'string' ? error.code : 'FOCUS_PREVIEW_UNAVAILABLE',
                    message: error instanceof Error
                        ? error.message
                        : 'Pandora could not prepare object focus right now.',
                },
            });
        }
    });
    router.post('/projects/:projectId/change', async (request, response) => {
        noStore(response);
        const current = actor(response);
        try {
            const result = await projectChangeExecutor({
                actor: current,
                projectId: request.params.projectId,
                body: request.body,
            });
            const status = result?.httpStatus === 200 ? 200 : 202;
            const body = { ...result };
            delete body.httpStatus;
            response.status(status).json(body);
        }
        catch (error) {
            const status = Number.isInteger(error?.status) && error.status >= 400 && error.status <= 599
                ? error.status
                : 503;
            response.status(status).json({
                ok: false,
                state: status >= 500 ? 'waiting' : 'blocked',
                error: {
                    code: typeof error?.code === 'string' ? error.code : 'PROJECT_CHANGE_UNAVAILABLE',
                    message: error instanceof Error
                        ? error.message
                        : 'Pandora could not prepare that project change.',
                },
            });
        }
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
