import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { createBuildExecutionRequest, mapGatewayEnvironment } from '../src/tool-build-boundary.mjs';

const require = createRequire(import.meta.url);
const tools = require('../../pandora-tools/src/index.js');

const ORG = '11111111-1111-4111-8111-111111111111';
const PROJECT = '22222222-2222-4222-8222-222222222222';
const VERSION = '33333333-3333-4333-8333-333333333333';
const JOB = '44444444-4444-4444-8444-444444444444';
const EXECUTION = '55555555-5555-4555-8555-555555555555';
const SOURCE = '0123456789abcdef0123456789abcdef01234567';

function context(overrides = {}) {
  return {
    organizationId: ORG,
    projectId: PROJECT,
    projectVersionId: VERSION,
    buildJobId: JOB,
    executionId: EXECUTION,
    source: { kind: 'git_commit', repository: 'pandora-rvw-314296438-20260820/pandoras-box', commitSha: SOURCE },
    attempt: 1,
    networkPolicy: { mode: 'deny' },
    credentialLeaseRefs: [],
    ...overrides,
  };
}

function authorize(rawProposal, capabilities) {
  const validated = tools.validateToolProposal(rawProposal);
  const decision = tools.evaluatePolicy({
    definition: validated.definition,
    args: validated.proposal.arguments,
    actor: { id: 'worker-j-test', organization_id: ORG, capabilities },
    organization_id: ORG,
    project: { id: PROJECT, organization_id: ORG, version_id: VERSION },
    environment: validated.proposal.arguments.environment,
  });
  return { proposal: validated.proposal, decision };
}

test('Tool Gateway forbids production build and workspace mutations before Worker D', () => {
  for (const [tool, capability, extra] of [
    ['request_build', 'build.execute', { version_id: VERSION }],
    ['write_file', 'workspace.files.write', { path: 'src/app.js', content_ref: 'artifact://payload-1' }],
    ['delete_file', 'workspace.files.delete', { path: 'src/old.js' }],
    ['move_file', 'workspace.files.write', { from_path: 'src/a.js', to_path: 'src/b.js' }],
  ]) {
    const validated = tools.validateToolProposal({
      tool,
      version: 1,
      arguments: { project_id: PROJECT, environment: 'production', request_id: `request-${tool}`, idempotency_key: `idem-${tool}`, ...extra },
      reason: 'controlled integration proof',
    });
    const capabilities = tool === 'move_file' ? ['workspace.files.write', 'workspace.files.delete', 'production.access'] : [capability, 'production.access'];
    const decision = tools.evaluatePolicy({
      definition: validated.definition,
      args: validated.proposal.arguments,
      actor: { id: 'worker-j-test', organization_id: ORG, capabilities },
      organization_id: ORG,
      project: { id: PROJECT, organization_id: ORG, version_id: VERSION },
      environment: 'production',
    });
    assert.equal(decision.disposition, tools.TOOL_DECISIONS.DENY);
    assert.equal(decision.reason_code, 'ENVIRONMENT_NOT_ALLOWED');
  }
});

test('authorized request_build becomes a bounded preview-build request', () => {
  const { proposal, decision } = authorize({
    tool: 'request_build', version: 1,
    arguments: { project_id: PROJECT, environment: 'preview', version_id: VERSION, request_id: 'request-build-01', idempotency_key: 'idem-build-01' },
    reason: 'build exact candidate', requirement_refs: ['R-1'],
  }, ['build.execute']);
  assert.equal(decision.disposition, tools.TOOL_DECISIONS.ALLOW);
  const request = createBuildExecutionRequest({ proposal, policyDecision: decision, context: context() });
  assert.equal(request.operation, 'build_project');
  assert.equal(request.authorizedCapability, 'build.project.execute');
  assert.equal(request.environment, 'preview-build');
  assert.equal(request.projectVersionId, VERSION);
  assert.equal(request.arguments.requestedVersionId, VERSION);
  assert.match(request.arguments.gatewayActionHash, /^[0-9a-f]{64}$/);
  assert.match(request.idempotencyKey, /^gateway:[0-9a-f]{64}$/);
});

test('authorized workspace write carries only scoped file authority', () => {
  const { proposal, decision } = authorize({
    tool: 'write_file', version: 1,
    arguments: { project_id: PROJECT, environment: 'development', path: 'src/booking.js', content_ref: 'artifact://payload-2', request_id: 'request-write-01', idempotency_key: 'idem-write-01' },
    reason: 'materialize approved artifact',
  }, ['workspace.files.write']);
  const request = createBuildExecutionRequest({ proposal, policyDecision: decision, context: context({ credentialLeaseRefs: ['lease-artifact-read'] }) });
  assert.equal(request.operation, 'write_file');
  assert.equal(request.authorizedCapability, 'build.files.write');
  assert.equal(request.environment, 'sandbox');
  assert.deepEqual(request.credentialLeaseRefs, ['lease-artifact-read']);
  assert.equal(request.arguments.path, 'src/booking.js');
  assert.equal(request.arguments.contentRef, 'artifact://payload-2');
});

test('gateway denial, stale bindings and raw credentials fail closed', () => {
  const { proposal, decision } = authorize({
    tool: 'request_build', version: 1,
    arguments: { project_id: PROJECT, environment: 'preview', version_id: VERSION, request_id: 'request-build-02', idempotency_key: 'idem-build-02' },
    reason: 'build exact candidate',
  }, ['build.execute']);
  assert.throws(() => createBuildExecutionRequest({ proposal, policyDecision: { ...decision, disposition: tools.TOOL_DECISIONS.DENY }, context: context() }), /did not authorize/);
  assert.throws(() => createBuildExecutionRequest({ proposal, policyDecision: decision, context: context({ projectId: '66666666-6666-4666-8666-666666666666' }) }), /project binding/);
  assert.throws(() => createBuildExecutionRequest({ proposal, policyDecision: decision, context: context({ projectVersionId: '77777777-7777-4777-8777-777777777777' }) }), /project version/);
  assert.throws(() => createBuildExecutionRequest({ proposal, policyDecision: decision, context: context({ token: 'forbidden' }) }), /raw credential field/);
});

test('environment mapping never maps production into Worker D', () => {
  assert.equal(mapGatewayEnvironment('write_file', 'development'), 'sandbox');
  assert.equal(mapGatewayEnvironment('write_file', 'preview'), 'preview-build');
  assert.equal(mapGatewayEnvironment('request_build', 'development'), 'preview-build');
  assert.throws(() => mapGatewayEnvironment('request_build', 'production'), /forbidden/);
});
