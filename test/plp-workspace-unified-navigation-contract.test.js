import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const shell = readFileSync(
  'apps/pandora-mobile/lib/app/plp_enterprise_shell.dart',
  'utf8',
);
const chat = readFileSync(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const team = readFileSync(
  'apps/pandora-mobile/lib/features/enterprise/plp_team_management_screen.dart',
  'utf8',
);
const projection = readFileSync(
  'supabase/migrations/20260923133000_plp_team_access_governed_projection_v5.sql',
  'utf8',
);

test('persistent commands stay on the current PLP surface', () => {
  assert.match(shell, /_commandBusy = true/);
  assert.match(
    shell,
    /submitExternalPrompt\([\s\S]*requestFocus: false/,
  );
  assert.match(shell, /_commandReply = reply/);
  assert.match(shell, /_refresh\(\);/);
  assert.doesNotMatch(
    shell,
    /Future<void> _submitCommand[\s\S]*?_index = 1;/,
  );
  assert.match(chat, /Future<String\?> submitExternalPrompt/);
});

test('PLP navigation remembers origin and Android back restores it', () => {
  assert.match(shell, /final List<int> _surfaceHistory/);
  assert.match(shell, /_surfaceHistory\.add\(_index\)/);
  assert.match(shell, /_surfaceHistory\.removeLast\(\)/);
  assert.match(shell, /bool _handleWorkspaceBack\(\)/);
  assert.match(shell, /PopScope<void>\([\s\S]*_handleWorkspaceBack/);
  assert.match(shell, /void _openHome\(\)/);
});

test('Team management is PLP-native and uses the governed admin gateway', () => {
  assert.doesNotMatch(shell, /TeamScreen\(/);
  assert.match(shell, /PlpTeamManagementScreen\(/);
  assert.match(team, /SupabasePandoraUserAdminGateway\(\)/);
  assert.match(team, /_gateway\.loadMembers\(/);
  assert.match(team, /_gateway\.inviteMember\(/);
  assert.match(team, /_gateway\.updateMember\(/);
  assert.match(team, /plp-team-management-page/);
});

test('PLP team projection uses every organization membership status', () => {
  assert.match(
    projection,
    /'schemaVersion','plp\.enterprise\.mobile-bootstrap\.v5'/,
  );
  assert.match(projection, /'totalMemberCount',total_member_count/);
  assert.match(projection, /where m\.organization_id=prop\.organization_id/);
  assert.doesNotMatch(projection, /not like '%staging%'/);
  assert.match(
    projection,
    /'accessModel','organization_membership_all_statuses'/,
  );
});
