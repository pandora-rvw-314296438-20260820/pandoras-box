"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const shell=fs.readFileSync("apps/pandora-mobile/lib/app/pandora_chat_shell.dart","utf8");
const tax=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/tax_compliance_screen.dart","utf8");
const marketing=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/marketing_growth_workspace_screen.dart","utf8");
const batalla=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/batalla_workspace_screen.dart","utf8");
const vision=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/enterprise_vision_screen.dart","utf8");
const connections=fs.readFileSync("apps/pandora-mobile/lib/features/connections/connections_screen.dart","utf8");
const plugins=fs.readFileSync("apps/pandora-mobile/lib/features/plugins/plugins_screen.dart","utf8");
const catalog=fs.readFileSync("apps/pandora-mobile/lib/features/plugins/provider_catalog_screen.dart","utf8");

test("Lane E F: authorized non-destructive connection verification executes a real governed action",()=>{
  assert.match(connections,/runConnectionAction\([\s\S]*action: 'test'/);
  assert.match(connections,/connections-verify-all/);
});

test("Lane E G: provider connection actions enter the shared conversation without a new Ask Pandora route",()=>{
  for(const source of [connections,plugins,catalog]){
    assert.doesNotMatch(source,/AskPandoraScreen/);
  }
  assert.match(plugins,/shared\.submitPrompt\(prompt, selectedObject: selected\)/);
  assert.match(plugins,/'Connect Facebook'/);
  assert.match(catalog,/shared\.submitPrompt\(prompt, selectedObject: selected\)/);
});

test("Lane E shared composer owns Tax Marketing Batalla Vision and selected-record context",()=>{
  assert.doesNotMatch(tax,/AskPandoraScreen|tax-message-pandora/);
  assert.doesNotMatch(marketing,/AskPandoraScreen|marketing-growth-command-bar/);
  assert.doesNotMatch(batalla,/AskPandoraScreen|batalla-ask-pandora/);
  assert.doesNotMatch(vision,/Ask Pandora|onAskPandora/);
  assert.match(batalla,/bindEnterpriseContext\(_contextFor\(item\)\)/);
  assert.match(connections,/'recordType': 'connection'/);
  assert.match(catalog,/'recordType': 'provider_catalog_entry'/);
  assert.match(shell,/PandoraSharedConversationScope/);
  assert.match(shell,/showExternalFailureMessage/);
});
