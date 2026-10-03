import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const shell = readFileSync('apps/pandora-mobile/lib/app/pandora_chat_shell.dart','utf8');
const chat = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart','utf8');
const layer = readFileSync('apps/pandora-mobile/lib/app/pandora_conversation_layer.dart','utf8');
const operations = readFileSync('apps/pandora-mobile/lib/features/operations/operations_room_screen.dart','utf8');

test('main business shell mounts one app-level Pandora conversation', () => {
  assert.match(shell, /PandoraConversationLayer\(/);
  assert.match(shell, /shellOverlay:\s*true/);
  assert.equal((shell.match(/AskPandoraScreen\(/g) ?? []).length, 1);
  assert.match(layer, /compactComposerHeight = 80/);
  assert.match(layer, /MediaQuery\.viewPaddingOf\(context\)\.bottom/);
  assert.match(layer, /pandora-business-composer-clearance/);
  assert.match(layer, /Positioned\.fill\(child: conversation\)/);
});
test('generic pages no longer manufacture invalid enterprise context', () => {
  assert.match(shell, /_conversationContextForCurrentSurface\(\)/);
  assert.match(shell, /if \(_index != 0 \|\| _activeEnterpriseContext == null\) return null/);
  assert.match(shell, /route\.startsWith\('\/enterprise\/'\)/);
  assert.doesNotMatch(shell, /'surface': 'pandora_business_os'/);
});
test('shell mode keeps one keyboard-aware 54px floating composer', () => {
  assert.match(chat, /bottom:\s*keyboardInset,[\s\S]*?key:\s*_composerKey/);
  assert.match(chat, /Message Pandora…/);
  assert.match(chat, /height:\s*54/);
  assert.match(chat, /Color\(0xFF151515\)/);
  assert.match(chat, /BorderRadius\.circular\(27\)/);
  assert.match(chat, /ask-pandora-plus/);
  assert.match(chat, /ask-pandora-model-control/);
  assert.match(chat, /ask-pandora-submit/);
  assert.doesNotMatch(chat, /PandoraComposerModelControls/);
  assert.doesNotMatch(chat, /BackdropFilter/);
});
test('standalone chat stays intact while business chat is contextual', () => {
  assert.match(chat, /pandora-logo-only-landing/);
  assert.match(chat, /_shellHistoryExpanded =\s*widget\.shellOverlay/);
  assert.match(chat, /contextualOverlay/);
  assert.match(chat, /FractionallySizedBox\([\s\S]*heightFactor:\s*\.66/);
  assert.match(chat, /borderRadius:\s*BorderRadius\.circular\(24\)/);
  assert.match(chat, /color:\s*const Color\(0xFF0A0A0A\)/);
  assert.match(chat, /Offstage\([\s\S]*offstage: !_shellHistoryExpanded/);
  assert.doesNotMatch(chat, /pandora-active-chat-minimize/);
  assert.doesNotMatch(shell, /businessWorkspace:\s*Offstage\(/);
  assert.match(shell, /active:\s*index == _index/);
  assert.match(shell, /contextualOverlay:\s*businessOwnsNavigation/);
  assert.match(shell, /_chatKey\.currentState\?\.minimizeHistory\(\)/);
});
test('Operations Room defers chat ownership to the app-level conversation', () => {
  assert.match(shell, /PandoraOperationsRoomScreen\([\s\S]*globalConversation:\s*true/);
  assert.match(operations, /final bool globalConversation/);
});
