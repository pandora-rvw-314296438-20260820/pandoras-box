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
const teamAccess = read("apps/pandora-mobile/lib/features/enterprise/plp_team_access_screen.dart");
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
  assert.match(resort, /if \(includeWorkspaceRail\)[\s\S]{0,120}_SourceRecoveryPanel/);
  assert.match(resort, /else\s+_EmptyState\(detail\)/);
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
  assert.doesNotMatch(teamAccess, /PUEBLO LA PERLA/);
  assert.match(teamAccess, /'TEAM & ACCESS'[\s\S]{0,220}fontSize: 16[\s\S]{0,120}letterSpacing: 2\.6/);
  const taxTitle = tax.slice(
    tax.indexOf("'TAX & COMPLIANCE'"),
    tax.indexOf("else ...[", tax.indexOf("'TAX & COMPLIANCE'")),
  );
  assert.match(taxTitle, /fontFamily: 'serif'/);
  assert.match(taxTitle, /fontSize: 16/);
  assert.match(taxTitle, /letterSpacing: 2\.6/);
  assert.match(taxTitle, /fontWeight: FontWeight\.w400/);
});


test("PLP top chrome floats over content with a soft darkening scrim on every surface", () => {
  const navigation = read("apps/pandora-mobile/lib/core/widgets/pandora_navigation.dart");
  const shell = read("apps/pandora-mobile/lib/app/plp_enterprise_shell.dart");
  assert.match(navigation, /class PandoraTopScrim/);
  assert.match(navigation, /CircleBorder/);
  assert.match(navigation, /pandora-header-action-capsule/);
  assert.doesNotMatch(navigation, /child: ColoredBox\(\s*color: background/);
  assert.match(chat, /height: 126,[\s\S]{0,160}PandoraTopScrim/);
  assert.match(chat, /top: topInset \+ 8/);
  assert.match(chat, /'pandora-chat-new'/);
  assert.match(chat, /Icons\.edit_square/);
  assert.match(shell, /if \(_index != 1 \|\| _routedTool != null\)[\s\S]{0,260}PandoraTopScrim/);
  const chromeGate = shell.indexOf('if (_index != 1 || _routedTool != null)');
  const floatingMenu = shell.indexOf("'plp-floating-navigation'", chromeGate);
  assert.ok(chromeGate >= 0 && floatingMenu > chromeGate);
  const plpHeader = chat.slice(
    chat.indexOf('class _PlpE7ChatHeader'),
    chat.indexOf('class _PlpE7EmptyConversation'),
  );
  assert.doesNotMatch(plpHeader, /required this\.active/);
  assert.match(plpHeader, /'pandora-chat-new'/);
  assert.match(plpHeader, /'pandora-chat-overflow'/);
});
