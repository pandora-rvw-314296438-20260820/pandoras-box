
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
const core = fs.readFileSync(
  "apps/pandora-mobile/lib/features/core/pandora_core_screen.dart", "utf8",
);
const coreApi = fs.readFileSync(
  "apps/pandora-mobile/lib/core/data/pandora_core_api.dart", "utf8",
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
const plpDrawer = fs.readFileSync(
  "apps/pandora-mobile/lib/app/plp_navigation_drawer.dart",
  "utf8",
);
const plpShell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/plp_enterprise_shell.dart",
  "utf8",
);

test("owner Home uses canonical customer projections rather than the template directory", () => {
  assert.ok(/9 => _coreScreen\('home'\)/.test(shell), 'Home must use the Core projection');
  assert.ok(/_coreScreen[\s\S]*PandoraCoreScreen\(/.test(shell), 'Core stays inside the existing shell');
  assert.doesNotMatch(shell, /9 => EnterpriseWorkspaceHome\(/);
  assert.match(coreApi, /pandora_core_snapshot_v1/);
  assert.match(coreApi, /p_organization_id/);
  assert.doesNotMatch(core, /enterpriseWorkspaces|workspace-tax-quick/);
});

test("Euro-fish workspace keeps Home first and the requested business order", () => {
  const start = hub.indexOf("key: '1064-euro-fish-traders'");
  const end = hub.indexOf("key: 'batalla-associates'");
  assert.ok(start >= 0 && end > start);
  const block = hub.slice(start, end);
  const expected = [
    "Home",
    "Overview",
    "Tax & Compliance",
    "Orders & Shipments",
    "Suppliers & Buyers",
    "Inventory & Products",
    "Logistics & Customs",
    "Sales & Finance",
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


test("customer tax routes remain tenant scoped and separate from owner Home", () => {
  assert.doesNotMatch(core, /workspace-tax-quick/);
  assert.match(shell, /TaxComplianceScreen\(/);
  assert.match(shell, /section\.routeSlug ==\s*'tax-compliance'/);
});

test("tax command center reads live tenant-scoped backend truth and preserves legal action gates", () => {
  assert.match(tax, /pandora_tax_command_center_v1/);
  assert.match(tax, /organizationId/);
  assert.doesNotMatch(tax, /PandoraConfig\.organizationId/);
  assert.doesNotMatch(tax, /Message Pandora about taxes|AskPandoraScreen/);
  assert.match(tax, /filingSubmission/);
  assert.match(tax, /paymentExecution/);
  assert.match(tax, /The Philippines rule pack is still under professional review/);
  assert.doesNotMatch(tax, /service_role|SUPABASE_SERVICE_ROLE|access_token|refresh_token/);
});

test("workspace navigation uses admitted structured Enterprise context", () => {
  assert.match(hub, /'identityScope': 'enterprise_workspace'/);
  assert.match(hub, /'selectedObject': <String, String>/);
  assert.match(hub, /'surface': section\.surface/);
  assert.ok(hub.includes("'route': '/enterprise/workspaces/${workspace.key}/${section.routeSlug}'"));
});

test("shell boots to the logo-only Pandora landing and preserves Home plus Operations Room", () => {
  assert.match(shell, /final Set<int> _visited = <int>\{0\};/);
  assert.match(shell, /int _index = 0;/);
  assert.ok(/9 => _coreScreen\('home'\)/.test(shell), 'Home must use the Core projection');
  assert.ok(/_coreScreen[\s\S]*PandoraCoreScreen\(/.test(shell), 'Core stays inside the existing shell');
  assert.match(
    shell,
    /PandoraOperationsRoomScreen\([\s\S]*?onHome: \(\) => _select\(9\),[\s\S]*?globalConversation:\s*true/,
  );
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


test("workspace home keeps the hamburger fixed without a redundant app title", () => {
  assert.ok(!hub.includes("workspace-home-brand"));
  assert.ok(!hub.includes("workspace-home-title"));
  assert.ok(hub.includes("workspace-home-navigation"));
  assert.ok(hub.includes("PandoraMenuButton"));
  assert.ok(!hub.includes("Icons.menu_rounded"));
  assert.ok(hub.includes("workspace-home-search"));
  assert.ok(hub.includes("Recent chats"));
  assert.ok(hub.includes("Icons.history_rounded"));
  assert.ok(hub.includes("workspace-home-activity"));
  assert.ok(hub.includes("workspace-home-more"));
  assert.ok(
    hub.includes(
      "_header(context, openDrawer),\n              const SizedBox(height: 1),",
    ),
  );
  assert.ok(
    !hub.includes("const Divider(height: 1, color: Color(0x33FFFFFF))"),
  );
});


test("owner clients do not inherit repeated customer business quick actions", () => {
  assert.doesNotMatch(core, /Tax & Compliance|workspace-tax-quick/);
  assert.match(core, /Manage client/);
  assert.match(core, /Enter client workspace/);
});


test("PLP keeps resort work primary and Tax & Compliance available under System", () => {
  const todayAt = plpDrawer.indexOf("'home'");
  const staysAt = plpDrawer.indexOf("'stays'");
  const roomsAt = plpDrawer.indexOf("'rooms'");
  const guestsAt = plpDrawer.indexOf("'guests'");
  const operationsAt = plpDrawer.indexOf("'operations'");
  const revenueAt = plpDrawer.indexOf("'revenue'");
  const experiencesAt = plpDrawer.indexOf("'experiences'");
  const teamAt = plpDrawer.indexOf("'team'");
  const activityAt = plpDrawer.indexOf("'activity'");
  const systemAt = plpDrawer.indexOf("_systemItems");
  const taxAt = plpDrawer.indexOf("'tax-compliance'");

  assert.ok(todayAt >= 0);
  assert.ok(staysAt > todayAt && roomsAt > staysAt && guestsAt > roomsAt);
  assert.ok(operationsAt > guestsAt && revenueAt > operationsAt);
  assert.ok(experiencesAt > revenueAt && teamAt > experiencesAt && activityAt > teamAt);
  assert.ok(systemAt > activityAt && taxAt > systemAt);
  assert.doesNotMatch(plpDrawer, /_PlpDrawerDestination\('overview'/);
  assert.doesNotMatch(plpDrawer, /_PlpDrawerDestination\('needs-you'/);

  assert.match(plpShell, /'tax-compliance': 13/);
  assert.match(plpShell, /TaxComplianceScreen\(/);
  assert.match(plpShell, /'surface': 'enterprise_tax'/);
  assert.match(plpShell, /PandoraNavigationScope\(\s*openDrawer: null/);
  assert.match(plpShell, /'plp-floating-navigation'/);
  assert.doesNotMatch(plpShell, /_index == 4 \|\| _index == 12/);
  assert.doesNotMatch(tax, /bottomNavigationBar:/);
  assert.match(tax, /plp-tax-owner-status/);
});
