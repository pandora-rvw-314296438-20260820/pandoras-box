'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');

test('active chat dispatcher retires the ProjectOS fallback', () => {
  const migration = read('supabase', 'migrations', '20260914050000_pandora_projectos_retirement_v1.sql');
  const body = migration.split('as $body$')[1]?.split('$body$;')[0] ?? '';
  assert.ok(body.length > 1000);
  assert.doesNotMatch(body, /pandora_chat_universal_dispatch_v8/i);
  assert.doesNotMatch(body, /projectos_accept_intake/i);
  assert.doesNotMatch(body, /source['\s,:]+projectos_intake/i);
  assert.match(body, /pandora_native_intelligence/);
  assert.match(body, /project_workspace_change/);
});

test('production execution ledger no longer auto-enrolls work into ProjectOS', () => {
  const ledger = read('src', 'runtime', 'execution-ledger-client.js');
  assert.match(ledger, /this\.enforceMandatoryIntake = false/);
  assert.doesNotMatch(ledger, /shouldEnforceMandatoryIntake/);
  assert.doesNotMatch(ledger, /new mandatory_intake_js_1\.ProjectOSExecutionIntakeProvider/);
  assert.doesNotMatch(ledger, /Mandatory ProjectOS intake is required/);
});

test('mobile composer consumes sent text immediately and preserves a typed follow-up', () => {
  const chat = read('apps', 'pandora-mobile', 'lib', 'features', 'simple', 'ask_pandora_screen.dart');
  const start = chat.indexOf('Future<void> _submit() async');
  const end = chat.indexOf('void _useSuggestion', start);
  assert.ok(start >= 0 && end > start);
  const submit = chat.slice(start, end);
  assert.equal((submit.match(/_objective\.clear\(\);/g) ?? []).length, 1);
  assert.ok(submit.indexOf('_objective.clear();') < submit.indexOf('intelligence.chat('));
  assert.match(chat, /hintText:\s*submitting\s*\?\s*'Follow up'\s*:\s*'Message Pandora'/s);
});

test('mobile navigation uses the Pandora menu glyph instead of the stock hamburger', () => {
  const nav = read('apps', 'pandora-mobile', 'lib', 'core', 'widgets', 'pandora_navigation.dart');
  assert.match(nav, /class _PandoraMenuGlyph/);
  assert.match(nav, /_MenuBar\(width: 20/);
  assert.doesNotMatch(nav, /Icons\.menu_rounded/);
});

test('More and Domains use the current dark hierarchy without duplicate settings clutter', () => {
  const more = read('apps', 'pandora-mobile', 'lib', 'features', 'simple', 'more_screen.dart');
  const advanced = read('apps', 'pandora-mobile', 'lib', 'features', 'simple', 'advanced_mode_screen.dart');
  const domains = read('apps', 'pandora-mobile', 'lib', 'features', 'simple', 'domains_screen.dart');
  assert.match(more, /PandoraSimplePage/);
  assert.match(more, /Professional tools/);
  assert.doesNotMatch(more, /Advanced requests|Developer details|Detailed owner view/);
  assert.equal((more.match(/title: 'Settings'/g) ?? []).length, 0);
  assert.doesNotMatch(advanced, /SettingsScreen|title: 'Account'|title: 'Settings'/);
  assert.doesNotMatch(domains, /0xFFFFF8F9|0xFFF2D9DE|SettingsScreen/);
  assert.match(domains, /backgroundColor: PandoraSimpleColors\.surface/);
});
