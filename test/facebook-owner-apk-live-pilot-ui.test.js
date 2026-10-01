import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const main = readFileSync('apps/pandora-mobile/lib/main.dart','utf8');
const auth = readFileSync('apps/pandora-mobile/lib/features/auth/auth_gate.dart','utf8');
const shell = readFileSync('apps/pandora-mobile/lib/app/pandora_chat_shell.dart','utf8');
const home = readFileSync('apps/pandora-mobile/lib/features/enterprise/enterprise_workspace_home.dart','utf8');
const growth = readFileSync('apps/pandora-mobile/lib/features/enterprise/marketing_growth_workspace_screen.dart','utf8');
const plpShell = readFileSync('apps/pandora-mobile/lib/app/plp_enterprise_shell.dart','utf8');
const projection = readFileSync('supabase/migrations/20260930233508_pandora_growth_live_pilot_projection_v1.sql','utf8');
const businessAttribution = readFileSync('supabase/migrations/20260930235134_pandora_meta_paid_pilot_business_attribution_v1.sql','utf8');
const tracking = readFileSync('src/pandora-tracking-http.js','utf8');
const ownerControls = readFileSync('supabase/migrations/20261001001911_pandora_growth_owner_pilot_controls_v1.sql','utf8');

test('owner Android entrypoint reaches the live Marketing & Growth workspace', () => {
  assert.ok(main.includes('PandoraApp('));
  assert.ok(auth.includes('PandoraChatShell()'));
  assert.ok(home.includes("key: 'pandora-marketing-growth'"));
  assert.ok(shell.includes("workspace.key == 'pandora-marketing-growth'"));
  assert.ok(shell.includes('MarketingGrowthWorkspaceScreen('));
  assert.ok(growth.includes('pandora_marketing_growth_command_center_v2'));
});

test('owner Growth UI surfaces Meta connection and live paid-pilot evidence', () => {
  for (const token of [
    "data['metaConnection']",
    "data['paidPilot']",
    'deliveryObserved',
    'monitorHealthy',
    'maxSpendMinor',
    'dailyBudgetMinor',
    'spendMinor',
    'boundedCampaignMutationGranted',
    'providerCreativeReady',
    'providerCreativeBlocker',
    'trackedRedirect',
    'Meta connection',
    'Pilot spend',
    'Tracked creative',
  ]) assert.ok(growth.includes(token), token);
});

test('growth command center projects current bounded pilot instead of stale static denial', () => {
  assert.match(projection,/pandora_growth_paid_pilot_projection_v1/);
  assert.match(projection,/pandora_growth_meta_connection_projection_v1/);
  assert.match(projection,/authorizationGranted/);
  assert.match(projection,/boundedCampaignMutationGranted/);
  assert.match(projection,/metaConnected/);
  assert.match(projection,/then 'granted' else 'not_granted'/);
});

test('web landing carries the opaque click into server-owned attribution', () => {
  assert.match(main,/queryParameters\['pcid'\]/);
  assert.match(main,/\/api\/tracking\/event/);
  assert.match(main,/landing\.viewed/);
  assert.match(tracking,/select: "tenant_id,campaign_id,is_test"/);
  assert.match(tracking,/test_marker_mismatch/);
  assert.match(tracking,/is_test: clickIsTest/);
});

test('live Meta IDs belong to the business campaign, not the historical test campaign', () => {
  assert.match(businessAttribution,/pandora-meta-main/);
  assert.match(businessAttribution,/'business_kpi',true/);
  assert.match(businessAttribution,/tracked_redirect','https:\/\/mcpmaster\.vercel\.app\/t\/pandora-meta-main'/);
  assert.match(businessAttribution,/historical_acceptance',true/);
  assert.match(businessAttribution,/provider_campaign_id=null/);
  assert.match(businessAttribution,/pandora_meta_paid_pilot_target_is_allowed_v1/);
  const readiness = readFileSync('supabase/migrations/20260930235454_pandora_growth_provider_creative_readiness_projection_v1.sql','utf8');
  assert.match(readiness,/providerCreativeReady/);
  assert.match(readiness,/providerCreativeBlocker/);
  assert.match(readiness,/meta_app_development_mode/);
});

test('owner Growth page exposes only bounded owner pilot lifecycle controls', () => {
  assert.ok(growth.includes('pandora_growth_paid_pilot_owner_control_v1'));
  assert.ok(growth.includes('marketing-growth-pilot-prepare'));
  assert.ok(growth.includes('marketing-growth-pilot-activate'));
  assert.ok(growth.includes('marketing-growth-pilot-stop'));
  assert.ok(growth.includes('Tracked Meta creative is not provider-ready yet'));
  assert.equal(growth.includes('budget TextField'), false);

  assert.ok(ownerControls.includes("v_role is distinct from 'owner'"));
  assert.ok(ownerControls.includes("v_action not in ('prepare','activate','stop')"));
  assert.ok(ownerControls.includes('a.max_spend_minor<>500000'));
  assert.ok(ownerControls.includes('a.daily_budget_minor<>40000'));
  assert.ok(ownerControls.includes('a.duration_seconds<>604800'));
  assert.ok(ownerControls.includes('provider_creative_ready'));
  assert.ok(ownerControls.includes('PANDORA_GROWTH_OWNER_CONTROL_CREATIVE_NOT_READY'));
  assert.equal(ownerControls.includes('p_budget'), false);
  assert.equal(ownerControls.includes('p_target_id'), false);
});

test('PLP client APK remains isolated from Pandora owner Facebook marketing', () => {
  assert.doesNotMatch(plpShell,/MarketingGrowthWorkspaceScreen/);
  assert.doesNotMatch(plpShell,/pandora-marketing-growth/);
  assert.doesNotMatch(plpShell,/pandora_marketing_growth_command_center_v2/);
});
