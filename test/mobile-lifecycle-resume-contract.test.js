import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workspace = readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart',
  'utf8',
);
const durableResume = readFileSync(
  'apps/pandora-mobile/test/project_build_background_resume_test.dart',
  'utf8',
);

test('Task65 V2 workspace reconstructs durable state when Android resumes', () => {
  assert.match(
    workspace,
    /class _ProjectWorkspaceV2ScreenState extends State<ProjectWorkspaceV2Screen>\s+with WidgetsBindingObserver/,
  );
  assert.match(
    workspace,
    /didChangeAppLifecycleState\(AppLifecycleState state\)[\s\S]*?state == AppLifecycleState\.resumed[\s\S]*?_resumeFromDurableState\(\)/,
  );
  assert.match(
    workspace,
    /Future<void> _resumeFromDurableState\(\)[\s\S]*?_projectionSubscription = null;[\s\S]*?_liveBuildSubscription = null;[\s\S]*?await _startProjection\(\);[\s\S]*?await _refresh\(\);/,
    'resume must discard stale subscriptions before reloading server-authoritative project truth',
  );
});

test('Task65 projection transport errors clear the stale subscription before retry', () => {
  assert.match(
    workspace,
    /onError: \(_\) \{[\s\S]*?_recoverProjectionAfterError\(\)/,
  );
  assert.match(
    workspace,
    /Future<void> _recoverProjectionAfterError\(\)[\s\S]*?await _projectionSubscription\?\.cancel\(\);[\s\S]*?_projectionSubscription = null;[\s\S]*?_scheduleProjectionRetry\(\);/,
  );
});

test('Task65 live build transport errors reopen resilient replay instead of stranding theatre', () => {
  assert.match(
    workspace,
    /watchResilientBuildStream[\s\S]*?onError: \(_\) \{[\s\S]*?_recoverLiveBuildAfterError\(buildJobId\)/,
  );
  assert.match(
    workspace,
    /Future<void> _recoverLiveBuildAfterError\(String buildJobId\)[\s\S]*?await _liveBuildSubscription\?\.cancel\(\);[\s\S]*?_liveBuildSubscription = null;[\s\S]*?_scheduleLiveBuildRetry\(buildJobId\);/,
  );
});

test('Task65 retains existing duplicate-safe N+1 durable replay acceptance', () => {
  assert.match(durableResume, /admissionCount, 1/);
  assert.match(durableResume, /seedCursor\(persistedCursor\)/);
  assert.match(durableResume, /mergeReplay\([\s\S]*?reconnecting: true/);
  assert.match(durableResume, /<int>\[3, 4, 5\]/);
  assert.match(durableResume, /must not duplicate already-observed events/);
});

test('Task124 initial Android build excludes background time and refreshes on resume', () => {
  assert.match(
    workspace,
    /class _ProjectBuildExperienceV2ScreenState\s+extends State<ProjectBuildExperienceV2Screen>\s+with WidgetsBindingObserver/,
  );
  assert.match(
    workspace,
    /didChangeAppLifecycleState\(AppLifecycleState state\)[\s\S]*?state == AppLifecycleState\.resumed[\s\S]*?_flowStartedAt =[\s\S]*?startedAt\.add\(\s*DateTime\.now\(\)\.difference\(backgroundedAt\),?\s*\)[\s\S]*?_timer\?\.cancel\(\);[\s\S]*?_requestAuthoritativeRefresh\(\)/,
    'background duration must be excluded before authoritative resume refresh',
  );
  assert.match(
    workspace,
    /state == AppLifecycleState\.inactive[\s\S]*?state == AppLifecycleState\.paused[\s\S]*?state == AppLifecycleState\.detached[\s\S]*?_flowBackgroundedAt = DateTime\.now\(\);[\s\S]*?_lifecycleGeneration \+= 1;[\s\S]*?_timer\?\.cancel\(\)/,
  );
  assert.match(
    workspace,
    /Future<void> _refreshAndAdvance\(\) async \{[\s\S]*?if \(_flowBackgroundedAt != null\) return;/,
    'backgrounded initial build must not poll or expire before resume',
  );
  assert.match(
    workspace,
    /void _requestAuthoritativeRefresh\(\)[\s\S]*?if \(_refreshing\)[\s\S]*?_refreshAfterInFlight = true;[\s\S]*?unawaited\(_refreshAndAdvance\(\)\)/,
    'resume must queue one authoritative refresh when an older request is still in flight',
  );
  assert.match(
    workspace,
    /final lifecycleGeneration = _lifecycleGeneration;[\s\S]*?refreshIsStale\(\)[\s\S]*?lifecycleGeneration != _lifecycleGeneration[\s\S]*?if \(refreshIsStale\(\)\) return;/,
    'responses started before backgrounding must not mutate resumed UI state',
  );
  assert.match(
    workspace,
    /void dispose\(\) \{[\s\S]*?WidgetsBinding\.instance\.removeObserver\(this\);/,
  );
});