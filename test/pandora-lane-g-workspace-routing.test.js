"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const shell=fs.readFileSync("apps/pandora-mobile/lib/app/pandora_chat_shell.dart","utf8");
const plp=fs.readFileSync("apps/pandora-mobile/lib/app/plp_enterprise_shell.dart","utf8");
const euro=fs.readFileSync("apps/pandora-mobile/lib/app/eurofish_enterprise_shell.dart","utf8");
const bok=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/bok_workspace_screen.dart","utf8");
test("shared shell routes all known enterprise workspaces to non-empty business surfaces",()=>{
  assert.match(shell,/PlpEnterpriseShell/);assert.match(shell,/EurofishEnterpriseShell/);assert.match(shell,/BokWorkspaceScreen/);
  assert.match(shell,/embeddedRouteSlug/);assert.match(shell,/embedded: true/);
  assert.ok(shell.indexOf("'plp-boracay'")<shell.lastIndexOf("const SizedBox.expand()"));
});
test("PLP embedded mode suppresses its legacy scaffold and command dock",()=>{
  assert.match(plp,/if \(widget.embeddedRouteSlug != null\)[\s\S]*_PlpLazyIndexedStack/);
  const embedded=plp.slice(plp.indexOf("if (widget.embeddedRouteSlug != null)"),plp.indexOf("return KeyedSubtree(",plp.indexOf("if (widget.embeddedRouteSlug != null)")+1));
  assert.doesNotMatch(embedded,/PlpCommandDock|AskPandoraScreen/);
});
test("Euro-Fish embedded sections render provider-backed operational content instead of a chat screen",()=>{
  assert.match(euro,/_EurofishOperationalSection/);assert.match(euro,/widget.embedded \? _body\(\)/);
  assert.match(euro,/Provider-backed data is unavailable for this section/);
});
test("BOK section is a real fail-closed operational page, not an empty box",()=>{
  assert.match(bok,/Operational workspace/);assert.match(bok,/keep operational values unknown/);
});
