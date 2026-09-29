import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const registry = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/plp_resort_workspace.dart",
  "utf8",
);
const drawer = fs.readFileSync(
  "apps/pandora-mobile/lib/app/plp_navigation_drawer.dart",
  "utf8",
);
const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/plp_enterprise_shell.dart",
  "utf8",
);
const home = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/plp_enterprise_home.dart",
  "utf8",
);
const ask = fs.readFileSync(
  "apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart",
  "utf8",
);
const edge = fs.readFileSync(
  "supabase/functions/pandora-intelligence-chat/index.ts",
  "utf8",
);
const migration = fs.readFileSync(
  "supabase/migrations/20260929190000_plp_resort_operating_manifest_v1.sql",
  "utf8",
);

test("PLP exposes all grouped resort operating surfaces", () => {
  const count = (registry.match(/  PlpResortModule\(/g) || []).length;
  assert.equal(count, 45);
  for (const group of [
    "Guest & Stay",
    "Rooms & Property",
    "Hospitality & Experiences",
    "Commercial",
    "Finance & Supply",
    "People & Governance",
    "Intelligence & System",
  ]) {
    assert.ok(registry.includes(group));
  }
  assert.match(drawer, /plpResortGroupOrder/);
  assert.match(drawer, /plpResortModules/);
  assert.match(shell, /PlpResortWorkspaceScreen/);
});

test("MFR is canonical for the PLP assistant", () => {
  assert.match(shell, /'name': 'MFR'/);
  assert.match(shell, /hintText: 'Message MFR'/);
  assert.match(home, /title: 'MFR'/);
  assert.match(home, /plp-open-mfr/);
  assert.match(ask, /\/enterprise\/plp-boracay\/mfr/);
  assert.match(ask, /'assistant': 'mfr'/);
  assert.match(ask, /Message MFR/);
  assert.match(edge, /plp-boracay\/mfr/);
  assert.match(edge, /plp-boracay\/alfred/);
});

test("PLP manifest keeps design and truth contracts explicit", () => {
  assert.match(migration, /plp_resort_operating_manifest_v1/);
  assert.match(migration, /light_ivory_editorial_luxury/);
  assert.match(migration, /navigationPanel', 'pure_black'/);
  assert.match(migration, /assistantIdentity', 'MFR'/);
  assert.match(migration, /verified_events_only/);
  assert.match(migration, /fabricatedMetricsAllowed', false/);
  assert.match(migration, /revoke all on function/);
  assert.match(migration, /grant execute[\s\S]*authenticated/);
  assert.match(shell, /plp_resort_operating_manifest_v1/);
});
