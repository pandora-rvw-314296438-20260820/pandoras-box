"use strict";

const C = require("./contracts");

const id = { type: "string", minLength: 1, maxLength: 128, format: "id" };
const env = { type: "string", enum: ["development", "preview", "production"] };
const path = { type: "string", minLength: 1, maxLength: 1024, format: "project-path" };
const artifact = { type: "string", minLength: 12, maxLength: 300, format: "artifact-ref" };
const domain = { type: "string", minLength: 1, maxLength: 253, format: "domain" };
const digest = { type: "string", minLength: 64, maxLength: 64, pattern: "^[0-9a-f]{64}$" };
const idem = { type: "string", minLength: 8, maxLength: 200, format: "idempotency-key" };

function object(properties, required = Object.keys(properties)) {
  return { type: "object", properties, required, additionalProperties: false };
}
const base = { project_id: id, environment: env };
const mutation = { request_id: idem, idempotency_key: idem };
const statusOutput = object({ status: { type: "string", minLength: 1, maxLength: 64 } });

function tool(name, description, inputSchema, capabilities, executor, options = {}) {
  return Object.freeze({
    name, version: 1, key: `${name}@1`, description, inputSchema,
    outputSchema: options.outputSchema || statusOutput,
    capabilityRequirements: Object.freeze([...capabilities]),
    allowedEnvironments: Object.freeze(options.environments || ["development", "preview", "production"]),
    defaultRisk: options.risk || C.RISK_LEVELS.LOW,
    idempotency: options.idempotency || C.IDEMPOTENCY_MODES.NONE,
    approval: options.approval || C.APPROVAL_MODES.NONE,
    timeoutMs: options.timeoutMs || 30_000,
    maxPayloadBytes: options.maxPayloadBytes || 64 * 1024,
    sideEffect: options.sideEffect || C.SIDE_EFFECTS.READ,
    retry: options.retry || C.RETRY_MODES.SAFE_RETRY,
    executor,
    expensive: options.expensive === true,
  });
}
function mut(name, description, schema, capabilities, executor, options = {}) {
  return tool(name, description, object({ ...base, ...schema, ...mutation }), capabilities, executor, {
    risk: C.RISK_LEVELS.MEDIUM,
    idempotency: C.IDEMPOTENCY_MODES.REQUIRED,
    approval: C.APPROVAL_MODES.POLICY,
    sideEffect: C.SIDE_EFFECTS.PROJECT_MUTATION,
    retry: C.RETRY_MODES.IDEMPOTENT_RETRY,
    ...options,
  });
}

const d = [
  tool("get_project", "Read project metadata", object(base), ["project.read"], "ProjectContextExecutor"),
  tool("get_project_spec", "Read current immutable ProjectSpec", object(base), ["project.read"], "ProjectContextExecutor"),
  tool("get_project_context", "Read bounded project context", object({ ...base, context_kinds: { type: "array", items: { type: "string", enum: ["requirements", "files", "schema", "history", "verification"] }, minItems: 1, maxItems: 10 } }), ["project.read"], "ProjectContextExecutor"),

  tool("list_files", "List authorized project files", object({ ...base, path }), ["workspace.files.read"], "WorkspaceExecutor"),
  tool("read_file", "Read an authorized project file", object({ ...base, path }), ["workspace.files.read"], "WorkspaceExecutor", { maxPayloadBytes: 16 * 1024 }),
  mut("write_file", "Write artifact-backed project content", { path, content_ref: artifact }, ["workspace.files.write"], "WorkspaceExecutor"),
  mut("delete_file", "Delete an authorized project file", { path }, ["workspace.files.delete"], "WorkspaceExecutor"),
  mut("move_file", "Move a project file within authorized paths", { from_path: path, to_path: path }, ["workspace.files.write", "workspace.files.delete"], "WorkspaceExecutor"),

  tool("inspect_schema", "Inspect database schema metadata", object(base), ["database.inspect"], "DatabaseExecutor"),
  tool("query_schema", "Run a bounded structured read query", object({ ...base, query: object({ operation: { type: "string", enum: ["select"] }, table: id, columns: { type: "array", items: id, minItems: 1, maxItems: 50 }, limit: { type: "integer", minimum: 1, maximum: 500 } }, ["operation", "table", "columns"]) }), ["database.inspect"], "DatabaseExecutor", { maxPayloadBytes: 32 * 1024 }),
  mut("request_migration", "Request governed migration preflight", { migration_ref: artifact, migration_kind: { type: "string", enum: ["schema_change", "data_change", "rls_policy", "index", "constraint"] }, destructive: { type: "boolean" } }, ["database.migration.request"], "DatabaseExecutor", { sideEffect: C.SIDE_EFFECTS.EXTERNAL_MUTATION, expensive: true }),
  tool("inspect_migration_result", "Inspect migration result", object({ ...base, migration_execution_id: id }), ["database.inspect"], "DatabaseExecutor"),

  mut("request_build", "Request bounded project build", { version_id: id }, ["build.execute"], "BuildExecutor", { risk: C.RISK_LEVELS.LOW, approval: C.APPROVAL_MODES.NONE, sideEffect: C.SIDE_EFFECTS.EXTERNAL_MUTATION, expensive: true }),
  tool("get_build_status", "Read build status", object({ ...base, build_id: id }), ["build.execute"], "BuildExecutor"),
  tool("inspect_build_error", "Read normalized build diagnostics", object({ ...base, build_id: id }), ["build.execute"], "BuildExecutor"),
  mut("request_tests", "Request project tests", { version_id: id, test_profile: { type: "string", enum: ["unit", "integration", "full"] } }, ["test.execute"], "VerificationExecutor", { risk: C.RISK_LEVELS.LOW, approval: C.APPROVAL_MODES.NONE, sideEffect: C.SIDE_EFFECTS.EXTERNAL_MUTATION, expensive: true }),
  tool("get_test_results", "Read normalized test results", object({ ...base, test_run_id: id }), ["test.execute"], "VerificationExecutor"),

  mut("create_preview", "Create disposable exact-version preview", { version_id: id, artifact_digest: digest }, ["preview.create"], "PreviewExecutor", { risk: C.RISK_LEVELS.LOW, approval: C.APPROVAL_MODES.NONE, environments: ["development", "preview"], sideEffect: C.SIDE_EFFECTS.EXTERNAL_MUTATION, expensive: true }),
  tool("inspect_preview", "Inspect preview state", object({ ...base, preview_id: id }), ["preview.inspect"], "PreviewExecutor"),
  mut("request_publish", "Publish exact verified immutable version", { version_id: id, verification_run_id: id, preview_id: id, artifact_digest: digest, target_environment: { type: "string", enum: ["production"] } }, ["production.publish"], "DeploymentExecutor", { risk: C.RISK_LEVELS.HIGH, approval: C.APPROVAL_MODES.REQUIRED, environments: ["production"], sideEffect: C.SIDE_EFFECTS.PRODUCTION_MUTATION, expensive: true }),
  tool("get_deployment_status", "Read normalized deployment state", object({ ...base, deployment_id: id }), ["production.publish"], "DeploymentExecutor"),
  mut("request_domain_attach", "Attach or change canonical hostname", { hostname: domain, target_environment: { type: "string", enum: ["preview", "production"] }, deployment_id: id }, ["domain.attach"], "DomainExecutor", { risk: C.RISK_LEVELS.HIGH, approval: C.APPROVAL_MODES.REQUIRED, sideEffect: C.SIDE_EFFECTS.PRODUCTION_MUTATION }),
  tool("inspect_domain_status", "Inspect domain state", object({ ...base, hostname: domain }), ["domain.attach"], "DomainExecutor"),

  mut("create_artifact", "Create project-scoped immutable artifact metadata", { content_type: { type: "string", minLength: 1, maxLength: 120 }, content_digest: digest, size_bytes: { type: "integer", minimum: 0, maximum: 50 * 1024 * 1024 } }, ["artifact.write"], "ArtifactExecutor"),
  tool("read_artifact_metadata", "Read project-scoped artifact metadata", object({ ...base, artifact_ref: artifact }), ["project.read"], "ArtifactExecutor"),
];

const TOOL_REGISTRY = Object.freeze(Object.fromEntries(d.map((value) => [value.name, value])));
function getToolDefinition(name, version = 1) {
  const value = TOOL_REGISTRY[name];
  return value?.version === version ? value : undefined;
}
function listToolDefinitions() { return Object.values(TOOL_REGISTRY); }

module.exports = { TOOL_REGISTRY, getToolDefinition, listToolDefinitions };
