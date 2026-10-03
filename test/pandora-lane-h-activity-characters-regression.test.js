"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const chat=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");

test("Lane H keeps non-trivial Activity Theatre available in the global chat shell",()=>{
  assert.match(chat,/activityRequested: _activityTheatreRequested/);
  assert.match(chat,/activitySuppressed: _activityTheatreSuppressed/);
  assert.doesNotMatch(chat,/widget\.shellOverlay \? false : _activityTheatreRequested/);
  assert.doesNotMatch(chat,/widget\.shellOverlay \? true : _activityTheatreSuppressed/);
});

test("Lane H send path does not block on phone-AI preference IO",()=>{
  assert.match(chat,/unawaited\(PandoraLocalAiPreference\.load\(\)\)/);
  assert.match(chat,/final localEnabled = PandoraLocalAiPreference\.cachedEnabled/);
  assert.doesNotMatch(chat,/final localEnabled = await PandoraLocalAiPreference\.load\(\)/);
});

test("Characters remains available and selected context stays visible",()=>{
  assert.match(chat,/ask-pandora-menu-characters/);
  assert.match(chat,/ask-pandora-character-context/);
  assert.match(chat,/Character · \$\{characterContext!\.name\}/);
});

test("approved picker Phone AI gate remains exact",()=>{
  assert.match(picker,/widget\.localAiEnabled && widget\.localAiAvailable/);
});
