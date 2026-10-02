import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
const api=fs.readFileSync("apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart","utf8");
const ask=fs.readFileSync("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart","utf8");
const picker=fs.readFileSync("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart","utf8");
const migration=fs.readFileSync("supabase/migrations/20261003015000_pandora_chat_model_picker_projection_v1.sql","utf8");

test("mobile model picker is backend-catalog driven and sends Lane F selection",()=>{
  assert.match(api,/pandora_chat_model_picker_v1/);
  assert.match(api,/'modelSelection': modelSelection\.toJson\(\)/);
  assert.match(ask,/mode: _reasoningMode/);
  assert.match(ask,/modelSelection: _modelSelection/);
  assert.match(ask,/intelligence\.modelPicker\(threadId: threadId\)/);
  assert.match(picker,/model\.selectable/);
  assert.doesNotMatch(picker,/gpt-|claude-|gemini-|mistral\.|deepseek\.|llama/i);
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
test("composer keeps model and reasoning controls separate and compact",()=>{
  assert.match(picker,/ask-pandora-model-control/);
  assert.match(picker,/ask-pandora-reasoning-control/);
  assert.match(picker,/Model · \$modelLabel/);
  assert.match(picker,/Reasoning · \$_reasoningLabel/);
  assert.match(ask,/PandoraComposerModelControls/);
  assert.match(ask,/compact: true/);
});
