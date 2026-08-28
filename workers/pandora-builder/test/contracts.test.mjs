import assert from 'node:assert/strict';
import test from 'node:test';
import { canonicalRequestDigest, validateBuildExecutionRequest } from '../src/contracts/build-execution.mjs';

const request = () => ({
  schemaVersion: 1,
  executionId: '11111111-1111-4111-8111-111111111111',
  buildJobId: '22222222-2222-4222-8222-222222222222',
  projectId: '33333333-3333-4333-8333-333333333333',
  organizationId: '44444444-4444-4444-8444-444444444444',
  projectVersionId: '55555555-5555-4555-8555-555555555555',
  source: { kind: 'git_commit', repository: 'owner/repo', commitSha: 'a'.repeat(40) },
  authorizedCapability: 'build.project.execute',
  operation: 'build_project',
  environment: 'sandbox',
  timeoutMs: 60_000,
  resourceLimits: {},
  networkPolicy: { mode: 'deny' },
  credentialLeaseRefs: [],
  idempotencyKey: 'build:333:version:555:attempt:1',
  attempt: 1,
  cancellationRef: 'cancel:222',
  arguments: { adapter: 'node-web' },
});

test('validates immutable authorized execution request', () => {
  const value = validateBuildExecutionRequest(request());
  assert.equal(value.operation, 'build_project');
  assert.equal(value.source.commitSha, 'a'.repeat(40));
});

test('rejects generic arbitrary command operations', () => {
  assert.throws(() => validateBuildExecutionRequest({ ...request(), operation: 'shell' }), /OPERATION_NOT_ALLOWED/);
});

test('rejects raw credentials in request contract', () => {
  assert.throws(() => validateBuildExecutionRequest({ ...request(), token: 'should-never-be-here' }), /RAW_CREDENTIALS_FORBIDDEN/);
});

test('request digest is deterministic', () => {
  assert.equal(canonicalRequestDigest(request()), canonicalRequestDigest(request()));
});
