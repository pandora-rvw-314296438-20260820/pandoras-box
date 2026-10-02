import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const api=fs.readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart','utf8');
const chat=fs.readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart','utf8');
const picker=fs.readFileSync('apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart','utf8');
const edge=fs.readFileSync('supabase/functions/pandora-intelligence-chat/index.ts','utf8');
const migration=fs.readFileSync('supabase/migrations/20261003001500_pandora_lane_e_model_picker_ui_contract_v1.sql','utf8');
const bedrockBridge=fs.readFileSync('api/pandora-chat-bedrock.ts','utf8');

test('mobile model choices come from the authenticated backend catalog',()=>{
  assert.match(api,/pandora_intelligence_model_catalog_v1/);
  assert.match(api,/pandora_intelligence_thread_model_selection_v1/);
  assert.match(chat,/intelligence\.modelCatalog\(\)/);
  assert.match(chat,/intelligence\.threadModelState\(threadId\)/);
  assert.doesNotMatch(api+'\n'+chat+'\n'+picker,/\b(?:deepseek|anthropic|mistral|moonshotai|qwen|meta\.llama|cohere)\.[A-Za-z0-9._:-]+/i);
});

test('catalog exposes conversational Bedrock rows but only probe-verified routable rows are selectable',()=>{
  assert.match(migration,/from private\.pandora_bedrock_reasoning_catalog/);
  assert.match(migration,/c\.conversational=true/);
  assert.match(migration,/c\.present_in_latest_sync=true/);
  assert.match(migration,/c\.routable=true/);
  assert.match(migration,/c\.runtime_verification_status='passed'/);
  assert.match(migration,/'provider','bedrock'/);
  assert.match(migration,/'Payment blocked'/);
  assert.match(migration,/'Access denied'/);
  assert.match(migration,/'Not entitled'/);
  assert.match(picker,/onTap: model\.available/);
});

test('composer keeps separate Model and Reasoning controls and sends the thread preference contract',()=>{
  assert.match(chat,/ask-pandora-model-control/);
  assert.match(chat,/ask-pandora-reasoning-control/);
  assert.match(chat,/modelSelection: _modelSelection/);
  assert.match(chat,/mode: _reasoningMode/);
  assert.match(api,/'modelSelection': modelSelection\.toJson\(\)/);
  assert.match(api,/fallbackMode = 'allow_fallback'/);
  assert.match(migration,/'reasoningMode',v_route\.reasoning_mode/);
});

test('requested versus executed model lineage is returned to the mobile client',()=>{
  assert.match(edge,/routing:routeAudit/);
  assert.match(api,/class PandoraIntelligenceRouting/);
  assert.match(api,/requestedModel/);
  assert.match(api,/executedModel/);
  assert.match(chat,/_lastRouting = turn\.routing/);
});


test('existing threads persist Model and Reasoning changes immediately',()=>{
  assert.match(api,/pandora_intelligence_thread_model_selection_set_v1/);
  assert.match(chat,/saveThreadModelState/);
  assert.match(migration,/pandora_intelligence_thread_model_selection_set_v1/);
});

test('manual Bedrock selection has a server-only verified execution path',()=>{
  assert.match(edge,/effectiveSelection\.selection==="manual"&&effectiveSelection\.provider==="bedrock"/);
  assert.match(edge,/pandora_list_conversational_models_v1/);
  assert.match(edge,/pandora-chat-bedrock/);
  assert.match(migration,/pandora_bedrock_chat_route_v1/);
  assert.match(bedrockBridge,/x-pandora-signature/);
  assert.match(bedrockBridge,/converseWithBedrockTarget/);
  assert.match(bedrockBridge,/pandora_bedrock_chat_route_v1/);
});
