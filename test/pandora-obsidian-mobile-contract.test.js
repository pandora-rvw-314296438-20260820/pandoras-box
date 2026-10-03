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
  const emptyStart = chat.indexOf('class _EmptyConversation extends StatelessWidget');
  const conversationStart = chat.indexOf('class _Conversation extends StatefulWidget', emptyStart);
  const composerStart = chat.indexOf('class _Composer extends StatelessWidget');
  const compactMenuStart = chat.indexOf('class _CompactAttachmentMenu extends StatelessWidget', composerStart);
  assert.ok(emptyStart >= 0 && conversationStart > emptyStart);
  assert.ok(composerStart >= 0 && compactMenuStart > composerStart);
  const genericLanding = chat.slice(emptyStart, conversationStart);
  const genericComposer = chat.slice(composerStart, compactMenuStart);

  assert.match(genericLanding, /pandora-logo-only-landing/);
  assert.match(genericLanding, /size:\s*28/);
  assert.doesNotMatch(
    genericLanding,
    /What can I help with|Ask a question, describe a change|_suggestions|_ObsidianSuggestion/,
  );
  assert.match(genericComposer, /Message Pandora…/);
  assert.match(genericComposer, /height:\s*54/);
  assert.match(genericComposer, /Color\(0xFF151515\)/);
  assert.match(genericComposer, /BorderRadius\.circular\(27\)/);
  assert.match(genericComposer, /ask-pandora-composer/);
  assert.match(genericComposer, /final voiceReady =\s*!submitting && empty/);
  assert.match(genericComposer, /tooltip: voiceReady[\s\S]*?'Voice input'[\s\S]*?'Send'/);
  assert.doesNotMatch(genericComposer, /backgroundColor:\s*Colors\.white/);
  assert.doesNotMatch(chat, /WebView|InAppWebView/);
});

test('PLP may retain its verified e7 chat presentation without changing generic Core chat', () => {
  assert.match(chat, /plp-e7-chat-surface/);
  assert.match(chat, /class _PlpE7Composer/);
  assert.match(chat, /Icons\.view_in_ar_outlined/);
  assert.match(chat, /Icons\.mic_none_rounded/);
  assert.match(chat, /Icons\.arrow_upward_rounded/);
  assert.match(chat, /ask-pandora-menu-model/);
  assert.match(chat, /ask-pandora-menu-reasoning/);
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
