import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const shell = readFileSync('apps/pandora-mobile/lib/app/pandora_chat_shell.dart','utf8');
const chat = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart','utf8');
const composer = readFileSync('apps/pandora-mobile/lib/features/simple/chat/pandora_chat_composer.dart','utf8');
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
test('shell mode uses one measured persistent composer inside the resized viewport', () => {
  assert.equal((chat.match(/child: PandoraChatComposer\(/g) ?? []).length, 1);
  assert.match(chat, /resizeToAvoidBottomInset:\s*true/);
  assert.match(chat, /padding: EdgeInsets\.only\(bottom: safeBottom\)/);
  assert.match(chat, /composerExtent: _composerHeight \+ safeBottom/);
  assert.match(composer, /Message Pandora…/);
  assert.match(composer, /height:\s*54/);
  assert.match(composer, /Color\(0xFF151515\)/);
  assert.match(composer, /BorderRadius\.circular\(27\)/);
  assert.match(chat, /ask-pandora-plus/);
  assert.match(composer, /ask-pandora-model-control/);
  assert.match(composer, /ask-pandora-submit/);
  assert.doesNotMatch(chat, /PandoraComposerModelControls/);
  assert.doesNotMatch(chat, /BackdropFilter/);
});
test('empty landing is logo-only, opaque, and not draggable', () => {
  assert.match(chat, /pandora-logo-only-landing/);
  assert.match(chat, /_shellHistoryExpanded =\s*widget\.shellOverlay/);
  assert.match(chat, /color:\s*PandoraSimpleColors\.canvas/);
  assert.match(chat, /Offstage\([\s\S]*offstage: !_shellHistoryExpanded/);
  assert.doesNotMatch(chat, /pandora-active-chat-minimize/);
  assert.match(shell, /_chatKey\.currentState\?\.minimizeHistory\(\)/);
});
test('Operations Room defers chat ownership to the app-level conversation', () => {
  assert.match(shell, /PandoraOperationsRoomScreen\([\s\S]*globalConversation:\s*true/);
  assert.match(operations, /final bool globalConversation/);
});
