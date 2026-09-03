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
