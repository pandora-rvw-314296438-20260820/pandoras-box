"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const sql = fs.readFileSync(
  "supabase/migrations/20260927041500_facebook_first_party_event_contract_v1.sql",
  "utf8",
);

test("FB-017 extends the existing tracking ledger without creating a competing event table", () => {
  assert.match(sql, /alter table public\.pandora_tracking_events/);
  assert.doesNotMatch(sql, /create table/i);
  assert.match(sql, /schema_version smallint not null default 1/);
  assert.match(sql, /consent jsonb not null/);
  assert.match(sql, /is_test boolean not null default false/);
  assert.match(sql, /consent - array\['analytics','marketing'\]/);
});
