"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migrationRoot = path.resolve(__dirname, "../supabase/migrations");
const readMigration = (name) => fs.readFileSync(path.join(migrationRoot, name), "utf8");
const canonicalMigrations = [
  "20260921092755_pandora_first_party_tracking_v1.sql",
  "20260925072000_pandora_tracking_dashboard_recovery_v1.sql",
  "20260927041500_facebook_first_party_event_contract_v1.sql",
].map(readMigration);
const migration = readMigration("20260929014500_pandora_tracking_minimization_v1.sql");

const ORG = "11111111-1111-4111-8111-111111111111";
const PROJECT = "22222222-2222-4222-8222-222222222222";
const TENANT = "33333333-3333-4333-8333-333333333333";
const CAMPAIGN = "44444444-4444-4444-8444-444444444444";

async function database() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create schema extensions;
    create extension pgcrypto with schema extensions;
    create schema auth;
    create schema private;
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create function auth.jwt() returns jsonb language sql stable
      as 'select ''{"role":"service_role"}''::jsonb';
    create table public.organizations(id uuid primary key);
    create table private.project_canonical_registry(
      project_id uuid primary key,
      organization_id uuid not null references public.organizations(id)
    );
  `);
  for (const sql of canonicalMigrations) await db.exec(sql);
  await db.query("insert into public.organizations(id) values($1)", [ORG]);
  await db.query(
    "insert into private.project_canonical_registry(project_id,organization_id) values($1,$2)",
    [PROJECT, ORG],
  );
  await db.query(
    `insert into public.pandora_tracking_tenants(
       id,workspace_key,display_name,organization_id,project_id
     ) values($1,'fixture','Fixture',$2,$3)`,
    [TENANT, ORG, PROJECT],
  );
  await db.query(
    `insert into public.pandora_tracking_campaigns(
       id,tenant_id,slug,name,destination_url,source,medium,campaign,provider
     ) values($1,$2,'fixture-campaign','Fixture','https://example.test/offer',
       'source','medium','campaign','meta')`,
    [CAMPAIGN, TENANT],
  );
  return db;
}
async function seedHistoricalRows(db) {
  await db.query(`
    insert into public.pandora_tracking_clicks(
      tenant_id,campaign_id,click_id,occurred_at,landing_url,referrer,user_agent,
      ip_hash,visitor_hash,platform_click_ids,query_params,metadata
    ) values($1,$2,'pdc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','2026-09-29T00:00:00Z',
      'https://example.test/?legacy=1','https://referrer.test/private','legacy-agent',
      $3,$4,'{"fbclid":"legacy"}','{"utm_source":"legacy"}','{"caller":"legacy"}')`,
    [TENANT, CAMPAIGN, "a".repeat(64), "b".repeat(64)],
  );
  await db.query(`
    insert into public.pandora_tracking_events(
      tenant_id,campaign_id,click_id,event_type,event_name,source,external_event_id,
      value,currency,occurred_at,schema_version,consent,is_test,metadata
    ) values($1,$2,'pdc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','sale','purchase','server',
      'legacy-event',10,'USD','2026-09-29T00:00:00Z',1,
      '{"analytics":true,"marketing":false}',false,'{"caller":"legacy"}')`,
    [TENANT, CAMPAIGN],
  );
  await db.query(`
    insert into public.pandora_tracking_costs(
      tenant_id,campaign_id,provider,external_record_id,bucket_date,spend,
      impressions,provider_clicks,currency,metadata
    ) values($1,$2,'meta','legacy-cost','2026-09-29',2,10,1,'USD',
      '{"caller":"legacy"}')`,
    [TENANT, CAMPAIGN],
  );
}
test("canonical tracking schema enforces minimized writes and preserves reporting", async () => {
  const db = await database();
  try {
    await seedHistoricalRows(db);
    await db.exec(migration);

    const states = await db.query(`
      select conname,convalidated from pg_constraint
      where conname like 'pandora_tracking_%_v1_check'
      order by conname
    `);
    assert.equal(states.rows.length, 3);
    assert.ok(states.rows.every((row) => row.convalidated === false));

    const old = await db.query(`
      select c.query_params,e.metadata as event_metadata,k.metadata as cost_metadata
      from public.pandora_tracking_clicks c
      join public.pandora_tracking_events e using(tenant_id,campaign_id)
      join public.pandora_tracking_costs k using(tenant_id,campaign_id)
      where c.click_id='pdc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    `);
    assert.deepEqual(old.rows[0], {
      query_params: { utm_source: "legacy" },
      event_metadata: { caller: "legacy" },
      cost_metadata: { caller: "legacy" },
    });

    await db.query(`
      insert into public.pandora_tracking_clicks(
        tenant_id,campaign_id,click_id,occurred_at,landing_url,referrer,user_agent,
        ip_hash,visitor_hash,platform_click_ids,query_params,metadata
      ) values($1,$2,'pdc_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','2026-09-29T01:00:00Z',
        'https://example.test/offer',null,null,null,null,'{}','{}','{"collector":"vercel"}')`,
      [TENANT, CAMPAIGN],
    );
    await db.query(`
      insert into public.pandora_tracking_events(
        tenant_id,campaign_id,click_id,event_type,event_name,source,external_event_id,
        value,currency,occurred_at,schema_version,consent,is_test,metadata
      ) values($1,$2,'pdc_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','sale','purchase','server',
        'registered-event',20,'USD','2026-09-29T01:00:00Z',1,
        '{"analytics":true,"marketing":false}',true,'{}')`,
      [TENANT, CAMPAIGN],
    );
    await db.query(`
      insert into public.pandora_tracking_costs(
        tenant_id,campaign_id,provider,external_record_id,bucket_date,spend,
        impressions,provider_clicks,currency,metadata
      ) values($1,$2,'meta','registered-cost','2026-09-29',3,20,2,'USD','{}')`,
      [TENANT, CAMPAIGN],
    );

    const traffic = await db.query(`
      select clicks,unique_visitors,sales
      from public.pandora_tracking_campaign_traffic_daily_v2
      where tenant_id=$1 and campaign_id=$2 and day='2026-09-29'`,
      [TENANT, CAMPAIGN],
    );
    assert.deepEqual(traffic.rows, [{ clicks: 2, unique_visitors: 1, sales: 2 }]);

    const financial = await db.query(`
      select monetized_sales,spend::text,net_revenue::text,cac::text,roas::text
      from public.pandora_tracking_campaign_financial_daily_v2
      where tenant_id=$1 and campaign_id=$2 and day='2026-09-29' and currency='USD'`,
      [TENANT, CAMPAIGN],
    );
    assert.deepEqual(financial.rows, [{
      monetized_sales: 2,
      spend: "5.0000",
      net_revenue: "30.0000",
      cac: "2.5000",
      roas: "6.0000",
    }]);

    for (const mutation of [
      "landing_url='https://example.test/?secret=x'",
      "referrer='https://referrer.test/private'",
      "user_agent='raw-agent'",
      "ip_hash='" + "c".repeat(64) + "'",
      "visitor_hash='" + "d".repeat(64) + "'",
      "platform_click_ids='{\"fbclid\":\"secret\"}'::jsonb",
      "query_params='{\"utm_source\":\"secret\"}'::jsonb",
      "metadata='{\"caller\":\"secret\"}'::jsonb",
    ]) {
      await assert.rejects(
        db.query(
          "update public.pandora_tracking_clicks set " + mutation +
            " where click_id='pdc_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'",
        ),
        (error) => error.code === "23514",
        mutation,
      );
    }

    await assert.rejects(db.query(`
      insert into public.pandora_tracking_events(
        tenant_id,campaign_id,event_type,event_name,source,external_event_id,
        occurred_at,metadata
      ) values($1,$2,'event','page.viewed','browser','bad-event',now(),
        '{"secret":"x"}')`, [TENANT, CAMPAIGN]), (error) => error.code === "23514");
    await assert.rejects(db.query(`
      insert into public.pandora_tracking_costs(
        tenant_id,campaign_id,provider,external_record_id,bucket_date,currency,metadata
      ) values($1,$2,'meta','bad-cost','2026-09-29','USD',
        '{"secret":"x"}')`, [TENANT, CAMPAIGN]), (error) => error.code === "23514");

    await assert.rejects(db.query(`
      insert into public.pandora_tracking_events(
        tenant_id,campaign_id,event_type,event_name,source,external_event_id,
        value,currency,occurred_at,metadata
      ) values($1,$2,'sale','purchase','server','registered-event',
        20,'USD',now(),'{}')`, [TENANT, CAMPAIGN]), (error) => error.code === "23505");
  } finally {
    await db.close();
  }
});

test("migration is additive and leaves canonical reporting definitions untouched", () => {
  assert.doesNotMatch(migration, /\b(?:update|delete|truncate)\s+public\.pandora_tracking_/i);
  assert.doesNotMatch(migration, /\b(?:grant|revoke|policy|row level security)\b/i);
  assert.doesNotMatch(migration, /create\s+(?:or\s+replace\s+)?view/i);
  assert.doesNotMatch(migration, /validate\s+constraint/i);
  assert.match(migration, /not valid/gi);
});
