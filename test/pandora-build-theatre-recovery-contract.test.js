import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const root = process.cwd();
const conversation = readFileSync(
  join(
    root,
    'apps/pandora-mobile/lib/features/simple/project_build_conversation.dart',
  ),
  'utf8',
);
const api = readFileSync(
  join(root, 'apps/pandora-mobile/lib/core/data/project_experience_api.dart'),
  'utf8',
);

test('Build Theatre reconnects and replays the same durable stream', () => {
  assert.match(api, /watchResilientBuildStream/);
  assert.match(api, /snapshot\.requiresReplay/);
  assert.match(conversation, /snapshot\.requiresReplay/);
  assert.match(conversation, /snapshot\.reconnecting/);
  assert.match(
    conversation,
    /Reconnecting to the same build\. Your project continues from its saved state\./,
  );
});

test('Build Theatre surfaces consequential blocker and safe failure truth', () => {
  assert.match(conversation, /experience\?\.needsYou == true/);
  assert.match(conversation, /title: 'Needs You'/);
  assert.match(conversation, /experience\?\.hasSafeFailure == true/);
  assert.match(conversation, /experience\?\.safeFailureMessage/);
  assert.match(conversation, /title: 'Problem'/);
});

test('Build Theatre exposes retry and rollback availability without automatic mutation', () => {
  assert.match(conversation, /experience\?\.retryAvailable == true/);
  assert.match(conversation, /Pandora will not retry automatically/);
  assert.match(conversation, /experience\?\.canRollback == true/);
  assert.match(conversation, /remains approval-gated/);
});

test('Build Theatre can render provider fallback and rollback lifecycle events', () => {
  assert.match(conversation, /case 'provider_fallback_started':/);
  assert.match(conversation, /case 'provider_fallback_completed':/);
  assert.match(conversation, /case 'rollback_started':/);
  assert.match(conversation, /case 'rollback_completed':/);
});
