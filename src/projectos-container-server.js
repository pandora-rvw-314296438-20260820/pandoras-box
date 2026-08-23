"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveCanonicalMemoryOidcToken = resolveCanonicalMemoryOidcToken;
exports.createCanonicalMemoryHealthProbe = createCanonicalMemoryHealthProbe;
exports.createProjectOsContainerApp = createProjectOsContainerApp;
exports.startProjectOsContainerServer = startProjectOsContainerServer;
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
const express_1 = __importDefault(require("express"));
const http_server_js_1 = require("./http-server.js");
const operator_public_config_js_1 = require("./operator-public-config.js");
const memory_js_1 = require("./tools/memory.js");
const canonical_status_provider_js_1 = require("./projectos/canonical-status-provider.js");
const worker_plan_context_provider_js_1 = require("./projectos/worker-plan-context-provider.js");
const CANONICAL_MEMORY_ORIGIN = 'https://pandorasbox-memory.vercel.app';
const MEMORY_HEALTH_TTL_MS = 5 * 60 * 1000;
const MEMORY_DEGRADED_TTL_MS = 30 * 1000;
function runtimePort(environment) {
    const value = environment.PORT?.trim() || '3000';
    const port = Number.parseInt(value, 10);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
        throw new Error('PORT must be an integer between 1 and 65535');
    }
    return port;
}
function resolveCanonicalMemoryOidcToken(requestHeaderValue, environment = process.env) {
    const requestToken = requestHeaderValue?.trim();
    if (requestToken)
        return requestToken;
    const environmentToken = environment.VERCEL_OIDC_TOKEN?.trim();
    return environmentToken || undefined;
}
function createCanonicalMemoryHealthProbe(environment = process.env, fetchFn = globalThis.fetch, now = Date.now) {
    let cached;
    let inFlight;
    return async (requestOidcToken) => {
        const current = now();
        if (cached && cached.expiresAt > current)
            return cached.value;
        if (inFlight)
            return inFlight;
        inFlight = (async () => {
            const checkedAt = new Date(now()).toISOString();
            const oidcToken = resolveCanonicalMemoryOidcToken(requestOidcToken, environment);
            if (!oidcToken) {
                return {
                    status: 'degraded',
                    service: 'pandoras-box-memory-bridge',
                    authentication: 'vercel_oidc',
                    namespace: 'real_life',
                    origin: CANONICAL_MEMORY_ORIGIN,
                    searchVerified: false,
                    checkedAt,
                    reason: 'workload_identity_unavailable',
                };
            }
            try {
                const memory = new memory_js_1.PandoraMemoryMCPServer({
                    baseUrl: CANONICAL_MEMORY_ORIGIN,
                    oidcToken,
                    allowedNamespaces: ['real_life'],
                    grantedScopes: ['memory:health', 'memory:read'],
                    timeoutMs: 8000,
                    maxResponseBytes: 500000,
                }, fetchFn);
                const health = await memory.health();
                const search = await memory.search({
                    namespace: 'real_life',
                    query: 'Pandoras-Box canonical runtime connectivity proof',
                    currentTask: 'Verify the canonical container workload identity and bounded Memory retrieval',
                    maxItems: 1,
                    includeSemantic: true,
                    includeProfiles: true,
                    includeRecent: true,
                    includeOpenLoops: true,
                });
                if (health.ok !== true
                    || health.status !== 'projectos-connected'
                    || health.authentication !== 'vercel_oidc'
                    || search.ok !== true
                    || search.namespace !== 'real_life') {
                    throw new Error('unexpected_memory_contract');
                }
                return {
                    status: 'healthy',
                    service: 'pandoras-box-memory-bridge',
                    authentication: 'vercel_oidc',
                    namespace: 'real_life',
                    origin: CANONICAL_MEMORY_ORIGIN,
                    memoryStatus: health.status,
                    searchVerified: true,
                    warningCount: search.warnings.length,
                    checkedAt,
                };
            }
            catch (error) {
                console.error('canonical_memory_health_failed', {
                    errorType: error instanceof Error ? error.name : 'unknown',
                    status: typeof error === 'object' && error && 'status' in error
                        ? error.status
                        : undefined,
                });
                return {
                    status: 'degraded',
                    service: 'pandoras-box-memory-bridge',
                    authentication: 'vercel_oidc',
                    namespace: 'real_life',
                    origin: CANONICAL_MEMORY_ORIGIN,
                    searchVerified: false,
                    checkedAt,
                    reason: 'memory_unavailable',
                };
            }
        })();
        try {
            const value = await inFlight;
            cached = {
                expiresAt: now() + (value.status === 'healthy'
                    ? MEMORY_HEALTH_TTL_MS
                    : MEMORY_DEGRADED_TTL_MS),
                value,
            };
            return value;
        }
        finally {
            inFlight = undefined;
        }
    };
}
function createContainerOperatorRuntime(environment) {
    const config = (0, operator_public_config_js_1.loadOperatorPublicConfig)(environment);
    const { SupabaseBearerAuthenticator, } = require('../apps/meta-business-mcp/dist/auth/supabase-bearer.js');
    const { SupabaseOrganizationMembershipResolver, } = require('../apps/meta-business-mcp/dist/auth/membership.js');
    const { createOperatorApiApp, } = require('../apps/meta-business-mcp/dist/operator/api.js');
    const authenticator = new SupabaseBearerAuthenticator({
        supabaseUrl: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
    });
    const membershipResolver = new SupabaseOrganizationMembershipResolver({
        supabaseUrl: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
    });
    const statusProvider = (0, canonical_status_provider_js_1.createCanonicalStatusProviderFromEnvironment)({
        env: environment,
    });
    const workerContextProvider = new worker_plan_context_provider_js_1.WorkerPlanContextProvider();
    const runtime = (0, express_1.default)();
    runtime.disable('x-powered-by');
    runtime.set('trust proxy', 1);
    runtime.use((request, _response, next) => {
        const platformOidc = environment.VERCEL === '1'
            ? request.headers?.['x-vercel-oidc-token']
            : undefined;
        Object.defineProperty(request, '__canonicalVercelOidcToken', {
            configurable: false,
            enumerable: false,
            writable: false,
            value: typeof platformOidc === 'string' ? platformOidc : undefined,
        });
        next();
    });
    runtime.use(express_1.default.json({ limit: '256kb' }));
    runtime.use(createOperatorApiApp({
        authenticator,
        membershipResolver,
        organizationId: config.organizationId,
        supabaseUrl: config.supabaseUrl,
        supabasePublishableKey: config.supabasePublishableKey,
        allowedOrigins: config.allowedOrigins,
        requestsPerMinute: config.requestsPerMinute,
        statusProvider,
        workerContextProvider,
        runtimeFactory: (embeddedConfig) => (0, http_server_js_1.createHttpApp)(embeddedConfig),
    }));
    return runtime;
}
function createProjectOsContainerApp(environment = process.env) {
    const app = (0, express_1.default)();
    const publicDirectory = node_path_1.default.resolve(process.cwd(), 'public');
    const controlTowerDirectory = node_path_1.default.resolve(process.cwd(), 'apps/control-tower');
    const publicIndex = node_path_1.default.join(publicDirectory, 'index.html');
    const controlTowerIndex = node_path_1.default.join(controlTowerDirectory, 'index.html');
    const consentPage = node_path_1.default.join(publicDirectory, 'oauth', 'consent.html');
    const consentScript = node_path_1.default.join(publicDirectory, 'oauth', 'consent.browser.js.txt');
    const shellIndex = (0, node_fs_1.existsSync)(publicIndex) ? publicIndex : controlTowerIndex;
    const memoryHealth = createCanonicalMemoryHealthProbe(environment);
    app.disable('x-powered-by');
    app.set('trust proxy', 1);
    app.get('/health', (_request, response) => {
        response.setHeader('Cache-Control', 'no-store');
        response.json({
            status: 'healthy',
            service: 'mcpmaster-projectos-container',
            mode: 'projectos',
            timestamp: new Date().toISOString(),
        });
    });
    app.get('/health/memory', async (request, response, next) => {
        try {
            const snapshot = await memoryHealth(request.get('x-vercel-oidc-token'));
            response.setHeader('Cache-Control', 'no-store');
            response.status(snapshot.status === 'healthy' ? 200 : 503).json(snapshot);
        }
        catch (error) {
            next(error);
        }
    });
    app.get('/oauth/consent', (_request, response, next) => {
        response.setHeader('Cache-Control', 'no-store');
        response.setHeader('X-Content-Type-Options', 'nosniff');
        response.sendFile(consentPage, (error) => {
            if (error)
                next(error);
        });
    });
    app.get('/oauth/consent.js', (_request, response, next) => {
        response.setHeader('Cache-Control', 'public, max-age=300, must-revalidate');
        response.setHeader('Content-Type', 'text/javascript; charset=utf-8');
        response.setHeader('X-Content-Type-Options', 'nosniff');
        response.sendFile(consentScript, (error) => {
            if (error)
                next(error);
        });
    });
    app.use('/api/operator', createContainerOperatorRuntime(environment));
    app.use('/api', (0, http_server_js_1.createHttpApp)());
    app.get([
        '/control-tower/projectos-status.json',
        '/control-tower/release.json',
    ], (_request, response) => {
        response.setHeader('Cache-Control', 'no-store');
        response.status(410).json({
            ok: false,
            error: {
                code: 'HISTORICAL_STATUS_SURFACE_GONE',
                message: 'This static snapshot is historical. Use the authenticated canonical status endpoint.',
            },
            supersededBy: '/api/operator/status',
        });
    });
    app.use('/control-tower', express_1.default.static(controlTowerDirectory, {
        fallthrough: true,
        index: false,
        maxAge: '1h',
        setHeaders(response, filePath) {
            response.setHeader('X-Content-Type-Options', 'nosniff');
            if (filePath.endsWith('.html')) {
                response.setHeader('Cache-Control', 'no-store');
            }
        },
    }));
    app.use(express_1.default.static(publicDirectory, {
        fallthrough: true,
        index: false,
        maxAge: '1h',
    }));
    app.use((request, response, next) => {
        if (request.method !== 'GET' || !request.accepts('html')) {
            next();
            return;
        }
        response.setHeader('Cache-Control', 'no-store');
        response.sendFile(shellIndex, (error) => {
            if (error)
                next(error);
        });
    });
    app.use((_request, response) => {
        response.status(404).json({
            ok: false,
            error: { code: 'NOT_FOUND', message: 'Route not found.' },
        });
    });
    app.use((error, _request, response, _next) => {
        console.error(error);
        response.status(500).json({
            ok: false,
            error: {
                code: 'CONTAINER_RUNTIME_ERROR',
                message: error instanceof Error ? error.message : 'Unknown container runtime error',
            },
        });
    });
    return app;
}
function startProjectOsContainerServer(environment = process.env) {
    const port = runtimePort(environment);
    const host = environment.HOST?.trim() || '0.0.0.0';
    const app = createProjectOsContainerApp(environment);
    const server = app.listen(port, host, () => {
        console.log(`ProjectOS container listening on ${host}:${port}`);
    });
    const shutdown = (signal) => {
        console.log(`Received ${signal}; shutting down ProjectOS container.`);
        server.close((error) => {
            if (error) {
                console.error('ProjectOS container shutdown failed');
                process.exitCode = 1;
            }
            process.exit();
        });
    };
    process.once('SIGTERM', () => shutdown('SIGTERM'));
    process.once('SIGINT', () => shutdown('SIGINT'));
    return server;
}
//# sourceMappingURL=projectos-container-server.js.map
