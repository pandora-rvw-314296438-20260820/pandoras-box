const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const chat = readFileSync(
  join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'app', 'pandora_chat_shell.dart'),
  'utf8',
);
const plp = readFileSync(
  join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'app', 'plp_navigation_drawer.dart'),
  'utf8',
);

test('Pandora chat side panel uses the same pure-black canvas as chat', () => {
  assert.match(chat, /drawer:\s*Drawer\([\s\S]*?backgroundColor:\s*const Color\(0xFA000000\)/);
  assert.match(chat, /class _PandoraSidePanel[\s\S]*?Material\([\s\S]*?color:\s*const Color\(0xFA000000\)/);
  assert.match(chat, /drawerScrimColor:\s*const Color\(0xD9000000\)/);
});

test('PLP navigation side panel is opaque pure black', () => {
  assert.match(plp, /DecoratedBox\([\s\S]*?color:\s*Color\(0xFF000000\)/);
  assert.doesNotMatch(plp, /color:\s*Color\(0xF20A0C10\)/);
});
