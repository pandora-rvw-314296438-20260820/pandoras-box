import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");
const home = read("apps/pandora-mobile/lib/features/enterprise/plp_enterprise_home.dart");
const resort = read("apps/pandora-mobile/lib/features/enterprise/plp_resort_workspace.dart");
const drawer = read("apps/pandora-mobile/lib/app/plp_navigation_drawer.dart");
const shell = read("apps/pandora-mobile/lib/app/plp_enterprise_shell.dart");
const migration = read("supabase/migrations/20261001044500_plp_resort_command_center_v1.sql");
const operationsMigration = read("supabase/migrations/20261001070000_plp_resort_operations_v1.sql");
const operational = read("apps/pandora-mobile/lib/features/enterprise/plp_resort_operational_screens.dart");
const activity = read("apps/pandora-mobile/lib/features/enterprise/plp_activity_screen.dart");
const teamManagement = read("apps/pandora-mobile/lib/features/enterprise/plp_team_management_screen.dart");
const productionActivityIsolation = read("supabase/migrations/20261003201314_plp_production_activity_isolation_v1.sql");
const plpAuthGate = read("apps/pandora-mobile/lib/features/auth/plp_auth_gate.dart");
const signIn = read("apps/pandora-mobile/lib/features/auth/sign_in_screen.dart");
const failClosedTruth = read("supabase/migrations/20261001070517_plp_fail_closed_source_truth_v1.sql");

test("PLP Home is one shared resort workspace, not a second editorial design", () => {
  assert.match(home, /PlpResortWorkspaceScreen/);
  assert.match(home, /plpResortSectionById\('today'\)/);
  assert.doesNotMatch(home, /OWNERâ€™S HOME|Your private briefing/);
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

test("PLP disconnected customer source truth cannot claim connection or manufacture current metrics", () => {
  const failClosed = read("supabase/migrations/20261001070517_plp_fail_closed_source_truth_v1.sql");
  assert.match(
    failClosed,
    /'customerTenantConnected',\s*effective_source_state in \('healthy','current','live','ready'\)/,
  );
  assert.match(failClosed, /'customerTenantActive'/);
  assert.match(
    failClosed,
    /'available',case when live_operational_data_available then greatest\(rooms_total-rooms_occupied,0\) else null end/,
  );
  assert.match(
    failClosed,
    /'bookedValue30dPhp',case when live_operational_data_available then booked_value_30d else null end/,
  );
  assert.doesNotMatch(
    failClosed,
    /'customerTenantConnected',\s*prop\.organization_id<>/,
  );
});

test("PLP resort projection is bounded to existing truth and excludes direct contact data", () => {
  assert.match(migration, /active PLP membership required/);
  assert.match(migration, /plp_runtime\.plp_bookings/);
  assert.match(migration, /enterprise_hospitality_housekeeping_jobs/);
  assert.match(migration, /contactDetailsExcluded/);
  assert.doesNotMatch(migration, /g\.email|g\.phone/);
  assert.match(migration, /revoke execute on function public\.plp_resort_command_center_v1\(\)\s+from public, anon/);
});


test("PLP capability tiles navigate to real system pages instead of issuing chat prompts", () => {
  for (const moduleId of ["housekeeping","maintenance","linen","concierge","vip","transfers","property","security","transport","rates","channels","forecast","dining","wellness","activities","events"]) {
    assert.match(resort, new RegExp("onOpenModule\\?\\.call\\('" + moduleId + "'\\)"));
  }
  assert.doesNotMatch(resort, /\(\) => onAskPandora\(/);
  assert.match(shell, /void _openResortModule\(/);
  assert.match(shell, /PlpResortOperationalScreen/);
  assert.match(operational, /New task/);
  assert.match(operational, /PlpStaffTaskAction/);
});

test("PLP shell owns a fixed floating hamburger without a top app bar", () => {
  assert.match(shell, /'plp-floating-navigation'/);
  assert.match(shell, /PandoraNavigationScope\(\s*openDrawer: null/);
  assert.doesNotMatch(resort, /key: const ValueKey\('plp-open-navigation'\)/);
});

test("PLP operational detail projection exposes real work queues without fabricating rows", () => {
  assert.match(shell, /plp_resort_operations_v1/);
  assert.match(operationsMigration, /plp_runtime\.plp_staff_tasks/);
  assert.match(operationsMigration, /plp_runtime\.plp_ota_conflicts/);
  assert.match(operationsMigration, /enterprise_hospitality_housekeeping_jobs/);
  assert.match(operationsMigration, /'noSyntheticRows',true/);
  assert.match(operationsMigration, /active PLP membership required/);
  assert.match(operationsMigration, /revoke execute on function public\.plp_resort_operations_v1\(\)\s+from public,anon/);
});


test("PLP 6405 audit keeps normal work operational and strips client-facing implementation leakage", () => {
  assert.doesNotMatch(resort, /The resort needs a little attention\./);
  assert.doesNotMatch(resort, /The resort is composed\./);
  assert.doesNotMatch(resort, /Every stay in one calm view\./);
  assert.doesNotMatch(resort, /Hospitality beyond the room\./);
  assert.doesNotMatch(resort, /The people running the property\./);
  assert.doesNotMatch(resort, /What changed, without the noise\./);
  assert.doesNotMatch(resort, /Staff IDs/);
  assert.match(resort, /_humanStatus/);
  assert.match(resort, /_clientRecords/);
  assert.match(resort, /_clientSourceMessage/);
  assert.match(resort, /Sales today/);
  assert.doesNotMatch(resort, /source\['message'\]/);
  assert.doesNotMatch(resort, /onAskPandora/);
});

test("PLP Team is one resort workspace and legacy Team & Access is not routed", () => {
  assert.match(shell, /plpResortSectionById\('team'\)!/);
  assert.match(shell, /_openTeamManagement\(bootstrap\)/);
  assert.doesNotMatch(shell, /PlpTeamAccessScreen/);
  assert.doesNotMatch(shell, /plp_team_access_screen\.dart/);
});

test("PLP authentication is explicitly resort-branded", () => {
  assert.match(plpAuthGate, /SignInPresentation\.plp/);
  assert.match(signIn, /Pueblo La Perla/);
  assert.match(signIn, /PLP BORACAY .* LUXURY RESORT/);
  assert.match(signIn, /allowFacebookSignIn: false/);
});

test("PLP live business truth fails closed while the source is unavailable", () => {
  assert.match(failClosedTruth, /liveOperationalDataAvailable/);
  assert.match(failClosedTruth, /liveBusinessSourceConnected/);
  assert.match(failClosedTruth, /when not live_operational_data_available then 'unknown'/);
  assert.match(failClosedTruth, /available'.*case when live_operational_data_available/s);
  assert.match(failClosedTruth, /bookedValue30dPhp'.*case when live_operational_data_available/s);
});


test("PLP uses one compact contextual page header instead of repeating resort and page names", () => {
  assert.match(resort, /headerTitle: 'RESORT STATUS'/);
  assert.match(resort, /section\.headerTitle/);
  assert.doesNotMatch(resort, /class _HeroLine/);
  assert.doesNotMatch(operational, /const Text\('PLP Boracay'/);
  assert.match(activity, /'ACTIVITY & AUDIT'/);
  assert.match(teamManagement, /'TEAM & ACCESS'/);
  assert.doesNotMatch(activity, /'PUEBLO LA PERLA'/);
  assert.doesNotMatch(teamManagement, /'PUEBLO LA PERLA'/);
});

test("PLP deep surfaces preserve parent navigation and contextual Pandora", () => {
  assert.match(shell, /'activity-feed'/);
  assert.match(shell, /onOpenActivity: _openActivityFeed/);
  assert.match(shell, /toolKey == 'team-management'/);
  assert.match(shell, /toolKey == 'activity-feed'/);
  assert.match(shell, /Ask about infrastructure…/);
  assert.match(shell, /hintMaxLines: 1/);
  assert.doesNotMatch(shell, /hintText\.length > 28/);
  assert.match(shell, /AnnotatedRegion<SystemUiOverlayStyle>/);
});

test("PLP verified production activity excludes mock QA and synthetic history at provider and UI boundaries", () => {
  assert.match(productionActivityIsolation, /and not is_mock/);
  assert.match(productionActivityIsolation, /'testDataExcluded',true/);
  assert.match(productionActivityIsolation, /not like '%synthetic%'/);
  assert.match(activity, /_productionActivity/);
  assert.match(operational, /_productionRecords/);
  assert.match(operational, /plpRecordIsTestData\(item\)/);
});

test("PLP source outages remain actionable without manufacturing current business values", () => {
  assert.match(resort, /class _SourceRecoveryPanel/);
  assert.match(resort, /Refresh status/);
  assert.match(resort, /Open infrastructure/);
  assert.match(resort, /_cachedOperationalSnapshot/);
  assert.match(resort, /_sourceAvailableActions/);
});


const activityModel = read("apps/pandora-mobile/lib/features/enterprise/plp_activity_read_model.dart");
const markerPrecision = read("supabase/migrations/20261003215433_plp_activity_test_marker_precision_v2.sql");

test("PLP summary and detail share lazy activity reads without adding startup work", () => {
  assert.match(shell, /readModel: _activityReadModel/);
  assert.match(shell, /_bootstrapInFlight/);
  assert.match(shell, /Future\.wait<void>/);
  assert.match(activityModel, /if \(pending != null\) return pending/);
  assert.match(activityModel, /payload\['items'\] is! List/);
  assert.match(activity, /widget\.readModel!\.load/);
  assert.match(resort, /plpProductionActivityRecords/);
});

test("PLP explicit test provenance does not erase ordinary production descriptions", () => {
  assert.match(markerPrecision, /plp_activity_record_is_test_v2/);
  assert.match(markerPrecision, /PLP_PRODUCTION_FALSE_POSITIVE/);
  assert.match(markerPrecision, /Mockingbird PMS/);
  assert.match(activityModel, /bool plpRecordIsTestData/);
  assert.match(resort, /plpRecordIsTestData\(item\)/);
  assert.doesNotMatch(activityModel, /source\.contains\('mock'\)/);
  assert.doesNotMatch(activityModel, /text\.contains\('synthetic'\)/);
});
