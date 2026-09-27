"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { PGlite } = require("@electric-sql/pglite");

const guard = fs.readFileSync(path.resolve(
  __dirname, "../ops/supabase/facebook-client-login/pandora_facebook_identity_guard_v1.sql"
), "utf8");
const owner = "11111111-1111-4111-8111-111111111111";
const fresh = "22222222-2222-4222-8222-222222222222";
const passwordOnly = "33333333-3333-4333-8333-333333333333";

async function database() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema private;
    create table auth.users (
      id uuid primary key,
      email text,
      raw_app_meta_data jsonb not null default '{}'::jsonb
    );
    create table auth.identities (
      id uuid primary key,
      user_id uuid not null references auth.users(id),
      provider text not null,
      identity_data jsonb not null default '{}'::jsonb,
      email text generated always as (identity_data ->> 'email') stored
    );
  `);
  await db.exec(guard);
  return db;
}
async function user(db, id, email, metadata = {}) {
  await db.query(
    "insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3::jsonb)",
    [id, email, JSON.stringify(metadata)]
  );
}
async function identity(db, id, userId, provider, email) {
  return db.query(
    "insert into auth.identities(id,user_id,provider,identity_data) " +
      "values($1,$2,$3,jsonb_build_object('email',$4))",
    [id, userId, provider, email]
  );
}
async function counts(db) {
  const result = await db.query(
    "select (select count(*) from auth.users)::int as users, " +
    "(select count(*) from auth.identities)::int as identities"
  );
  return result.rows[0];
}

test("existing confirmed email/owner account cannot acquire Facebook identity", async () => {
  const db = await database();
  try {
    await user(db, owner, "client@example.test", { role: "owner" });
    await identity(db, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", owner, "email", "client@example.test");
    const before = await counts(db);
    await assert.rejects(
      identity(db, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", owner, "facebook", "client@example.test"),
      (error) => error.code === "23514"
    );
    assert.deepEqual(await counts(db), before);
    const row = (await db.query("select raw_app_meta_data from auth.users where id=$1", [owner])).rows[0];
    assert.equal(row.raw_app_meta_data.role, "owner");
  } finally {
    await db.close();
  }
});

test("existing account without identity rows cannot be linked by email", async () => {
  const db = await database();
  try {
    await user(db, passwordOnly, "unconfirmed@example.test");
    await assert.rejects(
      identity(db, "cccccccc-cccc-4ccc-8ccc-cccccccccccc", passwordOnly, "facebook", "unconfirmed@example.test"),
      (error) => error.code === "23514"
    );
    await db.exec("begin");
    await db.query("update auth.users set raw_app_meta_data=$1::jsonb where id=$2", [
      JSON.stringify({ provider: "facebook" }), passwordOnly
    ]);
    await assert.rejects(
      identity(db, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", passwordOnly, "facebook", "unconfirmed@example.test"),
      (error) => error.code === "23514"
    );
    await db.exec("rollback");
    assert.deepEqual(await counts(db), { users: 1, identities: 0 });
  } finally {
    await db.close();
  }
});

test("same-email new Facebook account rolls back instead of duplicating an existing user", async () => {
  const db = await database();
  try {
    await user(db, owner, "client@example.test");
    await db.exec("begin");
    try {
      await user(db, fresh, "CLIENT@example.test", { provider: "facebook" });
      await assert.rejects(
        identity(db, "dddddddd-dddd-4ddd-8ddd-dddddddddddd", fresh, "facebook", "CLIENT@example.test"),
        (error) => error.code === "23505"
      );
    } finally {
      await db.exec("rollback");
    }
    assert.deepEqual(await counts(db), { users: 1, identities: 0 });
  } finally {
    await db.close();
  }
});

test("a new Facebook user succeeds only with a matching first identity", async () => {
  const db = await database();
  try {
    await db.exec("begin");
    await user(db, fresh, "new@example.test", { provider: "facebook" });
    await identity(db, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", fresh, "facebook", "new@example.test");
    await db.exec("commit");
    assert.deepEqual(await counts(db), { users: 1, identities: 1 });
    const consumed = await db.query("select count(*)::int as receipts from private.pandora_facebook_new_user_receipts_v1");
    assert.equal(consumed.rows[0].receipts, 0);
    await assert.rejects(
      identity(db, "ffffffff-ffff-4fff-8fff-ffffffffffff", fresh, "facebook", "new@example.test"),
      (error) => error.code === "23514"
    );
    assert.deepEqual(await counts(db), { users: 1, identities: 1 });
  } finally {
    await db.close();
  }
});

test("mismatched identity email is denied while existing non-Facebook signup is unchanged", async () => {
  const db = await database();
  try {
    await db.exec("begin");
    await user(db, fresh, "new@example.test", { provider: "facebook" });
    await assert.rejects(
      identity(db, "99999999-9999-4999-8999-999999999999", fresh, "facebook", "other@example.test"),
      (error) => error.code === "23514"
    );
    await db.exec("rollback");
    await user(db, owner, "email@example.test");
    await identity(db, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", owner, "email", "email@example.test");
    assert.deepEqual(await counts(db), { users: 1, identities: 1 });
  } finally {
    await db.close();
  }
});
