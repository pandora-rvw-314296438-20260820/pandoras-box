"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const pref=fs.readFileSync("apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart","utf8");
const settings=fs.readFileSync("apps/pandora-mobile/lib/features/settings/local_ai_settings_screen.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");
const ask=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
const adapters=fs.readFileSync("apps/pandora-mobile/lib/features/simple/chat/pandora_chat_action_adapters.dart","utf8");
test("Phone AI remains default OFF and Settings exposes the authoritative preference",()=>{
 assert.match(pref,/static bool _enabled = false/);
 assert.match(pref,/getBool\(storageKey\) \?\? false/);
 assert.match(settings,/phone-ai-enabled-toggle/);
 assert.match(settings,/PandoraLocalAiPreference\.setEnabled\(enabled\)/);
 assert.match(settings,/Off by default/);
});
test("model picker always shows Local device Qwen and locks it while Phone AI is off",()=>{
 assert.match(picker,/Local device \(Qwen\)/);
 assert.match(picker,/widget\.localAiEnabled && widget\.localAiAvailable/);
 assert.match(picker,/locked: !_localSelectable/);
 assert.match(picker,/Icons\.lock_outline_rounded/);
});
test("manual local selection is handled on-device and never sent as a cloud provider",()=>{
 assert.match(adapters,/dispatch\.preferences\.provider == pandoraLocalDeviceProvider/);
 assert.match(adapters,/_executePhoneAi\(dispatch, input, forceLocal: forceLocal\)/);
 assert.match(adapters,/if \(forceLocal\) \{[\s\S]*?_chat\.fail\([\s\S]*?return true;/);
 const cloudStart=ask.indexOf("intelligence.executeChatTurn(dispatch)");
 const localRoute=ask.indexOf("await _executeLocalRoute(dispatch, input, dependencies)");
 assert.ok(localRoute>=0&&cloudStart>localRoute);
 assert.match(ask,/if \(handled \|\| !_current\(token\)\) return/);
});
