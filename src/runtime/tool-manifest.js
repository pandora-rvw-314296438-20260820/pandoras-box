"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.toolManifests = void 0;
exports.getToolManifest = getToolManifest;
exports.expectedConfirmation = expectedConfirmation;
exports.assertManifestConfirmation = assertManifestConfirmation;
exports.highImpactReason = highImpactReason;
exports.assertHighImpactPolicy = assertHighImpactPolicy;
function manifest(name, provider, risk, mutation, scope, requiredProviderScopes, options = {}) {
    return {
        name,
        provider,
        risk,
        mutation,
        scope,
        requiredProviderScopes,
        responsePolicy: 'redact-sensitive',
        ...options,
    };
}
const entries = [
    manifest('github.get-repository', 'github', 'read', false, 'repository', ['repositories:read']),
    manifest('github.list-repositories', 'github', 'read', false, 'account', ['repositories:read']),
    manifest('github.get-issue', 'github', 'read', false, 'repository', ['issues:read']),
    manifest('github.list-issues', 'github', 'read', false, 'repository', ['issues:read']),
    manifest('github.create-issue', 'github', 'write', true, 'repository', ['issues:write']),
    manifest('github.update-issue', 'github', 'write', true, 'repository', ['issues:write']),
    manifest('github.get-pull-request', 'github', 'read', false, 'repository', ['pull_requests:read']),
    manifest('github.list-pull-requests', 'github', 'read', false, 'repository', ['pull_requests:read']),
    manifest('github.create-pull-request', 'github', 'write', true, 'repository', ['pull_requests:write']),
    manifest('github.merge-pull-request', 'github', 'destructive', true, 'repository', ['pull_requests:write']),
    manifest('github.list-workflow-runs', 'github', 'read', false, 'repository', ['workflows:read']),
    manifest('github.get-workflow-run', 'github', 'read', false, 'repository', ['workflows:read']),
    manifest('github.search-repositories', 'github', 'read', false, 'account', ['repositories:read']),
    manifest('github.search-issues', 'github', 'read', false, 'account', ['issues:read', 'pull_requests:read']),
    manifest('github.get-me', 'github', 'read', false, 'account', ['identity:read']),
    manifest('github.read-repository-api', 'github', 'read', false, 'repository', ['repositories:read'], { confirmationKind: 'github-repository-api', highImpactCapable: false }),
    manifest('github.write-repository-api', 'github', 'write', true, 'repository', ['repositories:write'], { confirmationKind: 'github-repository-api', highImpactCapable: true }),
    manifest('github.delete-repository-api', 'github', 'destructive', true, 'repository', ['repositories:write'], { confirmationKind: 'github-repository-api', highImpactCapable: true }),
    manifest('supabase.list-accounts', 'supabase', 'read', false, 'account', []),
    manifest('supabase.list-organizations', 'supabase', 'read', false, 'account', ['organizations:read']),
    manifest('supabase.list-projects', 'supabase', 'read', false, 'organization', ['projects:read']),
    manifest('supabase.get-project', 'supabase', 'read', false, 'project', ['projects:read']),
    manifest('supabase.get-auth-security-config', 'supabase', 'read', false, 'project', ['auth:read']),
    manifest('supabase.enable-leaked-password-protection', 'supabase', 'write', true, 'project', ['auth:read', 'auth:write']),
    manifest('supabase.pause-project', 'supabase', 'destructive', true, 'project', ['projects:write']),
    manifest('supabase.restore-project', 'supabase', 'write', true, 'project', ['projects:write']),
    manifest('supabase.read-project-api', 'supabase', 'read', false, 'project', ['projects:read'], { confirmationKind: 'supabase-project-api' }),
    manifest('supabase.write-project-api', 'supabase', 'write', true, 'project', ['projects:write'], { confirmationKind: 'supabase-project-api', highImpactCapable: true }),
    manifest('supabase.delete-project-api', 'supabase', 'destructive', true, 'project', ['projects:write'], { confirmationKind: 'supabase-project-api', highImpactCapable: true }),
    manifest('supabase.read-organization-api', 'supabase', 'read', false, 'organization', ['organizations:read'], { confirmationKind: 'supabase-organization-api' }),
    manifest('supabase.write-organization-api', 'supabase', 'write', true, 'organization', ['organizations:write'], { confirmationKind: 'supabase-organization-api', highImpactCapable: true }),
    manifest('supabase.delete-organization-api', 'supabase', 'destructive', true, 'organization', ['organizations:write'], { confirmationKind: 'supabase-organization-api', highImpactCapable: true }),
    manifest('supabase.read-branch-api', 'supabase', 'read', false, 'branch', ['projects:read'], { confirmationKind: 'supabase-branch-api' }),
    manifest('supabase.write-branch-api', 'supabase', 'write', true, 'branch', ['projects:write'], { confirmationKind: 'supabase-branch-api' }),
    manifest('supabase.delete-branch-api', 'supabase', 'destructive', true, 'branch', ['projects:write'], { confirmationKind: 'supabase-branch-api' }),
    manifest('flutterflow.list-accounts', 'flutterflow', 'read', false, 'account', []),
    manifest('flutterflow.list-projects', 'flutterflow', 'read', false, 'account', ['projects:read']),
    manifest('flutterflow.inspect-readiness', 'flutterflow', 'read', false, 'project', ['projects:read', 'project_schema:read']),
    manifest('memory.health', 'memory', 'read', false, 'capability', ['memory:health']),
    manifest('memory.search', 'memory', 'read', false, 'capability', ['memory:read']),
    manifest('memory.canonicalContext', 'memory', 'read', false, 'capability', ['memory:read']),
    manifest('memory.submitEvidenceCandidate', 'memory', 'write', true, 'project', ['memory:evidence-candidate:submit']),
];
exports.toolManifests = Object.freeze(Object.fromEntries(entries.map((entry) => [entry.name, Object.freeze(entry)])));
function getToolManifest(toolName) {
    return exports.toolManifests[toolName];
}
function pathSegments(args) {
    return Array.isArray(args.pathSegments)
        ? args.pathSegments.filter((value) => typeof value === 'string')
        : [];
}
function renderedPath(args) {
    const segments = pathSegments(args);
    return segments.length > 0 ? `/${segments.join('/')}` : '';
}
function expectedConfirmation(toolName, args) {
    const tool = getToolManifest(toolName);
    if (!tool?.confirmationKind || !tool.mutation)
        return undefined;
    const method = tool.risk === 'destructive'
        ? 'DELETE'
        : typeof args.method === 'string'
            ? args.method
            : undefined;
    const suffix = renderedPath(args);
    switch (tool.confirmationKind) {
        case 'github-repository-api': {
            const owner = typeof args.owner === 'string' ? args.owner : undefined;
            const repo = typeof args.repo === 'string' ? args.repo : undefined;
            return method && owner && repo ? `${method} ${owner}/${repo}${suffix}` : undefined;
        }
        case 'supabase-project-api': {
            const projectRef = typeof args.projectRef === 'string' ? args.projectRef : undefined;
            return method && projectRef ? `${method} PROJECT ${projectRef}${suffix}` : undefined;
        }
        case 'supabase-organization-api': {
            const organizationSlug = typeof args.organizationSlug === 'string'
                ? args.organizationSlug
                : undefined;
            return method && organizationSlug
                ? `${method} ORGANIZATION ${organizationSlug}${suffix}`
                : undefined;
        }
        case 'supabase-branch-api': {
            const projectRef = typeof args.projectRef === 'string' ? args.projectRef : undefined;
            const branchIdOrRef = typeof args.branchIdOrRef === 'string' ? args.branchIdOrRef : undefined;
            return method && projectRef && branchIdOrRef
                ? `${method} BRANCH ${projectRef}:${branchIdOrRef}${suffix}`
                : undefined;
        }
        default:
            return undefined;
    }
}
function assertManifestConfirmation(toolName, args) {
    const tool = getToolManifest(toolName);
    if (!tool?.mutation || !tool.confirmationKind)
        return;
    const expected = expectedConfirmation(toolName, args);
    if (!expected || args.confirmation !== expected) {
        throw new Error(expected
            ? `Confirmation must exactly equal "${expected}"`
            : 'Provider action confirmation could not be validated');
    }
}
function normalizedPath(args) {
    return pathSegments(args).map((segment) => segment.toLowerCase()).join('/');
}
function highImpactReason(toolName, args) {
    const tool = getToolManifest(toolName);
    if (!tool?.highImpactCapable || !tool.mutation)
        return undefined;
    const path = normalizedPath(args);
    const segments = path ? path.split('/') : [];
    if (tool.provider === 'github') {
        if (tool.risk === 'destructive' && segments.length === 0)
            return 'repository deletion';
        if (segments[0] === 'transfer')
            return 'repository transfer';
        if (path.startsWith('actions/permissions'))
            return 'GitHub Actions permission changes';
        if (segments.includes('secrets'))
            return 'repository or environment secret changes';
        if (path.endsWith('/protection') && tool.risk === 'destructive')
            return 'branch protection removal';
        if (path === 'pages' && tool.risk === 'destructive')
            return 'GitHub Pages deletion';
    }
    if (tool.provider === 'supabase') {
        if (tool.scope === 'project' && tool.risk === 'destructive' && segments.length === 0) {
            return 'Supabase project deletion';
        }
        if (tool.scope === 'organization' && tool.risk === 'destructive' && segments.length === 0) {
            return 'Supabase organization deletion';
        }
        if (segments.some((segment) => ['secrets', 'api-keys', 'password'].includes(segment))) {
            return 'Supabase credential or secret changes';
        }
        if (path.includes('network-restrictions') || path.includes('ssl-enforcement')) {
            return 'Supabase network security changes';
        }
    }
    return undefined;
}
function assertHighImpactPolicy(toolName, args, breakGlassEnabled = process.env.MCPMASTER_BREAK_GLASS_MUTATIONS === 'true') {
    const reason = highImpactReason(toolName, args);
    if (reason && !breakGlassEnabled) {
        throw new Error(`${reason} is disabled by default; set MCPMASTER_BREAK_GLASS_MUTATIONS=true for an explicitly supervised operation`);
    }
}
//# sourceMappingURL=tool-manifest.js.map
