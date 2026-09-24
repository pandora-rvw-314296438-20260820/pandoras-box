import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const chat = readFileSync('supabase/functions/pandora-intelligence-chat/index.ts', 'utf8');
const mobile = readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', 'utf8');
const ask = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', 'utf8');
const native = readFileSync('apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraLocalAiChannel.kt', 'utf8');
const repair = readFileSync('supabase/migrations/20260923183000_pandora_system_audit_repair_v1.sql', 'utf8');
const bootstrap = readFileSync('supabase/migrations/20260923183500_plp_bootstrap_source_truth_v6.sql', 'utf8');
const pubspec = readFileSync('apps/pandora-mobile/pubspec.yaml', 'utf8');

test('terminal Activity evidence is emitted before execution is sealed', () => {
  const dispatchStart = chat.indexOf('const dispatchThreadId=');
  const dispatchResult = chat.indexOf('dispatch-verified:', dispatchStart);
  const dispatchFinish = chat.indexOf('finishActivityExecution(c.admin,i.activityJobId,executionClaim.claimId,"complete",dispatchResult,null)', dispatchStart);
  assert.ok(dispatchStart >= 0 && dispatchResult > dispatchStart && dispatchFinish > dispatchResult);

  const providerStart = chat.indexOf('const terminalActivity=');
  const providerResult = chat.indexOf('state:"result"', providerStart);
  const providerFinish = chat.indexOf('finishActivityExecution(c.admin,i.activityJobId,executionClaim.claimId,"complete",responsePayload,null)', providerStart);
  assert.ok(providerStart >= 0 && providerResult > providerStart && providerFinish > providerResult);
});

test('completed persisted chat can recover when an old terminal event was missing', () => {
  assert.match(mobile, /execution_state'\]\) != 'complete'/);
  assert.match(mobile, /terminalState\.isNotEmpty && terminalState != 'result'/);
  assert.match(mobile, /if \(result\.isEmpty\) return null/);
});

test('recent chat timestamps are maintained from the message ledger', () => {
  assert.match(repair, /pandora_intelligence_touch_thread_v1/);
  assert.match(repair, /max\(created_at\) actual_last/);
});

test('stale never-claimed Activity jobs are cancelled and swept automatically', () => {
  assert.match(repair, /pandora_activity_expire_stale_ready_v1/);
  assert.match(repair, /execution_state='ready'/);
  assert.match(repair, /ACTIVITY_REQUEST_EXPIRED/);
  assert.match(repair, /cron\.schedule/);
});

test('PLP remains demo staging and source health cannot masquerade as current customer data', () => {
  assert.match(bootstrap, /plp\.enterprise\.mobile-bootstrap\.v6/);
  assert.match(bootstrap, /effective_source_state/);
  assert.match(bootstrap, /demo_staging/);
  assert.match(bootstrap, /customerTenantConnected/);
  assert.match(repair, /Customer production tenant is not connected/);
  assert.doesNotMatch(repair, /076a9306-5c4e-4d9d-98d3-e3a6fea968fb/);
});

test('automatic Qwen prewarm does not run synthetic generation or reset loops', () => {
  const start = ask.indexOf('Future<void> _prewarmPlpLocalAiIfSafe()');
  const end = ask.indexOf('Future<void> _restoreLocalConversation()', start);
  const prewarm = ask.slice(start, end);
  assert.doesNotMatch(prewarm, /\.generate\(/);
  assert.doesNotMatch(prewarm, /resetConversation\(/);
  assert.match(prewarm, /model_ready_without_synthetic_generation/);
  assert.match(ask, /timeout\(const Duration\(seconds: 30\)\)/);
  assert.match(native, /WARM_DEADLINE_MS = 180_000L/);
});

test('active mobile runtime uses Pandora project registry names', () => {
  assert.doesNotMatch(mobile, /projectos_projects/);
  assert.match(mobile, /\.from\('pandora_projects'\)/);
});

test('next APK has a unique monotonic release identity', () => {
  assert.match(pubspec, /version: 0\.4\.0-rc\.14\+21/);
});

test('security-definer enterprise and provider RPCs are not anonymously executable', () => {
  assert.match(repair, /revoke execute on function public\.pandora_eurofish_github_request_v1/);
  assert.match(repair, /revoke execute on function public\.pandora_eurofish_memory_github_request_v1/);
  assert.match(repair, /revoke execute on function public\.pandora_eurofish_github_ci_dispatch_v1/);
  assert.match(repair, /revoke execute on function public\.pandora_eurofish_workspace_v1/);
  assert.match(repair, /revoke execute on function public\.pandora_vision_overview_v1/);
});
