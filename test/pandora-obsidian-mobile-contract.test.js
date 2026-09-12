const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const simple = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'pandora_simple_ui.dart'), 'utf8');
const v2 = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'pandora_v2_ui.dart'), 'utf8');
const shell = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'app', 'pandora_chat_shell.dart'), 'utf8');
const navigation = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'core', 'widgets', 'pandora_navigation.dart'), 'utf8');
const chat = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'ask_pandora_screen.dart'), 'utf8');
const projects = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'projects_screen.dart'), 'utf8');

test('approved Obsidian palette is native Flutter dark UI', () => {
  assert.match(simple, /canvas = Color\(0xFF000000\)/);
  assert.match(simple, /surface = Color\(0xFF0A0A0A\)/);
  assert.match(simple, /line = Color\(0xFF222222\)/);
  assert.match(v2, /canvas = Color\(0xFF000000\)/);
  assert.match(shell, /ColorScheme\.dark\(/);
  assert.match(shell, /brightness: Brightness\.dark/);
});

test('chat matches the Obsidian conversation-first hierarchy without a WebView shell', () => {
  assert.match(chat, /What can I help with\?/);
  assert.match(chat, /class _ObsidianSuggestion/);
  assert.match(chat, /backgroundColor: Colors\.white/);
  assert.match(chat, /Icons\.arrow_upward_rounded/);
  assert.doesNotMatch(chat, /WebView|InAppWebView/);
});

test('projects use native Obsidian workspace cards backed by real ProjectSummary data', () => {
  assert.match(projects, /GridView\.builder/);
  assert.match(projects, /class _ObsidianProjectCard/);
  assert.match(projects, /ProjectSummary project/);
  assert.match(projects, /projectPurposeForDisplay/);
});


test('latest Obsidian navigation hierarchy stays conversation-first and centered', () => {
  assert.match(shell, /Settings & More/);
  assert.match(shell, /Connections/);
  assert.match(navigation, /Stack\(/);
  assert.match(navigation, /keyboard_arrow_down_rounded/);
  assert.match(navigation, /showPandoraChevron/);
});
