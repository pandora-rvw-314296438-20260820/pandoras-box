"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.executionPayloadHash = executionPayloadHash;
exports.destructiveCapabilityReservationDeliveryId = destructiveCapabilityReservationDeliveryId;
exports.createDestructiveCapabilityReservationIntent = createDestructiveCapabilityReservationIntent;
exports.createHttpApp = createHttpApp;
exports.startHttpServer = startHttpServer;
const crypto_1 = require("crypto");
const path_1 = __importDefault(require("path"));
const cors_1 = __importDefault(require("cors"));
const express_1 = __importDefault(require("express"));
const helmet_1 = __importDefault(require("helmet"));
const zod_1 = require("zod");
const index_js_1 = require("./tools/index.js");
const service_config_js_1 = require("./runtime/service-config.js");
const tool_policy_js_1 = require("./runtime/tool-policy.js");
const runtime_security_resolver_js_1 = require("./runtime/runtime-security-resolver.js");
const execution_ledger_client_js_1 = require("./runtime/execution-ledger-client.js");
const execution_payload_js_1 = require("./runtime/execution-payload.js");
const destructive_capability_reservation_js_1 = require("./runtime/destructive-capability-reservation.js");
const provider_execution_state_machine_js_1 = require("./runtime/provider-execution-state-machine.js");
const runtime_rate_limit_client_js_1 = require("./runtime/runtime-rate-limit-client.js");
const VERSION = '1.3.0-observability';
const MAX_AUDIT_EVENTS = 500;
const DEFAULT_PRODUCTION_ORIGIN = 'https://mcpmaster.vercel.app';
const PLAN_TTL_MS = 10 * 60 * 1000;
const runtimeConfigSchema = zod_1.z.object({
    port: zod_1.z.coerce.number().int().positive().max(65535).default(3000),
    adminToken: zod_1.z.string().min(32, 'BRIDGE_ADMIN_TOKEN must contain at least 32 characters').optional(),
    approvalToken: zod_1.z.string().min(32).optional(),
    allowedOrigins: zod_1.z.string().default(DEFAULT_PRODUCTION_ORIGIN),
    rateLimitRequests: zod_1.z.coerce.number().int().positive().default(60),
    rateLimitWindowMs: zod_1.z.coerce.number().int().positive().default(60000),
});
const executionSchema = zod_1.z.object({
    tool: zod_1.z.string().min(1),
    args: zod_1.z.record(zod_1.z.unknown()).optional().default({}),
    dryRun: zod_1.z.boolean().optional().default(false),
});
const planInputSchema = zod_1.z.object({
    tool: zod_1.z.string().min(1),
    args: zod_1.z.record(zod_1.z.unknown()).optional().default({}),
});
const planReferenceSchema = zod_1.z.object({
    planId: zod_1.z.string().uuid(),
});
const approvalSchema = zod_1.z.object({
    planId: zod_1.z.string().uuid(),
});
function loadRuntimeConfig() {
    return runtimeConfigSchema.parse({
        port: process.env.PORT,
        adminToken: process.env.BRIDGE_ADMIN_TOKEN || undefined,
        approvalToken: process.env.BRIDGE_APPROVAL_TOKEN || undefined,
        allowedOrigins: process.env.CORS_ALLOWED_ORIGINS || DEFAULT_PRODUCTION_ORIGIN,
        rateLimitRequests: process.env.RATE_LIMIT_REQUESTS,
        rateLimitWindowMs: process.env.RATE_LIMIT_WINDOW_MS,
    });
}
function commaSeparatedOrigins(value) {
    return value
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean);
}
function bearerToken(request) {
    const authorization = request.header('authorization');
    const match = authorization?.match(/^Bearer\s+(.+)$/i);
    return match?.[1]?.trim();
}
function vercelOidcToken(request) {
    const descriptor = Object.getOwnPropertyDescriptor(request, '__canonicalVercelOidcToken');
    if (descriptor
        && descriptor.enumerable === false
        && descriptor.writable === false
        && typeof descriptor.value === 'string'
        && descriptor.value.trim()) {
        return descriptor.value.trim();
    }
    return request.header('x-vercel-oidc-token') || process.env.VERCEL_OIDC_TOKEN || undefined;
}
const requestIds = new WeakMap();
function requestId(request) {
    const existing = requestIds.get(request);
    if (existing)
        return existing;
    const candidate = request.header('x-request-id');
    const resolved = candidate && zod_1.z.string().uuid().safeParse(candidate).success
        ? candidate
        : (0, crypto_1.randomUUID)();
    requestIds.set(request, resolved);
    return resolved;
}
function distributedRuntime(request) {
    return Boolean(vercelOidcToken(request)
        && (process.env.VERCEL === '1' || process.env.VERCEL_ENV === 'production'));
}
function rateLimitKeyHash(request) {
    const address = request.ip || request.socket.remoteAddress || 'unknown';
    return (0, crypto_1.createHash)('sha256').update(`http:${address}`, 'utf8').digest('hex');
}
function structuredLog(event) {
    console.info(JSON.stringify(event));
}
function createRequestTelemetry(metrics) {
    return (request, response, next) => {
        const startedAt = Date.now();
        const id = requestId(request);
        response.setHeader('X-Request-Id', id);
        response.once('finish', () => {
            const durationMs = Date.now() - startedAt;
            const statusClass = `${Math.floor(response.statusCode / 100)}xx`;
            metrics.requestsTotal += 1;
            metrics.totalDurationMs += durationMs;
            metrics.responsesByStatus[statusClass] = (metrics.responsesByStatus[statusClass] || 0) + 1;
            structuredLog({
                event: 'http_request_completed',
                requestId: id,
                method: request.method,
                path: request.path,
                statusCode: response.statusCode,
                durationMs,
                environment: process.env.VERCEL_ENV || process.env.NODE_ENV || 'local',
                region: process.env.VERCEL_REGION || process.env.AWS_REGION || 'unknown',
                commitSha: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 12),
            });
        });
        next();
    };
}
function executionPayloadHash(tool, args) {
    return (0, execution_payload_js_1.executionPayloadHash)(tool, args);
}
function destructiveCapabilityReservationDeliveryId(tool, args) {
    return (0, destructive_capability_reservation_js_1.destructiveCapabilityReservationDeliveryId)(tool, args);
}
function createDestructiveCapabilityReservationIntent(claimedPlan) {
    return (0, destructive_capability_reservation_js_1.createDestructiveCapabilityReservationIntent)(claimedPlan);
}
function assertBoundLedgerPlan(plan, planId, status) {
    if (!plan || plan.planId !== planId || plan.status !== status) {
        throw new execution_ledger_client_js_1.ExecutionLedgerError('Durable ledger returned a mismatched plan identity or state', 409);
    }
    return plan;
}
function resultSummary(result) {
    if (result === null)
        return { type: 'null' };
    if (Array.isArray(result))
        return { type: 'array', length: result.length };
    if (typeof result === 'object') {
        const keys = Object.keys(result).sort();
        return { type: 'object', keyCount: keys.length, keys: keys.slice(0, 50) };
    }
    if (typeof result === 'string')
        return { type: 'string', length: result.length };
    return { type: typeof result };
}
function boundedProviderFailure(error) {
    const failure = error?.failure;
    if (!failure || typeof failure !== 'object' || Array.isArray(failure))
        return undefined;
    try {
        const message = JSON.stringify(failure);
        if (message !== error.message || Buffer.byteLength(message, 'utf8') > 1000)
            return undefined;
        return {
            status: Number.isInteger(error.status) && error.status >= 400 && error.status <= 599
                ? error.status
                : 503,
            code: typeof failure.safeErrorCode === 'string'
                ? failure.safeErrorCode
                : 'provider_execution_failed',
            message,
        };
    }
    catch {
        return undefined;
    }
}
async function resolveRuntimeSecurity(config, request, resolver) {
    let remote;
    const oidcToken = vercelOidcToken(request);
    if (oidcToken)
        remote = await resolver.resolve(oidcToken);
    return {
        adminToken: config.adminToken,
        approvalToken: config.approvalToken,
        adminTokenHash: remote?.adminTokenHash,
        approvalTokenHash: remote?.approvalTokenHash,
        allowedOrigins: remote?.allowedOrigins || commaSeparatedOrigins(config.allowedOrigins),
    };
}
function adminConfigured(security) {
    return Boolean(security.adminToken || security.adminTokenHash);
}
function approvalConfigured(security) {
    return Boolean(security.approvalToken || security.approvalTokenHash);
}
function adminTokenValid(provided, security) {
    return (0, tool_policy_js_1.secureTokenMatches)(provided, security.adminToken)
        || (0, tool_policy_js_1.secureTokenHashMatches)(provided, security.adminTokenHash);
}
function approvalTokenValid(provided, security) {
    return (0, tool_policy_js_1.secureTokenMatches)(provided, security.approvalToken)
        || (0, tool_policy_js_1.secureTokenHashMatches)(provided, security.approvalTokenHash);
}
function createAdminGuard(config, resolver) {
    return async (request, response, next) => {
        let security;
        try {
            security = await resolveRuntimeSecurity(config, request, resolver);
        }
        catch {
            response.status(503).json({
                ok: false,
                error: {
                    code: 'ADMIN_AUTH_NOT_CONFIGURED',
                    message: 'Protected routes are disabled until runtime authentication is available.',
                },
            });
            return;
        }
        if (!adminConfigured(security)) {
            response.status(503).json({
                ok: false,
                error: {
                    code: 'ADMIN_AUTH_NOT_CONFIGURED',
                    message: 'Protected routes are disabled until runtime authentication is available.',
                },
            });
            return;
        }
        if (!adminTokenValid(bearerToken(request), security)) {
            response.status(401).json({
                ok: false,
                error: { code: 'UNAUTHORIZED', message: 'A valid bearer token is required.' },
            });
            return;
        }
        response.locals.runtimeSecurity = security;
        next();
    };
}
function createRateLimiter(config, provider, metrics) {
    const clients = new Map();
    return async (request, response, next) => {
        const oidcToken = vercelOidcToken(request);
        let result;
        if (oidcToken && distributedRuntime(request)) {
            try {
                result = await provider.consume(oidcToken, {
                    keyHash: rateLimitKeyHash(request),
                    limit: config.rateLimitRequests,
                    windowSeconds: Math.max(1, Math.ceil(config.rateLimitWindowMs / 1000)),
                });
            }
            catch (error) {
                metrics.rateLimitControlErrors += 1;
                structuredLog({
                    event: 'runtime_rate_limit_control_unavailable',
                    requestId: requestId(request),
                    errorType: error instanceof Error ? error.name : 'unknown',
                });
                response.status(503).json({
                    ok: false,
                    error: {
                        code: 'RATE_LIMIT_CONTROL_UNAVAILABLE',
                        message: 'Protected routes are unavailable until distributed rate limiting recovers.',
                    },
                });
                return;
            }
        }
        else {
            const now = Date.now();
            const key = rateLimitKeyHash(request);
            const existing = clients.get(key);
            const state = !existing || existing.resetAt <= now
                ? { count: 0, resetAt: now + config.rateLimitWindowMs }
                : existing;
            state.count += 1;
            clients.set(key, state);
            result = {
                allowed: state.count <= config.rateLimitRequests,
                limit: config.rateLimitRequests,
                remaining: Math.max(0, config.rateLimitRequests - state.count),
                count: state.count,
                resetAt: new Date(state.resetAt).toISOString(),
                windowSeconds: Math.max(1, Math.ceil(config.rateLimitWindowMs / 1000)),
            };
            if (clients.size > 10000) {
                for (const [clientKey, clientState] of clients.entries()) {
                    if (clientState.resetAt <= now)
                        clients.delete(clientKey);
                }
            }
        }
        response.setHeader('RateLimit-Limit', result.limit.toString());
        response.setHeader('RateLimit-Remaining', result.remaining.toString());
        response.setHeader('RateLimit-Reset', Math.ceil(new Date(result.resetAt).getTime() / 1000).toString());
        if (!result.allowed) {
            metrics.rateLimitDenied += 1;
            structuredLog({
                event: 'runtime_rate_limit_denied',
                requestId: requestId(request),
                count: result.count,
                limit: result.limit,
                resetAt: result.resetAt,
            });
            response.status(429).json({
                ok: false,
                error: { code: 'RATE_LIMITED', message: 'Too many requests. Try again later.' },
            });
            return;
        }
        next();
    };
}
function createCorsOptions(config) {
    const allowedOrigins = commaSeparatedOrigins(config.allowedOrigins);
    return {
        methods: ['GET', 'POST', 'OPTIONS'],
        allowedHeaders: [
            'Authorization',
            'Content-Type',
            'X-Approval-Token',
            'X-Approver-Id',
            'X-Request-Id',
        ],
        origin(origin, callback) {
            if (!origin || allowedOrigins.includes(origin)) {
                callback(null, true);
                return;
            }
            callback(new Error('Origin is not allowed'));
        },
    };
}
function publicToolMetadata() {
    return Object.entries(index_js_1.toolRegistry).map(([name, metadata]) => ({
        name,
        service: metadata.handler,
        description: metadata.description,
        risk: (0, tool_policy_js_1.classifyToolRisk)(name),
        approvalRequired: (0, tool_policy_js_1.requiresApproval)(name),
        provider: metadata.manifest.provider,
        scope: metadata.manifest.scope,
        mutation: metadata.manifest.mutation,
        requiredProviderScopes: [...metadata.manifest.requiredProviderScopes],
        confirmationKind: metadata.manifest.confirmationKind,
        highImpactCapable: metadata.manifest.highImpactCapable,
        inputSchema: metadata.inputSchema,
        ...(0, service_config_js_1.inspectToolConfiguration)(name),
    }));
}
function planResponse(entry, plan) {
    return {
        planId: plan.planId,
        requestId: plan.requestId,
        tool: plan.tool,
        service: entry.handler,
        description: entry.description,
        risk: plan.risk,
        payloadHash: plan.payloadHash,
        status: plan.status,
        expiresAt: plan.expiresAt,
        approvalRequired: plan.risk ? (0, tool_policy_js_1.requiresApproval)(plan.tool || '') : true,
        configuration: plan.tool ? (0, service_config_js_1.inspectToolConfiguration)(plan.tool) : undefined,
    };
}
function createHttpApp(config = loadRuntimeConfig(), runtimeSecurityResolver = new runtime_security_resolver_js_1.RuntimeSecurityResolver(), executionLedger = new execution_ledger_client_js_1.ExecutionLedgerClient(), runtimeRateLimiter = new runtime_rate_limit_client_js_1.RuntimeRateLimitClient(), connectionMetadataProvider = service_config_js_1.buildProviderConnectionMetadata, toolExecutor = async (tool, args, context) => (0, index_js_1.executeTool)(tool, args, (0, service_config_js_1.buildToolConfiguration)(tool, context))) {
    const providerExecution = (0, provider_execution_state_machine_js_1.createProviderExecutionStateMachine)({
        execute: toolExecutor,
        ledger: executionLedger,
    });
    executionLedger = providerExecution.ledger;
    toolExecutor = providerExecution.execute;
    const app = (0, express_1.default)();
    const localAuditEvents = [];
    const runtimeMetrics = {
        requestsTotal: 0,
        responsesByStatus: {},
        totalDurationMs: 0,
        rateLimitDenied: 0,
        rateLimitControlErrors: 0,
    };
    const recordLocalAudit = (event) => {
        localAuditEvents.push(event);
        if (localAuditEvents.length > MAX_AUDIT_EVENTS)
            localAuditEvents.shift();
    };
    app.disable('x-powered-by');
    app.set('trust proxy', 1);
    app.use((request, response, next) => {
        providerExecution.run(() => {
            const requestState = providerExecution.currentState();
            const originalJson = response.json.bind(response);
            const originalStatus = response.status.bind(response);
            response.status = function governedStatus(value) {
                const outcomeStatus = requestState?.execution?.error?.status;
                return originalStatus(value === 500 && Number.isInteger(outcomeStatus)
                    ? outcomeStatus
                    : value);
            };
            response.json = function governedJson(value) {
                let prepared;
                try {
                    prepared = providerExecution.preparePresentation(value, 'http_response_shaping_failed');
                }
                catch (error) {
                    providerExecution.recordResponseFailure(error, 'http_response_shaping_failed', requestState?.execution?.durablePlanId);
                    throw error;
                }
                try {
                    return originalJson(prepared);
                }
                catch (error) {
                    providerExecution.recordResponseFailure(error, 'http_response_delivery_failed', requestState?.execution?.durablePlanId);
                    throw error;
                }
            };
            response.once('close', () => {
                if (response.writableEnded)
                    return;
                providerExecution.recordResponseFailureForState(requestState, new Error('HTTP connection closed before response completion'), 'http_connection_closed', requestState?.execution?.durablePlanId);
            });
            next();
        });
    });
    app.use(createRequestTelemetry(runtimeMetrics));
    app.use((0, helmet_1.default)({ contentSecurityPolicy: false }));
    app.use((0, cors_1.default)(createCorsOptions(config)));
    app.use(express_1.default.json({ limit: '256kb' }));
    app.get('/', (_request, response) => {
        response.json({
            name: 'MCPMaster Workflow Control Tower',
            version: VERSION,
            mode: 'secure-http',
            description: 'Plan-bound, approval-gated tool execution with durable audit controls.',
            endpoints: {
                health: '/health',
                tools: '/tools',
                connections: '/connections',
                plan: '/tools/plan',
                approve: '/tools/approve',
                execute: '/tools/execute',
            },
        });
    });
    app.get('/health', async (request, response) => {
        let protectedRoutesConfigured = Boolean(config.adminToken);
        if (!protectedRoutesConfigured) {
            try {
                const security = await resolveRuntimeSecurity(config, request, runtimeSecurityResolver);
                protectedRoutesConfigured = adminConfigured(security);
            }
            catch {
                protectedRoutesConfigured = false;
            }
        }
        response.json({
            status: 'healthy',
            version: VERSION,
            protectedRoutesConfigured,
            durableLedgerConfigured: Boolean(vercelOidcToken(request)),
            distributedRateLimitConfigured: distributedRuntime(request),
            timestamp: new Date().toISOString(),
        });
    });
    const protectedRouter = express_1.default.Router();
    protectedRouter.use(createRateLimiter(config, runtimeRateLimiter, runtimeMetrics));
    protectedRouter.use(createAdminGuard(config, runtimeSecurityResolver));
    protectedRouter.get('/metrics', (_request, response) => {
        response.json({
            uptimeSeconds: process.uptime(),
            memory: process.memoryUsage(),
            timestamp: new Date().toISOString(),
            toolCount: (0, index_js_1.getAllTools)().length,
            localAuditEventCount: localAuditEvents.length,
            requestsTotal: runtimeMetrics.requestsTotal,
            responsesByStatus: runtimeMetrics.responsesByStatus,
            averageDurationMs: runtimeMetrics.requestsTotal > 0
                ? Math.round(runtimeMetrics.totalDurationMs / runtimeMetrics.requestsTotal)
                : 0,
            rateLimitDenied: runtimeMetrics.rateLimitDenied,
            rateLimitControlErrors: runtimeMetrics.rateLimitControlErrors,
        });
    });
    protectedRouter.get('/tools', (_request, response) => {
        response.json({ tools: publicToolMetadata() });
    });
    protectedRouter.get('/connections', async (request, response, next) => {
        try {
            response.set({
                'Cache-Control': 'no-store',
                Pragma: 'no-cache',
                Expires: '0',
            });
            response.json({
                connections: await connectionMetadataProvider({
                    vercelOidcToken: vercelOidcToken(request),
                }),
            });
        }
        catch (error) {
            next(error);
        }
    });
    protectedRouter.get('/plans', async (request, response, next) => {
        try {
            const requestedLimit = Number.parseInt(String(request.query.limit || '100'), 10);
            const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 500) : 100;
            const oidcToken = vercelOidcToken(request);
            if (!oidcToken) {
                response.status(503).json({
                    ok: false,
                    error: {
                        code: 'DURABLE_LEDGER_REQUIRED',
                        message: 'Plan listing requires the production durable ledger.',
                    },
                });
                return;
            }
            response.json({ ok: true, plans: await executionLedger.listPlans(oidcToken, limit) });
        }
        catch (error) {
            next(error);
        }
    });
    protectedRouter.post('/tools/plan', async (request, response, next) => {
        try {
            const input = planInputSchema.parse(request.body);
            const entry = index_js_1.toolRegistry[input.tool];
            if (!entry)
                throw new service_config_js_1.UnknownToolError(input.tool);
            const id = requestId(request);
            const risk = (0, tool_policy_js_1.classifyToolRisk)(input.tool);
            const payloadHash = executionPayloadHash(input.tool, input.args);
            const oidcToken = vercelOidcToken(request);
            if (!oidcToken) {
                recordLocalAudit({
                    id: (0, crypto_1.randomUUID)(),
                    requestId: id,
                    timestamp: new Date().toISOString(),
                    tool: input.tool,
                    risk,
                    status: 'planned',
                });
                response.json({
                    ok: true,
                    durable: false,
                    requestId: id,
                    plan: {
                        tool: input.tool,
                        service: entry.handler,
                        description: entry.description,
                        args: input.args,
                        risk,
                        payloadHash,
                        approvalRequired: (0, tool_policy_js_1.requiresApproval)(input.tool),
                        configuration: (0, service_config_js_1.inspectToolConfiguration)(input.tool),
                    },
                });
                return;
            }
            const plan = await executionLedger.createPlan(oidcToken, {
                requestId: id,
                tool: input.tool,
                risk,
                args: input.args,
                payloadHash,
                expiresAt: new Date(Date.now() + PLAN_TTL_MS).toISOString(),
            });
            response.json({
                ok: true,
                durable: true,
                requestId: plan.requestId,
                plan: planResponse(entry, plan),
            });
        }
        catch (error) {
            next(error);
        }
    });
    protectedRouter.post('/tools/approve', async (request, response, next) => {
        try {
            const input = approvalSchema.parse(request.body);
            const runtimeSecurity = response.locals.runtimeSecurity;
            if (!runtimeSecurity || !approvalConfigured(runtimeSecurity)) {
                response.status(503).json({
                    ok: false,
                    error: {
                        code: 'APPROVALS_NOT_CONFIGURED',
                        message: 'Write approval authentication is not configured.',
                    },
                });
                return;
            }
            if (!approvalTokenValid(request.header('x-approval-token'), runtimeSecurity)) {
                response.status(403).json({
                    ok: false,
                    error: { code: 'APPROVAL_REQUIRED', message: 'A valid approval credential is required.' },
                });
                return;
            }
            const oidcToken = vercelOidcToken(request);
            if (!oidcToken) {
                response.status(503).json({
                    ok: false,
                    error: {
                        code: 'DURABLE_LEDGER_REQUIRED',
                        message: 'Plan approval requires the production durable ledger.',
                    },
                });
                return;
            }
            const plan = assertBoundLedgerPlan(await executionLedger.approvePlan(oidcToken, input.planId, request.header('x-approver-id') || 'admin-token'), input.planId, 'approved');
            response.json({ ok: true, plan });
        }
        catch (error) {
            next(error);
        }
    });
    const executeHandler = async (request, response, next) => {
        const startedAt = Date.now();
        let id = requestId(request);
        let tool = 'unknown';
        let risk = 'write';
        let claimedPlanId;
        let claimedExecutionPlan;
        let oidcToken;
        try {
            oidcToken = vercelOidcToken(request);
            const planReference = planReferenceSchema.safeParse(request.body);
            let args;
            if (planReference.success) {
                if (!oidcToken) {
                    response.status(503).json({
                        ok: false,
                        error: {
                            code: 'DURABLE_LEDGER_REQUIRED',
                            message: 'Plan execution requires the production durable ledger.',
                        },
                    });
                    return;
                }
                const claimed = assertBoundLedgerPlan(await executionLedger.claimPlan(oidcToken, planReference.data.planId), planReference.data.planId, 'executing');
                if (!claimed.tool || !claimed.risk || !claimed.args || !claimed.payloadHash) {
                    throw new execution_ledger_client_js_1.ExecutionLedgerError('Claimed execution plan is incomplete');
                }
                const digest = executionPayloadHash(claimed.tool, claimed.args);
                if (digest !== claimed.payloadHash) {
                    throw new execution_ledger_client_js_1.ExecutionLedgerError('Execution plan payload hash mismatch');
                }
                claimedPlanId = claimed.planId;
                claimedExecutionPlan = claimed;
                id = claimed.requestId;
                tool = claimed.tool;
                risk = claimed.risk;
                args = claimed.args;
            }
            else {
                const input = executionSchema.parse(request.body);
                tool = input.tool;
                risk = (0, tool_policy_js_1.classifyToolRisk)(tool);
                args = input.args;
                const entry = index_js_1.toolRegistry[tool];
                if (!entry)
                    throw new service_config_js_1.UnknownToolError(tool);
                if (input.dryRun) {
                    const payloadHash = executionPayloadHash(tool, args);
                    if (!oidcToken) {
                        recordLocalAudit({
                            id: (0, crypto_1.randomUUID)(),
                            requestId: id,
                            timestamp: new Date().toISOString(),
                            tool,
                            risk,
                            status: 'planned',
                        });
                        response.json({
                            ok: true,
                            durable: false,
                            requestId: id,
                            dryRun: true,
                            plan: {
                                tool,
                                service: entry.handler,
                                description: entry.description,
                                args,
                                risk,
                                payloadHash,
                                approvalRequired: (0, tool_policy_js_1.requiresApproval)(tool),
                                configuration: (0, service_config_js_1.inspectToolConfiguration)(tool),
                            },
                        });
                        return;
                    }
                    const created = await executionLedger.createPlan(oidcToken, {
                        requestId: id,
                        tool,
                        risk,
                        args,
                        payloadHash,
                        expiresAt: new Date(Date.now() + PLAN_TTL_MS).toISOString(),
                    });
                    response.json({
                        ok: true,
                        durable: true,
                        requestId: created.requestId,
                        dryRun: true,
                        plan: planResponse(entry, created),
                    });
                    return;
                }
                if (oidcToken) {
                    if ((0, tool_policy_js_1.requiresApproval)(tool)) {
                        response.status(409).json({
                            ok: false,
                            requestId: id,
                            error: {
                                code: 'PLAN_REQUIRED',
                                message: 'Create and approve a durable plan before executing a write or destructive tool.',
                            },
                        });
                        return;
                    }
                    const created = await executionLedger.createPlan(oidcToken, {
                        requestId: id,
                        tool,
                        risk,
                        args,
                        payloadHash: executionPayloadHash(tool, args),
                        expiresAt: new Date(Date.now() + PLAN_TTL_MS).toISOString(),
                    });
                    const claimed = assertBoundLedgerPlan(await executionLedger.claimPlan(oidcToken, created.planId), created.planId, 'executing');
                    if (!claimed.payloadHash || claimed.payloadHash !== executionPayloadHash(tool, args)) {
                        throw new execution_ledger_client_js_1.ExecutionLedgerError('Execution plan payload hash mismatch');
                    }
                    claimedPlanId = claimed.planId;
                    claimedExecutionPlan = claimed;
                    id = claimed.requestId;
                }
                else if ((0, tool_policy_js_1.requiresApproval)(tool)) {
                    recordLocalAudit({
                        id: (0, crypto_1.randomUUID)(),
                        requestId: id,
                        timestamp: new Date().toISOString(),
                        tool,
                        risk,
                        status: 'denied',
                        error: 'Durable ledger required',
                    });
                    response.status(503).json({
                        ok: false,
                        requestId: id,
                        error: {
                            code: 'DURABLE_LEDGER_REQUIRED',
                            message: 'Write and destructive execution requires the production durable ledger.',
                        },
                    });
                    return;
                }
            }
            const entry = index_js_1.toolRegistry[tool];
            if (!entry)
                throw new service_config_js_1.UnknownToolError(tool);
            let destructiveCapabilityReservationUsed = false;
            const destructiveCapabilityReservation = claimedExecutionPlan
                ? () => {
                    if (destructiveCapabilityReservationUsed) {
                        throw new execution_ledger_client_js_1.ExecutionLedgerError('Destructive capability reservation intent is one-shot per execution', 409);
                    }
                    destructiveCapabilityReservationUsed = true;
                    return createDestructiveCapabilityReservationIntent(claimedExecutionPlan);
                }
                : undefined;
            const result = await toolExecutor(tool, args, {
                vercelOidcToken: oidcToken,
                destructiveCapabilityReservation,
            });
            const durationMs = Date.now() - startedAt;
            if (claimedPlanId && oidcToken) {
                await executionLedger.finishPlan(oidcToken, {
                    planId: claimedPlanId,
                    status: 'completed',
                    durationMs,
                    resultSummary: resultSummary(result),
                });
            }
            else {
                recordLocalAudit({
                    id: (0, crypto_1.randomUUID)(),
                    requestId: id,
                    timestamp: new Date().toISOString(),
                    tool,
                    risk,
                    status: 'completed',
                    durationMs,
                });
            }
            response.json({ ok: true, requestId: id, planId: claimedPlanId, tool, risk, durationMs, result });
        }
        catch (error) {
            const durationMs = Date.now() - startedAt;
            if (claimedPlanId && oidcToken) {
                try {
                    await executionLedger.finishPlan(oidcToken, {
                        planId: claimedPlanId,
                        status: 'failed',
                        durationMs,
                        error: error instanceof Error ? error.message.slice(0, 1000) : 'Unknown error',
                    });
                }
                catch {
                    // Preserve the primary execution failure. The control plane records claim state.
                }
            }
            else {
                recordLocalAudit({
                    id: (0, crypto_1.randomUUID)(),
                    requestId: id,
                    timestamp: new Date().toISOString(),
                    tool,
                    risk,
                    status: 'failed',
                    durationMs,
                    error: error instanceof Error ? error.message : 'Unknown error',
                });
            }
            next(error);
        }
    };
    protectedRouter.post('/tools/execute', executeHandler);
    protectedRouter.post('/tools', (request, response, next) => {
        response.setHeader('Deprecation', 'true');
        response.setHeader('Link', '</tools/execute>; rel="successor-version"');
        executeHandler(request, response, next);
    });
    protectedRouter.get('/logs', async (request, response, next) => {
        try {
            const requestedLimit = Number.parseInt(String(request.query.limit || '100'), 10);
            const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 500) : 100;
            const oidcToken = vercelOidcToken(request);
            if (!oidcToken) {
                response.json({ durable: false, events: localAuditEvents.slice(-limit) });
                return;
            }
            const events = await executionLedger.listAudit(oidcToken, limit);
            response.json({ durable: true, events });
        }
        catch (error) {
            next(error);
        }
    });
    protectedRouter.get('/logs/verify', async (request, response, next) => {
        try {
            const oidcToken = vercelOidcToken(request);
            if (!oidcToken) {
                response.status(503).json({
                    ok: false,
                    error: {
                        code: 'DURABLE_LEDGER_REQUIRED',
                        message: 'Audit-chain verification requires the production durable ledger.',
                    },
                });
                return;
            }
            response.json({ ok: true, verification: await executionLedger.verifyAudit(oidcToken) });
        }
        catch (error) {
            next(error);
        }
    });
    const webRoot = path_1.default.join(process.cwd(), 'web');
    protectedRouter.use('/control-panel', express_1.default.static(path_1.default.join(webRoot, 'control-panel')));
    protectedRouter.use('/wow-control', express_1.default.static(path_1.default.join(webRoot, 'wow-control')));
    protectedRouter.use('/live-ops', express_1.default.static(path_1.default.join(webRoot, 'live-ops')));
    protectedRouter.use('/memgraph', express_1.default.static(path_1.default.join(webRoot, 'memgraph')));
    protectedRouter.use('/audit-cinema', express_1.default.static(path_1.default.join(webRoot, 'audit-cinema')));
    app.use(protectedRouter);
    app.use((_request, response) => {
        response.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Route not found.' } });
    });
    app.use((error, _request, response, _next) => {
        if (error instanceof zod_1.ZodError) {
            response.status(400).json({
                ok: false,
                error: { code: 'INVALID_REQUEST', message: 'Request validation failed.', issues: error.issues },
            });
            return;
        }
        if (error instanceof service_config_js_1.UnknownToolError) {
            response.status(404).json({ ok: false, error: { code: 'UNKNOWN_TOOL', message: error.message } });
            return;
        }
        if (error instanceof service_config_js_1.MissingConfigurationError) {
            response.status(503).json({
                ok: false,
                error: { code: 'SERVICE_NOT_CONFIGURED', message: error.message, missing: error.missing },
            });
            return;
        }
        if (error instanceof execution_ledger_client_js_1.ExecutionLedgerError) {
            const status = error.status && error.status >= 400 && error.status < 600 ? error.status : 502;
            response.status(status).json({
                ok: false,
                error: { code: 'EXECUTION_LEDGER_ERROR', message: error.message },
            });
            return;
        }
        const providerFailure = boundedProviderFailure(error);
        if (providerFailure) {
            response.status(providerFailure.status).json({
                ok: false,
                error: { code: providerFailure.code, message: providerFailure.message },
            });
            return;
        }
        console.error(JSON.stringify({
            event: 'http_internal_error',
            errorType: error instanceof Error ? error.name : 'unknown',
        }));
        response.status(500).json({
            ok: false,
            error: { code: 'INTERNAL_ERROR', message: 'An internal ProjectOS error occurred.' },
        });
    });
    return app;
}
function startHttpServer() {
    const config = loadRuntimeConfig();
    const app = createHttpApp(config);
    const server = app.listen(config.port, () => {
        console.log(`MCPMaster secure HTTP runtime listening on port ${config.port}`);
    });
    const shutdown = (signal) => {
        console.log(`Received ${signal}; shutting down.`);
        server.close(() => process.exit(0));
    };
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
    return server;
}
//# sourceMappingURL=http-app.js.map
