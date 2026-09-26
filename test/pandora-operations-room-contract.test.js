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
const roles = readFileSync(
  join(
    root,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'operations',
    'operations_room_roles.dart',
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

const ROSTER = [
  'ATHENA',
  'APOLLO',
  'HERMES',
  'HEPHAESTUS',
  'ARTEMIS',
  'THEMIS',
  'MNEMOSYNE',
  'HESTIA',
  'IRIS',
  'ASCLEPIUS',
  'NIKE',
  'HECATE',
  'PROMETHEUS',
  'DEMETER',
];

test('Operations Room is a first-class persistent Pandora navigation surface', () => {
  assert.match(shell, /Operations Room/);
  assert.match(shell, /PandoraOperationsRoomScreen\(onHome: \(\) => _select\(9\)\)/);
  assert.match(room, /operations-room-chat/);
  assert.match(room, /operations-room-composer/);
  assert.match(room, /recentThreads\(limit: 100\)/);
  assert.match(room, /intelligence\.messages\(room\.id, limit: 500\)/);
  assert.match(room, /_roomThreadPrefix/);
  assert.match(room, /mode\.name/);
});

test('Operations Room binds all fourteen specialist identities in one registry', () => {
  for (const role of ROSTER) {
    assert.match(roles, new RegExp(role));
    assert.match(intelligence, new RegExp(role));
  }
  assert.match(roles, /operationsRoomRoles/);
  assert.match(room, /import 'operations_room_roles\.dart'/);
  assert.match(room, /hiddenCount specialists/);
});

test('automatic routing selects a bounded relevant team rather than all specialists', () => {
  assert.match(room, /operationsRoomRecommendedRoles/);
  assert.ok(room.includes('operationsRoomRequestsTeam'));
  assert.ok(room.includes("['HERMES', 'HEPHAESTUS', 'ARTEMIS']"));
  assert.match(room, /return selected\.take\(4\)/);
  assert.match(room, /HECATE.*NIKE.*PROMETHEUS/s);
  assert.match(room, /HEPHAESTUS.*HESTIA.*ASCLEPIUS.*ARTEMIS/s);
  assert.match(room, /HEPHAESTUS.*THEMIS.*ARTEMIS.*ASCLEPIUS.*HESTIA/s);
});

test('Operations Room context stays inside the live selected-object cap', () => {
  for (const field of [
    'roomMode',
    'mentions',
    'orchestrationStage',
    'targetRole',
    'roomRosterVersion',
    'architecturePolicy',
    'localModel',
    'localRuntimeEvidence',
  ]) {
    assert.ok(room.includes("'" + field + "':"));
  }
  for (const removed of [
    'acceptedLocalModelSha256',
    'infrastructurePolicy',
    'accelerationPolicy',
    'forbiddenCompute',
  ]) {
    assert.ok(!room.includes("'" + removed + "':"));
  }
  assert.ok(
    intelligence.includes(
      'if(entries.length>8)throw Error("INVALID_ENTERPRISE_CONTEXT")',
    ),
  );
});

test('real specialist turns precede Athena coordination', () => {
  assert.match(room, /stage: 'specialist_analysis'/);
  assert.match(room, /targetRole: role/);
  assert.match(room, /findings\.add/);
  assert.match(room, /stage: allowExecution \? 'lead' : 'athena_synthesis'/);
  assert.match(room, /OPERATIONS_ROOM_INTERNAL/);
  assert.match(intelligence, /real specialist turn/);
  assert.match(intelligence, /no specialist message or provider event may be invented/);
});

test('advisory turns remain analysis-only while execution lead retains capability routing', () => {
  assert.match(
    intelligence,
    /operationsStage==="specialist_analysis"\|\|operationsStage==="athena_synthesis"/,
  );
  assert.match(
    intelligence,
    /dispatched=operationsAdvisory\?null:await universalDispatch/,
  );
  assert.match(room, /allowExecution = _mode == OperationsRoomMode\.execution/);
});

test('mobile room uses compact roster, unclipped mode buttons, home navigation and live evidence', () => {
  assert.match(room, /14 specialists · shared team thread/);
  assert.match(room, /operations-room-roster/);
  assert.match(room, /operations-room-home/);
  assert.match(room, /operations-room-live-event/);
  assert.match(room, /Flexible\(/);
  assert.doesNotMatch(room, /SegmentedButton<OperationsRoomMode>/);
});

test('working state is driven only by real in-flight room turns', () => {
  assert.match(room, /_setActive\(role\)/);
  assert.match(room, /_setActive\('ATHENA'\)/);
  assert.match(room, /_activeRoles = const <String>\{\}/);
  assert.ok(room.includes('activeRoles.length == 1'));
});
