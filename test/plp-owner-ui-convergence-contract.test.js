import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");
const home = read("apps/pandora-mobile/lib/features/enterprise/plp_enterprise_home.dart");
const editorial = read("apps/pandora-mobile/lib/features/enterprise/plp_editorial_surfaces.dart");
const guests = read("apps/pandora-mobile/lib/features/enterprise/plp_guests_screen.dart");
const team = read("apps/pandora-mobile/lib/features/enterprise/plp_team_access_screen.dart");
const activity = read("apps/pandora-mobile/lib/features/enterprise/plp_activity_screen.dart");
const tax = read("apps/pandora-mobile/lib/features/enterprise/tax_compliance_screen.dart");
const shell = read("apps/pandora-mobile/lib/app/plp_enterprise_shell.dart");

test("PLP Home is an adaptive briefing rather than a duplicate Overview", () => {
  assert.match(home, /plp-owner-briefing/);
  assert.match(home, /The resort is quiet today\./);
  assert.match(home, /A few things need you\./);
  assert.doesNotMatch(home, /TODAY AT PUEBLO LA PERLA|COMMAND PLP|plp-metric-occupancy/);
});

test("PLP deeper surfaces keep the quiet editorial grammar", () => {
  assert.doesNotMatch(editorial, /Turn the overview into action\./);
  assert.match(editorial, /No guest movement today\./);
  assert.doesNotMatch(editorial, /Ask about what matters\.|Interrogate the number\./);
  assert.doesNotMatch(editorial, /Customer-owned PLP cameras can replace/);
});

test("Guest, Team, and Activity headers converge without generic stacked branding", () => {
  assert.match(guests, /PUEBLO LA PERLA/);
  assert.match(guests, /GUEST EXPERIENCE/);
  assert.doesNotMatch(guests, /class _PropertyIdentity/);
  assert.match(guests, /Needs personal attention/);
  assert.doesNotMatch(team, /PUEBLO\\nLA PERLA\\nBORACAY/);
  assert.match(team, /TEAM & ACCESS/);
  assert.doesNotMatch(activity, /PUEBLO\\nLA PERLA\\nBORACAY/);
  assert.match(activity, /Provider-backed audit trail/);
});

test("PLP tax is owner-first and does not duplicate the global Pandora composer", () => {
  assert.match(tax, /bottomNavigationBar: _isPlp \? null : SafeArea/);
  assert.match(tax, /plp-tax-owner-status/);
  assert.match(tax, /Professional review required\./);
  assert.match(tax, /Approved rule authority/);
  assert.match(tax, /The Philippines rule pack is still under professional review\./);
});

test("PLP shell uses integrated headers and one context-aware Pandora command dock", () => {
  assert.match(shell, /openDrawer: _openDrawer/);
  assert.match(shell, /if \(_index == 4 \|\| _index == 12\)/);
  assert.match(shell, /Ask what matters today…/);
  assert.match(shell, /Ask about a guest or stay…/);
  assert.match(shell, /Ask about tax readiness…/);
  assert.match(shell, /hintText: _commandHint/);
});
