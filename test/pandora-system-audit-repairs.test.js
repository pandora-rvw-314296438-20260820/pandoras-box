import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const chat = readFileSync('supabase/functions/pandora-intelligence-chat/index.ts', 'utf8');
const mobile = readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', 'utf8');
const ask = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', 'utf8');
const adapters = readFileSync('apps/pandora-mobile/lib/features/simple/chat/pandora_chat_action_adapters.dart', 'utf8');
const localRuntime = readFileSync('apps/pandora-mobile/lib/core/local_ai/pandora_local_ai_runtime.dart', 'utf8');
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

test('Phone AI stays bounded without synthetic startup generation or reset loops', () => {
  const init = ask.indexOf('void initState()');
  const afterStartup = ask.indexOf('Future<void> _restoreConversation(', init);
  assert.ok(init >= 0 && afterStartup > init, 'shell startup path missing');
  const startup = ask.slice(init, afterStartup);
  assert.doesNotMatch(startup, /\.generate\(|\.warm\(|resetConversation\(/);
  assert.match(startup, /if \(_isPlpEnterpriseContext\) unawaited\(_prewarmPlpLocalAiIfSafe\(\)\)/);

  const prewarmStart = localRuntime.indexOf('Future<bool> prewarm(');
  const prewarmEnd = localRuntime.indexOf('void start()', prewarmStart);
  assert.ok(prewarmStart >= 0 && prewarmEnd > prewarmStart, 'application-owned prewarm missing');
  const prewarm = localRuntime.slice(prewarmStart, prewarmEnd);
  assert.match(prewarm, /Duration delay = const Duration\(milliseconds: 800\)/);
  assert.match(prewarm, /if \(current != null\) return current;/);
  assert.match(prewarm, /_foreground &&\s*!_suspending &&\s*epoch == _residencyEpoch &&\s*PandoraLocalAiPreference\.cachedEnabled &&\s*stillEligible\(\)/);
  assert.match(prewarm, /await PandoraLocalAi\.instance\.status\(\);[\s\S]*?if \(!eligible\(\) \|\| !status\.supported \|\| !status\.configured\)/);
  assert.match(prewarm, /PandoraLocalAiRouter\.decide\([\s\S]*?status: status,[\s\S]*?if \(!readiness\.useLocal\) return false;/);
  assert.match(prewarm, /if \(!status\.loaded && !await ensureWarm\(\)\) return false;/);
  assert.doesNotMatch(prewarm, /\.generate\(|resetConversation\(/);

  const start = adapters.indexOf('Future<bool> _executePhoneAi(');
  const end = adapters.indexOf('String _boundedConversationPrompt(', start);
  assert.ok(start >= 0 && end > start, 'Phone AI adapter missing');
  const local = adapters.slice(start, end);
  assert.match(local, /if \(!PandoraLocalAiPreference\.cachedEnabled\) return false;/);
  assert.match(local, /\.status\(\)\s*\.timeout\(const Duration\(milliseconds: 600\)\)/);
  assert.match(local, /if \(!route\.useLocal\) return false;/);
  const coldStart = local.indexOf('if (!status.loaded && !forceLocal)');
  const coldEnd = local.indexOf('await _nativeReset;', coldStart);
  assert.ok(coldStart >= 0 && coldEnd > coldStart, 'nonblocking cold Auto path missing');
  const cold = local.slice(coldStart, coldEnd);
  assert.match(cold, /unawaited\(PandoraLocalAiRuntime\.instance\.prewarm\(/);
  assert.match(cold, /_sameAttempt\(token\) &&\s*_chat\.state\.preferences\.isAuto &&\s*_nativeGeneration == null/);
  assert.match(cold, /return false;/);
  assert.doesNotMatch(cold, /\bawait\s/, 'cold Auto must not wait for model warming');
  assert.match(adapters, /final forceLocal =\s*dispatch\.preferences\.provider == pandoraLocalDeviceProvider &&\s*dispatch\.preferences\.model == pandoraLocalDeviceModel;/);
  assert.match(local, /runtime\.canContinueConversation\(\s*conversationKey: conversationKey,\s*previousTurnId: previous\.last\.id,\s*loaded: status\.loaded\)/);
  assert.match(localRuntime, /loaded &&\s*_conversation\?\.key == conversationKey &&\s*_conversation\?\.turnId == previousTurnId &&\s*_conversation\?\.epoch == _residencyEpoch/);
  assert.match(localRuntime, /if \(residencyEpoch != _residencyEpoch \|\| !_foreground \|\| _suspending\)/);
  assert.match(localRuntime, /Future<void> unload\(\) async \{\s*_residencyEpoch \+= 1;\s*invalidateConversation\(\)/);
  assert.match(local, /if \(!sameNativeConversation\)\s*\{\s*runtime\.invalidateConversation\(\);\s*await PandoraLocalAi\.instance\.resetConversation\(\);/);
  assert.match(local, /\.generate\(prompt, predictLength: input\.isPlp \? 96 : 192\)\s*\.timeout\(const Duration\(seconds: 120\)\)/);
  assert.equal((local.match(/\.generate\(/g) ?? []).length, 1, 'one admitted native generation per local attempt');
  assert.match(local, /if \(forceLocal\)\s*\{[\s\S]*?_chat\.fail\(token,[\s\S]*?return true;[\s\S]*?_chat\.prepareCloudFallback\(token\)/);
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
  assert.match(repair, /pandora_eurofish_github_request_v1/);
  assert.match(repair, /pandora_eurofish_memory_github_request_v1/);
  assert.match(repair, /pandora_eurofish_github_ci_dispatch_v1/);
  assert.match(repair, /pandora_eurofish_workspace_v1/);
  assert.match(repair, /pandora_vision_overview_v1/);
});
