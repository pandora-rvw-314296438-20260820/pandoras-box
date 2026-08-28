import { createRequire } from 'node:module';
import { validateBuildExecutionRequest } from '../../../workers/pandora-builder/src/contracts/build-execution.mjs';

const require = createRequire(import.meta.url);
const tools = require('../../pandora-tools/src/index.js');

const C_TO_D_TOOL_MAP = Object.freeze({
  request_build: Object.freeze({ operation: 'build_project', capability: 'build.project.execute', environment: 'preview-build' }),
  write_file: Object.freeze({ operation: 'write_file', capability: 'build.files.write' }),
  delete_file: Object.freeze({ operation: 'delete_file', capability: 'build.files.write' }),
  move_file: Object.freeze({ operation: 'move_file', capability: 'build.files.write' }),
});

const RAW_SECRET_FIELDS = Object.freeze(['credentials', 'secrets', 'token', 'apiKey', 'api_key', 'password', 'serviceRoleKey']);

function assertRecord(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${name} must be an object`);
  return value;
}

function mapGatewayEnvironment(toolName, environment) {
  if (environment === 'production') throw new Error('production build/workspace execution is forbidden');
  if (!['development', 'preview'].includes(environment)) throw new Error(`unsupported gateway execution environment: ${environment}`);
  if (toolName === 'request_build') return 'preview-build';
  return environment === 'preview' ? 'preview-build' : 'sandbox';
}

function operationArguments(toolName, args, authorization) {
  const lineage = {
    gatewayActionHash: authorization.actionHash,
    gatewayPolicyVersion: authorization.policyVersion,
    gatewayReasonCode: authorization.reasonCode,
    gatewayRequestId: args.request_id,
  };
  switch (toolName) {
    case 'request_build':
      return { ...lineage, requestedVersionId: args.version_id };
    case 'write_file':
      return { ...lineage, path: args.path, contentRef: args.content_ref };
    case 'delete_file':
      return { ...lineage, path: args.path };
    case 'move_file':
      return { ...lineage, fromPath: args.from_path, toPath: args.to_path };
    default:
      throw new Error(`Tool ${toolName} is not executable by Worker D`);
  }
}

function deriveAuthorization(proposal, policyDecision, context) {
  if (policyDecision?.disposition !== tools.TOOL_DECISIONS.ALLOW) throw new Error('Tool Gateway did not authorize execution');
  if (!policyDecision.policy_version) throw new Error('Tool Gateway policy version is required');
  const actionHash = tools.computeActionHash({
    tool: proposal.tool,
    version: proposal.version,
    arguments: proposal.arguments,
    organization_id: context.organizationId,
    project_id: context.projectId,
    environment: proposal.arguments.environment,
    target_resource: context.targetResource ?? null,
    project_version: context.projectVersionId,
    policy_version: policyDecision.policy_version,
  });
  if (context.expectedActionHash !== undefined && !tools.secureEqualHex(context.expectedActionHash, actionHash)) {
    throw new Error('authorized action hash does not match the current proposal');
  }
  return Object.freeze({
    actionHash,
    policyVersion: policyDecision.policy_version,
    reasonCode: policyDecision.reason_code ?? 'POLICY_ALLOWED',
  });
}

function assertAuthorityBindings(proposal, context) {
  assertRecord(context, 'context');
  for (const field of RAW_SECRET_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(context, field)) throw new Error(`raw credential field is forbidden: ${field}`);
  }
  if (proposal.arguments.project_id !== context.projectId) throw new Error('gateway project binding does not match Worker D context');
  if (proposal.arguments.version_id !== undefined && proposal.arguments.version_id !== context.projectVersionId) {
    throw new Error('gateway project version does not match Worker D context');
  }
  if (!C_TO_D_TOOL_MAP[proposal.tool]) throw new Error(`Tool ${proposal.tool} is not executable by Worker D`);
  if (!Array.isArray(context.credentialLeaseRefs ?? [])) throw new Error('credentialLeaseRefs must be an array of opaque lease references');
}

function createBuildExecutionRequest({ proposal, policyDecision, context }) {
  assertRecord(proposal, 'proposal');
  assertRecord(proposal.arguments, 'proposal.arguments');
  assertAuthorityBindings(proposal, context);
  const mapping = C_TO_D_TOOL_MAP[proposal.tool];
  const environment = mapGatewayEnvironment(proposal.tool, proposal.arguments.environment);
  const authorization = deriveAuthorization(proposal, policyDecision, context);
  const idempotencyKey = `gateway:${tools.sha256Hex({
    actionHash: authorization.actionHash,
    gatewayIdempotencyKey: proposal.arguments.idempotency_key,
    buildJobId: context.buildJobId,
    projectVersionId: context.projectVersionId,
  })}`;

  return validateBuildExecutionRequest({
    schemaVersion: 1,
    executionId: context.executionId,
    buildJobId: context.buildJobId,
    projectId: context.projectId,
    organizationId: context.organizationId,
    projectVersionId: context.projectVersionId,
    source: context.source,
    authorizedCapability: mapping.capability,
    operation: mapping.operation,
    environment,
    timeoutMs: context.timeoutMs,
    resourceLimits: context.resourceLimits,
    networkPolicy: context.networkPolicy,
    credentialLeaseRefs: context.credentialLeaseRefs ?? [],
    idempotencyKey,
    attempt: context.attempt,
    cancellationRef: context.cancellationRef ?? null,
    arguments: operationArguments(proposal.tool, proposal.arguments, authorization),
  });
}

export { C_TO_D_TOOL_MAP, createBuildExecutionRequest, mapGatewayEnvironment };
