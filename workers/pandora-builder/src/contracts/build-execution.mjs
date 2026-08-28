import { createHash } from 'node:crypto';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SAFE_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;

const OPERATIONS = new Set([
  'install_dependencies',
  'build_project',
  'run_unit_tests',
  'run_integration_tests',
  'run_typecheck',
  'run_lint',
  'list_files',
  'read_file',
  'write_file',
  'delete_file',
  'move_file',
  'collect_artifacts',
]);

const CAPABILITIES = new Set([
  'build.dependencies.install',
  'build.project.execute',
  'build.tests.execute',
  'build.files.read',
  'build.files.write',
  'build.artifacts.collect',
]);

const ENVIRONMENTS = new Set(['sandbox', 'test', 'preview-build']);
const FAILURE_CLASSES = new Set([
  'dependency', 'syntax', 'type', 'compile', 'test', 'timeout', 'resource_limit',
  'network', 'configuration', 'filesystem', 'sandbox', 'cancelled',
  'authorization', 'credential', 'unknown',
]);

function isRecord(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function requiredString(value, name, pattern = SAFE_ID) {
  if (typeof value !== 'string' || !pattern.test(value)) {
    throw new Error(`INVALID_${name.toUpperCase()}`);
  }
  return value;
}

function positiveInteger(value, name, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`INVALID_${name.toUpperCase()}`);
  }
  return value;
}

function normalizeResourceLimits(value = {}) {
  if (!isRecord(value)) throw new Error('INVALID_RESOURCE_LIMITS');
  return Object.freeze({
    wallClockMs: positiveInteger(value.wallClockMs ?? 15 * 60_000, 'wall_clock_ms', 1_000, 30 * 60_000),
    cpuMillis: positiveInteger(value.cpuMillis ?? 10 * 60_000, 'cpu_millis', 1_000, 30 * 60_000),
    memoryBytes: positiveInteger(value.memoryBytes ?? 2 * 1024 ** 3, 'memory_bytes', 64 * 1024 ** 2, 16 * 1024 ** 3),
    diskBytes: positiveInteger(value.diskBytes ?? 8 * 1024 ** 3, 'disk_bytes', 64 * 1024 ** 2, 64 * 1024 ** 3),
    processCount: positiveInteger(value.processCount ?? 128, 'process_count', 1, 1024),
    outputBytes: positiveInteger(value.outputBytes ?? 4 * 1024 ** 2, 'output_bytes', 1024, 64 * 1024 ** 2),
    fileCount: positiveInteger(value.fileCount ?? 100_000, 'file_count', 1, 1_000_000),
    artifactBytes: positiveInteger(value.artifactBytes ?? 512 * 1024 ** 2, 'artifact_bytes', 1024, 4 * 1024 ** 3),
    dependencyInstallMs: positiveInteger(value.dependencyInstallMs ?? 10 * 60_000, 'dependency_install_ms', 1_000, 30 * 60_000),
  });
}

function normalizeNetworkPolicy(value = { mode: 'deny' }) {
  if (!isRecord(value)) throw new Error('INVALID_NETWORK_POLICY');
  const mode = value.mode ?? 'deny';
  if (!['deny', 'allowlist'].includes(mode)) throw new Error('INVALID_NETWORK_POLICY');
  const allow = value.allow ?? [];
  if (!Array.isArray(allow) || allow.length > 64 || allow.some((item) => typeof item !== 'string' || item.length > 253)) {
    throw new Error('INVALID_NETWORK_POLICY');
  }
  if (mode === 'deny' && allow.length) throw new Error('INVALID_NETWORK_POLICY');
  return Object.freeze({ mode, allow: Object.freeze([...allow]) });
}

function normalizeSource(value) {
  if (!isRecord(value)) throw new Error('INVALID_SOURCE');
  if (value.kind === 'git_commit') {
    return Object.freeze({
      kind: 'git_commit',
      repository: requiredString(value.repository, 'repository', /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
      commitSha: requiredString(value.commitSha, 'commit_sha', SHA40),
    });
  }
  if (value.kind === 'artifact_snapshot') {
    return Object.freeze({
      kind: 'artifact_snapshot',
      artifactId: requiredString(value.artifactId, 'artifact_id'),
      sha256: requiredString(value.sha256, 'source_sha256', SHA256),
    });
  }
  throw new Error('INVALID_SOURCE');
}

function validateBuildExecutionRequest(value) {
  if (!isRecord(value)) throw new Error('INVALID_BUILD_EXECUTION_REQUEST');
  const operation = requiredString(value.operation, 'operation');
  const authorizedCapability = requiredString(value.authorizedCapability, 'authorized_capability');
  const environment = requiredString(value.environment, 'environment');
  if (!OPERATIONS.has(operation)) throw new Error('OPERATION_NOT_ALLOWED');
  if (!CAPABILITIES.has(authorizedCapability)) throw new Error('CAPABILITY_NOT_ALLOWED');
  if (!ENVIRONMENTS.has(environment)) throw new Error('ENVIRONMENT_NOT_ALLOWED');
  const credentialLeaseRefs = value.credentialLeaseRefs ?? [];
  if (!Array.isArray(credentialLeaseRefs) || credentialLeaseRefs.length > 16 || credentialLeaseRefs.some((entry) => typeof entry !== 'string' || !SAFE_ID.test(entry))) {
    throw new Error('INVALID_CREDENTIAL_LEASE_REFS');
  }
  if ('credentials' in value || 'secrets' in value || 'token' in value || 'apiKey' in value) {
    throw new Error('RAW_CREDENTIALS_FORBIDDEN');
  }
  return Object.freeze({
    schemaVersion: value.schemaVersion === 1 ? 1 : (() => { throw new Error('INVALID_SCHEMA_VERSION'); })(),
    executionId: requiredString(value.executionId, 'execution_id', UUID),
    buildJobId: requiredString(value.buildJobId, 'build_job_id', UUID),
    projectId: requiredString(value.projectId, 'project_id', UUID),
    organizationId: requiredString(value.organizationId, 'organization_id', UUID),
    projectVersionId: requiredString(value.projectVersionId, 'project_version_id', UUID),
    source: normalizeSource(value.source),
    authorizedCapability,
    operation,
    environment,
    timeoutMs: positiveInteger(value.timeoutMs ?? 15 * 60_000, 'timeout_ms', 1_000, 30 * 60_000),
    resourceLimits: normalizeResourceLimits(value.resourceLimits),
    networkPolicy: normalizeNetworkPolicy(value.networkPolicy),
    credentialLeaseRefs: Object.freeze([...credentialLeaseRefs]),
    idempotencyKey: requiredString(value.idempotencyKey, 'idempotency_key'),
    attempt: positiveInteger(value.attempt, 'attempt', 1, 100),
    cancellationRef: value.cancellationRef == null ? null : requiredString(value.cancellationRef, 'cancellation_ref'),
    arguments: isRecord(value.arguments) ? structuredClone(value.arguments) : {},
  });
}

function canonicalRequestDigest(request) {
  const normalized = validateBuildExecutionRequest(request);
  return createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
}

function createBuildExecutionResult({ request, status, startedAt, finishedAt, exitCode = null, failureClass = null, stdoutArtifactRef = null, stderrArtifactRef = null, artifactRefs = [], changedFiles = [], retryable = false, resourceUsage = {}, cleanupStatus = 'pending' }) {
  const validated = validateBuildExecutionRequest(request);
  if (!['completed', 'failed', 'cancelled'].includes(status)) throw new Error('INVALID_RESULT_STATUS');
  if (failureClass !== null && !FAILURE_CLASSES.has(failureClass)) throw new Error('INVALID_FAILURE_CLASS');
  if (status === 'completed' && (failureClass !== null || exitCode !== 0)) throw new Error('INVALID_COMPLETED_RESULT');
  return Object.freeze({
    schemaVersion: 1,
    executionId: validated.executionId,
    buildJobId: validated.buildJobId,
    projectId: validated.projectId,
    projectVersionId: validated.projectVersionId,
    attempt: validated.attempt,
    status,
    startedAt,
    finishedAt,
    exitCode,
    failureClass,
    stdoutArtifactRef,
    stderrArtifactRef,
    artifactRefs: Object.freeze([...artifactRefs]),
    changedFiles: Object.freeze(changedFiles.map((entry) => Object.freeze({ ...entry }))),
    retryable: Boolean(retryable),
    resourceUsage: Object.freeze({ ...resourceUsage }),
    cleanupStatus,
  });
}

export {
  CAPABILITIES,
  ENVIRONMENTS,
  FAILURE_CLASSES,
  OPERATIONS,
  canonicalRequestDigest,
  createBuildExecutionResult,
  normalizeNetworkPolicy,
  normalizeResourceLimits,
  validateBuildExecutionRequest,
};
