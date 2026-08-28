import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const api = readFileSync(
  'apps/pandora-mobile/lib/core/data/pandora_user_admin_api.dart',
  'utf8',
);
const screen = readFileSync(
  'apps/pandora-mobile/lib/features/team/team_screen.dart',
  'utf8',
);
const more = readFileSync(
  'apps/pandora-mobile/lib/features/simple/more_screen.dart',
  'utf8',
);
const fn = readFileSync(
  'supabase/functions/pandora-user-admin/index.ts',
  'utf8',
);

test('mobile client uses signed-in function invocation without embedded service role', () => {
  assert.match(api, /Supabase\.instance\.client/);
  assert.match(api, /x-organization-id/);
  assert.match(api, /functionName = 'pandora-user-admin'/);
  assert.doesNotMatch(api, /SERVICE_ROLE_KEY|service_role/i);
});

test('Team screen exposes real invite and member states', () => {
  assert.match(screen, /loadOrganizations\(\)/);
  assert.match(screen, /loadMembers\(/);
  assert.match(screen, /inviteMember\(/);
  assert.match(screen, /Owner or administrator access required/);
  assert.match(screen, /No one has been added yet/);
  assert.match(screen, /Invitation sent to/);
});

test('normal owner navigation includes Team', () => {
  assert.match(more, /title: 'Team'/);
  assert.match(more, /TeamScreen\(gateway: teamGateway\)/);
});

test('server authority remains in the Edge Function', () => {
  assert.match(fn, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(fn, /auth\.admin\s*\.inviteUserByEmail/);
  assert.match(fn, /pandora_admin_add_organization_member/);
  assert.match(fn, /ADMIN_ROLE_REQUIRED/);
});
