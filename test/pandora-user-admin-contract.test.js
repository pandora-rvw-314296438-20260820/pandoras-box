const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const edge = read('supabase/functions/pandora-user-admin/index.ts');
const foundation = read(
  'supabase/migrations/20260826005701_pandora_organization_user_administration_v1.sql',
);
const boundary = read(
  'supabase/migrations/20260826010748_pandora_user_administration_service_boundary_v1.sql',
);
const cleanup = read(
  'supabase/migrations/20260826011131_remove_legacy_pandora_user_admin_rpc_v1.sql',
);

test('Edge Function keeps Auth invitation and membership mutation server-side', () => {
  assert.match(edge, /auth\.admin\s*\n?\s*\.inviteUserByEmail\(/);
  assert.match(edge, /auth\.getUser\(jwt\)/);
  assert.match(edge, /pandora_admin_add_organization_member/);
  assert.match(edge, /context\.adminClient\.rpc\(/);
  assert.match(edge, /x-organization-id/);
  assert.match(edge, /\["owner", "admin"\]/);
  assert.match(edge, /consume_runtime_rate_limit/);
  assert.doesNotMatch(edge, /console\.error\([^\n]*(email|authorization|token|service_role)/i);
});

test('Invitation acceptance activates membership and writes bounded audit evidence', () => {
  assert.match(foundation, /on_auth_user_confirmed_memberships/);
  assert.match(foundation, /status = 'active'::public\.membership_status/);
  assert.match(foundation, /organization\.member\.activated/);
  assert.match(foundation, /private\.append_audit_event/);
  assert.match(foundation, /'source', 'auth-email-confirmation'/);
});

test('Database mutation is service-role-only and rechecks organization authority', () => {
  assert.match(boundary, /coalesce\(auth\.role\(\), ''\) <> 'service_role'/);
  assert.match(boundary, /active owner or administrator membership required/);
  assert.match(boundary, /administrators cannot grant owner or admin roles/);
  assert.match(boundary, /pg_advisory_xact_lock/);
  assert.match(boundary, /grant execute[\s\S]*to service_role;/);
  assert.match(boundary, /revoke all[\s\S]*from public, anon, authenticated;/);
});

test('Transitional client-callable SECURITY DEFINER RPC is removed', () => {
  assert.match(cleanup, /drop function if exists public\.pandora_add_organization_member/);
});
