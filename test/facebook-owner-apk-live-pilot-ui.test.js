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

test('owner Android entrypoint reaches the live Marketing & Growth workspace', () => {
  assert.match(main,/PandoraApp\\(/);
  assert.match(auth,/PandoraChatShell\\(\\)/);
  assert.match(home,/key: 'pandora-marketing-growth'/);
  assert.match(shell,/workspace\\.key ==\\s*'pandora-marketing-growth'/);
  assert.match(shell,/MarketingGrowthWorkspaceScreen\\(/);
  assert.match(growth,/pandora_marketing_growth_command_center_v2/);
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
    'Meta connection',
    'Pilot spend',
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

test('PLP client APK remains isolated from Pandora owner Facebook marketing', () => {
  assert.doesNotMatch(plpShell,/MarketingGrowthWorkspaceScreen/);
  assert.doesNotMatch(plpShell,/pandora-marketing-growth/);
  assert.doesNotMatch(plpShell,/pandora_marketing_growth_command_center_v2/);
});
