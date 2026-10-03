"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const read = (p) => fs.readFileSync(p, "utf8");
const chat = read("apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart");
const picker = read("apps/pandora-mobile/lib/features/simple/pandora_model_picker.dart");
const resort = read("apps/pandora-mobile/lib/features/enterprise/plp_resort_workspace.dart");
const activity = read("apps/pandora-mobile/lib/features/enterprise/plp_activity_screen.dart");
const team = read("apps/pandora-mobile/lib/features/enterprise/plp_team_management_screen.dart");
const operational = read("apps/pandora-mobile/lib/features/enterprise/plp_resort_operational_screens.dart");
const editorial = read("apps/pandora-mobile/lib/features/enterprise/plp_editorial_surfaces.dart");
const guests = read("apps/pandora-mobile/lib/features/enterprise/plp_guests_screen.dart");
const infrastructure = read("apps/pandora-mobile/lib/features/enterprise/plp_connectivity_infrastructure_screen.dart");
const tax = read("apps/pandora-mobile/lib/features/enterprise/tax_compliance_screen.dart");

test("PLP uses the restored e7 chat, with model choice compact and left anchored only there", () => {
  assert.match(chat, /Widget _buildPlpE7Chat\(BuildContext context\)/);
  assert.match(chat, /compactLeftAnchored: true/);
  assert.match(chat, /class _PlpE7Composer/);
  assert.match(chat, /Icons\.mic_none_rounded/);
  assert.match(chat, /Icons\.arrow_upward_rounded/);
  assert.match(picker, /final bool compactLeftAnchored/);
  assert.match(picker, /left: widget\.compactLeftAnchored \? 14 : null/);
  assert.match(picker, /width: widget\.compactLeftAnchored \? 260 : 285/);
});

test("PLP source outage state never masquerades as business Needs Attention", () => {
  const recovery = resort.slice(
    resort.indexOf("class _SourceRecoveryPanel"),
    resort.indexOf("class _SourceBand"),
  );
  assert.doesNotMatch(recovery, /Needs Attention/);
  assert.match(recovery, /Icons\.cloud_off_outlined/);
  assert.match(resort, /_SectionHeader\(\s*'NEEDS ATTENTION'/);
});

test("PLP contextual headers use the accepted editorial title typography", () => {
  for (const source of [resort, activity, team, operational]) {
    assert.match(source, /fontFamily: 'serif'[\s\S]{0,100}fontSize: 16[\s\S]{0,100}fontWeight: FontWeight\.w400[\s\S]{0,100}letterSpacing: 2\.6/);
  }
  assert.match(editorial, /title\.toUpperCase\(\)[\s\S]{0,220}fontSize: 16[\s\S]{0,120}letterSpacing: 2\.6/);
  assert.doesNotMatch(editorial.slice(editorial.indexOf("class PlpEditorialHeader"), editorial.indexOf("class PlpEditorialPage")), /PUEBLO LA PERLA/);
  assert.doesNotMatch(guests.slice(guests.indexOf("class _GuestHeader")), /PUEBLO LA PERLA/);
  assert.doesNotMatch(infrastructure.slice(infrastructure.indexOf("class _Header")), /Pueblo La Perla/);
  assert.match(tax, /'TAX & COMPLIANCE'[\s\S]{0,220}fontSize: 16[\s\S]{0,120}letterSpacing: 2\.6/);
});
