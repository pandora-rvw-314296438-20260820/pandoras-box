const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync(
  'supabase/migrations/20260903082500_pandora_visible_creation_canary_control_v1.sql',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);
const analytics = fs.readFileSync(
  'apps/pandora-mobile/lib/core/analytics/owner_analytics.dart',
  'utf8',
);

test('Visible Creation canary defaults off and is service-only', () => {
  assert.match(migration, /enabled boolean not null default false/);
  assert.match(migration, /target_kind in \('user','project'\)/);
  assert.match(migration, /enable row level security/);
  assert.match(
    migration,
    /revoke all on table public\.pandora_visible_creation_canary_control from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /revoke all on table public\.pandora_visible_creation_canary_allowlist from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /grant execute on function public\.pandora_visible_creation_canary_allowed_v1\(uuid, uuid\) to service_role/,
  );
});

test('canary decision requires kill switch enabled plus user or project allowlist membership', () => {
  assert.match(migration, /coalesce\(\([\s\S]*c\.enabled[\s\S]*\), false\)/);
  assert.match(migration, /a\.enabled = true/);
  assert.match(migration, /a\.target_kind = 'user' and a\.target_id = p_user_id/);
  assert.match(migration, /a\.target_kind = 'project' and a\.target_id = p_project_id/);
});

test('build admission replays existing sessions before gating new canary work', () => {
  const existing = generator.indexOf('if (existingSession.data)');
  const gate = generator.indexOf('pandora_visible_creation_canary_allowed_v1');
  const spec = generator.indexOf('let { data: spec, error: specError }');
  assert.ok(existing >= 0, 'existing idempotent session path must exist');
  assert.ok(gate > existing, 'kill switch must not break replay of already-admitted sessions');
  assert.ok(spec > gate, 'new build work must be gated before spec compilation/admission');
  assert.match(generator, /if \(canary\.error \|\| canary\.data !== true\) throw new Error\("VISIBLE_CREATION_CANARY_DISABLED"\)/);
  assert.match(generator, /code === "VISIBLE_CREATION_CANARY_DISABLED" \? 403/);
});

test('canary cohort reliability and cost signals remain measurable without adding PII', () => {
  for (const eventName of [
    'build_admitted',
    'build_admission_failed',
    'first_stream_event',
    'stream_reconnected',
    'history_gap',
    'source_paywall_viewed',
  ]) {
    assert.ok(analytics.includes(`'${eventName}'`), `missing bounded analytics event ${eventName}`);
  }
  for (const metric of [
    'provider_latency_ms',
    'transport_latency_ms',
    'time_to_first_token_ms',
    'stream_completion_latency_ms',
    'end_to_end_latency_ms',
  ]) {
    assert.ok(generator.includes(metric), `missing source-generation metric ${metric}`);
  }
  assert.ok(!analytics.includes("'email':"));
  assert.ok(!analytics.includes("'ip':"));
});

test('canary-disabled admission is terminal and cannot amplify queue retries', () => {
  assert.match(
    generator,
    /\["BUILD_TYPE_NOT_SUPPORTED", "PROJECT_SPEC_NOT_READY", "PROJECT_NOT_AVAILABLE", "VISIBLE_CREATION_CANARY_DISABLED"\]\.includes\(code\)/,
  );
});
