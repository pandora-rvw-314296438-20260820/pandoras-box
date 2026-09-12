const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const conversation = readFileSync(
  join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'project_build_conversation.dart'),
  'utf8',
);
const projection = readFileSync(
  join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'live_build_theatre', 'project_build_stream_theatre_projection.dart'),
  'utf8',
);

test('Build Theatre stays in chat until the owner explicitly opens the result', () => {
  assert.doesNotMatch(conversation, /_autoOpenedResult/);
  assert.doesNotMatch(conversation, /_maybeAutoOpenResult/);
  assert.match(conversation, /label: 'Open result'/);
  assert.match(conversation, /onPressed: onOpenProject/);
});

test('Build Theatre remains projected only from the authoritative resilient stream', () => {
  assert.match(conversation, /ProjectBuildStreamTheatreProjection\.fromSnapshot/);
  assert.match(projection, /without inventing ordering, source bytes, metrics or lifecycle state/);
  assert.match(projection, /snapshot\.events/);
});
