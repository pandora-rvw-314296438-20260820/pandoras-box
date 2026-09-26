"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const migration=fs.readFileSync("supabase/migrations/20260926093500_operations_max_concurrency_v1.sql","utf8");
const handler=fs.readFileSync("supabase/functions/pandora-operations-runtime/handler.mjs","utf8");

test("owner concurrency control is revision-fenced and range-bounded",()=>{
  assert.match(migration,/p_max_concurrency not between 1 and 16/);
  assert.match(migration,/OPS_CONTROL_REVISION_CONFLICT/);
  assert.match(migration,/OPS_MAX_CONCURRENCY_BELOW_ACTIVE_LEASES/);
  assert.match(migration,/owner_set_max_concurrency/);
  assert.match(migration,/role in \('owner','admin'\)/);
});
test("concurrency control preserves existing scheduler fences",()=>{
  assert.match(migration,/state<>'released'/);
  assert.doesNotMatch(migration,/update private\.pandora_ops_tasks set status='implementing'/);
  assert.doesNotMatch(migration,/insert into private\.pandora_ops_leases/);
  assert.doesNotMatch(migration,/no_production=false/);
});
test("privileged functions are not public APIs",()=>{
  assert.match(migration,/revoke all on function public\.pandora_ops_set_max_concurrency_v1[\s\S]*from public,anon,authenticated/);
  assert.match(migration,/grant execute on function public\.pandora_ops_set_max_concurrency_v1[\s\S]*to service_role/);
});

test("existing frozen Operations Edge handler is not modified by this release",()=>{
  const handler=fs.readFileSync("supabase/functions/pandora-operations-runtime/handler.mjs","utf8");
  assert.doesNotMatch(handler,/set_max_concurrency/);
});
