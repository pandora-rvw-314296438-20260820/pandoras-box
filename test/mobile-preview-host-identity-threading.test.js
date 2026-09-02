const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const api = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/core/data/project_experience_api.dart'),
  'utf8',
);
const identity = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/core/models/project_preview_identity.dart'),
  'utf8',
);
const host = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/core/platform/pandora_preview_host.dart'),
  'utf8',
);

test('preview-content hosted identity is validated and threaded into every preview file', () => {
  assert.match(api, /final hostedPreview = _map\(data\['hostedPreview'\]\);/);
  assert.match(api, /_optionalText\(hostedPreview\?\['deploymentId'\]\)/);
  assert.match(api, /_optionalText\(hostedPreview\?\['sourceSha256'\]\)/);
  assert.match(api, /'previewDeploymentId': previewDeploymentId/);
  assert.match(api, /'local-artifact'/);
  assert.match(api, /_optionalText\(data\['sourceSha256'\]\)/);
  assert.match(api, /if \(sourceSha256 != null\) 'sourceSha256': sourceSha256/);
});

test('paid local preview remains exact without inventing a hosted deployment identity', () => {
  assert.match(identity, /static const localArtifactDeploymentId = 'local-artifact';/);
  assert.match(identity, /optionalText\(first, 'previewDeploymentId'\) \?\?[\s\S]*localArtifactDeploymentId/);
  assert.match(identity, /optionalText\(first, 'sourceSha256'\) \?\? ''/);
});

test('preview host fails closed when parsed and explicit identities drift', () => {
  assert.match(host, /final parsed = ProjectPreviewIdentity\.tryParse/);
  assert.match(host, /if \(parsed == null\) return null;/);
  assert.match(host, /explicit\.artifactDigest != parsed\.artifactDigest/);
  assert.match(host, /explicit\.deploymentId != parsed\.deploymentId/);
  assert.match(host, /explicit\.sourceSha256 != parsed\.sourceSha256/);
  assert.match(host, /if \(resolved == null \|\|/);
});
