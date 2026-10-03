"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const chat=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
const contexts=fs.readFileSync("apps/pandora-mobile/lib/features/simple/chat/pandora_chat_context_actions.dart","utf8");
const details=fs.readFileSync("apps/pandora-mobile/lib/features/simple/chat/pandora_chat_activity_details.dart","utf8");
const adapters=fs.readFileSync("apps/pandora-mobile/lib/features/simple/chat/pandora_chat_action_adapters.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");

test("Lane H keeps non-trivial Activity Theatre available in the global chat shell",()=>{
  assert.match(chat,/pandoraShouldRequestActivityTheatre\(turn\.text/);
  assert.match(chat,/_showActivityDetails\(turn\)/);
  assert.match(details,/PandoraActivityTimelineView\(/);
  assert.match(details,/presentContextRoute\(route\)/);
  assert.match(details,/events: intelligence\.watchChatActivity\(jobId\)/);
  assert.doesNotMatch(chat,/activityRequested:|activitySuppressed:/, 'temporary Activity events stay behind per-turn Details');
});

test("Lane H send path does not block on phone-AI preference IO",()=>{
  assert.match(chat,/unawaited\(PandoraLocalAiPreference\.load\(\)\)/);
  const start=adapters.indexOf("Future<bool> _executePhoneAi(");
  const end=adapters.indexOf("final route = PandoraLocalAiRouter.decide",start);
  assert.ok(start>=0&&end>start);
  const local=adapters.slice(start,end);
  assert.match(local,/PandoraLocalAiPreference\.cachedEnabled/);
  assert.doesNotMatch(local,/await PandoraLocalAiPreference\.load\(\)/);
});

test("Characters remains available and selected context stays visible",()=>{
  assert.match(chat,/_showAttachmentActions/);
  assert.match(contexts,/ValueKey<String>\('ask-pandora-menu-\$suffix'\)/);
  assert.match(contexts,/if \(widget\.allowCharacterContext\)\s*item\(_AttachmentAction\.characters, 'characters', 'Characters'/);
  assert.match(contexts,/case _AttachmentAction\.characters:\s*await _pickCharacterContext\(\)/);
  assert.match(contexts,/_characterContext = selected/);
  assert.match(chat,/ask-pandora-character-context/);
  assert.match(chat,/Character · \$\{_characterContext!\.name\}/);
  assert.match(chat,/onRemove: _removeCharacterContext/);
});

test("approved picker Phone AI gate remains exact",()=>{
  assert.match(picker,/widget\.localAiEnabled && widget\.localAiAvailable/);
});
