import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const generator = readFileSync(
  new URL('../supabase/functions/pandora-project-source-generator/index.ts', import.meta.url),
  'utf8',
);
const hardening = readFileSync(
  new URL('../supabase/migrations/20260830225000_pandora_static_fallback_hardening_v1.sql', import.meta.url),
  'utf8',
);

test('static source generation rejects placeholder-only pages before build intake', () => {
  assert.match(generator, /MIN_STATIC_INDEX_BYTES = 1024/);
  assert.match(generator, /name=\["'\]viewport/);
  assert.match(generator, /coming soon\|placeholder\).*normalizedIndex/);
  assert.match(generator, /never replace a complete product with a loading shell/);
});

test('static fallback persists capability before independent verification', () => {
  assert.match(hardening, /pandora_create_supabase_preview_fallback_20260830/);
  assert.match(hardening, /preview_fallback_committed/);
  assert.match(hardening, /pandora_worker_e_verify_supabase_preview_20260830/);
  assert.match(hardening, /provider='supabase_preview'/);
  assert.match(hardening, /previewCapabilityHash/);
  assert.match(hardening, /previewCapabilityExpiresAt/);
});

test('generated source repair preserves immutable artifact ancestry and supersedes stale work', () => {
  assert.match(hardening, /parent_version_id/);
  assert.match(hardening, /v_parent_artifact_version_id/);
  assert.match(hardening, /SUPERSEDED_BY_NEWER_VERSION/);
  assert.match(hardening, /status='cancelled'/);
});
