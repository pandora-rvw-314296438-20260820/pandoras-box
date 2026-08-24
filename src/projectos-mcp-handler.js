"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.projectOsMcpVercelConfig = void 0;
exports.createProjectOsMcpHandler = createProjectOsMcpHandler;
exports.handleProjectOsMcp = handleProjectOsMcp;

const { randomUUID } = require("node:crypto");
const { ExecutionLedgerClient } = require("./runtime/execution-ledger-client.js");
const { buildToolConfiguration } = require("./runtime/service-config.js");
const { classifyToolRisk } = require("./runtime/tool-policy.js");
const { resolveVercelWorkloadToken } = require("./runtime/vercel-workload-identity.js");
const { executeTool, getAllTools, toolRegistry } = require("./tools/index.js");
const { executionPayloadHash, createDestructiveCapabilityReservationIntent } = require("./http-app.js");
const { loadOperatorPublicConfig } = require("./operator-public-config.js");
const {
    canApproveProjectOsPlan,
    projectOsApproverAttribution,
} = require("./projectos-approval-authorization.js");
const {
    SupabaseBearerAuthenticator,
} = require("../apps/meta-business-mcp/dist/auth/supabase-bearer.js");
const {
    SupabaseOrganizationMembershipResolver,
} = require("../apps/meta-business-mcp/dist/auth/membership.js");

const PLAN_TTL_MS = 10 * 60 * 1000;
const MAX_BODY_BYTES = 256 * 1024;
const DEFAULT_RESOURCE_ORIGIN = "https://mcpmaster.vercel.app";
const AUTHORIZATION_SERVER = "https://jcyqixttuebxqqfkjonq.supabase.co/auth/v1";
const IDENTITY_SCOPES = Object.freeze(["openid", "email", "profile"]);
const LEGACY_IDENTITY_SCOPES = new Set([...IDENTITY_SCOPES, "offline_access"]);
const MCP_ALLOWED_METHODS = "GET,POST,DELETE,OPTIONS";
const MCP_ALLOWED_HEADERS = "Authorization,Content-Type,Mcp-Protocol-Version,Last-Event-ID,X-Request-Id";
const MCP_EXPOSED_HEADERS = "WWW-Authenticate,Mcp-Protocol-Version,X-Request-Id";
const METADATA_PATHS = new Set([
    "/.well-known/oauth-protected-resource",
    "/.well-known/oauth-protected-resource/mcp",
]);
const ACTIVE_ROLES = new Set(["owner", "admin", "operator", "member", "viewer"]);
const EXECUTOR_ROLES = new Set(["owner", "admin"]);
const LEGACY_PLAN_TOOL_PREFIX = "projectos_plan_";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

exports.projectOsMcpVercelConfig = Object.freeze({
    api: { bodyParser: false },
    maxDuration: 60,
});

function resourceOrigin() {
    return (process.env.PROJECTOS_MCP_RESOURCE_ORIGIN?.trim() || DEFAULT_RESOURCE_ORIGIN).replace(/\/+$/, "");
}

function requestHeader(request, name) {
    const value = request.headers?.[name];
    return Array.isArray(value) ? value[0] : value;
}

function ownStringDataProperty(value, name) {
    if (!value || (typeof value !== "object" && typeof value !== "function")) {
        return undefined;
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    return descriptor
        && Object.prototype.hasOwnProperty.call(descriptor, "value")
        && typeof descriptor.value === "string"
        ? descriptor.value
        : undefined;
}

function requestUrlValue(request) {
    return ownStringDataProperty(request, "originalUrl")
        || ownStringDataProperty(request, "url")
        || "/";
}

function parsedRequestUrl(request) {
    try {
        return new URL(requestUrlValue(request), DEFAULT_RESOURCE_ORIGIN);
    } catch {
        return new URL("/", DEFAULT_RESOURCE_ORIGIN);
    }
}

function requestPath(request) {
    return parsedRequestUrl(request).pathname;
}

function metadataSelector(request) {
    const values = parsedRequestUrl(request).searchParams.getAll("metadata");
    return values.length === 1 ? values[0] : undefined;
}

function isMetadataRequest(request) {
    if (request.method !== "GET") return false;
    const selector = metadataSelector(request);
    return selector === "root" || selector === "mcp" || METADATA_PATHS.has(requestPath(request));
}

function applyMcpBaseHeaders(request, response) {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("CDN-Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    const suppliedRequestId = requestHeader(request, "x-request-id");
    response.setHeader(
        "X-Request-Id",
        typeof suppliedRequestId === "string" && /^[A-Za-z0-9._:-]{1,128}$/.test(suppliedRequestId)
            ? suppliedRequestId
            : randomUUID(),
    );
}

function applyMcpCors(request, response, allowedOrigins) {
    const origin = requestHeader(request, "origin");
    if (origin) {
        if (!Array.isArray(allowedOrigins) || !allowedOrigins.includes(origin)) {
            throw Object.assign(new Error("Forbidden origin"), { status: 403, rpcCode: -32003 });
        }
        response.setHeader("Access-Control-Allow-Origin", origin);
        response.setHeader("Vary", "Origin");
    }
    response.setHeader("Access-Control-Allow-Headers", MCP_ALLOWED_HEADERS);
    response.setHeader("Access-Control-Allow-Methods", MCP_ALLOWED_METHODS);
    response.setHeader("Access-Control-Expose-Headers", MCP_EXPOSED_HEADERS);
}

function oauthChallenge() {
    return `Bearer resource_metadata="${resourceOrigin()}/.well-known/oauth-protected-resource/mcp", scope="${IDENTITY_SCOPES.join(" ")}"`;
}

function protectedResourceMetadata() {
    const origin = resourceOrigin();
    return {
        resource: `${origin}/mcp`,
        resource_name: "Banatao Systems ProjectOS",
        authorization_servers: [AUTHORIZATION_SERVER],
        scopes_supported: [...IDENTITY_SCOPES],
        bearer_methods_supported: ["header"],
        resource_documentation: `${origin}/control-tower`,
    };
}

function clearPrivilegedCallerHeaders(request) {
    delete request.headers["x-approval-token"];
    delete request.headers["x-approver-id"];
    delete request.headers["x-vercel-oidc-token"];
    delete request.headers["x-vercel-sc-headers"];
}

function authorizationHeader(request) {
    return requestHeader(request, "authorization");
}

async function jsonBody(request) {
    if (request.body && typeof request.body === "object") return request.body;
    let size = 0;
    const chunks = [];
    for await (const chunk of request) {
        size += chunk.length;
        if (size > MAX_BODY_BYTES) throw Object.assign(new Error("Request body is too large"), { status: 413 });
        chunks.push(chunk);
    }
    if (chunks.length === 0) return {};
    try {
        return JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
        throw Object.assign(new Error("Request body must be valid JSON"), { status: 400 });
    }
}

function toolResult(value) {
    return {
        content: [{ type: "text", text: JSON.stringify(value) }],
        structuredContent: value,
    };
}

function rpcResult(response, id, result) {
    response.status(200).json({ jsonrpc: "2.0", id, result });
}

function rpcError(response, id, code, message, status = 400) {
    response.status(status).json({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });
}

function publicTools() {
    const controls = [
        {
            name: "projectos_tool_catalog",
            description: "List ProjectOS provider tools and their enforced risk, scope, allowlist, and approval policy.",
            inputSchema: { type: "object", additionalProperties: false },
        },
        {
            name: "projectos_list_plans",
            description: "List durable ProjectOS plans and current one-time execution states.",
            inputSchema: {
                type: "object",
                properties: { limit: { type: "integer", minimum: 1, maximum: 500 } },
                additionalProperties: false,
            },
        },
        {
            name: "projectos_list_audit",
            description: "List recent hash-linked ProjectOS execution audit events.",
            inputSchema: {
                type: "object",
                properties: { limit: { type: "integer", minimum: 1, maximum: 500 } },
                additionalProperties: false,
            },
        },
        {
            name: "projectos_verify_audit",
            description: "Verify the ProjectOS execution audit hash chain.",
            inputSchema: { type: "object", additionalProperties: false },
        },
        {
            name: "projectos_create_plan",
            description: "Create an exact durable ProjectOS plan. This does not approve or execute it.",
            inputSchema: {
                type: "object",
                required: ["tool", "args"],
                properties: {
                    tool: { type: "string", minLength: 1 },
                    args: { type: "object" },
                },
                additionalProperties: false,
            },
        },
        {
            name: "projectos_approve_plan",
            description: "Approve one exact pending durable plan as an authenticated ProjectOS owner or admin. Approval does not execute it.",
            inputSchema: {
                type: "object",
                required: ["planId"],
                properties: { planId: { type: "string", format: "uuid" } },
                additionalProperties: false,
            },
        },
        {
            name: "projectos_execute_plan",
            description: "Separately claim and execute one exact approved plan; payload integrity, one-time claim, allowlists, mutation policy, and destructive gates remain enforced.",
            inputSchema: {
                type: "object",
                required: ["planId"],
                properties: { planId: { type: "string", format: "uuid" } },
                additionalProperties: false,
            },
        },
    ];
    const providerTools = getAllTools().flatMap((name) => {
        const definition = toolRegistry[name];
        if (classifyToolRisk(name) === "read") {
            return [{
                name,
                description: `${definition.description} [ProjectOS risk: read]`,
                inputSchema: definition.inputSchema,
            }];
        }
        return [{
            name: legacyPlanToolName(name),
            description: `Create a durable ProjectOS plan for ${name}. This does not execute the operation until an authorized approval and execution call occur.`,
            inputSchema: definition.inputSchema,
        }];
    });
    return [...controls, ...providerTools];
}

function legacyPlanToolName(toolName) {
    return `${LEGACY_PLAN_TOOL_PREFIX}${toolName.replace(".", "_")}`;
}

function legacyPlannedTool(name) {
    if (!name.startsWith(LEGACY_PLAN_TOOL_PREFIX)) return undefined;
    return getAllTools().find((toolName) => (
        classifyToolRisk(toolName) !== "read" && legacyPlanToolName(toolName) === name
    ));
}

function requiredString(value, name) {
    if (typeof value !== "string" || value.trim().length === 0) {
        throw Object.assign(new Error(`${name} is required`), { status: 400 });
    }
    return value.trim();
}

function requiredObject(value, name) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        throw Object.assign(new Error(`${name} must be an object`), { status: 400 });
    }
    return value;
}

function requiredUuid(value, name) {
    const resolved = requiredString(value, name);
    if (!UUID_PATTERN.test(resolved)) {
        throw Object.assign(new Error(`${name} must be a UUID`), { status: 400 });
    }
    return resolved;
}

function assertPlanIdentity(plan, planId, status) {
    if (!plan || plan.planId !== planId || (status && plan.status !== status)) {
        throw Object.assign(new Error("Durable ledger returned a mismatched plan identity or state"), { status: 409 });
    }
    return plan;
}

function defaultDependencies() {
    const config = loadOperatorPublicConfig();
    return {
        organizationId: config.organizationId,
        allowedOrigins: config.allowedOrigins,
        authenticator: new SupabaseBearerAuthenticator({
            supabaseUrl: config.supabaseUrl,
            publishableKey: config.supabasePublishableKey,
        }),
        membershipResolver: new SupabaseOrganizationMembershipResolver({
            supabaseUrl: config.supabaseUrl,
            publishableKey: config.supabasePublishableKey,
        }),
        ledger: new ExecutionLedgerClient(),
        workloadToken: resolveVercelWorkloadToken,
        execute: executeTool,
        toolConfiguration: buildToolConfiguration,
        now: Date.now,
    };
}

async function actorFor(request, dependencies) {
    const identity = await dependencies.authenticator.authenticate(authorizationHeader(request));
    const membership = await dependencies.membershipResolver.resolve(
        dependencies.organizationId,
        identity.userId,
        identity.accessToken,
    );
    if (!membership || !ACTIVE_ROLES.has(membership.role)) {
        throw Object.assign(new Error("An active ProjectOS organization membership is required"), { status: 403 });
    }
    if (membership.organizationId !== dependencies.organizationId || membership.userId !== identity.userId) {
        throw Object.assign(new Error("ProjectOS membership does not match the authenticated user and organization"), { status: 403 });
    }
    return { identity, membership };
}

async function workloadToken(dependencies) {
    const token = (await dependencies.workloadToken())?.trim();
    if (!token) throw Object.assign(new Error("The server-side ProjectOS workload identity is unavailable"), { status: 503 });
    return token;
}

function requiredToolScope(name) {
    switch (name) {
        case "projectos_tool_catalog":
        case "projectos_list_plans":
        case "projectos_list_audit":
        case "projectos_verify_audit":
            return "projectos:read";
        case "projectos_create_plan":
            return "projectos:plan";
        case "projectos_approve_plan":
            return "projectos:approve";
        case "projectos_execute_plan":
            return "projectos:execute";
        default:
            if (legacyPlannedTool(name)) return "projectos:plan";
            if (toolRegistry[name]) {
                return classifyToolRisk(name) === "read" ? "projectos:read" : "projectos:plan";
            }
            return undefined;
    }
}

function assertToolScope(name, actor) {
    const granted = new Set(Array.isArray(actor.identity?.scopes) ? actor.identity.scopes : []);
    if (!granted.has("openid")) {
        throw Object.assign(new Error("OAuth scope openid is required"), { status: 403, requiredScope: "openid" });
    }
    const projectScopes = [...granted].filter((scope) => scope.startsWith("projectos:"));
    if (projectScopes.length === 0) {
        // Existing ChatGPT installations were consented before ProjectOS action
        // scopes existed. Keep only that exact identity grant compatible until
        // staged connector re-consent is complete; any broader or malformed
        // non-ProjectOS grant remains fail closed.
        const isBoundedLegacyGrant = IDENTITY_SCOPES.every((scope) => granted.has(scope))
            && [...granted].every((scope) => LEGACY_IDENTITY_SCOPES.has(scope));
        if (isBoundedLegacyGrant) return;
    }
    const required = requiredToolScope(name);
    if (!required || (!granted.has(required) && !granted.has("projectos:*"))) {
        throw Object.assign(new Error(`OAuth scope ${required || "projectos"} is required`), {
            status: 403,
            requiredScope: required || "projectos",
        });
    }
}

async function createDurablePlan(tool, toolArgs, dependencies) {
    if (!toolRegistry[tool]) throw Object.assign(new Error(`Unknown tool: ${tool}`), { status: 400 });
    const payloadHash = executionPayloadHash(tool, toolArgs);
    return dependencies.ledger.createPlan(await workloadToken(dependencies), {
        requestId: randomUUID(),
        tool,
        risk: classifyToolRisk(tool),
        args: toolArgs,
        payloadHash,
        expiresAt: new Date(dependencies.now() + PLAN_TTL_MS).toISOString(),
    });
}

async function callTool(name, args, actor, dependencies) {
    assertToolScope(name, actor);
    const plannedTool = legacyPlannedTool(name);
    if (plannedTool) {
        return toolResult({ plan: await createDurablePlan(plannedTool, args, dependencies) });
    }
    if (toolRegistry[name]) {
        if (classifyToolRisk(name) !== "read") {
            throw Object.assign(new Error("A durable ProjectOS plan is required before any provider mutation"), {
                status: 409,
            });
        }
        const token = await workloadToken(dependencies);
        return toolResult(await dependencies.execute(
            name,
            args,
            dependencies.toolConfiguration(name, { vercelOidcToken: token }),
        ));
    }
    switch (name) {
        case "projectos_tool_catalog":
            return toolResult({
                tools: getAllTools().map((name) => {
                    const tool = toolRegistry[name];
                    return {
                        name,
                        description: tool.description,
                        risk: classifyToolRisk(name),
                        provider: tool.manifest.provider,
                        scope: tool.manifest.scope,
                        mutation: tool.manifest.mutation,
                        requiredProviderScopes: [...tool.manifest.requiredProviderScopes],
                    };
                }),
            });
        case "projectos_list_plans": {
            const limit = Number.isInteger(args.limit) ? Math.min(Math.max(args.limit, 1), 500) : 100;
            return toolResult({ plans: await dependencies.ledger.listPlans(await workloadToken(dependencies), limit) });
        }
        case "projectos_list_audit": {
            const limit = Number.isInteger(args.limit) ? Math.min(Math.max(args.limit, 1), 500) : 100;
            return toolResult({ events: await dependencies.ledger.listAudit(await workloadToken(dependencies), limit) });
        }
        case "projectos_verify_audit": {
            return toolResult({ verification: await dependencies.ledger.verifyAudit(await workloadToken(dependencies)) });
        }
        case "projectos_create_plan": {
            const tool = requiredString(args.tool, "tool");
            const toolArgs = requiredObject(args.args, "args");
            return toolResult({ plan: await createDurablePlan(tool, toolArgs, dependencies) });
        }
        case "projectos_approve_plan": {
            if (!canApproveProjectOsPlan(actor)) {
                throw Object.assign(new Error("Plan approval requires a ProjectOS owner or admin session"), { status: 403 });
            }
            const planId = requiredUuid(args.planId, "planId");
            const plan = assertPlanIdentity(await dependencies.ledger.approvePlan(
                await workloadToken(dependencies),
                planId,
                projectOsApproverAttribution(actor),
            ), planId, "approved");
            return toolResult({ plan });
        }
        case "projectos_execute_plan": {
            if (!EXECUTOR_ROLES.has(actor.membership.role)) {
                throw Object.assign(new Error("Plan execution requires a ProjectOS owner or admin session"), { status: 403 });
            }
            const planId = requiredUuid(args.planId, "planId");
            const token = await workloadToken(dependencies);
            const claimed = assertPlanIdentity(await dependencies.ledger.claimPlan(token, planId), planId, "executing");
            if (!claimed.tool || !claimed.args || !claimed.payloadHash) {
                throw Object.assign(new Error("Claimed execution plan is incomplete"), { status: 409 });
            }
            if (executionPayloadHash(claimed.tool, claimed.args) !== claimed.payloadHash) {
                throw Object.assign(new Error("Execution plan payload hash mismatch"), { status: 409 });
            }
            if (!toolRegistry[claimed.tool]) throw Object.assign(new Error(`Unknown tool: ${claimed.tool}`), { status: 400 });
            const startedAt = dependencies.now();
            try {
                let destructiveCapabilityReservationUsed = false;
                const destructiveCapabilityReservation = claimed.tool === "supabase.delete-child-branch"
                    ? () => {
                        if (destructiveCapabilityReservationUsed) {
                            throw Object.assign(new Error("Destructive capability reservation intent is one-shot per execution"), { status: 409 });
                        }
                        destructiveCapabilityReservationUsed = true;
                        return createDestructiveCapabilityReservationIntent(claimed);
                    }
                    : undefined;
                const result = await dependencies.execute(
                    claimed.tool,
                    claimed.args,
                    dependencies.toolConfiguration(claimed.tool, {
                        vercelOidcToken: token,
                        destructiveCapabilityReservation,
                    }),
                );
                await dependencies.ledger.finishPlan(token, {
                    planId: claimed.planId,
                    status: "completed",
                    durationMs: Math.max(0, dependencies.now() - startedAt),
                    resultSummary: { type: typeof result },
                });
                return toolResult({ planId: claimed.planId, result });
            } catch (error) {
                await dependencies.ledger.finishPlan(token, {
                    planId: claimed.planId,
                    status: "failed",
                    durationMs: Math.max(0, dependencies.now() - startedAt),
                    error: error instanceof Error ? error.message.slice(0, 1000) : "Unknown execution error",
                });
                throw error;
            }
        }
        default:
            throw Object.assign(new Error(`Unknown ProjectOS MCP tool: ${name}`), { status: 400 });
    }
}

function createProjectOsMcpHandler(overrides = {}) {
    const dependencies = { ...defaultDependencies(), ...overrides };
    return async function projectOsMcpHandler(request, response) {
        applyMcpBaseHeaders(request, response);
        try {
            applyMcpCors(request, response, dependencies.allowedOrigins);
            if (request.method === "OPTIONS") {
                response.status(204).end();
                return;
            }
            if (isMetadataRequest(request)) {
                response.status(200).json(protectedResourceMetadata());
                return;
            }
            const authorization = authorizationHeader(request);
            clearPrivilegedCallerHeaders(request);
            if (!authorization) {
                throw Object.assign(new Error("A valid bearer access token is required"), { status: 401 });
            }
            const current = await actorFor({ ...request, headers: { ...request.headers, authorization } }, dependencies);
            if (request.method !== "POST") {
                response.setHeader("Allow", MCP_ALLOWED_METHODS);
                rpcError(response, null, -32600, "Method not allowed", 405);
                return;
            }
            const body = await jsonBody(request);
            const id = body.id ?? null;
            if (body.jsonrpc !== "2.0" || typeof body.method !== "string") {
                rpcError(response, id, -32600, "Invalid JSON-RPC request");
                return;
            }
            if (body.method === "initialize") {
                rpcResult(response, id, {
                    protocolVersion: "2025-06-18",
                    capabilities: { tools: { listChanged: false } },
                    serverInfo: { name: "MCPMaster ProjectOS", version: "1.3.0-recovered" },
                });
                return;
            }
            if (body.method === "notifications/initialized") {
                response.status(202).end();
                return;
            }
            if (body.method === "tools/list") {
                rpcResult(response, id, { tools: publicTools() });
                return;
            }
            if (body.method !== "tools/call") {
                rpcError(response, id, -32601, "Method not found");
                return;
            }
            const params = requiredObject(body.params, "params");
            const name = requiredString(params.name, "params.name");
            const args = params.arguments === undefined ? {} : requiredObject(params.arguments, "params.arguments");
            rpcResult(response, id, await callTool(name, args, current, dependencies));
        } catch (error) {
            const status = Number.isInteger(error?.status) ? error.status : 500;
            if (status === 401) response.setHeader("WWW-Authenticate", oauthChallenge());
            if (status === 403 && typeof error?.requiredScope === "string") {
                response.setHeader("WWW-Authenticate", `Bearer error="insufficient_scope", scope="${error.requiredScope}"`);
            }
            rpcError(
                response,
                null,
                Number.isInteger(error?.rpcCode)
                    ? error.rpcCode
                    : status === 401 ? -32001 : status >= 500 ? -32603 : -32000,
                error instanceof Error ? error.message : "ProjectOS MCP request failed",
                status,
            );
        }
    };
}

let defaultHandler;

async function handleProjectOsMcp(request, response) {
    if (!defaultHandler) defaultHandler = createProjectOsMcpHandler();
    return defaultHandler(request, response);
}
