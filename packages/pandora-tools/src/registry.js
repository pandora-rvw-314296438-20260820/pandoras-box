"use strict";

const { RISK_LEVELS, RETRY_MODES, IDEMPOTENCY_MODES, SIDE_EFFECTS, APPROVAL_MODES } = require("./contracts");

const id = { type: "string", minLength: 1, maxLength: 128, format: "id" };
const environment = { type: "string", enum: ["development", "preview", "production"] };
const pathField = { type: "string", minLength: 1, maxLength: 1024, format: "project-path" };
const artifactRef = { type: "string", minLength: 12, maxLength: 300, format: "artifact-ref" };
const domain = { type: "string", minLength: 1, maxLength: 253, format: "domain" };

function object(properties, required = Object.keys(properties)) {
  return { type: "object", properties, required, additionalProperties: false };
}

function def(name, description, inputSchema, {
  outputSchema = object({ status: { type: "string", minLength: 1, maxLength: 64 } }),
  capabilities = [],
  environments = ["development", "preview", "production"],
  risk = RISK_LEVELS.LOW,
  idempotency = IDEMPOTENCY_MODES.NONE,
  approval = APPROVAL_MODES.NONE,
  timeoutMs = 30_000,
  maxPayloadBytes = 64 * 1024,
  sideEffect = SIDE_EFFECTS.READ,
  retry = RETRY_MODES.SAFE_RETRY,
  executor,
  expensive = false,
} = {}) {
  return Object.freeze({
    name,
    version: 1,
    key: `${name}@1`,
    description,
    inputSchema,
    outputSchema,
    capabilityRequirements: Object.freeze([...capabilities]),
    allowedEnvironments: Object.freeze([...environments]),
    defaultRisk: risk,
    idempotency,
    approval,
    timeoutMs,
    maxPayloadBytes,
    sideEffect,
    retry,
    executor,
    expensive,
  });
}

const projectBase = { project_id: id, environment };
const mutationMeta = {
  request_id: { type: "string", minLength: 8, maxLength: 200, format: "idempotency-key" },
  idempotency_key: { type: "string", minLength: 8, maxLength: 200, format: "idempotency-key" },
};

const definitions = [
  def("get_project", "Read project metadata", object(projectBase), { capabilities: ["project.read"], executor: "ProjectContextExecutor" }),
  def("get_project_spec", "Read the current immutable ProjectSpec", object(projectBase), { capabilities: ["project.read"], executor: "ProjectContextExecutor" }),
  def("get_project_context", "Read bounded project context", object({ ...projectBase, context_kinds: { type: "array", items: { type: "string", enum: ["requirements", "files", "schema", "history", "verification"] }, minItems: 1, maxItems: 10 } }), { capabilities: ["project.read"], executor: "ProjectContextExecutor" }),

  def("list_files", "List files inside an authorized project path", object({ ...projectBase, path: pathField }), { capabilities: ["workspace.files.read"], executor: "WorkspaceExecutor" }),
  def("read_file", "Read a project file", object({ ...projectBase, path: pathField }), { capabilities: ["workspace.files.read"], executor: "WorkspaceExecutor", maxPayloadBytes: 16 * 1024 }),
  def("write_file", "Write artifact-backed content to a project file", object({ ...projectBase, path: pathField, content_ref: artifactRef, ...mutationMeta }), { capabilities: ["workspace.files.write"], risk: RISK_LEVELS.MEDIUM, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.POLICY, sideEffect: SIDE_EFFECTS.PROJECT_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "WorkspaceExecutor" }),
  def("delete_file", "Delete a project file", object({ ...projectBase, path: pathField, ...mutationMeta }), { capabilities: ["workspace.files.delete"], risk: RISK_LEVELS.MEDIUM, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.POLICY, sideEffect: SIDE_EFFECTS.PROJECT_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "WorkspaceExecutor" }),
  def("move_file", "Move a project file within authorized workspace paths", object({ ...projectBase, from_path: pathField, to_path: pathField, ...mutationMeta }), { capabilities: ["workspace.files.write", "workspace.files.delete"], risk: RISK_LEVELS.MEDIUM, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.POLICY, sideEffect: SIDE_EFFECTS.PROJECT_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "WorkspaceExecutor" }),

  def("inspect_schema", "Inspect database schema metadata", object(projectBase), { capabilities: ["database.inspect"], executor: "DatabaseExecutor" }),
  def("query_schema", "Run a bounded structured read query", object({ ...projectBase, query: object({ operation: { type: "string", enum: ["select"] }, table: id, columns: { type: "array", items: id, minItems: 1, maxItems: 50 }, limit: { type: "integer", minimum: 1, maximum: 500 } }, ["operation", "table", "columns"]) }), { capabilities: ["database.inspect"], executor: "DatabaseExecutor", maxPayloadBytes: 32 * 1024 }),
  def("request_migration", "Request a migration artifact for governed preflight and execution", object({ ...projectBase, migration_ref: artifactRef, migration_kind: { type: "string", enum: ["schema_change", "data_change", "rls_policy", "index", "constraint"] }, destructive: { type: "boolean" }, ...mutationMeta }), { capabilities: ["database.migration.request"], risk: RISK_LEVELS.MEDIUM, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.POLICY, sideEffect: SIDE_EFFECTS.EXTERNAL_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "DatabaseExecutor", expensive: true }),
  def("inspect_migration_result", "Inspect a migration execution result", object({ ...projectBase, migration_execution_id: id }), { capabilities: ["database.inspect"], executor: "DatabaseExecutor" }),

  def("request_build", "Request a bounded project build", object({ ...projectBase, version_id: id, ...mutationMeta }), { capabilities: ["build.execute"], risk: RISK_LEVELS.LOW, idempotency: IDEMPOTENCY_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.EXTERNAL_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "BuildExecutor", expensive: true }),
  def("get_build_status", "Read build status", object({ ...projectBase, build_id: id }), { capabilities: ["build.execute"], executor: "BuildExecutor" }),
  def("inspect_build_error", "Read normalized build failure diagnostics", object({ ...projectBase, build_id: id }), { capabilities: ["build.execute"], executor: "BuildExecutor" }),

  def("request_tests", "Request project tests", object({ ...projectBase, version_id: id, test_profile: { type: "string", enum: ["unit", "integration", "full"] }, ...mutationMeta }), { capabilities: ["test.execute"], idempotency: IDEMPOTENCY_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.EXTERNAL_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "VerificationExecutor", expensive: true }),
  def("get_test_results", "Read normalized test results", object({ ...projectBase, test_run_id: id }), { capabilities: ["test.execute"], executor: "VerificationExecutor" }),

  def("create_preview", "Create a disposable preview for an exact project version", object({ ...projectBase, version_id: id, artifact_digest: { type: "string", minLength: 64, maxLength: 64, pattern: "^[0-9a-f]{64}$" }, ...mutationMeta }), { capabilities: ["preview.create"], environments: ["development", "preview"], risk: RISK_LEVELS.LOW, idempotency: IDEMPOTENCY_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.EXTERNAL_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "PreviewExecutor", expensive: true }),
  def("inspect_preview", "Inspect preview metadata and state", object({ ...projectBase, preview_id: id }), { capabilities: ["preview.inspect"], executor: "PreviewExecutor" }),

  def("request_publish", "Publish an exact verified immutable version", object({ ...projectBase, version_id: id, verification_run_id: id, preview_id: id, artifact_digest: { type: "string", minLength: 64, maxLength: 64, pattern: "^[0-9a-f]{64}$" }, target_environment: { type: "string", enum: ["production"] }, ...mutationMeta }), { capabilities: ["production.publish"], environments: ["production"], risk: RISK_LEVELS.HIGH, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.PRODUCTION_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "DeploymentExecutor", expensive: true }),
  def("get_deployment_status", "Read normalized deployment state", object({ ...projectBase, deployment_id: id }), { capabilities: ["production.publish"], executor: "DeploymentExecutor" }),

  def("request_domain_attach", "Attach or change a canonical hostname for a project", object({ ...projectBase, hostname: domain, target_environment: { type: "string", enum: ["preview", "production"] }, deployment_id: id, ...mutationMeta }), { capabilities: ["domain.attach"], risk: RISK_LEVELS.HIGH, idempotency: IDEMPOTENCY_MODES.REQUIRED, approval: APPROVAL_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.PRODUCTION_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "DomainExecutor" }),
  def("inspect_domain_status", "Inspect domain ownership and attachment state", object({ ...projectBase, hostname: domain }), { capabilities: ["domain.attach"], executor: "DomainExecutor" }),

  def("create_artifact", "Create project-scoped immutable artifact metadata", object({ ...projectBase, content_type: { type: "string", minLength: 1, maxLength: 120 }, content_digest: { type: "string", minLength: 64, maxLength: 64, pattern: "^[0-9a-f]{64}$" }, size_bytes: { type: "integer", minimum: 0, maximum: 50 * 1024 * 1024 }, ...mutationMeta }), { capabilities: ["artifact.write"], risk: RISK_LEVELS.MEDIUM, idempotency: IDEMPOTENCY_MODES.REQUIRED, sideEffect: SIDE_EFFECTS.PROJECT_MUTATION, retry: RETRY_MODES.IDEMPOTENT_RETRY, executor: "ArtifactExecutor" }),
  def("read_artifact_metadata", "Read project-scoped immutable artifact metadata", object({ ...projectBase, artifact_ref: artifactRef }), { capabilities: ["project.read"], executor: "ArtifactExecutor" }),
];

const TOOL_REGISTRY = Object.freeze(Object.fromEntries(definitions.map((tool) => [tool.name, tool])));

function getToolDefinition(name, version = 1) {
  const tool = TOOL_REGISTRY[name];
  return tool && tool.version === version ? tool : undefined;
}

function listToolDefinitions() {
  return Object.values(TOOL_REGISTRY);
}

module.exports = { TOOL_REGISTRY, getToolDefinition, listToolDefinitions };
