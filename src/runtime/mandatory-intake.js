"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ProjectOSExecutionIntakeProvider = void 0;
exports.buildExecutionIntakeRequest = buildExecutionIntakeRequest;
exports.shouldEnforceMandatoryIntake = shouldEnforceMandatoryIntake;
const zod_1 = require("zod");
const control_client_js_1 = require("../projectos/control-client.js");
const source_authority_js_1 = require("./source-authority.js");
const RepositorySchema = zod_1.z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/);
const ProjectKeySchema = zod_1.z.string().regex(/^[a-z0-9][a-z0-9._-]{0,79}$/);
const IntakeResultSchema = zod_1.z.object({
    intake: zod_1.z.object({
        id: zod_1.z.string().uuid(),
        project_id: zod_1.z.string().uuid(),
        status: zod_1.z.enum(['accepted', 'analyzing', 'planned', 'executing', 'completed', 'blocked', 'rejected']),
        idempotency_key: zod_1.z.string().min(1),
    }).passthrough(),
    project: zod_1.z.object({
        id: zod_1.z.string().uuid(),
        project_key: ProjectKeySchema,
        name: zod_1.z.string().min(1),
        repository: RepositorySchema.nullable().optional(),
    }).passthrough(),
});
const STRUCTURAL_PROJECT_KEYS = [
    'projectKey', 'project_key', 'project',
];
const STRUCTURAL_REPOSITORY_KEYS = [
    'repository_full_name', 'repository',
];
function boundedStructuralString(value, maximum = 240) {
    if (typeof value !== 'string')
        return undefined;
    const normalized = value.replace(/\s+/g, ' ').trim();
    if (!normalized || normalized.length > maximum)
        return undefined;
    return normalized;
}
function repositoryFromArgs(args) {
    for (const key of STRUCTURAL_REPOSITORY_KEYS) {
        const candidate = boundedStructuralString(args[key]);
        if (candidate && RepositorySchema.safeParse(candidate).success)
            return candidate;
    }
    const owner = boundedStructuralString(args.owner);
    const repo = boundedStructuralString(args.repo);
    if (owner && repo) {
        const combined = `${owner}/${repo}`;
        if (RepositorySchema.safeParse(combined).success)
            return combined;
    }
    return undefined;
}
function projectKeyFromArgs(args) {
    for (const key of STRUCTURAL_PROJECT_KEYS) {
        const candidate = boundedStructuralString(args[key])?.toLowerCase();
        if (candidate && ProjectKeySchema.safeParse(candidate).success)
            return candidate;
    }
    return undefined;
}
function projectName(repository, projectKey) {
    if (repository)
        return repository.split('/')[1];
    if (projectKey)
        return projectKey.replace(/[-_.]+/g, ' ');
    return undefined;
}
function requestType(tool) {
    if (/(deploy|release|rollback|promote)/i.test(tool))
        return 'release';
    if (/(incident|outage|restore|recover)/i.test(tool))
        return 'incident';
    if (/(audit|inspect|search|list|get|read)/i.test(tool))
        return 'research';
    return 'work';
}
function buildExecutionIntakeRequest(input) {
    const repository = repositoryFromArgs(input.args);
    if (repository)
        (0, source_authority_js_1.assertOperationalRepository)(repository, 'create new work for');
    const explicitProjectKey = projectKeyFromArgs(input.args);
    const fallbackProjectKey = repository ? undefined : 'mcpmaster-pandoras-box';
    const resolvedProjectKey = explicitProjectKey ?? fallbackProjectKey;
    const target = repository ?? resolvedProjectKey ?? 'projectos-inbox';
    return {
        requestText: `Execute ${input.tool} for ${target}.`,
        projectKey: resolvedProjectKey,
        projectName: projectName(repository, resolvedProjectKey),
        repository,
        requestType: requestType(input.tool),
        source: 'system',
        idempotencyKey: `execution:${input.requestId}`,
    };
}
class ProjectOSExecutionIntakeProvider {
    constructor(client = new control_client_js_1.ProjectOSControlClient()) {
        this.client = client;
    }
    async accept(vercelOidcToken, input) {
        const request = buildExecutionIntakeRequest(input);
        const parsed = IntakeResultSchema.parse(await this.client.acceptIntake(vercelOidcToken, request));
        if (!['accepted', 'analyzing', 'planned', 'executing'].includes(parsed.intake.status)) {
            throw new Error(`ProjectOS intake is not executable from status ${parsed.intake.status}`);
        }
        return {
            intakeId: parsed.intake.id,
            projectId: parsed.project.id,
            projectKey: parsed.project.project_key,
            projectName: parsed.project.name,
            ...(parsed.project.repository ? { repository: parsed.project.repository } : {}),
            status: parsed.intake.status,
            idempotencyKey: parsed.intake.idempotency_key,
        };
    }
}
exports.ProjectOSExecutionIntakeProvider = ProjectOSExecutionIntakeProvider;
function shouldEnforceMandatoryIntake() {
    if (process.env.PROJECTOS_MANDATORY_INTAKE_ENABLED === 'false')
        return false;
    return process.env.VERCEL === '1' && process.env.VERCEL_ENV === 'production';
}
//# sourceMappingURL=mandatory-intake.js.map
