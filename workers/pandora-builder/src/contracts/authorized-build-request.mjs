const TOOL_CAPABILITIES = Object.freeze({
  request_build: 'build.execute',
  request_tests: 'test.execute',
  list_files: 'workspace.files.read',
  read_file: 'workspace.files.read',
  write_file: 'workspace.files.write',
  delete_file: 'workspace.files.delete',
  move_file: 'workspace.files.write',
  create_artifact: 'artifact.write',
});

function assertWorkerCAuthorization({ gateway, request }) {
  if (!gateway || typeof gateway !== 'object') throw new Error('WORKER_C_AUTHORIZATION_REQUIRED');
  if (gateway.version !== 1 || typeof gateway.tool !== 'string') throw new Error('INVALID_WORKER_C_AUTHORIZATION');
  const expectedCapability = TOOL_CAPABILITIES[gateway.tool];
  if (!expectedCapability || gateway.capability !== expectedCapability) throw new Error('WORKER_C_CAPABILITY_MISMATCH');
  if (String(gateway.projectId) !== String(request.projectId)) throw new Error('WORKER_C_PROJECT_SCOPE_MISMATCH');
  if (gateway.projectVersionId != null && String(gateway.projectVersionId) !== String(request.projectVersionId)) throw new Error('WORKER_C_VERSION_SCOPE_MISMATCH');
  if (gateway.environment === 'production' || request.environment === 'production') throw new Error('WORKER_D_PRODUCTION_FORBIDDEN');
  if (!gateway.authorizationId || !gateway.idempotencyKey) throw new Error('WORKER_C_AUTHORIZATION_IDENTITY_REQUIRED');
  return Object.freeze({ tool: gateway.tool, version: gateway.version, capability: gateway.capability, authorizationId: gateway.authorizationId, idempotencyKey: gateway.idempotencyKey });
}

export { TOOL_CAPABILITIES, assertWorkerCAuthorization };
