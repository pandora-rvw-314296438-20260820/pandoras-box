"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { pathToFileURL } = require("node:url");
const { test } = require("node:test");

const root = join(__dirname, "..");
const migrationPath = join(
  root,
  "supabase",
  "migrations",
  "20260909030000_pandora_external_experience_write_control_v1.sql",
);
const gateModuleUrl = pathToFileURL(
  join(
    root,
    "supabase",
    "functions",
    "pandora-project-runtime",
    "external-write-gate.mjs",
  ),
).href;
const migration = readFileSync(migrationPath, "utf8");

const routeCases = [
  ["/projects", "project.create"],
  ["/projects/11111111-1111-4111-8111-111111111111/previews", "preview.create"],
  ["/projects/11111111-1111-4111-8111-111111111111/undo", "project.undo"],
  ["/projects/11111111-1111-4111-8111-111111111111/rollback", "project.rollback"],
  ["/projects/11111111-1111-4111-8111-111111111111/publish", "project.publish"],
  [
    "/projects/11111111-1111-4111-8111-111111111111/production-verification",
    "production.verify",
  ],
];

async function makeDb() {
  const { PGlite } = await import("@electric-sql/pglite");
  const db = new PGlite();

  await db.exec(`
    do $bootstrap$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
      end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin bypassrls;
      end if;
    end
    $bootstrap$;
  `);
  await db.exec(migration);
  return db;
}

async function expectDenied(db, role, sql) {
  await db.exec(`set role ${role};`);
  try {
    await assert.rejects(
      db.query(sql),
      (error) => {
        assert.match(String(error.message), /permission denied|not allowed/i);
        return true;
      },
    );
  } finally {
    await db.exec("reset role;");
  }
}

async function decision(db, origin, operation) {
  const result = await db.query(
    `select public.pandora_external_experience_write_allowed_v1(
      $1::text,
      $2::text
    ) as allowed`,
    [origin, operation],
  );
  assert.equal(result.rows.length, 1);
  return result.rows[0].allowed;
}

test("anon and authenticated cannot inspect or mutate rollout controls or execute the decision RPC", async () => {
  const db = await makeDb();
  try {
    for (const role of ["anon", "authenticated"]) {
      for (const sql of [
        "select * from public.pandora_external_experience_write_control",
        "select * from public.pandora_external_experience_write_allowlist",
        "update public.pandora_external_experience_write_control set enabled = true where singleton = true",
        `insert into public.pandora_external_experience_write_allowlist(origin, operation, enabled)
         values ('https://example.invalid', 'project.create', true)`,
        "delete from public.pandora_external_experience_write_allowlist",
        `select public.pandora_external_experience_write_allowed_v1(
          'https://example.invalid',
          'project.create'
        )`,
      ]) {
        await expectDenied(db, role, sql);
      }
    }
  } finally {
    await db.close();
  }
});

test("service-role decision remains false until both global and exact origin-operation controls are enabled", async () => {
  const db = await makeDb();
  const origin = "https://base44.example";
  const operation = "project.create";

  try {
    await db.exec("set role service_role;");

    assert.equal(await decision(db, origin, operation), false);

    await db.exec(
      "delete from public.pandora_external_experience_write_control where singleton = true",
    );
    assert.equal(await decision(db, origin, operation), false);

    await db.exec(`
      insert into public.pandora_external_experience_write_control(singleton, enabled)
      values (true, false)
    `);
    assert.equal(await decision(db, origin, operation), false);

    await db.exec(
      "update public.pandora_external_experience_write_control set enabled = true where singleton = true",
    );
    assert.equal(await decision(db, origin, operation), false);

    await db.query(
      `insert into public.pandora_external_experience_write_allowlist(
        origin,
        operation,
        enabled
      ) values ($1, $2, false)`,
      [origin, operation],
    );
    assert.equal(await decision(db, origin, operation), false);

    await db.query(
      `update public.pandora_external_experience_write_allowlist
       set enabled = true
       where origin = $1 and operation = $2`,
      [origin, operation],
    );
    assert.equal(await decision(db, origin, operation), true);
    assert.equal(
      await decision(db, "https://different.example", operation),
      false,
    );
    assert.equal(await decision(db, origin, "preview.create"), false);
  } finally {
    await db.exec("reset role;");
    await db.close();
  }
});

test("shared request gate maps the exact six privileged POST routes", async () => {
  const {
    externalExperienceWriteOperationForRequest,
  } = await import(gateModuleUrl);

  for (const [route, operation] of routeCases) {
    assert.equal(
      externalExperienceWriteOperationForRequest("POST", route),
      operation,
    );
  }
  assert.equal(
    externalExperienceWriteOperationForRequest("GET", "/projects"),
    null,
  );
  assert.equal(
    externalExperienceWriteOperationForRequest("POST", "/projects/x/runtime"),
    null,
  );
  assert.equal(
    externalExperienceWriteOperationForRequest("POST", "/unknown"),
    null,
  );
});

test("configured external origins fail closed with 403 semantics on every privileged route", async () => {
  const {
    EXTERNAL_EXPERIENCE_WRITE_DISABLED,
    enforceExternalExperienceWriteRequest,
  } = await import(gateModuleUrl);
  const firstPartyOrigins = new Set([
    "https://pandoras-box-system.vercel.app",
    "https://mcpmaster.vercel.app",
  ]);
  const origin = "https://base44.example";

  const denyCases = [
    ["false", async () => false],
    ["null", async () => null],
    ["rpc-error", async () => {
      throw new Error("rpc unavailable");
    }],
  ];

  for (const [label, decide] of denyCases) {
    for (const [route] of routeCases) {
      await assert.rejects(
        enforceExternalExperienceWriteRequest({
          origin,
          method: "POST",
          route,
          firstPartyOrigins,
          decide,
        }),
        (error) => {
          assert.equal(error.message, EXTERNAL_EXPERIENCE_WRITE_DISABLED, label);
          assert.equal(error.status, 403, label);
          assert.equal(error.retryable, false, label);
          assert.equal(error.outcomeKnown, true, label);
          return true;
        },
      );
    }
  }
});

test("configured external origins proceed only on literal true for every privileged route", async () => {
  const {
    enforceExternalExperienceWriteRequest,
  } = await import(gateModuleUrl);
  const firstPartyOrigins = new Set([
    "https://pandoras-box-system.vercel.app",
    "https://mcpmaster.vercel.app",
  ]);

  for (const [route, operation] of routeCases) {
    const calls = [];
    const result = await enforceExternalExperienceWriteRequest({
      origin: "https://base44.example",
      method: "POST",
      route,
      firstPartyOrigins,
      decide: async (origin, checkedOperation) => {
        calls.push([origin, checkedOperation]);
        return true;
      },
    });
    assert.deepEqual(result, { operation, checked: true });
    assert.deepEqual(calls, [["https://base44.example", operation]]);
  }
});

test("first-party and no-Origin requests never call the rollout decision RPC", async () => {
  const {
    enforceExternalExperienceWriteRequest,
  } = await import(gateModuleUrl);
  const firstPartyOrigins = new Set([
    "https://pandoras-box-system.vercel.app",
    "https://mcpmaster.vercel.app",
  ]);

  let calls = 0;
  const decide = async () => {
    calls += 1;
    throw new Error("decision should not be called");
  };

  for (const [route, operation] of routeCases) {
    assert.deepEqual(
      await enforceExternalExperienceWriteRequest({
        origin: "https://mcpmaster.vercel.app",
        method: "POST",
        route,
        firstPartyOrigins,
        decide,
      }),
      { operation, checked: false },
    );
    assert.deepEqual(
      await enforceExternalExperienceWriteRequest({
        origin: null,
        method: "POST",
        route,
        firstPartyOrigins,
        decide,
      }),
      { operation, checked: false },
    );
  }
  assert.equal(calls, 0);
});
