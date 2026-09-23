import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const shell = readFileSync(
  'apps/pandora-mobile/lib/app/plp_enterprise_shell.dart',
  'utf8',
);
const chat = readFileSync(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const team = readFileSync(
  'apps/pandora-mobile/lib/features/team/team_screen.dart',
  'utf8',
);
const operationsRoom = readFileSync(
  'apps/pandora-mobile/lib/features/operations/operations_room_screen.dart',
  'utf8',
);

test('shared PLP command dock follows the keyboard only while its field owns focus', () => {
  assert.match(shell, /AnimatedBuilder\([\s\S]*animation: focusNode/);
  assert.match(shell, /focusNode\.hasFocus[\s\S]*MediaQuery\.viewInsetsOf\(context\)\.bottom/);
  assert.match(shell, /plp-command-keyboard-offset/);
  assert.match(shell, /AnimatedPadding\(/);
  assert.match(shell, /padding: EdgeInsets\.only\(bottom: keyboardInset\)/);
});

test('Ask Pandora full chat composer follows the keyboard inset', () => {
  assert.match(chat, /final keyboardInset = media\.viewInsets\.bottom/);
  assert.match(
    chat,
    /Positioned\([\s\S]*left: 0,[\s\S]*right: 0,[\s\S]*bottom: keyboardInset,[\s\S]*key: _composerKey/,
  );
});

test('shared command dock remains shell-level across every non-chat PLP destination', () => {
  assert.match(shell, /bottomNavigationBar: _index == 1[\s\S]*PlpCommandDock\(/);
  for (const destination of [
    "'home': 0",
    "'operations': 2",
    "'vision': 3",
    "'local-ai': 4",
    "'overview': 5",
    "'guests': 6",
    "'team-access': 7",
    "'revenue': 8",
    "'needs-you': 9",
    "'activity': 10",
    "'settings': 11",
    "'developer': 12",
  ]) {
    assert.ok(shell.includes(destination), `missing PLP destination ${destination}`);
  }
});

test('nested PLP tool inputs own their keyboard space without the shared dock taking over', () => {
  assert.ok(
    (team.match(/MediaQuery\.viewInsetsOf\(context\)\.bottom/g) ?? []).length >= 2,
    'Team invite and access sheets must pad for the keyboard',
  );
  assert.match(operationsRoom, /return Scaffold\(/);
  assert.match(operationsRoom, /operations-room-composer/);
  assert.doesNotMatch(
    operationsRoom,
    /resizeToAvoidBottomInset:\s*false/,
    'Operations Room should retain Scaffold keyboard resizing',
  );
});
