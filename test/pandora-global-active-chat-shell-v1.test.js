import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const shell = readFileSync(
  'apps/pandora-mobile/lib/app/pandora_chat_shell.dart',
  'utf8',
);
const chat = readFileSync(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const layer = readFileSync(
  'apps/pandora-mobile/lib/app/pandora_conversation_layer.dart',
  'utf8',
);
const operations = readFileSync(
  'apps/pandora-mobile/lib/features/operations/operations_room_screen.dart',
  'utf8',
);

test('main business shell mounts one app-level Pandora conversation', () => {
  assert.match(shell, /PandoraConversationLayer\(/);
  assert.match(shell, /shellOverlay:\s*true/);
  assert.equal((shell.match(/AskPandoraScreen\(/g) ?? []).length, 1);
  assert.match(layer, /compactComposerHeight = 68/);
  assert.match(layer, /MediaQuery\.viewPaddingOf\(context\)\.bottom/);
  assert.match(layer, /pandora-business-composer-clearance/);
  assert.match(layer, /EdgeInsets\.only\(bottom: businessBottomInset\)/);
  assert.match(layer, /removeBottom:\s*true/);
  assert.match(layer, /Positioned\.fill\(child: conversation\)/);
});

test('navigation rebinds page context without resetting the chat state', () => {
  assert.match(shell, /_conversationContextForCurrentSurface\(\)/);
  assert.match(shell, /if \(_index == 0 && _activeEnterpriseContext != null\)/);
  assert.match(shell, /'route': route/);
  const newChat = shell.slice(
    shell.indexOf('void _newChat()'),
    shell.indexOf('Future<void> _openThread', shell.indexOf('void _newChat()')),
  );
  assert.doesNotMatch(newChat, /_roots\.remove\(0\)|_select\(0\)/);
  assert.match(newChat, /chat\.newChat\(\)/);
  assert.match(newChat, /chat\.showHistory\(\)/);
});

test('shell mode keeps a compact keyboard-aware composer with one voice/send action', () => {
  assert.match(chat, /bool shellOverlay/);
  assert.match(chat, /bottom:\s*keyboardInset,[\s\S]*?key:\s*_composerKey/);
  assert.match(chat, /compact:\s*true/);
  assert.match(chat, /Message Pandora…/);
  assert.match(chat, /color:\s*compact \? const Color\(0xFF050505\) : Colors\.transparent/);
  assert.match(chat, /compact[\s\S]*?BoxDecoration\(color: Color\(0xFF050505\)\)/);
  assert.match(chat, /border:\s*compact[\s\S]*?\? null/);
  assert.match(chat, /fontSize:\s*compact \? 15\.5 : 16/);
  assert.match(chat, /final voiceReady =\s*compact && !submitting && empty/);
  assert.match(chat, /voiceReady \? onDictate : onSubmit/);
  assert.match(chat, /tooltip: voiceReady[\s\S]*?'Voice input'[\s\S]*?'Send'/);
  assert.doesNotMatch(chat, /backgroundColor:\s*Colors\.white/);
});

test('empty landing is globally logo-only with no legacy prompt or suggestion UI', () => {
  assert.match(chat, /class _EmptyConversation/);
  assert.match(chat, /pandora-logo-only-landing/);
  assert.match(chat, /size:\s*28/);
  assert.doesNotMatch(
    chat,
    /What can I help with|Ask a question, describe a change|_suggestions|_ObsidianSuggestion/,
  );
});


test('history expands after engagement and minimizes without unmounting the conversation', () => {
  assert.match(chat, /if \(widget\.shellOverlay\) _shellHistoryExpanded = true/);
  assert.match(chat, /Offstage\([\s\S]*offstage: !_shellHistoryExpanded/);
  assert.match(chat, /pandora-active-chat-minimize/);
  assert.match(chat, /void minimizeHistory\(\)/);
  assert.match(chat, /activityRequested:[\s\S]*widget\.shellOverlay \? false/);
});

test('Operations Room defers chat ownership to the app-level conversation', () => {
  assert.match(shell, /PandoraOperationsRoomScreen\([\s\S]*globalConversation:\s*true/);
  assert.match(operations, /final bool globalConversation/);
  assert.match(operations, /if \(widget\.globalConversation\) \{[\s\S]*_buildGlobalConversationWorkspace\(\)/);
  const embedded = operations.slice(
    operations.indexOf('Widget _buildGlobalConversationWorkspace'),
    operations.indexOf('@override\n  Widget build', operations.indexOf('Widget _buildGlobalConversationWorkspace')),
  );
  assert.doesNotMatch(embedded, /operations-room-chat|operations-room-composer/);
});
