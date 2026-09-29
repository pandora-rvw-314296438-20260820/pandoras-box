const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const home = fs.readFileSync(
  path.join(root, "apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart"),
  "utf8",
);
const shell = fs.readFileSync(
  path.join(root, "apps/pandora-mobile/lib/app/pandora_chat_shell.dart"),
  "utf8",
);

test("Marketing & Growth workspace exposes the approved top-level flow", () => {
  const start = home.indexOf("key: 'pandora-marketing-growth'");
  const end = home.indexOf("key: 'plp-boracay'", start);
  assert.ok(start >= 0 && end > start);
  const block = home.slice(start, end);
  const expected = [
    "Home",
    "Overview",
    "Campaigns",
    "Leads",
    "Experiments",
    "Learning",
    "Approvals",
    "Settings",
  ];
  let cursor = -1;
  for (const label of expected) {
    const next = block.indexOf("'" + label + "'", cursor + 1);
    assert.ok(next > cursor, label + " must be present in order");
    cursor = next;
  }
});

test("generic enterprise sections preserve persistent contextual Pandora chat", () => {
  assert.match(shell, /AskPandoraScreen\(/);
  assert.match(shell, /enterpriseContext:\s*_activeEnterpriseContext/);
  assert.match(home, /identityScope': 'enterprise_workspace'/);
  assert.match(home, /workspaceKey': workspace\.key/);
});

test("Marketing & Growth remains measurement-first and does not imply spend authority", () => {
  const start = home.indexOf("key: 'pandora-marketing-growth'");
  const end = home.indexOf("key: 'plp-boracay'", start);
  const block = home.slice(start, end);
  assert.doesNotMatch(block, /spend|budget|launch|publish/i);
});
