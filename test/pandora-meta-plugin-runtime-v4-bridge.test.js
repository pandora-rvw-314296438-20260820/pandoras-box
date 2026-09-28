import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';

const root = join(import.meta.dirname, '..');
const migrationPath = join(
  root,
  'supabase',
  'migrations',
  '20260928203000_pandora_meta_plugin_runtime_v4_bridge.sql',
);
const apiPath = join(
  root,
  'apps',
  'pandora-mobile',
  'lib',
  'core',
  'data',
  'pandora_intelligence_api.dart',
);
const migration = await readFile(migrationPath, 'utf8');
const api = await readFile(apiPath, 'utf8');

const orgA = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const orgB = '66666666-6666-4666-8666-666666666666';
const owner = '22222222-2222-4222-8222-222222222222';
const member = '33333333-3333-4333-8333-333333333333';

const baseProviders = [
  {
    provider: 'github',
    label: 'GitHub',
    state: 'Connected',
    health: { rawStatus: 'stale', canUseNow: false },
    actions: [{ name: 'repository.read', mode: 'read', available: true }],
    fixtureMarker: { preserve: 'github' },
  },
  {
    provider: 'supabase',
    label: 'Supabase',
    state: 'Connected',
    health: { rawStatus: 'healthy', canUseNow: true },
    actions: [{ name: 'project.read', mode: 'read', available: true }],
    fixtureMarker: { preserve: 'supabase' },
  },
  {
    provider: 'meta',
    label: 'Legacy duplicate',
    state: 'Connected',
    health: { rawStatus: 'unsafe', canUseNow: true },
    actions: [{ name: 'legacy.write', mode: 'write', available: true }],
    secretRef: 'must-not-survive',
  },
];

const healthyMeta = {
  connected: true,
  state: 'Connected',
  canUseNow: true,
  rawStatus: 'connected',
  account: { id: '123456', label: 'Fixture Meta', verified: true },
  scopes: ['pages_show_list', 'pages_read_engagement', 'ads_read'],
  scopesVerified: true,
  lastVerifiedAt: '2026-09-28T10:00:00Z',
  pages: [{ id: 'page-private-to-readback' }],
  adAccounts: [{ id: 'account-private-to-readback' }],
  secretRef: 'vault://must-not-render',
  userToken: 'must-not-render',
};

async function fixture() {
  const { PGlite } = await import('@electric-sql/pglite');
  const db = new PGlite();
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create schema private;
    create schema vault;
    create schema extensions;

    create table public.organizations(
      id uuid primary key,
      status text not null
    );
    create table public.memberships(
      organization_id uuid not null,
      user_id uuid not null,
      status text not null,
      role text not null
    );
    create table private.fixture_plugin_registry(
      organization_id uuid primary key,
      payload jsonb not null
    );
    create table private.fixture_meta_projection(
      organization_id uuid primary key,
      payload jsonb,
      failure_code text
    );

    create or replace function auth.uid() returns uuid
    language sql stable
    as $fn$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $fn$;

    create or replace function public.pandora_plugin_runtime_registry_v3(
      p_organization_id uuid
    ) returns jsonb
    language plpgsql security definer
    set search_path=pg_catalog,public,private,auth,pg_temp
    as $fn$
    declare
      v_uid uuid := auth.uid();
      v_payload jsonb;
    begin
      if v_uid is null or not exists (
        select 1
        from public.memberships m
        join public.organizations o on o.id=m.organization_id
        where m.organization_id=p_organization_id
          and m.user_id=v_uid
          and m.status='active'
          and m.role in ('owner','admin')
          and o.status='active'
      ) then
        raise exception 'pandora_chat_owner_required' using errcode='42501';
      end if;
      select payload into v_payload
      from private.fixture_plugin_registry
      where organization_id=p_organization_id;
      return coalesce(
        v_payload,
        jsonb_build_object(
          'contractVersion','fixture-v3',
          'organizationId',p_organization_id,
          'providers','[]'::jsonb
        )
      );
    end;
    $fn$;

    create or replace function public.pandora_meta_connection_v1(
      p_organization_id uuid
    ) returns jsonb
    language plpgsql security definer
    set search_path=pg_catalog,public,private,auth,pg_temp
    as $fn$
    declare
      v_uid uuid := auth.uid();
      v_payload jsonb;
      v_failure text;
    begin
      if v_uid is null or not exists (
        select 1
        from public.memberships m
        join public.organizations o on o.id=m.organization_id
        where m.organization_id=p_organization_id
          and m.user_id=v_uid
          and m.status='active'
          and m.role in ('owner','admin')
          and o.status='active'
      ) then
        raise exception 'pandora_meta_connection_owner_required'
          using errcode='42501';
      end if;
      select payload,failure_code into v_payload,v_failure
      from private.fixture_meta_projection
      where organization_id=p_organization_id;
      if v_failure='42501' then
        raise exception 'fixture_meta_authorization_denied' using errcode='42501';
      elsif v_failure='XX000' then
        raise exception 'fixture_meta_projection_failed' using errcode='XX000';
      end if;
      return coalesce(
        v_payload,
        jsonb_build_object(
          'ok',true,
          'provider','meta',
          'connected',false,
          'state','Needs authorization',
          'canUseNow',false
        )
      );
    end;
    $fn$;
  `);

  await db.query(
    'insert into public.organizations(id,status) values ($1,$3),($2,$3)',
    [orgA, orgB, 'active'],
  );
  await db.query(
    `insert into public.memberships(organization_id,user_id,status,role)
     values ($1,$2,'active','owner'),($1,$3,'active','member')`,
    [orgA, owner, member],
  );
  const base = {
    contractVersion: 'fixture-plugin-runtime-v3',
    organizationId: orgA,
    observedAt: '2026-09-28T09:00:00Z',
    projectRequired: false,
    providers: baseProviders,
    extraEnvelope: { preserve: true },
  };
  await db.query(
    'insert into private.fixture_plugin_registry(organization_id,payload) values ($1,$2::jsonb)',
    [orgA, JSON.stringify(base)],
  );
  await db.query(
    'insert into private.fixture_plugin_registry(organization_id,payload) values ($1,$2::jsonb)',
    [orgB, JSON.stringify({ ...base, organizationId: orgB })],
  );
  await db.query(
    'insert into private.fixture_meta_projection(organization_id,payload) values ($1,$2::jsonb)',
    [orgA, JSON.stringify(healthyMeta)],
  );
  await db.query(
    'insert into private.fixture_meta_projection(organization_id,payload) values ($1,$2::jsonb)',
    [orgB, JSON.stringify({
      ...healthyMeta,
      account: { id: 'foreign', label: 'Foreign Meta', verified: true },
    })],
  );
  await db.exec(migration);

  const setUser = async (userId) => {
    await db.query(
      "select set_config('request.jwt.claim.sub',$1,false)",
      [userId ?? ''],
    );
  };
  const read = async (organizationId = orgA) => (
    await db.query(
      'select public.pandora_plugin_runtime_registry_v4($1::uuid) as registry',
      [organizationId],
    )
  ).rows[0].registry;
  const setMeta = async (payload, failureCode = null) => {
    await db.query(
      `update private.fixture_meta_projection
       set payload=$2::jsonb,failure_code=$3
       where organization_id=$1`,
      [orgA, payload == null ? null : JSON.stringify(payload), failureCode],
    );
  };
  return { db, setUser, read, setMeta };
}

test('v4 bridge preserves legacy provider semantics and adds one closed Meta projection', async () => {
  const f = await fixture();
  try {
    await f.setUser(owner);
    const registry = await f.read();
    assert.equal(registry.contractVersion, 'pandora-plugin-runtime-registry-v4');
    assert.deepEqual(
      registry.providers.map((provider) => provider.provider),
      ['github', 'supabase', 'meta'],
    );
    assert.equal(registry.providers.filter((p) => p.provider === 'meta').length, 1);

    const github = registry.providers[0];
    assert.deepEqual(github.fixtureMarker, { preserve: 'github' });
    assert.equal(github.connected, false);
    assert.equal(github.canUseNow, false);
    assert.equal(github.actions[0].available, false);

    const supabase = registry.providers[1];
    assert.deepEqual(supabase.fixtureMarker, { preserve: 'supabase' });
    assert.equal(supabase.connected, true);
    assert.equal(supabase.canUseNow, true);
    assert.equal(supabase.actions[0].available, true);

    const meta = registry.providers[2];
    assert.equal(meta.label, 'Meta');
    assert.equal(meta.state, 'Connected');
    assert.equal(meta.connected, true);
    assert.equal(meta.canUseNow, true);
    assert.equal(meta.readAvailable, true);
    assert.equal(meta.writeAvailable, false);
    assert.deepEqual(meta.account, healthyMeta.account);
    assert.deepEqual(meta.scopes, healthyMeta.scopes);
    assert.equal(meta.scopesVerified, true);
    assert.deepEqual(
      meta.actions.map(({ name, available }) => ({ name, available })),
      [
        { name: 'pages.read', available: true },
        { name: 'ads.read', available: true },
        { name: 'ads.manage', available: false },
      ],
    );
    assert.equal(meta.actions[2].approval, 'owner');
    assert.equal(meta.actions[2].reason, 'external_write_not_exposed');
    const serialized = JSON.stringify(meta);
    for (const forbidden of [
      'must-not-render',
      'page-private-to-readback',
      'account-private-to-readback',
      'secretRef',
      'userToken',
    ]) {
      assert.doesNotMatch(serialized, new RegExp(forbidden));
    }
  } finally {
    await f.db.close();
  }
});

test('v4 bridge retains legacy rows with missing and null provider keys in order', async () => {
  const f = await fixture();
  try {
    const missingProvider = {
      label: 'Legacy missing provider',
      state: 'Needs authorization',
      fixtureMarker: { preserve: 'missing' },
      actions: [{ name: 'legacy.read', available: false }],
    };
    const nullProvider = {
      ...missingProvider,
      provider: null,
      label: 'Legacy null provider',
      fixtureMarker: { preserve: 'null' },
    };
    const providers = [
      baseProviders[0], missingProvider, baseProviders[2],
      nullProvider, baseProviders[1], baseProviders[2],
    ];
    await f.db.query(
      `update private.fixture_plugin_registry
       set payload=jsonb_set(payload,'{providers}',$2::jsonb)
       where organization_id=$1`,
      [orgA, JSON.stringify(providers)],
    );
    await f.setUser(owner);
    const rows = (await f.read()).providers;
    assert.deepEqual(
      rows.map((row) => row.provider),
      ['github', undefined, null, 'supabase', 'meta'],
    );
    assert.equal(Object.hasOwn(rows[1], 'provider'), false);
    assert.equal(rows[2].provider, null);
    for (const [row, original] of [
      [rows[1], missingProvider], [rows[2], nullProvider],
    ]) {
      assert.equal(row.label, original.label);
      assert.equal(row.state, original.state);
      assert.deepEqual(row.fixtureMarker, original.fixtureMarker);
      assert.deepEqual(row.actions, original.actions);
      assert.equal(row.connected, false);
      assert.equal(row.canUseNow, false);
    }
    assert.equal(rows.filter((row) => row.provider === 'meta').length, 1);
    assert.equal(rows.at(-1).label, 'Meta');
    assert.doesNotMatch(JSON.stringify(rows), /must-not-survive/);
  } finally {
    await f.db.close();
  }
});

test('absent and unready Meta states remain visible with no available action', async () => {
  const f = await fixture();
  try {
    await f.setUser(owner);
    const cases = [
      { connected: false, state: 'Needs authorization', canUseNow: false },
      { connected: true, state: 'Reconnect required', canUseNow: false },
      { connected: true, state: 'Permissions incomplete', canUseNow: false },
      { connected: true, state: 'Verification required', canUseNow: false },
    ];
    for (const projection of cases) {
      await f.setMeta(projection);
      const registry = await f.read();
      const meta = registry.providers.find((row) => row.provider === 'meta');
      assert.ok(meta, projection.state);
      assert.equal(meta.state, projection.state);
      assert.equal(meta.connected, false);
      assert.equal(meta.canUseNow, false);
      assert.equal(meta.readAvailable, false);
      assert.equal(meta.writeAvailable, false);
      assert.ok(meta.actions.every((action) => action.available === false));
    }

    await f.db.query(
      'delete from private.fixture_meta_projection where organization_id=$1',
      [orgA],
    );
    const absent = (await f.read()).providers.find(
      (row) => row.provider === 'meta',
    );
    assert.equal(absent.state, 'Needs authorization');
    assert.equal(absent.connected, false);
    assert.ok(absent.actions.every((action) => action.available === false));
  } finally {
    await f.db.close();
  }
});

test('projection failures are closed while authorization failures still reject', async () => {
  const f = await fixture();
  try {
    await f.setUser(owner);
    await f.setMeta(null, 'XX000');
    const meta = (await f.read()).providers.find(
      (row) => row.provider === 'meta',
    );
    assert.equal(meta.state, 'Problem');
    assert.equal(meta.connected, false);
    assert.equal(meta.failure.code, 'META_PROJECTION_UNAVAILABLE');
    assert.ok(meta.actions.every((action) => action.available === false));
    assert.doesNotMatch(JSON.stringify(meta), /fixture_meta_projection_failed/);

    await f.setMeta(null, '42501');
    await assert.rejects(
      f.read(),
      (error) => error.code === '42501'
        && /fixture_meta_authorization_denied/.test(error.message),
    );
  } finally {
    await f.db.close();
  }
});
test('unauthenticated, ordinary-member, and cross-organization reads fail closed', async () => {
  const f = await fixture();
  try {
    await f.setUser(null);
    await assert.rejects(f.read(), (error) => error.code === '42501');

    await f.setUser(member);
    await assert.rejects(f.read(), (error) => error.code === '42501');

    await f.setUser(owner);
    await assert.rejects(
      f.read(orgB),
      (error) => error.code === '42501'
        && /pandora_chat_owner_required/.test(error.message),
    );

    const privileges = await f.db.query(`
      select
        has_function_privilege(
          'anon',
          'public.pandora_plugin_runtime_registry_v4(uuid)',
          'EXECUTE'
        ) as anon_execute,
        has_function_privilege(
          'authenticated',
          'public.pandora_plugin_runtime_registry_v4(uuid)',
          'EXECUTE'
        ) as authenticated_execute
    `);
    assert.equal(privileges.rows[0].anon_execute, false);
    assert.equal(privileges.rows[0].authenticated_execute, true);
  } finally {
    await f.db.close();
  }
});

test('bridge changes only the closed projection and mobile keeps the v4 parser contract', () => {
  assert.match(migration, /pandora_plugin_runtime_registry_v3\(p_organization_id\)/);
  assert.match(migration, /pandora_meta_connection_v1\(p_organization_id\)/);
  assert.match(migration, /when sqlstate '42501' then\s+raise/);
  assert.match(migration, /filter \(where item->>'provider' is distinct from 'meta'\)/);
  assert.match(migration, /'name', 'ads\.manage'[\s\S]*'available', false/);
  assert.doesNotMatch(
    migration,
    /pandora_meta_oauth_(?:prepare|material|commit)_v1|vault\.decrypted_secrets|secret_ref/,
  );
  assert.match(api, /'pandora_plugin_runtime_registry_v4'/);
  assert.match(api, /bool get installed => state == 'Connected' && canUseNow/);
  assert.match(api, /health\['canUseNow'\] == true \|\| json\['canUseNow'\] == true/);
  assert.match(api, /account\['verified'\] == true/);
  assert.match(api, /json\['scopesVerified'\] == true/);
});
