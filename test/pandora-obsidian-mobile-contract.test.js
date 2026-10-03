const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const simple = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'pandora_simple_ui.dart'), 'utf8');
const v2 = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'pandora_v2_ui.dart'), 'utf8');
const tokens = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'core', 'design', 'pandora_tokens.dart'), 'utf8');
const shell = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'app', 'pandora_chat_shell.dart'), 'utf8');
const navigation = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'core', 'widgets', 'pandora_navigation.dart'), 'utf8');
const chat = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'ask_pandora_screen.dart'), 'utf8');
const composer = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'chat', 'pandora_chat_composer.dart'), 'utf8');
const projects = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'projects_screen.dart'), 'utf8');

test('approved Obsidian palette is native Flutter dark UI', () => {
  assert.match(simple, /canvas = Color\(0xFF000000\)/);
  assert.match(simple, /surface = Color\(0xFF0A0A0A\)/);
  assert.match(simple, /line = Color\(0xFF222222\)/);
  assert.match(v2, /canvas = Color\(0xFF000000\)/);
  assert.match(v2, /surface = Color\(0xFF0A0A0A\)/);
  assert.match(v2, /line = Color\(0xFF222222\)/);
  assert.match(v2, /action = Color\(0xFFFFFFFF\)/);
  assert.match(v2, /onAction = Color\(0xFF000000\)/);
  assert.match(shell, /ColorScheme\.dark\(/);
  assert.match(shell, /brightness: Brightness\.dark/);
});

test('chat landing is logo-only with a bare borderless always-live composer', () => {
  assert.match(chat, /pandora-logo-only-landing/);
  assert.match(chat, /size:\s*28/);
  assert.doesNotMatch(
    chat,
    /What can I help with|Ask a question, describe a change|_suggestions|_ObsidianSuggestion/,
  );
  assert.match(chat, /PandoraChatComposer\(/);
  assert.match(composer, /Message Pandora…/);
  assert.match(composer, /BoxConstraints\(minHeight:\s*54\)/);
  assert.match(composer, /Color\(0xFF151515\)/);
  assert.match(composer, /BorderRadius\.circular\(27\)/);
  assert.match(composer, /ask-pandora-composer/);
  assert.match(composer, /bool get canDictate[\s\S]*?voiceAvailable[\s\S]*?phase == PandoraComposerPhase\.idle/);
  assert.match(composer, /final voice = empty && widget\.onVoice != null/);
  assert.match(composer, /'Voice input'/);
  assert.match(composer, /'Send message'/);
  assert.match(composer, /liveActivation:[\s\S]*?_activatePrimary/);
  assert.doesNotMatch(composer, /hintText:\s*'Follow up|Text\('Back'\)/);
  assert.doesNotMatch(chat + composer, /backgroundColor:\s*Colors\.white/);
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
