import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

import {
  assertTenantActionBinding,
  createTenantScopedConnectionApi,
} from '../packages/pandora-connections-quality/src/tenant-isolation.mjs';

const root = join(import.meta.dirname, '..');
const foundationPath = join(
  root,
  'supabase/migrations/20260724010000_control_plane_foundation.sql',
);
const ownerApiPath = join(root, 'supabase/functions/pandora-owner-api/index.ts');

const actorA = {
  organizationId: 'org-a',
  tenantId: 'tenant-a',
  accountId: 'account-a',
};
const connectionA = {
  id: 'connection-a',
  organizationId: 'org-a',
  tenantId: 'tenant-a',
  accountId: 'account-a',
  provider: 'example',
  state: 'healthy',
};
const connectionB = {
  id: 'connection-b',
  organizationId: 'org-b',
  tenantId: 'tenant-b',
  accountId: 'account-b',
  provider: 'example',
  state: 'healthy',
};
const credentialA = {
  credentialReferenceId: 'credential-a',
  organizationId: 'org-a',
  tenantId: 'tenant-a',
  accountId: 'account-a',
  connectionId: 'connection-a',
};
const credentialB = {
  credentialReferenceId: 'credential-b',
  organizationId: 'org-b',
  tenantId: 'tenant-b',
  accountId: 'account-b',
  connectionId: 'connection-b',
};

function harness(overrides = {}) {
  const calls = { credential: 0, execute: 0 };
  const connections = new Map([
    [connectionA.id, connectionA],
    [connectionB.id, connectionB],
  ]);
  const credentials = new Map([
    [connectionA.id, credentialA],
    [connectionB.id, credentialB],
  ]);
  const api = createTenantScopedConnectionApi({
    async listConnections(organizationId) {
      return [...connections.values()].filter((item) => item.organizationId === organizationId);
    },
    async getConnection(connectionId) {
      return connections.get(connectionId) ?? null;
    },
    async getCredentialReference(connectionId) {
      calls.credential += 1;
      return credentials.get(connectionId) ?? null;
    },
    async executeAction() {
      calls.execute += 1;
    },
    ...overrides,
  });
  return { api, calls, connections, credentials };
}

test('RLS contract isolates connector rows and makes credential references server-only', {
  skip: !existsSync(foundationPath),
}, () => {
  const migration = readFileSync(foundationPath, 'utf8');
  assert.match(
    migration,
    /alter table public[.]connector_installations enable row level security;/i,
  );
  assert.match(
    migration,
    /alter table public[.]credential_refs enable row level security;/i,
  );
  assert.match(
    migration,
    /connector_installations_select_member[\s\S]*?using \(private[.]is_org_member\(organization_id\)\)/i,
  );
  assert.match(
    migration,
    /foreign key \(installation_id, organization_id\)[\s\S]*?references public[.]connector_installations\(id, organization_id\)/i,
  );
  assert.match(
    migration,
    /revoke all on public[.]credential_refs from authenticated;/i,
  );
  assert.doesNotMatch(
    migration,
    /grant\s+(?:select|all)[^;]*public[.]credential_refs\s+to authenticated/i,
  );
  assert.match(
    migration,
    /revoke all on public[.]connector_installations from authenticated;\s*grant select on public[.]connector_installations to authenticated;/i,
  );
});

test('RLS runtime prevents cross-organization connection and credential access', {
  skip: !existsSync(foundationPath),
}, async (t) => {
  const [{ PGlite }, { pgcrypto }] = await Promise.all([
    import('@electric-sql/pglite'),
    import('@electric-sql/pglite/contrib/pgcrypto'),
  ]);
  const db = new PGlite({ extensions: { pgcrypto } });
  t.after(() => db.close());
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema auth;
    create schema extensions;
    create table auth.users(
      id uuid primary key,
      raw_user_meta_data jsonb not null default '{}'::jsonb
    );
    create function auth.uid() returns uuid
      language sql stable
      as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    set search_path=public,extensions;
  `);
  await db.exec(readFileSync(foundationPath, 'utf8'));

  const userA = '20000000-0000-4000-8000-000000000001';
  const userB = '20000000-0000-4000-8000-000000000002';
  const orgA = '10000000-0000-4000-8000-000000000001';
  const orgB = '10000000-0000-4000-8000-000000000002';
  const connectionIdA = '30000000-0000-4000-8000-000000000001';
  const connectionIdB = '30000000-0000-4000-8000-000000000002';
  await db.query('insert into auth.users(id) values($1),($2)', [userA, userB]);
  await db.query(
    `insert into public.organizations(id,name,slug,created_by)
       values($1,'Org A','org-a',$2),($3,'Org B','org-b',$4)`,
    [orgA, userA, orgB, userB],
  );
  await db.query(
    `insert into public.memberships(organization_id,user_id,role,status,joined_at)
       values($1,$2,'owner','active',now()),($3,$4,'owner','active',now())`,
    [orgA, userA, orgB, userB],
  );
  await db.query(
    `insert into public.connector_installations(
       id,organization_id,provider,external_account_id,display_name,status,installed_by
     ) values
       ($1,$2,'example','account-a','Example A','active',$3),
       ($4,$5,'example','account-b','Example B','active',$6)`,
    [connectionIdA, orgA, userA, connectionIdB, orgB, userB],
  );
  await db.query(
    `insert into public.credential_refs(
       organization_id,installation_id,secret_ref,key_version,rotation_state
     ) values
       ($1,$2,'vault-reference-a',1,'current'),
       ($3,$4,'vault-reference-b',1,'current')`,
    [orgA, connectionIdA, orgB, connectionIdB],
  );

  async function actAs(userId) {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [userId]);
    await db.exec('set role authenticated');
  }

  await actAs(userA);
  const listA = await db.query(
    'select id,organization_id from public.connector_installations order by id',
  );
  assert.deepEqual(listA.rows, [{ id: connectionIdA, organization_id: orgA }]);
  assert.equal((await db.query(
    'select count(*)::int as n from public.connector_installations where id=$1',
    [connectionIdB],
  )).rows[0].n, 0);
  await assert.rejects(
    db.query('select * from public.credential_refs where installation_id=$1', [connectionIdB]),
    /permission denied/i,
  );
  await assert.rejects(
    db.query(
      "update public.connector_installations set last_health_check_at=now() where id=$1",
      [connectionIdB],
    ),
    /permission denied/i,
  );
  await assert.rejects(
    db.query(
      "update public.connector_installations set status='revoked' where id=$1",
      [connectionIdB],
    ),
    /permission denied/i,
  );

  await actAs(userB);
  const listB = await db.query(
    'select id,organization_id from public.connector_installations order by id',
  );
  assert.deepEqual(listB.rows, [{ id: connectionIdB, organization_id: orgB }]);
  assert.equal((await db.query(
    'select count(*)::int as n from public.connector_installations where id=$1',
    [connectionIdA],
  )).rows[0].n, 0);
});

test('owner API lists by organization and resolves actions only from that scoped list', {
  skip: !existsSync(ownerApiPath),
}, () => {
  const source = readFileSync(ownerApiPath, 'utf8');
  const listStart = source.indexOf('async function connections(');
  const listEnd = source.indexOf('\nfunction base64UrlBytes', listStart);
  const actionStart = source.indexOf('async function connectionAction(');
  const actionEnd = source.indexOf('\nasync function approvals(', actionStart);
  const githubStart = source.indexOf('async function verifyGithubConnection(');
  const githubEnd = source.indexOf('\nasync function verifySupabaseConnection(', githubStart);
  const supabaseStart = githubEnd;
  const supabaseEnd = source.indexOf('\nasync function verifyVercelConnection(', supabaseStart);
  const vercelStart = supabaseEnd;
  const vercelEnd = source.indexOf('\nasync function verifyMetaConnection(', vercelStart);
  const metaStart = vercelEnd;
  const metaEnd = actionStart;

  const listBlock = source.slice(listStart, listEnd);
  const actionBlock = source.slice(actionStart, actionEnd);
  assert.match(listBlock, /from\("connector_installations"\)/);
  assert.match(listBlock, /[.]eq\("organization_id", context[.]organizationId\)/);
  assert.match(actionBlock, /const item = \(await connections\(context\)\)[.]find/);
  assert.match(actionBlock, /if \(!item\) throw new Error\("CONNECTION_NOT_FOUND"\)/);

  for (const block of [
    source.slice(githubStart, githubEnd),
    source.slice(vercelStart, vercelEnd),
  ]) {
    assert.match(block, /[.]eq\("organization_id", context[.]organizationId\)/);
    assert.match(block, /[.]eq\("id", connectionId\)/);
  }
  for (const block of [
    source.slice(supabaseStart, supabaseEnd),
    source.slice(metaStart, metaEnd),
  ]) {
    assert.match(block, /p_organization_id: context[.]organizationId/);
    assert.match(block, /p_installation_id: connectionId/);
  }
});

test('org A cannot list or read an org B connection', async () => {
  const { api } = harness();
  assert.deepEqual(await api.list(actorA), [{
    id: 'connection-a',
    provider: 'example',
    state: 'healthy',
    accountId: 'account-a',
    tenantId: 'tenant-a',
  }]);
  await assert.rejects(api.read(actorA, connectionB.id), /ORGANIZATION_MISMATCH/);

  const breached = harness({
    async listConnections() {
      return [connectionA, connectionB];
    },
  });
  await assert.rejects(breached.api.list(actorA), /ORGANIZATION_MISMATCH/);
});

test('org A cannot use, refresh, or revoke org B and credential lookup never runs', async () => {
  for (const action of ['use', 'refresh', 'revoke']) {
    const { api, calls } = harness();
    await assert.rejects(api[action](actorA, connectionB.id), /ORGANIZATION_MISMATCH/);
    assert.equal(calls.credential, 0);
    assert.equal(calls.execute, 0);
  }
});

test('credential and account or tenant mismatch fail before provider execution', async () => {
  const cases = [
    [{ ...connectionA, accountId: 'account-b' }, credentialA, /ACCOUNT_MISMATCH/],
    [{ ...connectionA, tenantId: 'tenant-b' }, credentialA, /TENANT_MISMATCH/],
    [connectionA, { ...credentialA, accountId: 'account-b' }, /CREDENTIAL_ACCOUNT_MISMATCH/],
    [connectionA, { ...credentialA, tenantId: 'tenant-b' }, /CREDENTIAL_TENANT_MISMATCH/],
    [connectionA, { ...credentialB, organizationId: 'org-a' }, /CREDENTIAL_TENANT_MISMATCH/],
  ];
  for (const [connection, credential, expected] of cases) {
    let executed = false;
    const api = createTenantScopedConnectionApi({
      async listConnections() { return [connection]; },
      async getConnection() { return connection; },
      async getCredentialReference() { return credential; },
      async executeAction() { executed = true; },
    });
    await assert.rejects(api.refresh(actorA, connection.id), expected);
    assert.equal(executed, false);
  }
});

test('valid tenant-bound actions expose no credential reference or credential material', async () => {
  for (const action of ['use', 'refresh', 'revoke']) {
    const { api, calls } = harness();
    const result = await api[action](actorA, connectionA.id);
    assert.deepEqual(result, { ok: true, action, connectionId: connectionA.id });
    assert.equal(calls.credential, 1);
    assert.equal(calls.execute, 1);
    assert.doesNotMatch(JSON.stringify(result), /credential|secret|token|vault/i);
  }

  assert.throws(
    () => assertTenantActionBinding({
      action: 'refresh',
      actor: actorA,
      connection: connectionA,
      credential: { ...credentialA, accessToken: 'should-never-appear' },
    }),
    /CREDENTIAL_MATERIAL_FORBIDDEN/,
  );
});
