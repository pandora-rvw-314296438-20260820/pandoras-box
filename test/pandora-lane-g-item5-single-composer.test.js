"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(p,"utf8");
const shell=read("apps/pandora-mobile/lib/app/pandora_chat_shell.dart");
const ask=read("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart");
const targets=[
 "apps/pandora-mobile/lib/features/enterprise/tax_compliance_screen.dart",
 "apps/pandora-mobile/lib/features/enterprise/marketing_growth_workspace_screen.dart",
 "apps/pandora-mobile/lib/features/enterprise/batalla_workspace_screen.dart",
 "apps/pandora-mobile/lib/features/plugins/plugins_screen.dart",
 "apps/pandora-mobile/lib/features/plugins/provider_catalog_screen.dart",
 "apps/pandora-mobile/lib/features/connections/connections_screen.dart",
 "apps/pandora-mobile/lib/features/enterprise/enterprise_vision_screen.dart",
].map(read);

test("Lane E F: specialist pages cannot mount a second AskPandoraScreen",()=>{
 for(const source of targets) assert.doesNotMatch(source,/AskPandoraScreen\s*\(/);
 assert.match(shell,/PandoraConversationLayer/);
 assert.match(shell,/AskPandoraScreen\(/);
 assert.match(ask,/void primeExternalPrompt/);
});

test("Lane E G: selected record and provider actions hand bounded context to the global composer",()=>{
 assert.match(shell,/_surfaceContextOverride/);
 assert.match(shell,/_primeGlobalComposer/);
 assert.match(shell,/_openGlobalThread/);
 assert.match(targets[2],/onContextChanged/);
 assert.match(targets[2],/onOpenThread/);
 assert.match(targets[3],/providerId/);
 assert.match(targets[4],/providerKey/);
 assert.match(targets[5],/connectionId/);
});

test("Lane E H: Vision and Batalla remove duplicate Ask Pandora controls and failure state remains visible",()=>{
 assert.doesNotMatch(targets[6],/Ask Pandora/);
 assert.doesNotMatch(targets[2],/batalla-ask-pandora/);
 assert.match(targets[4],/Provider catalog could not load/);
 assert.match(targets[5],/Connections could not load/);
});
