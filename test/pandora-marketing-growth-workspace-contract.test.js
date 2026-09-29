const fs = require('node:fs');
const assert = require('node:assert/strict');
const test = require('node:test');

const screen = fs.readFileSync(
  'apps/pandora-mobile/lib/features/growth/marketing_growth_workspace_screen.dart',
  'utf8',
);
const shell = fs.readFileSync(
  'apps/pandora-mobile/lib/app/pandora_chat_shell.dart',
  'utf8',
);

test('FB-033 exposes Marketing & Growth as a first-class Pandora destination', () => {
  assert.match(shell, /'Marketing & Growth'/);
  assert.match(shell, /11 => 'marketing_growth'/);
  assert.match(shell, /11 => MarketingGrowthWorkspaceScreen\(/);
  assert.match(shell, /\[9, 11, 10, 0, 8, 1, 2, 4, 5, 6, 7, 3\]/);
});

test('FB-033 keeps the approved workspace sections visible', () => {
  for (const label of [
    'Overview', 'Campaigns', 'Leads', 'Experiments',
    'Learning', 'Approvals', 'Activity', 'Settings',
  ]) assert.ok(screen.includes("label: '" + label + "'"), label);
});

test('FB-033 preserves persistent Pandora chat across section changes', () => {
  assert.match(screen, /class MarketingGrowthWorkspaceScreen extends StatefulWidget/);
  assert.match(screen, /Expanded\([\s\S]*AskPandoraScreen\(/);
  assert.doesNotMatch(screen, /AskPandoraScreen\([\s\S]*key:/);
  assert.match(screen, /enterpriseContext:\s*marketingGrowthEnterpriseContext\(_section\)/);
});

test('FB-033 does not imply campaign write or spend authority', () => {
  assert.match(screen, /'capabilities': const <String>\[\]/);
  assert.match(screen, /read_only_until_explicit_approval/);
  assert.match(screen, /writes require explicit approval/);
});
