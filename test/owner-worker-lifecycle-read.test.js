const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');

test('authenticated owner API exposes a bounded exact worker lifecycle read', () => {
  const source = readFileSync(
    join(root, 'supabase/functions/pandora-owner-api/index.ts'),
    'utf8',
  );
  assert.match(source, /GET" && \/\^\\\/worker-plans\\\/\[\^\/\]\+\$\//);
  assert.match(source, /get_governed_worker_execution/);
  assert.match(source, /worker_01_claim_observed/);
  assert.match(source, /provider_result_observed/);
  assert.match(source, /final_proof_available/);
  assert.match(source, /label: "Worker-01"/);
  assert.doesNotMatch(
    source.slice(source.indexOf('async function governedWorkerExecution'),
      source.indexOf('async function acceptIntake')),
    /stdoutSha256|stderrSha256|jobPayload|jobSignature/,
  );
});

test('mobile exact-source card keeps one write key and polls the exact plan', () => {
  const repository = readFileSync(
    join(root, 'apps/pandora-mobile/lib/core/data/remote_pandora_repository.dart'),
    'utf8',
  );
  const card = readFileSync(
    join(root, 'apps/pandora-mobile/lib/features/command/exact_source_verification_card.dart'),
    'utf8',
  );
  assert.match(repository, /pathSegments: <String>\['worker-plans', id\]/);
  assert.match(card, /_idempotencyKey \?\?=/);
  assert.match(card, /workerExecution\(planId: planId\)/);
  assert.match(card, /Timer\.periodic/);
  assert.match(card, /exact-source-worker-claim/);
  assert.match(card, /Final reviewer proof/);
});
