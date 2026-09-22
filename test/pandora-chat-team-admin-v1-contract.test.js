import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const edge = readFileSync('supabase/functions/pandora-intelligence-chat/index.ts', 'utf8');
const mobile = readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', 'utf8');
const admin = readFileSync('supabase/functions/pandora-user-admin/index.ts', 'utf8');

test('Ask Pandora owns a deterministic multi-turn team-administration lane', () => {
  assert.match(edge, /type TeamAdminState=/);
  assert.match(edge, /teamAdminState/);
  assert.match(edge, /What email address should I invite\?/);
  assert.match(edge, /What role should I give them: owner, admin, operator, member, or viewer\?/);
  assert.match(edge, /Which team member should I change\?/);
  assert.match(edge, /team\.member\.invite/);
  assert.match(edge, /team\.member\.update/);
});

test('team chat delegates mutations to the governed user-admin backend', () => {
  assert.match(edge, /\/functions\/v1\/pandora-user-admin/);
  assert.match(edge, /invokeUserAdmin\(c\.authorization,c\.organizationId,"POST","\/invite"/);
  assert.match(edge, /invokeUserAdmin\(c\.authorization,c\.organizationId,"PATCH","\/member"/);
  assert.match(admin, /pandora_admin_add_organization_member/);
  assert.match(admin, /pandora_admin_update_organization_member/);
});

test('team chat persists both sides of clarification and verified mutation turns', () => {
  assert.match(edge, /author_role:"user",content:message/);
  assert.match(edge, /author_role:"assistant",content:reply/);
  assert.match(edge, /provider:"pandora_team_admin"/);
  assert.match(edge, /model:"deterministic-team-admin-v1"/);
  assert.match(edge, /if\(userWrite\.error\)throw Error\("BACKEND_WRITE_FAILED"\)/);
  assert.match(edge, /if\(assistantWrite\.error\)throw Error\("BACKEND_WRITE_FAILED"\)/);
});

test('activity execution routes team administration before generic capability/model dispatch', () => {
  const team = edge.indexOf('const teamTurn=await tryTeamAdminChat');
  const generic = edge.indexOf('let dispatched:any=null');
  assert.ok(team >= 0 && generic > team);
  assert.match(edge, /Team change completed and verified\./);
  assert.match(edge, /Pandora needs one more detail before changing team access\./);
});

test('direct mobile chat does not preflight team mutations through the generic SQL dispatcher', () => {
  assert.match(mobile, /_isTeamAdministrationRequest\(message\)/);
  assert.match(mobile, /!_isTeamAdministrationRequest\(message\)/);
  assert.ok(mobile.includes("team|member|staff|user|access|invite"));
});
