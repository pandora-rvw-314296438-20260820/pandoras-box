const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const room = readFileSync(
  join(
    root,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'operations',
    'operations_room_screen.dart',
  ),
  'utf8',
);
const shell = readFileSync(
  join(root, 'apps', 'pandora-mobile', 'lib', 'app', 'pandora_chat_shell.dart'),
  'utf8',
);
const intelligence = readFileSync(
  join(
    root,
    'supabase',
    'functions',
    'pandora-intelligence-chat',
    'index.ts',
  ),
  'utf8',
);

test('Operations Room is a first-class Pandora navigation surface', () => {
  assert.match(shell, /Operations Room/);
  assert.match(shell, /PandoraOperationsRoomScreen/);
  assert.match(room, /operations-room-chat/);
  assert.match(room, /operations-room-composer/);
});

test('Operations Room binds the six canonical specialist roles', () => {
  for (const role of [
    'ATHENA',
    'APOLLO',
    'HERMES',
    'HEPHAESTUS',
    'THEMIS',
    'ARTEMIS',
  ]) {
    assert.match(room, new RegExp(role));
    assert.match(intelligence, new RegExp('\\[\\[ROLE:' + role + '\\]\\]'));
  }
});

test('Operations Room preserves real runtime evidence and mode semantics', () => {
  assert.match(room, /PandoraActivityTimelineController/);
  assert.match(room, /PandoraActivityTimelineView/);
  assert.match(room, /OperationsRoomMode\.execution/);
  assert.match(room, /OperationsRoomMode\.council/);
  assert.match(room, /OperationsRoomMode\.incident/);
  assert.match(room, /specialist_analysis/);
  assert.match(room, /athena_synthesis/);
  assert.match(room, /Independent specialist findings/);
  assert.match(intelligence, /enterprise_operations_room/);
  assert.match(intelligence, /runtime evidence remains authoritative/);
  assert.match(intelligence, /real independent specialist turn/);
  assert.match(intelligence, /athena_synthesis/);
});

test('Council and Incident use independent specialist turns before Athena synthesis', () => {
  for (const role of ['APOLLO', 'HERMES', 'HEPHAESTUS', 'THEMIS', 'ARTEMIS']) {
    assert.match(room, new RegExp("'" + role + "'"));
  }
  assert.match(room, /for \(final role in roles\)/);
  assert.match(room, /targetRole: role/);
  assert.match(room, /targetRole: 'ATHENA'/);
});

test('advisory specialist and synthesis turns cannot execute capabilities', () => {
  assert.match(
    intelligence,
    /operationsStage==="specialist_analysis"\|\|operationsStage==="athena_synthesis"/,
  );
  assert.match(
    intelligence,
    /dispatched=operationsAdvisory\?null:await universalDispatch/,
  );
});
