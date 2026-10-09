const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { PGlite } = require('@electric-sql/pglite');

// This recovers existing provider SQL. It does not propose new PLP behavior.
const migrationBytes = readFileSync(join(__dirname,
  '../supabase/migrations/20261003201314_plp_production_activity_isolation_v1.sql'));
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const plpOrg = uuid(1);
const otherOrg = uuid(2);
const property = uuid(3);
const oldProperty = uuid(4);
const owner = uuid(11);
const admin = uuid(12);
const member = uuid(13);
const inactive = uuid(14);
const otherOwner = uuid(15);
const missingMember = uuid(16);
const job = uuid(21);
const otherJob = uuid(22);

async function createDb(t) {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema auth;
    create schema private;
    create schema plp_runtime;
    grant usage on schema public, auth to anon, authenticated, service_role;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create table public.organizations (id uuid primary key, slug text);
    create table public.pandora_enterprise_accounts (organization_id uuid);
    create table public.enterprise_properties (
      id uuid primary key, organization_id uuid, slug text, updated_at timestamptz
    );
    create table public.memberships (
      organization_id uuid, user_id uuid, role text, status text
    );
    create table public.profiles (id uuid primary key, display_name text);
    create table public.enterprise_business_activity (
      id uuid primary key, organization_id uuid, property_id uuid, category text,
      title text, summary text, source_label text, occurred_at timestamptz
    );
    create table plp_runtime.plp_staff_tasks (
      id uuid primary key, category text, kind text, title text, note text,
      source text, actor text, completed_at timestamptz, updated_at timestamptz,
      created_at timestamptz
    );
    create table plp_runtime.plp_guests (id uuid primary key, full_name text, metadata jsonb);
    create table plp_runtime.plp_bookings (
      id uuid primary key, guest_id uuid, status text, accommodation_name text,
      booking_reference text, source text, confirmed_at timestamptz,
      cancelled_at timestamptz, updated_at timestamptz, created_at timestamptz
    );
    create table public.pandora_activity_jobs (
      id uuid primary key, organization_id uuid, requested_by uuid, request_id text
    );
    create table public.pandora_activity_events (
      event_id text primary key, job_id uuid, organization_id uuid,
      sequence bigint, state text, message text, event jsonb, occurred_at timestamptz
    );

    -- The existing private authority helper is outside this recovery patch.
    -- This fail-closed seam proves invocation, organization binding and error
    -- propagation; it does not claim to test that helper's live authorization.
    create function private.pandora_core_legacy_client_scope_v1(p_org uuid)
    returns void language plpgsql as $$ begin
      if p_org is distinct from '${plpOrg}'::uuid then
        raise exception 'fixture legacy scope organization mismatch' using errcode='42501';
      end if;
      if current_setting('test.legacy_scope_denied', true) = 'on' then
        raise exception 'fixture legacy scope denied' using errcode='42501';
      end if;
    end $$;

    insert into public.organizations values ('${plpOrg}','plp-boracay'),('${otherOrg}','another-tenant');
    insert into public.pandora_enterprise_accounts values ('${plpOrg}'),('${otherOrg}');
    insert into public.enterprise_properties values
      ('${oldProperty}','${plpOrg}','plp-boracay','2026-01-01'),
      ('${property}','${plpOrg}','plp-boracay','2026-10-01');
    insert into public.memberships values
      ('${plpOrg}','${owner}','owner','active'),
      ('${plpOrg}','${admin}','admin','active'),
      ('${plpOrg}','${member}','member','active'),
      ('${plpOrg}','${inactive}','owner','inactive'),
      ('${otherOrg}','${otherOwner}','owner','active');
    insert into public.profiles values ('${owner}','Harbor Manager'),('${otherOwner}','Foreign Owner');
    insert into public.pandora_activity_jobs values
      ('${job}','${plpOrg}','${owner}','request-harbor'),
      ('${otherJob}','${otherOrg}','${otherOwner}','foreign-request');
  `);
  try {
    await db.exec(migrationBytes.toString('utf8'));
  } catch (error) {
    // PGlite includes SQL text on its error object. Report only the failure,
    // never attach the captured provider statement to test output.
    const failure = new Error(error.message);
    failure.code = error.code;
    throw failure;
  }
  return db;
}

async function actAs(db, user = owner, role = 'authenticated') {
  assert.ok(['authenticated', 'anon', 'service_role'].includes(role));
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
  await db.query("select set_config('test.legacy_scope_denied','off',false)");
  await db.exec(`set role ${role}`);
}

async function clearActivity(db) {
  await db.exec('reset role');
  await db.exec(`truncate public.enterprise_business_activity,
    plp_runtime.plp_staff_tasks, plp_runtime.plp_bookings,
    plp_runtime.plp_guests, public.pandora_activity_events`);
}

async function logs(db, args = {}) {
  const { rows } = await db.query(`select public.plp_pandora_activity_logs_v2(
    $1::timestamptz,$2::uuid,$3::bigint,$4::integer,$5::text) as result`,
  [args.beforeAt ?? null, args.beforeJobId ?? null, args.beforeSequence ?? null,
    args.limit ?? null, args.query ?? null]);
  return rows[0].result;
}

async function business(db, limit = null) {
  const { rows } = await db.query('select public.plp_recent_business_activity_v1($1::integer) as result', [limit]);
  return rows[0].result;
}

async function insertEvent(db, id, overrides = {}) {
  await db.query(`insert into public.pandora_activity_events
    (event_id,job_id,organization_id,sequence,state,message,event,occurred_at)
    values ($1,$2,$3,$4,$5,$6,$7,$8)`, [id, overrides.jobId ?? job,
    overrides.org ?? plpOrg, overrides.sequence ?? 1, overrides.state ?? 'result',
    overrides.message ?? 'Task completed', JSON.stringify(overrides.event ?? {}),
    overrides.at ?? '2026-10-03T12:00:00Z']);
}

async function insertBusiness(db, n, overrides = {}) {
  await db.query(`insert into public.enterprise_business_activity
    (id,organization_id,property_id,category,title,summary,source_label,occurred_at)
    values ($1,$2,$3,$4,$5,$6,$7,$8)`, [uuid(n), overrides.org ?? plpOrg,
    overrides.property ?? property, overrides.category ?? 'operations',
    overrides.title ?? `Business ${n}`, 'Production activity fixture',
    overrides.source ?? 'Front desk', overrides.at ?? '2026-10-03T11:00:00Z']);
}

function denied(code, message) {
  return (error) => error.code === code && message.test(error.message);
}

test('PLP activity recovery preserves the exact captured provider statement bytes', () => {
  assert.equal(migrationBytes.byteLength, 10939);
  assert.equal(createHash('sha256').update(migrationBytes).digest('hex'),
    '49ab29aabded20e0f1eeddcfdafc3d3f1f9e9f166abd3682bf369478b035db17');
});

test('recovered PLP activity functions execute with isolated database fixtures', async (t) => {
  const db = await createDb(t);

  await t.test('execution grants and definer configuration keep raw tables private', async () => {
    const { rows } = await db.query(`select p.proname, p.prosecdef, p.proconfig, md5(p.prosrc) as body_md5,
      has_function_privilege('anon',p.oid,'execute') as anon_execute,
      has_function_privilege('authenticated',p.oid,'execute') as authenticated_execute,
      has_function_privilege('service_role',p.oid,'execute') as service_execute
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in
        ('plp_recent_business_activity_v1','plp_pandora_activity_logs_v2')`);
    assert.equal(rows.length, 2);
    const receipt = JSON.parse(readFileSync(join(__dirname,
      '../docs/supabase/recovery/jcyqixttuebxqqfkjonq/20261003-source-parity-recovery.json'), 'utf8'));
    const functions = receipt.entries.find((entry) => entry.version === '20261003201314').functionReceipts;
    for (const row of rows) {
      assert.equal(row.body_md5, functions.find((entry) => entry.function_name === row.proname).body_md5);
      assert.equal(row.prosecdef, true);
      assert.deepEqual(row.proconfig, ['search_path=""']);
      assert.equal(row.anon_execute, false);
      assert.equal(row.authenticated_execute, true);
      assert.equal(row.service_execute, true);
    }
    await actAs(db, owner, 'anon');
    await assert.rejects(logs(db), denied('42501', /permission denied for function/));
    await assert.rejects(business(db), denied('42501', /permission denied for function/));
    await actAs(db);
    await assert.rejects(db.query('select * from public.pandora_activity_events'),
      denied('42501', /permission denied for table/));
  });

  await t.test('both RPCs retain authentication, membership and legacy-scope gates', async () => {
    for (const role of ['authenticated', 'service_role']) {
      await actAs(db, null, role);
      await assert.rejects(logs(db), denied('42501', /authentication required/));
      await assert.rejects(business(db), denied('42501', /authentication required/));
    }
    for (const user of [inactive, otherOwner, missingMember]) {
      await actAs(db, user);
      await assert.rejects(logs(db), denied('42501', /active PLP membership required/));
      await assert.rejects(business(db), denied('42501', /active PLP membership required/));
    }
    await actAs(db);
    await db.query("select set_config('test.legacy_scope_denied','on',false)");
    await assert.rejects(logs(db), denied('42501', /fixture legacy scope denied/));
    await assert.rejects(business(db), denied('42501', /fixture legacy scope denied/));
    await actAs(db);
    await db.exec('reset role');
    await db.exec(`update public.organizations set slug='wrong-scope' where id='${plpOrg}'`);
    await actAs(db);
    await assert.rejects(logs(db), denied('42501', /fixture legacy scope organization mismatch/));
    await assert.rejects(business(db), denied('42501', /fixture legacy scope organization mismatch/));
    await db.exec('reset role');
    await db.exec(`update public.organizations set slug='plp-boracay' where id='${plpOrg}'`);
  });

  await t.test('business activity admits active members while logs require owner or admin', async () => {
    await clearActivity(db);
    await insertEvent(db, 'visible-event');
    await insertBusiness(db, 101);
    await actAs(db, member);
    assert.equal((await business(db)).items.length, 1);
    await assert.rejects(logs(db), denied('42501', /owner or admin access required/));
    for (const user of [owner, admin]) {
      await actAs(db, user);
      assert.deepEqual((await logs(db)).items.map((x) => x.id), ['visible-event']);
    }
  });

  await t.test('tenant filtering also prevents a foreign job from contributing request or actor data', async () => {
    await clearActivity(db);
    await insertEvent(db, 'own-event');
    await insertEvent(db, 'foreign-event', { org: otherOrg, jobId: otherJob });
    await insertEvent(db, 'mismatched-job', { jobId: otherJob, sequence: 2 });
    await actAs(db);
    const result = await logs(db);
    assert.equal(result.schemaVersion, 'plp.pandora-activity-logs.v2');
    assert.equal(result.testDataExcluded, true);
    assert.deepEqual(result.items.map((x) => x.id).sort(), ['mismatched-job', 'own-event']);
    const own = result.items.find((x) => x.id === 'own-event');
    assert.equal(own.actorLabel, 'Harbor Manager');
    assert.equal(own.requestId, 'request-harbor');
    const mismatch = result.items.find((x) => x.id === 'mismatched-job');
    assert.equal(mismatch.actorLabel, 'Pandora');
    assert.equal(mismatch.requestId, null);
    assert.deepEqual((await logs(db, { query: 'foreign-request' })).items, []);
    assert.deepEqual((await logs(db, { query: 'Foreign Owner' })).items, []);
  });

  await t.test('logs exclude each supported test-data marker without suppressing ordinary events', async () => {
    await clearActivity(db);
    await insertEvent(db, 'ordinary', { event: { isTest: false, synthetic: 'false', mock: 'no' } });
    let number = 0;
    for (const key of ['isTest', 'synthetic', 'mock']) {
      for (const value of [true, 'TRUE', 1, 'yes']) {
        await insertEvent(db, `flag-${++number}`, { event: { [key]: value } });
      }
    }
    for (const sourceType of ['Mock Runtime', 'synthetic-device', 'QA_runner']) {
      await insertEvent(db, `source-${++number}`, { event: { provenance: { sourceType } } });
    }
    for (const message of ['Completed [MOCK QA] run', 'Synthetic result']) {
      await insertEvent(db, `message-${++number}`, { message });
    }
    await actAs(db);
    const result = await logs(db);
    assert.deepEqual(result.items.map((x) => x.id), ['ordinary']);
    assert.equal(result.items[0].domain, 'pandora');
    assert.equal(result.items[0].capability, 'activity');
    assert.equal(result.items[0].sourceType, 'runtime');
  });

  await t.test('search matches every exposed supported field and trims query whitespace', async () => {
    await clearActivity(db);
    await insertEvent(db, 'searchable', {
      message: 'Welcome arrival', state: 'verified',
      event: { domain: 'hospitality', capability: 'reservation', provenance: { sourceType: 'webhook' } },
    });
    await actAs(db);
    for (const query of [' WELCOME ', 'VERIFIED', 'hospitality', 'reservation', 'webhook',
      'Harbor Manager', 'request-harbor', job, '   ']) {
      assert.deepEqual((await logs(db, { query })).items.map((x) => x.id), ['searchable'], query);
    }
    assert.deepEqual((await logs(db, { query: 'absent term' })).items, []);
  });

  await t.test('complete tuple cursors page tied timestamps without duplicates or omissions', async () => {
    await clearActivity(db);
    const laterJob = uuid(23);
    for (const [id, jobId, sequence, at] of [
      ['first', laterJob, 2, '2026-10-03T12:00:00Z'],
      ['second', laterJob, 1, '2026-10-03T12:00:00Z'],
      ['third', job, 9, '2026-10-03T12:00:00Z'],
      ['fourth', job, 10, '2026-10-03T11:00:00Z'],
    ]) await insertEvent(db, id, { jobId, sequence, at });
    await actAs(db);
    await assert.rejects(logs(db, { beforeAt: '2026-10-03T12:00:00Z' }),
      denied('22023', /complete activity cursor required/));
    const first = await logs(db, { limit: 2 });
    assert.deepEqual(first.items.map((x) => x.id), ['first', 'second']);
    assert.equal(first.hasMore, true);
    const second = await logs(db, { limit: 2, beforeAt: first.nextBeforeAt,
      beforeJobId: first.nextBeforeJobId, beforeSequence: first.nextBeforeSequence });
    assert.deepEqual(second.items.map((x) => x.id), ['third', 'fourth']);
    assert.equal(second.hasMore, false);
    assert.equal(second.nextBeforeAt, null);
    assert.equal(second.nextBeforeJobId, null);
    assert.equal(second.nextBeforeSequence, null);
  });

  await t.test('business feed selects the latest property and excludes foreign property and tenant rows', async () => {
    await clearActivity(db);
    await insertBusiness(db, 101, { category: 'booking' });
    await insertBusiness(db, 102, { category: 'operations' });
    await insertBusiness(db, 103, { category: 'general' });
    await insertBusiness(db, 104, { property: oldProperty });
    await insertBusiness(db, 105, { org: otherOrg });
    await insertBusiness(db, 106, { source: 'Mock fixture' });
    await insertBusiness(db, 107, { source: 'QA runner' });
    await actAs(db, member);
    const result = await business(db);
    assert.equal(result.schemaVersion, 'plp.business-activity.v1');
    assert.equal(result.containsMockData, false);
    assert.equal(result.testDataExcluded, true);
    assert.deepEqual(result.items.map((x) => x.id), [103, 102, 101].map((n) => `business:${uuid(n)}`));
    assert.deepEqual(result.items.map((x) => x.audience), ['all', 'team', 'guests']);
    assert.ok(result.items.every((x) => x.isMock === false));
  });

  await t.test('business feed merges production staff tasks and bookings, excluding supported fixture markers', async () => {
    await clearActivity(db);
    await db.query(`insert into plp_runtime.plp_staff_tasks
      (id,category,kind,title,note,source,actor,created_at) values
      ($1,'','housekeeping','Room ready','','','staff','2026-10-03T12:00:00Z')`, [uuid(201)]);
    for (const [n, note, source, actor] of [
      [202, 'Task updated', 'qa_runner', 'staff'],
      [203, 'Task updated', 'runtime', 'qa-user'],
      [204, '[mock qa] updated', 'runtime', 'staff'],
      [205, 'Synthetic fixture', 'runtime', 'staff'],
    ]) await db.query(`insert into plp_runtime.plp_staff_tasks
      (id,note,source,actor,created_at) values ($1,$2,$3,$4,'2026-10-03T12:00:00Z')`,
    [uuid(n), note, source, actor]);
    for (const [n, metadata, source, reference] of [
      [301, {}, 'Front desk', 'BK-301'],
      [302, { mock: true }, 'Front desk', 'BK-302'],
      [303, { mock: 'yes' }, 'Front desk', 'BK-303'],
      [304, {}, 'qa_runner', 'BK-304'],
      [305, {}, 'Front desk', 'MOCK-305'],
    ]) {
      await db.query('insert into plp_runtime.plp_guests values ($1,$2,$3)',
        [uuid(n + 100), 'Guest Example', JSON.stringify(metadata)]);
      await db.query(`insert into plp_runtime.plp_bookings
        (id,guest_id,status,accommodation_name,booking_reference,source,created_at)
        values ($1,$2,'CONFIRMED','Garden Room',$3,$4,'2026-10-03T11:00:00Z')`,
      [uuid(n), uuid(n + 100), reference, source]);
    }
    await actAs(db);
    const result = await business(db);
    assert.deepEqual(result.items.map((x) => x.id), [`task:${uuid(201)}`, `booking:${uuid(301)}`]);
    assert.equal(result.items[0].category, 'housekeeping');
    assert.equal(result.items[0].sourceLabel, 'PLP runtime');
    assert.equal(result.items[0].summary, 'PLP staff task updated.');
    assert.equal(result.items[1].title, 'Booking confirmed');
    assert.equal(result.items[1].summary, 'Guest Example · Garden Room · BK-301');
  });

  await t.test('both RPCs enforce default, minimum and maximum page limits', async () => {
    await clearActivity(db);
    for (let n = 1; n <= 105; n += 1) {
      await insertEvent(db, `limit-${n}`, { sequence: n });
      await insertBusiness(db, 1000 + n);
    }
    await actAs(db);
    for (const [limit, expected] of [[null, 60], [0, 1], [-10, 1], [1000, 100]]) {
      assert.equal((await business(db, limit)).items.length, expected);
      const result = await logs(db, { limit });
      assert.equal(result.items.length, expected);
      assert.equal(result.hasMore, true);
    }
  });

  await t.test('missing property fails instead of returning an unscoped activity feed', async () => {
    await db.exec('reset role');
    await db.exec('delete from public.enterprise_properties');
    await actAs(db);
    await assert.rejects(business(db), denied('55000', /property is not configured/));
    await assert.rejects(logs(db), denied('55000', /property is not configured/));
  });
});
