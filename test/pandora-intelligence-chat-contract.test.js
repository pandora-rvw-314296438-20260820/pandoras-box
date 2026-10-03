import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const edgePath = new URL('../supabase/functions/pandora-intelligence-chat/index.ts', import.meta.url);
const migrationPath = new URL('../supabase/migrations/20260830104500_pandora_intelligence_chat_v1.sql', import.meta.url);
const mobilePath = new URL('../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', import.meta.url);
const doctrinePath = new URL('../PROJECT_CUSTOM_INSTRUCTION.md', import.meta.url);
const roadmapPath = new URL('../docs/roadmaps/PANDORAS_BOX_CANONICAL_ROADMAP_V2.md', import.meta.url);
const screenPlanPath = new URL('../docs/product/PANDORA_SCREEN_MASTER_PLAN.md', import.meta.url);
const askPandoraScreenPath = new URL('../apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', import.meta.url);

const [edge, migration, mobile, doctrine, roadmap, screenPlan, askPandoraScreen] = await Promise.all([
  readFile(edgePath, 'utf8'),
  readFile(migrationPath, 'utf8'),
  readFile(mobilePath, 'utf8'),
  readFile(doctrinePath, 'utf8'),
  readFile(roadmapPath, 'utf8'),
  readFile(screenPlanPath, 'utf8'),
  readFile(askPandoraScreenPath, 'utf8'),
]);

test('Ask Pandora uses the Vault-backed model provider boundary', () => {
  assert.match(edge, /pandora_worker_b_gemini_request_20260829/);
  assert.doesNotMatch(edge, /generativelanguage\.googleapis\.com/);
  assert.doesNotMatch(edge, /Deno\.env\.get\(["'](?:GEMINI|GOOGLE).*KEY/i);
  assert.match(edge, /credentials and side effects stay inside Pandora's capability runtime and Worker C/i);
});

test('fallback intelligence is universal and capability-neutral', () => {
  assert.match(edge, /const intents=new Set\(\["chat","clarify","act","other"\]\)/);
  assert.match(edge, /const actionable=new Set\(\["act"\]\)/);
  assert.match(edge, /Software building is one capability among communications, research, files, device actions, business, travel, scheduling, coding and future capabilities/);
  assert.match(edge, /const allowed=new Set<string>\(\)/);
  assert.match(edge, /kind:\s*["']capability_request["']/);
  assert.doesNotMatch(edge, /allowed names: [^"\n]*project\./i);
  assert.doesNotMatch(edge, /create_project","change_project","inspect_project/);
  assert.match(doctrine, /intent → project → build/);
  assert.match(doctrine, /unless the actual user request is a software-building task/i);
});

test('legacy mobile chat preserves capability-first fallback and v2 admits on the server', () => {
  assert.match(mobile, /pandora_chat_universal_dispatch_v9/);
  assert.match(
    mobile,
    /final capabilityTurn = await _dispatchCapability\([\s\S]*?projectId: projectId,[\s\S]*?if \(capabilityTurn != null\) return capabilityTurn;/,
  );
  assert.match(mobile, /if \(projectId != null\) 'p_project_id': projectId/);
  const dispatchIndex = mobile.indexOf('final capabilityTurn = await _dispatchCapability(');
  const fallbackIndex = mobile.indexOf('final response = await _client.functions.invoke(', dispatchIndex);
  assert.ok(dispatchIndex >= 0, 'universal capability dispatch must exist');
  assert.ok(fallbackIndex > dispatchIndex, 'universal capability dispatch must run before model fallback');
  const v2 = mobile.slice(mobile.indexOf('Stream<PandoraChatWireEvent> executeChatTurn('), mobile.indexOf('Stream<Map<String, dynamic>> watchChatActivity('));
  assert.match(v2, /'protocolVersion': 2/);
  assert.match(v2, /'clientTurnId': dispatch\.token\.turnId/);
  assert.match(v2, /_client\.functions\s*\.invoke\(/);
  assert.doesNotMatch(v2, /_dispatchCapability\(|startChatExecution\(|beginJob\(/,
    'v2 admission owns the Activity job and capability execution atomically');
});

test('native capability routing classifies only the owner message, never the Enterprise context envelope', () => {
  assert.match(
    edge,
    /dispatchMessage=controlledMessage\(controlState\.message,controlState\.constraints\)/,
  );
  assert.doesNotMatch(
    edge,
    /dispatchMessage=.*contextualMessage\(controlledMessage\(controlState\.message,controlState\.constraints\),i\.enterpriseContext\)/,
  );
});

test('current product doctrine is not delegated to builder-era roadmap inventories', () => {
  assert.match(roadmap, /HISTORICAL ROADMAP EVIDENCE/);
  assert.match(screenPlan, /HISTORICAL IMPLEMENTATION INVENTORY/);
  assert.match(roadmap, /universal personal AI operating layer/i);
  assert.match(screenPlan, /Universal Chat/i);
});

test('durable conversation history is owner-readable but service-written', () => {
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /created_by\s*=\s*auth\.uid\(\)/i);
  assert.match(migration, /revoke insert, update, delete[\s\S]*from anon, authenticated/i);
  assert.match(migration, /grant all[\s\S]*to service_role/i);
});

test('the APK calls Pandora intelligence and carries no provider secret contract', () => {
  assert.match(mobile, /functionName = 'pandora-intelligence-chat'/);
  assert.doesNotMatch(mobile, /gemini_api_key|x-goog-api-key|service[_-]?role/i);
});


test('mobile chat delegates anchoring to a stateful viewport and consumes Android insets once', () => {
  assert.match(askPandoraScreen, /resizeToAvoidBottomInset:\s*true/);
  assert.match(askPandoraScreen, /LayoutBuilder/);
  assert.match(askPandoraScreen, /viewportSize:\s*constraints\.biggest/);
  assert.match(askPandoraScreen, /PandoraChatViewport\(/);
  assert.match(askPandoraScreen, /top:\s*safeTop/);
  assert.match(askPandoraScreen, /bottom:\s*0/);
  assert.doesNotMatch(askPandoraScreen, /bottom:\s*keyboardInset/);
  assert.doesNotMatch(askPandoraScreen, /_scrollToBottom|_pendingMessage|_submitting/);
});

test('internal Enterprise context is sanitized before persistence, API response, and mobile rendering', () => {
  assert.match(edge, /const cleanReply=visibleModelReply\(v\.reply,handoff\)/);
  assert.match(edge, /author_role:"assistant",content:cleanReply/);
  assert.match(edge, /completionResult=\{threadId:tid,reply:cleanReply/);
  assert.match(edge, /responsePayload=\{\.\.\.completionResult,assistantMessageId\}/);
  assert.match(askPandoraScreen, /_sanitizeVisiblePandoraText/);
  assert.match(askPandoraScreen, /bounded enterprise page context:/i);
});


test('owner-facing Pandora injects canonical M5 Memory through the server workload boundary', () => {
  assert.match(edge, /https:\/\/mcpmaster\.vercel\.app\/api\/operations-memory/);
  assert.match(edge, /combinedTrustedContext\(req,c\.admin,c\.organizationId,i\.projectId,effectiveInitial,turn\?\.timings\?\?null\)/);
  assert.match(edge, /Use relevant prior failure lessons, procedures, outcomes, and provider evidence to avoid repeating known mistakes/);
  assert.match(edge, /canonicalMemoryItemIds/);
  assert.match(edge, /retrievalDoesNotGrantExecutionAuthority===true/);
  assert.doesNotMatch(edge, /x-pandora-vercel-oidc|getVercelOidcToken|resolveVercelWorkloadToken/);
});
