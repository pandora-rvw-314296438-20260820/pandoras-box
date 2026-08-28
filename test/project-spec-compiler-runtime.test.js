'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync('supabase/migrations/20260829104500_pandora_project_spec_compiler_v1.sql','utf8');
const edge = fs.readFileSync('supabase/functions/pandora-project-spec-compiler/index.ts','utf8');
const mobile = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart','utf8');
const config = fs.readFileSync('supabase/config.toml','utf8');

test('ProjectSpec compilation is one-intent idempotent and leased',()=>{
  assert.match(migration,/unique index if not exists pandora_project_specs_source_intent_uidx/);
  assert.match(migration,/unique \(source_intent_id\)/);
  assert.match(migration,/status in \('running','succeeded','failed'\)/);
  assert.match(migration,/started_at > now\(\) - interval '2 minutes'/);
  assert.match(migration,/claim_token=p_claim_token/);
});

test('ProjectSpec commit supersedes and inserts atomically behind service role',()=>{
  assert.match(migration,/for update/);
  assert.match(migration,/set status='superseded', superseded_at=now\(\)/);
  assert.match(migration,/insert into public\.pandora_project_specs/);
  assert.match(migration,/grant execute on function public\.pandora_commit_compiled_project_spec_20260829[\s\S]*to service_role/);
  assert.match(migration,/revoke all on function public\.pandora_commit_compiled_project_spec_20260829[\s\S]*from public, anon, authenticated/);
});

test('compiler rejects credential-shaped model output and never reads provider key',()=>{
  assert.doesNotMatch(edge,/Deno\.env\.get\(["'](?:GEMINI|GOOGLE|VERCEL|GITHUB).*KEY/i);
  assert.doesNotMatch(edge,/gemini_api_key/);
  assert.match(edge,/pandora_worker_b_gemini_request_20260829/);
  assert.match(edge,/INVALID_STRUCTURED_OUTPUT/);
  assert.match(edge,/github_pat_/);
  assert.match(edge,/responseMimeType:\s*"application\/json"/);
});

test('compiler surface is authenticated and provider-blind to the customer',()=>{
  assert.match(config,/\[functions\.pandora-project-spec-compiler\]\nverify_jwt = true/);
  assert.match(edge,/exactKeys\(body, \["intentId"\]\)/);
  assert.match(edge,/return response\(\{ ok: true, state: "ready" \}\)/);
  assert.doesNotMatch(edge,/return response\([^\n]*(?:gemini|provider)/i);
});

test('mobile waiting state requests compilation with cooldown and keeps durable truth',()=>{
  assert.match(mobile,/pandora-project-spec-compiler/);
  assert.match(mobile,/Duration\(seconds: 20\)/);
  assert.match(mobile,/unawaited\(_ensureCompilation\(expectedSourceIntentId\)\)/);
  assert.match(mobile,/return const OwnerProjectUnderstanding\.waiting\(\)/);
  assert.doesNotMatch(mobile,/Gemini|Vercel|GitHub|GPT/);
});
