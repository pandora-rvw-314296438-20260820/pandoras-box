const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const journey = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_journey_flow.dart', 'utf8');

test('Build Theatre retries a governed build handoff after a bounded waiting interval', () => {
  assert.match(journey, /DateTime\? _lastBuildRequestAt/);
  assert.match(journey, /Duration\(seconds: 20\)/);
  assert.match(journey, /_lastBuildRequestAt = DateTime\.now\(\)/);
  assert.match(journey, /_buildRequestStarted = false/);
  assert.match(journey, /_lastBuildRequestAt = null/);
  const guardAt = journey.indexOf('DateTime.now().difference(lastRequest)');
  const requestAt = journey.indexOf('unawaited(_requestBuild())');
  assert.ok(guardAt > 0 && requestAt > guardAt, 'retry cooldown must gate the build request');
});
