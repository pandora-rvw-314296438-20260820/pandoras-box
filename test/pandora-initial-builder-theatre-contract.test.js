import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart',
  'utf8',
);

const initialStart = source.indexOf('class _ProjectBuildExperienceV2ScreenState');
const workspaceStart = source.indexOf('class ProjectWorkspaceV2Screen');
assert.ok(initialStart >= 0 && workspaceStart > initialStart);
const initial = source.slice(initialStart, workspaceStart);

test('initial build surface renders only authoritative resilient theatre activity', () => {
  assert.match(source, /import 'live_build_theatre\/live_build_theatre\.dart';/);
  assert.match(initial, /StreamSubscription<ProjectBuildStreamSnapshot>\? _initialBuildSubscription/);
  assert.match(initial, /watchResilientBuildStream\(/);
  assert.match(initial, /ProjectBuildStreamTheatreProjection\.fromSnapshot\(/);
  assert.match(initial, /LiveBuildTheatre\(state: activity\)/);
  assert.match(initial, /snapshot\.requiresReplay/);
  assert.match(initial, /snapshot\.events\.isEmpty/);
});

test('fresh admission attaches the exact returned build stream', () => {
  assert.match(initial, /final start = await experience\.requestBuild\(/);
  assert.match(initial, /_attachInitialBuildStream\([\s\S]*start\.streamId,[\s\S]*buildJobId: start\.buildJobId/);
});

test('already-requested builds resume from durable active build identity', () => {
  assert.match(initial, /experience\.loadExperience\(widget\.project\.id\)/);
  assert.match(initial, /projection\.activeBuildJobId/);
  assert.match(initial, /experience\.findBuildStreamId\(/);
});

test('stream lifecycle is bounded and exact preview safety is preserved', () => {
  assert.match(initial, /_initialBuildSubscription\?\.cancel\(\)/);
  assert.match(initial, /_candidateIsCurrent/);
  assert.match(initial, /_loadExactPreviewFiles\(/);
  assert.match(initial, /PandoraPreviewHost\(/);
  assert.doesNotMatch(initial, /Timer\.periodic/);
  assert.doesNotMatch(initial, /progress\s*[:=]\s*[0-9]+/i);
});
