'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { PandoraAuthService, AuthRequiredError } = require('../packages/primitives/auth/src');
const { PandoraRbacService, PermissionDeniedError, roleDefinition } = require('../packages/primitives/rbac/src');

test('auth proves signup/login protected route sign-out and session invalidation', async () => {
  let session = null;
  const adapter = {
    async signUp({ email }) { session = { user: { userId:'u1', email, provider:'test', emailVerified:false } }; return session; },
    async signIn({ email }) { session = { user: { userId:'u1', email, provider:'test', emailVerified:true } }; return session; },
    async requestPasswordReset() {},
    async signOut() { session = null; },
    async getSession() { return session; },
  };
  const auth = new PandoraAuthService({ adapter, environment:'test' });
  await auth.signUp({ email:'USER@example.com', password:'correct-horse' });
  assert.equal((await auth.requireUser()).userId, 'u1');
  await auth.signOut();
  await assert.rejects(() => auth.requireUser(), AuthRequiredError);
});

test('auth rejects privileged client adapters and unsafe reset redirects', async () => {
  const base = { signUp(){}, signIn(){}, requestPasswordReset(){}, signOut(){}, getSession(){} };
  assert.throws(() => new PandoraAuthService({ adapter:{...base, privileged:true}, environment:'test' }), /privileged/);
  const auth = new PandoraAuthService({ adapter:base, environment:'test' });
  await assert.rejects(() => auth.requestPasswordReset({ email:'a@b.com', redirectUrl:'http://example.com/reset' }), /https/);
});

test('rbac owner can manage users while staff and customer are denied', async () => {
  const resolver = { async resolve({userId,tenantId}) { return [{ tenantId, role: userId==='owner'?'owner':userId==='staff'?'staff':'customer' }]; } };
  const rbac = new PandoraRbacService({ membershipResolver:resolver });
  assert.equal(await rbac.can({userId:'owner',tenantId:'t1',permission:'users.manage'}), true);
  await assert.rejects(() => rbac.assertAllowed({userId:'staff',tenantId:'t1',permission:'users.manage'}), PermissionDeniedError);
  await assert.rejects(() => rbac.assertAllowed({userId:'customer',tenantId:'t1',permission:'admin.manage'}), PermissionDeniedError);
});

test('rbac custom roles are explicit and cross-tenant memberships fail closed', async () => {
  assert.deepEqual(roleDefinition('custom',['booking.read','booking.manage']).permissions,['booking.manage','booking.read']);
  const rbac = new PandoraRbacService({ membershipResolver:{ async resolve(){ return [{tenantId:'other',role:'owner'}]; } } });
  await assert.rejects(() => rbac.permissionsFor({userId:'u1',tenantId:'t1'}), /cross-tenant/);
});

test('auth and rbac migrations enforce customer-runtime isolation, forced RLS and backend authorization', () => {
  const authSql = fs.readFileSync(require.resolve('../packages/primitives/auth/migrations/001_auth_profile.sql'),'utf8');
  const rbacSql = fs.readFileSync(require.resolve('../packages/primitives/rbac/migrations/001_rbac.sql'),'utf8');
  for (const sql of [authSql, rbacSql]) {
    assert.match(sql,/customer-app-runtime-only/);
    assert.match(sql,/refused on Pandora Control Plane-like schema/);
    assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
    assert.match(sql,/FORCE ROW LEVEL SECURITY/);
  }
  assert.match(rbacSql,/FOREIGN KEY \(tenant_id, role_key\)/);
  assert.match(rbacSql,/SECURITY DEFINER/);
  assert.match(rbacSql,/m\.user_id = \(SELECT auth\.uid\(\)\)/);
  assert.doesNotMatch(rbacSql,/GRANT (?:INSERT|UPDATE|DELETE).*authenticated/i);
});
