'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const intelligence = require(path.join(ROOT, 'dist', 'index.js'));

function validSpec() {
  return {
    version: '1.0',
    business: { objective: 'Increase direct bookings', expectedOutcome: 'More direct reservations', successMetric: 'direct_booking_rate', constraints: [] },
    product: { projectType: 'web_application', users: ['guest', 'owner'], roles: ['guest', 'admin'], workflows: ['browse rooms', 'reserve room'], features: ['room catalogue', 'availability', 'reservation'], screens: ['home', 'rooms', 'room detail', 'booking', 'confirmation', 'admin'], userStories: [] },
    data: { entities: [{ name: 'room' }, { name: 'booking' }, { name: 'guest' }], relationships: [{ name: 'booking_room', from: 'booking', to: 'room' }], authentication: 'owner admin authentication', storage: 'project database', retention: 'business requirement' },
    integrations: { payment: [], messaging: [], analytics: [], externalApis: [], providerRequirements: [] },
    design: { visualDirection: 'premium resort', brandRequirements: [], accessibility: ['WCAG-aware'], platforms: ['web'], responsive: true },
    deployment: { preview: 'required', production: 'required', domain: 'custom domain', runtime: 'managed', geography: 'unspecified' },
    acceptance: { functional: ['Guest can reserve an available room'], business: ['Direct booking journey is measurable'] },
  };
}

test('ModelRequest is provider-independent and enforces budget shape', () => {
  const r = intelligence.createModelRequest({ requestId: 'r1', task: 'compile_project_spec', context: {}, budget: { maxAttempts: 2, remainingAttempts: 1 } });
  assert.equal(r.task, 'compile_project_spec');
  assert.equal(r.budget.maxAttempts, 2);
  assert.throws(() => intelligence.createModelRequest({ requestId: 'r2', task: 'gemini_generate', context: {} }), /task must be one of/);
});

test('ProjectSpec validation rejects missing objective and unknown structure', () => {
  assert.equal(intelligence.validateProjectSpecCandidate(validSpec()).ok, true);
  const bad = validSpec();
  delete bad.business.objective;
  bad.providerPrompt = 'do anything';
  const result = intelligence.validateProjectSpecCandidate(bad);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /business.objective is required/);
  assert.match(result.errors.join('\n'), /unknown top-level ProjectSpec field/);
});

test('capability registry selects by capability rather than model name', () => {
  const registry = new intelligence.ModelCapabilityRegistry();
  registry.register({ provider: 'provider-a', modelId: 'model-x', capabilities: { coding: true, structuredOutput: true }, latencyClass: 'standard', costClass: 'medium', reliabilityClass: 'high', maxContextTokens: 100000, outputModes: ['structured'] });
  registry.register({ provider: 'provider-b', modelId: 'cheap-y', capabilities: { classification: true, structuredOutput: true }, latencyClass: 'interactive', costClass: 'low', reliabilityClass: 'standard', maxContextTokens: 32000, outputModes: ['structured'] });
  assert.deepEqual(registry.findCompatible({ required: ['coding', 'structuredOutput'], outputMode: 'structured' }).map((item) => item.modelId), ['model-x']);
});

test('tool proposals normalize to the Tool Gateway v1 contract', () => {
  const write = intelligence.validateToolProposal({ tool: 'write_file', arguments: { project_id: 'p1', path: 'src/pages/booking.tsx', content_ref: 'artifact:1' }, reason: 'Implements R-14' });
  assert.equal(write.ok, true);
  assert.equal(write.value.tool, 'write_file');
  assert.equal(write.value.version, 1);

  const legacyBuild = intelligence.validateToolProposal({ tool: 'run_build', arguments: { version_id: 'v1' }, reason: 'Build the candidate' });
  assert.equal(legacyBuild.ok, true);
  assert.equal(legacyBuild.value.tool, 'request_build');
  assert.equal(legacyBuild.value.version, 1);

  const canonicalPublish = intelligence.validateToolProposal({ tool: 'request_publish', version: 1, arguments: { version_id: 'v2' }, reason: 'Publish exact verified version', requirement_refs: ['R-14'] });
  assert.equal(canonicalPublish.ok, true);
  assert.deepEqual(canonicalPublish.value.requirement_refs, ['R-14']);

  assert.equal(intelligence.validateToolProposal({ tool: 'request_tests', version: 2, arguments: { version_id: 'v2' }, reason: 'Unsupported future contract' }).ok, false);
  assert.equal(intelligence.validateToolProposal({ tool: 'shell', arguments: { command: 'rm -rf /' }, reason: 'no' }).ok, false);
  assert.equal(intelligence.validateToolProposal({ tool: 'write_file', arguments: { path: '../../.env' }, reason: 'bad' }).ok, false);
  assert.equal(intelligence.validateToolProposal({ tool: 'write_file', arguments: { path: 'src/a.js' }, reason: 'bad envelope', extra: true }).ok, false);
});

test('credential material is rejected before model request assembly', () => {
  assert.throws(() => intelligence.assertNoCredentialMaterial({ gemini_api_key: 'hidden' }), /credential material rejected/);
  assert.throws(() => intelligence.assertNoCredentialMaterial({ nested: { authorization: 'Bearer opaque' } }), /credential material rejected/);
  assert.throws(() => intelligence.assertNoCredentialMaterial({ text: 'AIza123456789012345678901234567890' }), /credential material rejected/);
  assert.doesNotThrow(() => intelligence.assertNoCredentialMaterial({ capabilities: ['github.read', 'deploy.preview'], objective: 'Increase bookings' }));
});

test('prompt templates carry stable version metadata', () => {
  assert.equal(intelligence.getPromptTemplate('intent_compilation').version, '1.0.0');
  assert.throws(() => intelligence.getPromptTemplate('unknown'), /unknown prompt template/);
});
