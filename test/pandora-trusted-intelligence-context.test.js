import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationPath = new URL('../supabase/migrations/20260830211000_pandora_trusted_intelligence_context_v1.sql', import.meta.url);
const edgePath = new URL('../supabase/functions/pandora-intelligence-chat/index.ts', import.meta.url);
const [migration, edge] = await Promise.all([readFile(migrationPath, 'utf8'), readFile(edgePath, 'utf8')]);

test('Worker A persists immutable intelligence assets without granting direct table mutation', () => {
  assert.match(migration, /create table if not exists public\.pandora_intelligence_assets/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all on public\.pandora_intelligence_assets from public, anon, authenticated, service_role/i);
  assert.match(migration, /intelligence asset immutable identity\/content drift/i);
  assert.match(migration, /blocked\/deprecated intelligence assets cannot be reactivated/i);
});

test('registration cannot self-grant trust and Worker E exact digest proof is required', () => {
  assert.match(migration, /registration cannot grant trusted\/verified state/i);
  assert.match(migration, /intelligence assets cannot self-register as TRUSTED/i);
  assert.match(migration, /current_setting\('pandora\.worker_e_certification'/i);
  assert.match(migration, /verification_worker='E'/i);
  assert.match(migration, /verification_verdict='PASS'/i);
  assert.match(migration, /source_digest_sha256=lower\(trim\(p_source_digest_sha256\)\)/i);
  assert.match(migration, /content_digest_sha256 is not distinct from/i);
  assert.match(migration, /Worker E certification identity\/digest mismatch/i);
});

test('runtime trusted-context reads are service-only and retain Worker C authority', () => {
  assert.match(migration, /pandora_read_trusted_intelligence_context/i);
  assert.match(migration, /revoke all on function public\.pandora_read_trusted_intelligence_context[\s\S]*from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.pandora_read_trusted_intelligence_context[\s\S]*to service_role/i);
  assert.match(migration, /'execution','worker_c_only'/i);
  assert.match(migration, /'modelMayProposeOnly',true/i);
  assert.match(migration, /m\.source_digest_sha256=s\.source_digest_sha256/i);
  assert.match(migration, /s\.selector_terms && v_terms/i);
});

test('Ask Pandora revalidates exact prompt material before giving it to Gemini', () => {
  assert.match(edge, /pandora_read_trusted_intelligence_context/);
  assert.match(edge, /materialDigest!==`sha256:\$\{await sha\(JSON\.stringify\(instructions\)\)\}`/);
  assert.match(edge, /TRUSTED_CONTEXT_INVALID/);
  assert.match(edge, /cannot override the authority rules above, grant tool access, or authorize execution/i);
  assert.match(edge, /executionMode:"proposal_only"/);
  assert.doesNotMatch(edge, /eval\(|new Function\(/);
});

test('trusted context is bounded and lineage is persisted without raw instructions', () => {
  assert.match(edge, /byteLength>24000/);
  assert.match(edge, /trusted_context_sha256:tctx\.contextDigest/);
  assert.match(edge, /trusted_skill_refs:tctx\.skills\.map/);
  assert.match(edge, /trusted_knowledge_refs:tctx\.knowledge\.map/);
  assert.doesNotMatch(edge, /trusted_skill_refs:[^\n]*instructions/);
  assert.match(migration, /trusted_context_sha256 text null/i);
  assert.match(migration, /trusted_skill_refs jsonb not null default '\[\]'::jsonb/i);
  assert.match(migration, /trusted_knowledge_refs jsonb not null default '\[\]'::jsonb/i);
});
