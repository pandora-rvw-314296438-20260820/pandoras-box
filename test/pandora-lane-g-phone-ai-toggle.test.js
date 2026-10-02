"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const pref=fs.readFileSync("apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart","utf8");
const settings=fs.readFileSync("apps/pandora-mobile/lib/features/settings/local_ai_settings_screen.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");
const ask=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
test("Phone AI remains default OFF and Settings exposes the authoritative preference",()=>{
 assert.match(pref,/static bool _enabled = false/);
 assert.match(pref,/getBool\(storageKey\) \?\? false/);
 assert.match(settings,/phone-ai-enabled-toggle/);
 assert.match(settings,/PandoraLocalAiPreference\.setEnabled\(enabled\)/);
 assert.match(settings,/Off by default/);
});
test("model picker always shows Local device Qwen and locks it while Phone AI is off",()=>{
 assert.match(picker,/Local device \(Qwen\)/);
 assert.match(picker,/enabled: localAiEnabled && localAiAvailable/);
 assert.match(picker,/Turn on Phone AI in Settings/);
 assert.match(picker,/Icons\.lock_outline_rounded/);
});
test("manual local selection is handled on-device and never sent as a cloud provider",()=>{
 assert.match(ask,/isPandoraLocalDeviceSelection\(_modelSelection\)/);
 assert.match(ask,/_trySubmitLocalAi\(objective, forceLocal: forceLocal\)/);
 assert.match(ask,/Local device \(Qwen\) cannot safely handle this turn/);
 const cloudStart=ask.indexOf("startChatExecution(");
 const forceGuard=ask.indexOf("if (forceLocal) {");
 assert.ok(forceGuard>=0&&cloudStart>forceGuard);
});
