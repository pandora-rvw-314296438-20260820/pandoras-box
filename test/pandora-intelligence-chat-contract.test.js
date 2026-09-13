import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const edgePath = new URL('../supabase/functions/pandora-intelligence-chat/index.ts', import.meta.url);
const migrationPath = new URL('../supabase/migrations/20260830104500_pandora_intelligence_chat_v1.sql', import.meta.url);
const mobilePath = new URL('../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', import.meta.url);
const doctrinePath = new URL('../PROJECT_CUSTOM_INSTRUCTION.md', import.meta.url);
const roadmapPath = new URL('../docs/roadmaps/PANDORAS_BOX_CANONICAL_ROADMAP_V2.md', import.meta.url);
const screenPlanPath = new URL('../docs/product/PANDORA_SCREEN_MASTER_PLAN.md', import.meta.url);

const [edge, migration, mobile, doctrine, roadmap, screenPlan] = await Promise.all([
  readFile(edgePath, 'utf8'),
  readFile(migrationPath, 'utf8'),
  readFile(mobilePath, 'utf8'),
  readFile(doctrinePath, 'utf8'),
  readFile(roadmapPath, 'utf8'),
  readFile(screenPlanPath, 'utf8'),
]);

test('Ask Pandora uses the Vault-backed model provider boundary', () => {
  assert.match(edge, /pandora_worker_b_gemini_request_20260829/);
  assert.doesNotMatch(edge, /generativelanguage\.googleapis\.com/);
  assert.doesNotMatch(edge, /Deno\.env\.get\(["'](?:GEMINI|GOOGLE).*KEY/i);
  assert.match(edge, /You may propose actions|never execute tools/i);
});

test('fallback intelligence is universal and capability-neutral', () => {
  assert.match(edge, /const intents=new Set\(\["chat","clarify","act","other"\]\)/);
  assert.match(edge, /const actionable=new Set\(\["act"\]\)/);
  assert.match(edge, /Software building is one capability among communications, research, files, device actions, business, travel, scheduling, coding and future capabilities/);
  assert.match(edge, /const allowed=new Set<string>\(\)/);
  assert.match(edge, /kind:\s*["']governed_intake["']/);
  assert.doesNotMatch(edge, /project\.build\.request|project\.create/);
  assert.match(doctrine, /intent → project → build/);
  assert.match(doctrine, /unless the actual user request is a software-building task/i);
});

test('mobile chat dispatches universal capabilities before model fallback', () => {
  assert.match(mobile, /pandora_chat_universal_dispatch_v7/);
  assert.match(mobile, /if \(capabilityTurn != null\) return capabilityTurn/);
  assert.match(mobile, /Projects are optional and do not limit Pandora's general capabilities/);
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
