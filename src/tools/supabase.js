"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.supabaseTools = exports.SupabaseMCPServer = exports.SupabaseManagementError = void 0;
exports.executeSupabaseTool = executeSupabaseTool;
const zod_1 = require("zod");
const MANAGEMENT_API_ORIGIN = 'https://api.supabase.com/v1';
const DEFAULT_TIMEOUT_MS = 10000;
const DEFAULT_MAX_RESPONSE_BYTES = 1000000;
const AccountConfigurationSchema = zod_1.z.object({
    id: zod_1.z.string().regex(/^[a-z][a-z0-9_-]{1,63}$/),
    label: zod_1.z.string().min(1).max(160),
    authMode: zod_1.z.enum(['pat', 'oauth']).default('pat'),
    token: zod_1.z.string().min(1),
    allowMutations: zod_1.z.boolean().default(false),
    allowedOrganizationSlugs: zod_1.z.array(zod_1.z.string().min(1)).default([]),
    allowedProjectRefs: zod_1.z.array(zod_1.z.string().regex(/^[a-z0-9]{20}$/)).default([]),
});
const RuntimeConfigurationSchema = zod_1.z.object({
    accounts: zod_1.z.array(AccountConfigurationSchema).min(1),
    timeoutMs: zod_1.z.number().int().min(1000).max(30000).default(DEFAULT_TIMEOUT_MS),
    maxResponseBytes: zod_1.z.number().int().min(1024).max(5000000).default(DEFAULT_MAX_RESPONSE_BYTES),
}).superRefine((value, context) => {
    const ids = new Set();
    for (const account of value.accounts) {
        if (ids.has(account.id)) {
            context.addIssue({
                code: zod_1.z.ZodIssueCode.custom,
                path: ['accounts'],
                message: `duplicate Supabase account id: ${account.id}`,
            });
        }
        ids.add(account.id);
    }
});
const OrganizationSchema = zod_1.z.object({
    id: zod_1.z.string(),
    slug: zod_1.z.string(),
    name: zod_1.z.string(),
}).passthrough();
const ProjectSchema = zod_1.z.object({
    id: zod_1.z.union([zod_1.z.string(), zod_1.z.number()]).optional(),
    ref: zod_1.z.string(),
    organization_id: zod_1.z.string().optional(),
    organization_slug: zod_1.z.string().optional(),
    name: zod_1.z.string(),
    region: zod_1.z.string().optional(),
    created_at: zod_1.z.string().optional(),
    status: zod_1.z.string().optional(),
    database: zod_1.z.object({
        host: zod_1.z.string().optional(),
        version: zod_1.z.string().optional(),
        postgres_engine: zod_1.z.string().optional(),
        release_channel: zod_1.z.string().optional(),
    }).passthrough().optional(),
}).passthrough();
const ProjectListSchema = zod_1.z.union([
    zod_1.z.array(ProjectSchema),
    zod_1.z.object({ projects: zod_1.z.array(ProjectSchema) }).passthrough(),
]);
const MigrationSchema = zod_1.z.object({
    version: zod_1.z.string().regex(/^\d{14}$/),
    name: zod_1.z.string().min(1).max(240),
}).passthrough();
const AccountArgsSchema = zod_1.z.object({
    accountId: zod_1.z.string().min(1),
});
const ListProjectsArgsSchema = AccountArgsSchema.extend({
    organizationSlug: zod_1.z.string().min(1).optional(),
});
const ProjectArgsSchema = AccountArgsSchema.extend({
    projectRef: zod_1.z.string().regex(/^[a-z0-9]{20}$/),
});
const MutationArgsSchema = ProjectArgsSchema.extend({
    confirmation: zod_1.z.string().min(1),
});
function normalizeProject(project) {
    return {
        id: project.id,
        ref: project.ref,
        organizationId: project.organization_id,
        organizationSlug: project.organization_slug,
        name: project.name,
        region: project.region,
        createdAt: project.created_at,
        status: project.status,
        database: project.database ? {
            host: project.database.host,
            version: project.database.version,
            postgresEngine: project.database.postgres_engine,
            releaseChannel: project.database.release_channel,
        } : undefined,
    };
}
class SupabaseManagementError extends Error {
    constructor(message, status) {
        super(message);
        this.name = 'SupabaseManagementError';
        this.status = status;
    }
}
exports.SupabaseManagementError = SupabaseManagementError;
class SupabaseMCPServer {
    constructor(configuration, fetchFn = globalThis.fetch) {
        this.config = RuntimeConfigurationSchema.parse(configuration);
        this.fetchFn = fetchFn;
    }
    listAccounts() {
        return this.config.accounts.map((account) => ({
            id: account.id,
            label: account.label,
            authMode: account.authMode,
            allowMutations: account.allowMutations,
            allowedOrganizationSlugs: account.allowedOrganizationSlugs,
            allowedProjectRefs: account.allowedProjectRefs,
            credentialConfigured: Boolean(account.token),
        }));
    }
    async listOrganizations(accountId) {
        const account = this.account(accountId);
        const data = await this.request(account, '/organizations', 'GET');
        const organizations = zod_1.z.array(OrganizationSchema).parse(data);
        return organizations
            .filter((organization) => account.allowedOrganizationSlugs.includes(organization.slug))
            .map((organization) => ({
            id: organization.id,
            slug: organization.slug,
            name: organization.name,
        }));
    }
    async listProjects(accountId, organizationSlug) {
        const account = this.account(accountId);
        if (organizationSlug
            && (account.allowedOrganizationSlugs.length === 0
                || !account.allowedOrganizationSlugs.includes(organizationSlug))) {
            throw new SupabaseManagementError(`Supabase account ${account.id} is not allowed to access organization ${organizationSlug}`, 403);
        }
        if (!organizationSlug
            && account.allowedOrganizationSlugs.length === 0
            && account.allowedProjectRefs.length === 0) {
            throw new SupabaseManagementError(`Supabase account ${account.id} has no allowlisted projects or organizations`, 403);
        }
        const path = organizationSlug
            ? `/organizations/${encodeURIComponent(organizationSlug)}/projects?offset=0&limit=100`
            : '/projects';
        const data = ProjectListSchema.parse(await this.request(account, path, 'GET'));
        const projects = Array.isArray(data) ? data : data.projects;
        return projects
            .filter((project) => this.projectAllowed(account, project.ref, project.organization_slug))
            .map(normalizeProject);
    }
    async getProject(accountId, projectRef) {
        const account = this.account(accountId);
        this.assertProjectRefAllowed(account, projectRef);
        const project = ProjectSchema.parse(await this.request(account, `/projects/${encodeURIComponent(projectRef)}`, 'GET'));
        if (!this.projectAllowed(account, project.ref, project.organization_slug)) {
            throw new SupabaseManagementError(`Supabase account ${account.id} is not allowed to access project ${projectRef}`, 403);
        }
        return normalizeProject(project);
    }
    async listMigrations(accountId, projectRef) {
        const account = this.account(accountId);
        this.assertProjectRefAllowed(account, projectRef);
        const migrations = zod_1.z.array(MigrationSchema).max(10000).parse(await this.request(account, `/projects/${encodeURIComponent(projectRef)}/database/migrations`, 'GET'));
        const versions = new Set();
        for (const migration of migrations) {
            if (versions.has(migration.version)) {
                throw new SupabaseManagementError(`Supabase returned duplicate migration version ${migration.version}`, 502);
            }
            versions.add(migration.version);
        }
        return migrations.map((migration) => ({ version: migration.version, name: migration.name }));
    }
    async pauseProject(accountId, projectRef, confirmation) {
        const account = this.account(accountId);
        this.assertMutationAllowed(account);
        this.assertConfirmation(confirmation, `PAUSE ${projectRef}`);
        await this.ensureProjectAllowed(account, projectRef);
        await this.request(account, `/projects/${encodeURIComponent(projectRef)}/pause`, 'POST');
        return { accountId, projectRef, status: 'pause-requested' };
    }
    async restoreProject(accountId, projectRef, confirmation) {
        const account = this.account(accountId);
        this.assertMutationAllowed(account);
        this.assertConfirmation(confirmation, `RESTORE ${projectRef}`);
        await this.ensureProjectAllowed(account, projectRef);
        await this.request(account, `/projects/${encodeURIComponent(projectRef)}/restore`, 'POST');
        return { accountId, projectRef, status: 'restore-requested' };
    }
    account(accountId) {
        const account = this.config.accounts.find((candidate) => candidate.id === accountId);
        if (!account) {
            throw new SupabaseManagementError(`Unknown Supabase account: ${accountId}`, 404);
        }
        return account;
    }
    assertMutationAllowed(account) {
        if (!account.allowMutations) {
            throw new SupabaseManagementError(`Mutations are disabled for Supabase account ${account.id}`, 403);
        }
    }
    assertConfirmation(actual, expected) {
        if (actual !== expected) {
            throw new SupabaseManagementError(`Confirmation must exactly equal "${expected}"`, 400);
        }
    }
    assertProjectRefAllowed(account, projectRef) {
        if ((account.allowedProjectRefs.length === 0 && account.allowedOrganizationSlugs.length === 0)
            || (account.allowedProjectRefs.length > 0 && !account.allowedProjectRefs.includes(projectRef))) {
            throw new SupabaseManagementError(`Supabase account ${account.id} is not allowed to access project ${projectRef}`, 403);
        }
    }
    projectAllowed(account, projectRef, organizationSlug) {
        if (account.allowedProjectRefs.length === 0
            && account.allowedOrganizationSlugs.length === 0) {
            return false;
        }
        if (account.allowedProjectRefs.length > 0
            && !account.allowedProjectRefs.includes(projectRef)) {
            return false;
        }
        if (account.allowedOrganizationSlugs.length > 0
            && (!organizationSlug || !account.allowedOrganizationSlugs.includes(organizationSlug))) {
            return false;
        }
        return true;
    }
    async ensureProjectAllowed(account, projectRef) {
        this.assertProjectRefAllowed(account, projectRef);
        if (account.allowedOrganizationSlugs.length === 0) {
            return;
        }
        const project = ProjectSchema.parse(await this.request(account, `/projects/${encodeURIComponent(projectRef)}`, 'GET'));
        if (!this.projectAllowed(account, project.ref, project.organization_slug)) {
            throw new SupabaseManagementError(`Supabase account ${account.id} is not allowed to mutate project ${projectRef}`, 403);
        }
    }
    async request(account, path, method) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), this.config.timeoutMs);
        try {
            const response = await this.fetchFn(`${MANAGEMENT_API_ORIGIN}${path}`, {
                method,
                headers: {
                    Authorization: `Bearer ${account.token}`,
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'User-Agent': 'MCPMaster-Supabase-Control/1.0',
                },
                signal: controller.signal,
                redirect: 'error',
            });
            const declaredLength = Number(response.headers?.get('content-length') || '0');
            if (declaredLength > this.config.maxResponseBytes) {
                throw new SupabaseManagementError('Supabase Management API response exceeded size limit');
            }
            const text = await response.text();
            if (Buffer.byteLength(text, 'utf8') > this.config.maxResponseBytes) {
                throw new SupabaseManagementError('Supabase Management API response exceeded size limit');
            }
            if (!response.ok) {
                throw new SupabaseManagementError(`Supabase Management API request failed with ${response.status}`, response.status);
            }
            if (!text.trim()) {
                return {};
            }
            try {
                return JSON.parse(text);
            }
            catch {
                throw new SupabaseManagementError('Supabase Management API returned invalid JSON');
            }
        }
        catch (error) {
            if (error instanceof SupabaseManagementError) {
                throw error;
            }
            if (error instanceof Error && error.name === 'AbortError') {
                throw new SupabaseManagementError('Supabase Management API request timed out');
            }
            throw new SupabaseManagementError(`Supabase Management API request failed: ${error instanceof Error ? error.message : 'unknown error'}`);
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
exports.SupabaseMCPServer = SupabaseMCPServer;
exports.supabaseTools = {
    'supabase.list-accounts': {
        description: 'List configured Supabase account connections without exposing credentials',
        parameters: {
            type: 'object',
            properties: {},
        },
    },
    'supabase.list-organizations': {
        description: 'List organizations visible to one configured Supabase account',
        parameters: {
            type: 'object',
            properties: {
                accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' },
            },
            required: ['accountId'],
        },
    },
    'supabase.list-projects': {
        description: 'List projects visible to one configured Supabase account',
        parameters: {
            type: 'object',
            properties: {
                accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' },
                organizationSlug: { type: 'string', description: 'Optional exact organization slug' },
            },
            required: ['accountId'],
        },
    },
    'supabase.get-project': {
        description: 'Get one exact Supabase project through a selected account',
        parameters: {
            type: 'object',
            properties: {
                accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' },
                projectRef: { type: 'string', description: 'Exact 20-character Supabase project ref' },
            },
            required: ['accountId', 'projectRef'],
        },
    },
    'supabase.pause-project': {
        description: 'Pause one exact Supabase project; requires MCPMaster approval and account mutation enablement',
        parameters: {
            type: 'object',
            properties: {
                accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' },
                projectRef: { type: 'string', description: 'Exact 20-character Supabase project ref' },
                confirmation: { type: 'string', description: 'Must exactly equal PAUSE <projectRef>' },
            },
            required: ['accountId', 'projectRef', 'confirmation'],
        },
    },
    'supabase.restore-project': {
        description: 'Restore one exact paused Supabase project; requires MCPMaster approval and account mutation enablement',
        parameters: {
            type: 'object',
            properties: {
                accountId: { type: 'string', description: 'Configured MCPMaster Supabase account ID' },
                projectRef: { type: 'string', description: 'Exact 20-character Supabase project ref' },
                confirmation: { type: 'string', description: 'Must exactly equal RESTORE <projectRef>' },
            },
            required: ['accountId', 'projectRef', 'confirmation'],
        },
    },
};
async function executeSupabaseTool(tool, args, configuration, fetchFn) {
    const supabase = new SupabaseMCPServer(configuration, fetchFn);
    switch (tool) {
        case 'supabase.list-accounts':
            return supabase.listAccounts();
        case 'supabase.list-organizations': {
            const input = AccountArgsSchema.parse(args);
            return supabase.listOrganizations(input.accountId);
        }
        case 'supabase.list-projects': {
            const input = ListProjectsArgsSchema.parse(args);
            return supabase.listProjects(input.accountId, input.organizationSlug);
        }
        case 'supabase.get-project': {
            const input = ProjectArgsSchema.parse(args);
            return supabase.getProject(input.accountId, input.projectRef);
        }
        case 'supabase.pause-project': {
            const input = MutationArgsSchema.parse(args);
            return supabase.pauseProject(input.accountId, input.projectRef, input.confirmation);
        }
        case 'supabase.restore-project': {
            const input = MutationArgsSchema.parse(args);
            return supabase.restoreProject(input.accountId, input.projectRef, input.confirmation);
        }
        default:
            throw new SupabaseManagementError(`Unknown Supabase tool: ${tool}`, 404);
    }
}
//# sourceMappingURL=supabase.js.map
