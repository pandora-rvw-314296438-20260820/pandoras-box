import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const api=fs.readFileSync("apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart","utf8");
const ask=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");
const composer=fs.readFileSync("apps/pandora-mobile/lib/features/simple/chat/pandora_chat_composer.dart","utf8");
const controller=fs.readFileSync("apps/pandora-mobile/lib/core/chat/pandora_chat_controller.dart","utf8");
const migration=fs.readFileSync("supabase/migrations/20261003015000_pandora_chat_model_picker_projection_v1.sql","utf8");

test("mobile picker remains backend-catalog driven and sends Lane F selection",()=>{
  assert.match(api,/pandora_chat_model_picker_v1/);
  assert.match(api,/'modelSelection': modelSelection\.toJson\(\)/);
  assert.match(controller,/'mode': preferences\.reasoningMode/);
  assert.match(controller,/'modelSelection': preferences\.modelSelectionJson/);
  assert.match(ask,/selection: _modelSelection/);
  assert.match(ask,/reasoningMode: _reasoningMode/);
  assert.match(ask,/\.modelPicker\(threadId: _chat\.state\.threadId\)/);
  assert.match(picker,/models\.where\(\(model\) => model\.selectable\)/);
  assert.match(picker,/Mistral Large 3/);
  assert.match(picker,/Ministral 3B/);
  assert.match(picker,/model-picker-unavailable-count/);
});
test("catalog projection exposes unavailable models but only verified routable models are selectable",()=>{
  assert.match(migration,/from private\.pandora_bedrock_reasoning_catalog/);
  assert.match(migration,/c\.conversational=true/);
  assert.match(migration,/c\.routable=true[\s\S]*c\.runtime_verification_status='passed'[\s\S]*c\.lifecycle_status='ACTIVE'/);
  assert.match(migration,/'Payment or provider agreement required'/);
  assert.match(migration,/'Access denied'/);
  assert.match(migration,/'Not entitled'/);
  assert.match(migration,/grant execute[\s\S]*to authenticated,service_role/);
  assert.match(migration,/m\.role in \('owner','admin'\)/);
});
test("persistent adaptive composer opens a contained accessible model picker",()=>{
  assert.match(ask,/PandoraChatComposer\(/);
  assert.match(composer,/BoxConstraints\(minHeight:\s*54\)/);
  assert.match(composer,/Color\(0xFF151515\)/);
  assert.match(composer,/BorderRadius\.circular\(27\)/);
  assert.match(composer,/ask-pandora-model-control/);
  assert.match(composer,/maxLines:\s*5/);
  assert.match(composer,/widget\.state\.value\.canSend/);
  assert.doesNotMatch(ask,/PandoraComposerModelControls/);
  assert.doesNotMatch(ask,/BackdropFilter/);
  assert.match(picker,/PandoraModelPickerOverlay/);
  assert.match(picker,/ModalBarrier\(/);
  assert.match(picker,/BlockSemantics\(/);
  assert.match(picker,/SafeArea\(/);
  assert.match(picker,/_surfaceColor = Color\(0xFF1B1B1B\)/);
  assert.match(picker,/Material\(\s*key:[\s\S]*?color: _surfaceColor/);
  assert.match(picker,/clipBehavior:\s*Clip\.antiAlias/);
  assert.match(picker,/selected:\s*widget\.selection\.isAuto/);
  assert.match(picker,/Response depth/);
  assert.match(picker,/TraversalEdgeBehavior\.closedLoop/);
  assert.match(picker,/_advancedExpanded = !widget\.selection\.isAuto \|\| widget\.startAtEnd/);
  assert.doesNotMatch(picker,/showModalBottomSheet/);
});
test("chat authentication and organization scope remain explicit",()=>{
  assert.match(api,/_requireSession\(\)/);
  assert.match(api,/'x-organization-id': _organizationId/);
  assert.match(api,/Please sign in again\./);
  assert.match(ask,/pandora-chat-message-error/);
  assert.match(ask,/pandora-chat-retry/);
});
