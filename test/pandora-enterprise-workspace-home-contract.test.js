
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const hub = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart",
  "utf8",
);
const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/pandora_chat_shell.dart",
  "utf8",
);
const ask = fs.readFileSync(
  "apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart",
  "utf8",
);
const backend = fs.readFileSync(
  "supabase/functions/pandora-intelligence-chat/index.ts",
  "utf8",
);
const tax = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/tax_compliance_screen.dart",
  "utf8",
);

test("owner workspace home exposes the four requested businesses", () => {
  for (const value of [
    "PLP Boracay",
    "Luxury Resort",
    "1064 euro-fish traders",
    "Import/Export",
    "Batalla & Associates",
    "Law & Business Offices",
    "BOK",
    "Food & Hospitality Group",
  ]) {
    assert.ok(hub.includes(value), "missing " + value);
  }
});

test("Euro-fish workspace keeps Home first and the requested business order", () => {
  const start = hub.indexOf("key: '1064-euro-fish-traders'");
  const end = hub.indexOf("key: 'batalla-associates'");
  assert.ok(start >= 0 && end > start);
  const block = hub.slice(start, end);
  const expected = [
    "Home",
    "Overview",
    "Orders & Shipments",
    "Suppliers & Buyers",
    "Inventory & Products",
    "Logistics & Customs",
    "Sales & Finance",
    "Tax & Compliance",
    "Documents & Compliance",
    "Team & Access",
    "Activity",
    "Settings",
    "System / Developer",
  ];
  let cursor = -1;
  for (const label of expected) {
    const next = block.indexOf("'" + label + "'");
    assert.ok(next > cursor, label + " must follow the requested order");
    cursor = next;
  }
});


test("every enterprise workspace exposes the tax command center", () => {
  assert.ok((hub.match(/'Tax & Compliance'/g) ?? []).length >= 5);
  assert.equal((hub.match(/'enterprise_tax', 'tax-compliance'/g) ?? []).length, 4);
  assert.match(shell, /TaxComplianceScreen\(/);
  assert.match(shell, /section\.routeSlug ==\s*'tax-compliance'/);
});

test("tax command center reads live tenant-scoped backend truth and preserves legal action gates", () => {
  assert.match(tax, /pandora_tax_command_center_v1/);
  assert.match(tax, /PandoraConfig\.organizationId/);
  assert.match(tax, /Message Pandora about taxes/);
  assert.match(tax, /filingSubmission/);
  assert.match(tax, /paymentExecution/);
  assert.match(tax, /The Philippines rule pack is still under professional review/);
  assert.doesNotMatch(tax, /service_role|SUPABASE_SERVICE_ROLE|access_token|refresh_token/);
});

test("workspace navigation uses admitted structured Enterprise context", () => {
  assert.match(hub, /'identityScope': 'enterprise_workspace'/);
  assert.match(hub, /'selectedObject': <String, String>/);
  assert.match(hub, /'surface': section\.surface/);
  assert.match(hub, /'route': '\/enterprise\/workspaces\/'/);
});

test("shell boots to Home and preserves Operations Room", () => {
  assert.match(shell, /final Set<int> _visited = <int>\{9\};/);
  assert.match(shell, /int _index = 9;/);
  assert.match(shell, /9 => EnterpriseWorkspaceHome\(/);
  assert.match(shell, /8 => PandoraOperationsRoomScreen\(onHome: \(\) => _select\(9\)\)/);
});

test("workspace scope is passed to Ask Pandora without visible message injection", () => {
  assert.match(ask, /final Map<String, Object\?>\? enterpriseContext;/);
  assert.match(ask, /enterpriseContext: widget\.enterpriseContext,/);
  assert.match(ask, /_sanitizeVisiblePandoraText/);
});


test("control revisions preserve workspace scope across every provider body", () => {
  assert.ok(!backend.includes(
    "request(effectiveMessage,i.attachments,prior,ctx,tctx)",
  ));
  assert.ok(!backend.includes(
    "kimiBody(effectiveMessage,i.attachments,prior,ctx,tctx,modelClass)",
  ));
  assert.ok(!backend.includes(
    "openaiBody(effectiveMessage,i.attachments,prior,ctx,tctx,modelClass)",
  ));
  assert.ok(backend.includes(
    "request(effectiveMessage,i.attachments,prior,ctx,i.enterpriseContext,tctx)",
  ));
});


test("workspace home matches the screenshot header hierarchy", () => {
  assert.ok(hub.includes("workspace-home-brand"));
  assert.ok(hub.includes("workspace-home-navigation"));
  assert.ok(hub.includes("PandoraMenuButton"));
  assert.ok(!hub.includes("Icons.menu_rounded"));
  assert.ok(hub.includes("workspace-home-search"));
  assert.ok(hub.includes("workspace-home-activity"));
  assert.ok(hub.includes("workspace-home-more"));
});


test("tax is visible on every workspace card without opening the section list", () => {
  assert.match(hub, /String\? _expandedKey = 'plp-boracay'/);
  assert.match(hub, /workspace-tax-quick-/);
  assert.match(hub, /pandora_tax_command_center_v1/);
  assert.match(hub, /Professional review gate/);
  assert.match(hub, /onTap: \(\) => onOpen\(tax\)/);
  assert.match(hub, /final tax = workspace\.sections\.firstWhere/);
});
