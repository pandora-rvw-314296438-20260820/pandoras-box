"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MissingConfigurationError = exports.UnknownToolError = void 0;
exports.sanitizeProviderConnections = sanitizeProviderConnections;
exports.buildProviderConnectionMetadata = buildProviderConnectionMetadata;
exports.buildToolConfiguration = buildToolConfiguration;
exports.inspectToolConfiguration = inspectToolConfiguration;
const tool_catalog_js_1 = require("./tool-catalog.js");
const github_control_resolver_js_1 = require("./github-control-resolver.js");
const supabase_control_resolver_js_1 = require("./supabase-control-resolver.js");
/**
 * Canonical Pandora Memory origin, fixed by owner decision on 2026-08-06
 * (CONFLICT-001). The Vercel identity, service principal, Supabase binding,
 * and deployed application behind this hostname are authoritative.
 */
const DEFAULT_MEMORY_ORIGIN = 'https://pandorasbox-memory.vercel.app';
const FLUTTERFLOW_API_ORIGIN = 'https://api.flutterflow.io/v2';
/**
 * Legacy deployment retired by the same decision. It is quarantined rather
 * than merely non-default: MCPMaster and Pandora's-Box traffic must never
 * reach it, so configuring it is a startup error, not a silent fallback.
 */
const QUARANTINED_MEMORY_ORIGINS = new Set(['https://memory-mbanatao.vercel.app']);
class UnknownToolError extends Error {
    constructor(toolName) {
        super(`Unknown tool: ${toolName}`);
        this.name = 'UnknownToolError';
    }
}
exports.UnknownToolError = UnknownToolError;
class MissingConfigurationError extends Error {
    constructor(service, missing) {
        super(`Configuration missing for ${service}: ${missing.join(', ')}`);
        this.name = 'MissingConfigurationError';
        this.missing = missing;
    }
}
exports.MissingConfigurationError = MissingConfigurationError;
function requiredEnvironmentValue(service, name) {
    const value = process.env[name]?.trim();
    if (!value) {
        throw new MissingConfigurationError(service, [name]);
    }
    return value;
}
function commaSeparatedEnvironment(name) {
    return (process.env[name] || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
}
function boundedIntegerEnvironment(service, name, fallback, minimum, maximum) {
    const raw = process.env[name]?.trim();
    if (!raw)
        return fallback;
    if (!/^\d+$/.test(raw)) {
        throw new MissingConfigurationError(service, [
            `${name} as an integer from ${minimum} to ${maximum}`,
        ]);
    }
    const value = Number(raw);
    if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
        throw new MissingConfigurationError(service, [
            `${name} as an integer from ${minimum} to ${maximum}`,
        ]);
    }
    return value;
}
function buildGitHubEnvironmentConfiguration() {
    return {
        id: process.env.MCPMASTER_GITHUB_ACCOUNT_ID?.trim() || 'environment',
        label: process.env.GITHUB_ACCOUNT_LABEL?.trim() || 'Environment GitHub account',
        authMode: 'pat',
        token: requiredEnvironmentValue('github', 'GITHUB_TOKEN'),
        allowMutations: process.env.GITHUB_ALLOW_MUTATIONS === 'true',
        baseUrl: 'https://api.github.com',
        login: process.env.GITHUB_LOGIN?.trim() || undefined,
        allowedRepositories: commaSeparatedEnvironment('GITHUB_ALLOWED_REPOSITORIES'),
        grantedScopes: commaSeparatedEnvironment('GITHUB_GRANTED_SCOPES'),
    };
}
async function buildGitHubConfiguration(context) {
    // Production Vercel/OIDC is the governed primary path. A legacy GITHUB_TOKEN
    // must never shadow the Supabase/Vault control catalog in production; keep
    // the environment token only as the explicit non-OIDC fallback for local or
    // recovery runtimes.
    const oidcToken = context.vercelOidcToken || process.env.VERCEL_OIDC_TOKEN;
    if (oidcToken) {
        return new github_control_resolver_js_1.GitHubControlResolver().resolve(oidcToken, process.env.MCPMASTER_GITHUB_ACCOUNT_ID);
    }
    if (process.env.GITHUB_TOKEN?.trim()) {
        return buildGitHubEnvironmentConfiguration();
    }
    throw new MissingConfigurationError('github', [
        'Vercel OIDC request token or GITHUB_TOKEN',
    ]);
}
function buildSupabaseEnvironmentConfiguration() {
    const raw = requiredEnvironmentValue('supabase', 'SUPABASE_ACCOUNTS_JSON');
    let definitions;
    try {
        definitions = JSON.parse(raw);
    }
    catch {
        throw new MissingConfigurationError('supabase', ['valid SUPABASE_ACCOUNTS_JSON']);
    }
    if (!Array.isArray(definitions) || definitions.length === 0) {
        throw new MissingConfigurationError('supabase', ['non-empty SUPABASE_ACCOUNTS_JSON']);
    }
    return {
        accounts: definitions.map((definition) => ({
            id: definition.id,
            label: definition.label,
            authMode: definition.authMode || 'pat',
            token: requiredEnvironmentValue('supabase', definition.tokenEnv),
            allowMutations: definition.allowMutations === true,
            allowedOrganizationSlugs: definition.allowedOrganizationSlugs || [],
            allowedProjectRefs: definition.allowedProjectRefs || [],
            grantedScopes: definition.grantedScopes || [],
        })),
        timeoutMs: Number(process.env.SUPABASE_MANAGEMENT_TIMEOUT_MS || '10000'),
        maxResponseBytes: Number(process.env.SUPABASE_MANAGEMENT_MAX_RESPONSE_BYTES || '1000000'),
    };
}
async function buildSupabaseConfiguration(context) {
    if (process.env.SUPABASE_ACCOUNTS_JSON?.trim()) {
        return buildSupabaseEnvironmentConfiguration();
    }
    const oidcToken = context.vercelOidcToken || process.env.VERCEL_OIDC_TOKEN;
    if (!oidcToken) {
        throw new MissingConfigurationError('supabase', [
            'Vercel OIDC request token or SUPABASE_ACCOUNTS_JSON',
        ]);
    }
    return new supabase_control_resolver_js_1.SupabaseControlResolver().resolve(oidcToken);
}
function buildFlutterFlowEnvironmentConfiguration() {
    const raw = requiredEnvironmentValue('flutterflow', 'FLUTTERFLOW_ACCOUNTS_JSON');
    let definitions;
    try {
        definitions = JSON.parse(raw);
    }
    catch {
        throw new MissingConfigurationError('flutterflow', ['valid FLUTTERFLOW_ACCOUNTS_JSON']);
    }
    if (!Array.isArray(definitions) || definitions.length === 0) {
        throw new MissingConfigurationError('flutterflow', ['non-empty FLUTTERFLOW_ACCOUNTS_JSON']);
    }
    const accounts = definitions.map((definition) => {
        if (!definition
            || typeof definition !== 'object'
            || Array.isArray(definition)
            || typeof definition.id !== 'string'
            || typeof definition.label !== 'string'
            || typeof definition.tokenEnv !== 'string'
            || !/^FLUTTERFLOW_[A-Z0-9_]{1,96}$/.test(definition.tokenEnv)
            || !Array.isArray(definition.allowedProjectIds)
            || definition.allowedProjectIds.length === 0
            || !definition.allowedProjectIds.every((projectId) => (typeof projectId === 'string'
                && /^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$/.test(projectId)))) {
            throw new MissingConfigurationError('flutterflow', [
                'FLUTTERFLOW_ACCOUNTS_JSON entries with id, label, a FLUTTERFLOW_* tokenEnv, and valid allowedProjectIds',
            ]);
        }
        const baseUrl = definition.baseUrl || FLUTTERFLOW_API_ORIGIN;
        if (baseUrl !== FLUTTERFLOW_API_ORIGIN) {
            throw new MissingConfigurationError('flutterflow', [
                `baseUrl exactly equal to ${FLUTTERFLOW_API_ORIGIN}`,
            ]);
        }
        return {
            id: definition.id,
            label: definition.label,
            authMode: 'api_token',
            token: requiredEnvironmentValue('flutterflow', definition.tokenEnv),
            baseUrl,
            allowedProjectIds: definition.allowedProjectIds,
            grantedScopes: Array.isArray(definition.grantedScopes) ? definition.grantedScopes : [],
        };
    });
    return {
        accounts,
        timeoutMs: boundedIntegerEnvironment('flutterflow', 'FLUTTERFLOW_API_TIMEOUT_MS', 10000, 250, 30000),
        maxResponseBytes: boundedIntegerEnvironment('flutterflow', 'FLUTTERFLOW_API_MAX_RESPONSE_BYTES', 1000000, 1024, 2000000),
    };
}
function sanitizeProviderConnections(github, supabase, flutterflow) {
    return [
        {
            id: github.id,
            provider: 'github',
            label: github.label,
            account: github.login || github.id,
            mutations: github.allowMutations,
            scopes: [...github.grantedScopes],
            targets: {
                accounts: [github.login || github.id],
                repositories: [...github.allowedRepositories],
                organizations: [],
                projects: [],
            },
        },
        ...supabase.accounts.map((account) => ({
            id: account.id,
            provider: 'supabase',
            label: account.label,
            account: account.id,
            mutations: account.allowMutations,
            scopes: [...(account.grantedScopes || [])],
            targets: {
                accounts: [account.id],
                repositories: [],
                organizations: [...account.allowedOrganizationSlugs],
                projects: [...account.allowedProjectRefs],
            },
        })),
        ...(flutterflow?.accounts || []).map((account) => ({
            id: account.id,
            provider: 'flutterflow',
            label: account.label,
            account: account.id,
            mutations: false,
            scopes: [...(account.grantedScopes || [])],
            targets: {
                accounts: [account.id],
                repositories: [],
                organizations: [],
                projects: [...account.allowedProjectIds],
            },
        })),
    ];
}
async function buildProviderConnectionMetadata(context = {}) {
    const [github, supabase] = await Promise.all([
        buildGitHubConfiguration(context),
        buildSupabaseConfiguration(context),
    ]);
    let flutterflow;
    if (process.env.FLUTTERFLOW_ACCOUNTS_JSON?.trim()) {
        try {
            flutterflow = buildFlutterFlowEnvironmentConfiguration();
        }
        catch (error) {
            if (!(error instanceof MissingConfigurationError))
                throw error;
        }
    }
    return sanitizeProviderConnections(github, supabase, flutterflow);
}
function memoryNamespaces() {
    const configured = commaSeparatedEnvironment('PANDORA_MEMORY_ALLOWED_NAMESPACES');
    const values = configured.length > 0 ? configured : ['real_life'];
    const invalid = values.filter((value) => value !== 'real_life' && value !== 'au');
    if (invalid.length > 0) {
        throw new MissingConfigurationError('memory', [
            'valid PANDORA_MEMORY_ALLOWED_NAMESPACES (real_life,au)',
        ]);
    }
    return [...new Set(values)];
}
function memoryOrigin() {
    const baseUrl = process.env.PANDORA_MEMORY_BASE_URL?.trim() || DEFAULT_MEMORY_ORIGIN;
    let origin;
    try {
        origin = new URL(baseUrl);
    }
    catch {
        throw new MissingConfigurationError('memory', ['valid PANDORA_MEMORY_BASE_URL']);
    }
    if (origin.protocol !== 'https:'
        || origin.username
        || origin.password
        || origin.search
        || origin.hash
        || (origin.pathname !== '/' && origin.pathname !== '')) {
        throw new MissingConfigurationError('memory', [
            'PANDORA_MEMORY_BASE_URL as an HTTPS origin without credentials, path, query, or fragment',
        ]);
    }
    if (QUARANTINED_MEMORY_ORIGINS.has(origin.origin)) {
        throw new MissingConfigurationError('memory', [
            `PANDORA_MEMORY_BASE_URL that is not the quarantined legacy origin ${origin.origin}; the canonical origin is ${DEFAULT_MEMORY_ORIGIN}`,
        ]);
    }
    return origin.origin;
}
function memoryScopes() {
    const configured = commaSeparatedEnvironment('PANDORA_MEMORY_GRANTED_SCOPES');
    const scopes = configured.length > 0
        ? [...new Set(configured)]
        : ['memory:health', 'memory:read'];
    const invalid = scopes.filter((scope) => scope !== 'memory:health'
        && scope !== 'memory:read'
        && scope !== 'memory:write'
        && scope !== 'memory:evidence-candidate:submit');
    if (invalid.length > 0) {
        throw new MissingConfigurationError('memory', [
            'valid PANDORA_MEMORY_GRANTED_SCOPES (memory:health,memory:read,memory:write,memory:evidence-candidate:submit)',
        ]);
    }
    return scopes;
}
function memoryMutationsEnabled() {
    return process.env.PANDORA_MEMORY_ALLOW_MUTATIONS === 'true';
}
function buildMemoryConfiguration(context) {
    const oidcToken = context.vercelOidcToken?.trim()
        || process.env.VERCEL_OIDC_TOKEN?.trim();
    if (!oidcToken) {
        throw new MissingConfigurationError('memory', [
            'Vercel OIDC request token',
        ]);
    }
    if (oidcToken.length < 64) {
        throw new MissingConfigurationError('memory', [
            'valid Vercel OIDC request token',
        ]);
    }
    return {
        baseUrl: memoryOrigin(),
        oidcToken,
        allowedNamespaces: memoryNamespaces(),
        grantedScopes: memoryScopes(),
        allowMutations: memoryMutationsEnabled(),
        timeoutMs: boundedIntegerEnvironment('memory', 'PANDORA_MEMORY_TIMEOUT_MS', 8000, 250, 30000),
        maxResponseBytes: boundedIntegerEnvironment('memory', 'PANDORA_MEMORY_MAX_RESPONSE_BYTES', 500000, 1024, 2000000),
    };
}
async function buildToolConfiguration(toolName, context = {}) {
    const entry = tool_catalog_js_1.toolRegistry[toolName];
    if (!entry) {
        throw new UnknownToolError(toolName);
    }
    if (entry.handler === 'github') {
        return { github: await buildGitHubConfiguration(context) };
    }
    if (entry.handler === 'memory') {
        return { memory: buildMemoryConfiguration(context) };
    }
    if (entry.handler === 'flutterflow') {
        return { flutterflow: buildFlutterFlowEnvironmentConfiguration() };
    }
    return { supabase: await buildSupabaseConfiguration(context) };
}
function inspectToolConfiguration(toolName) {
    const entry = tool_catalog_js_1.toolRegistry[toolName];
    if (!entry)
        throw new UnknownToolError(toolName);
    try {
        if (entry.handler === 'github') {
            if (process.env.GITHUB_TOKEN?.trim()) {
                buildGitHubEnvironmentConfiguration();
                return { configured: true, missing: [] };
            }
            if (process.env.VERCEL === '1' || process.env.VERCEL_ENV || process.env.VERCEL_OIDC_TOKEN) {
                return { configured: true, missing: [] };
            }
            return {
                configured: false,
                missing: ['Vercel OIDC runtime or GITHUB_TOKEN'],
            };
        }
        if (entry.handler === 'memory') {
            memoryOrigin();
            memoryNamespaces();
            memoryScopes();
            memoryMutationsEnabled();
            boundedIntegerEnvironment('memory', 'PANDORA_MEMORY_TIMEOUT_MS', 8000, 250, 30000);
            boundedIntegerEnvironment('memory', 'PANDORA_MEMORY_MAX_RESPONSE_BYTES', 500000, 1024, 2000000);
            if (process.env.VERCEL === '1' || process.env.VERCEL_ENV || process.env.VERCEL_OIDC_TOKEN) {
                return { configured: true, missing: [] };
            }
            return {
                configured: false,
                missing: ['Vercel OIDC runtime'],
            };
        }
        if (entry.handler === 'flutterflow') {
            if (!process.env.FLUTTERFLOW_ACCOUNTS_JSON?.trim()) {
                return {
                    configured: false,
                    missing: ['FLUTTERFLOW_ACCOUNTS_JSON'],
                };
            }
            buildFlutterFlowEnvironmentConfiguration();
            return { configured: true, missing: [] };
        }
        if (process.env.SUPABASE_ACCOUNTS_JSON?.trim()) {
            buildSupabaseEnvironmentConfiguration();
            return { configured: true, missing: [] };
        }
        if (process.env.VERCEL === '1' || process.env.VERCEL_ENV || process.env.VERCEL_OIDC_TOKEN) {
            return { configured: true, missing: [] };
        }
        return {
            configured: false,
            missing: ['Vercel OIDC runtime or SUPABASE_ACCOUNTS_JSON'],
        };
    }
    catch (error) {
        if (error instanceof MissingConfigurationError) {
            return { configured: false, missing: error.missing };
        }
        throw error;
    }
}
//# sourceMappingURL=service-config.js.map
