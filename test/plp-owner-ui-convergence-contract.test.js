import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");
const home = read("apps/pandora-mobile/lib/features/enterprise/plp_enterprise_home.dart");
const resort = read("apps/pandora-mobile/lib/features/enterprise/plp_resort_workspace.dart");
const drawer = read("apps/pandora-mobile/lib/app/plp_navigation_drawer.dart");
const shell = read("apps/pandora-mobile/lib/app/plp_enterprise_shell.dart");
const migration = read("supabase/migrations/20261001044500_plp_resort_command_center_v1.sql");

test("PLP Home is one shared resort workspace, not a second editorial design", () => {
  assert.match(home, /PlpResortWorkspaceScreen/);
  assert.match(home, /plpResortSectionById\('today'\)/);
  assert.doesNotMatch(home, /OWNER’S HOME|Your private briefing/);
});

test("PLP exposes nine coherent resort workspaces instead of a feature catalog", () => {
  for (const id of ["today", "stays", "rooms", "guests", "operations", "revenue", "experiences", "team", "activity"]) {
    assert.match(resort, new RegExp("id: '" + id + "'"));
  }
  assert.match(resort, /ROOM PULSE/);
  assert.match(resort, /Concierge/);
  assert.match(resort, /Housekeeping/);
  assert.match(resort, /Rates/);
  assert.doesNotMatch(resort, /MFR/);
});

test("PLP navigation keeps resort work primary and technical machinery under System", () => {
  for (const label of ["Today", "Stays", "Rooms", "Guests", "Operations", "Revenue", "Experiences", "Team", "Activity"]) {
    assert.match(drawer, new RegExp("'" + label + "'"));
  }
  assert.doesNotMatch(drawer, /_PlpDrawerDestination\('overview'/);
  assert.doesNotMatch(drawer, /_PlpDrawerDestination\('needs-you'/);
  assert.match(drawer, /_systemItems[\s\S]*Tax & Compliance[\s\S]*Local AI[\s\S]*Developer diagnostics/);
});

test("PLP shell loads one additive resort projection and preserves contextual Pandora", () => {
  assert.match(shell, /plp_resort_command_center_v1/);
  assert.match(shell, /resortCommandCenter/);
  assert.match(shell, /'resort:' \+ destination/);
  assert.match(shell, /onOpenSection: _openResortSection/);
  assert.match(shell, /'name': 'Alfred'/);
  assert.match(shell, /hintText: _commandHint/);
});

test("PLP resort projection is bounded to existing truth and excludes direct contact data", () => {
  assert.match(migration, /active PLP membership required/);
  assert.match(migration, /plp_runtime\.plp_bookings/);
  assert.match(migration, /enterprise_hospitality_housekeeping_jobs/);
  assert.match(migration, /contactDetailsExcluded/);
  assert.doesNotMatch(migration, /g\.email|g\.phone/);
  assert.match(migration, /revoke execute on function public\.plp_resort_command_center_v1\(\)\s+from public, anon/);
});
