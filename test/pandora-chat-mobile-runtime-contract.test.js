const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const sourceMigration = readFileSync(
  join(root, 'supabase', 'migrations', '20260911143500_pandora_governed_mutations_v1.sql'),
  'utf8',
);
const repairMigration = readFileSync(
  join(root, 'supabase', 'migrations', '20260912182000_pandora_chat_source_contract_v1.sql'),
  'utf8',
);
const mobile = ['ask_pandora_screen.dart', 'chat/pandora_chat_composer.dart']
  .map(file => readFileSync(join(root, 'apps/pandora-mobile/lib/features/simple', file), 'utf8')).join('\n');

test('Pandora chat is an explicit ProjectOS intake source', () => {
  assert.match(sourceMigration, /'pandora_chat'/);
  assert.match(repairMigration, /projectos_intake_requests_source_check/);
  assert.match(repairMigration, /'pandora_chat'::text/);
  for (const source of ['operator', 'chatgpt', 'github', 'slack', 'email', 'api', 'system']) {
    assert.match(repairMigration, new RegExp(`'${source}'::text`));
  }
});

test('mobile chat keeps temporary-chat plus approved compact composer controls', () => {
  assert.match(mobile, /tooltip: 'Temporary chat'/);
  assert.match(mobile, /Icons\.history_toggle_off_rounded/);
  assert.match(mobile, /ask-pandora-plus/);
  assert.match(mobile, /ask-pandora-model-control/);
  assert.match(mobile, /Icons\.tune_rounded/);
  assert.match(mobile, /Icons\.mic_none_rounded/);
  assert.doesNotMatch(mobile, /Icons\.edit_square/);
});
