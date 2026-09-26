"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.join(__dirname,"..");
const worker=fs.readFileSync(path.join(root,"api/operations-native-worker.ts"),"utf8");
const vercel=JSON.parse(fs.readFileSync(path.join(root,"vercel.json"),"utf8"));
const migration=fs.readFileSync(path.join(root,"supabase/migrations/20260926044500_operations_vercel_cron_wake_v1.sql"),"utf8");

test("cron wake uses Vercel CRON_SECRET while manual wake retains native digest authorization",()=>{
  assert.match(worker,/request\.method === "GET"/);
  assert.match(worker,/request\.method === "POST"/);
  assert.match(worker,/process\.env\.CRON_SECRET/);
  assert.match(worker,/timingSafeEqual/);
  assert.match(worker,/operations_wake_authorize/);
  assert.match(worker,/if \(isManualWake\)/);
  assert.doesNotMatch(worker,/CRON_SECRET\s*=\s*["'][^"']+/);
});
test("cron route is fixed and has no arbitrary scope or query input",()=>{
  assert.deepEqual(vercel.crons,[{path:"/api/operations-native-worker",schedule:"*/5 * * * *"}]);
  assert.match(worker,/if \(url\.search \|\| url\.hash\)/);
  assert.match(worker,/OPERATIONS_PROJECT_ID|CANARY_TASK/);
});
test("provisioner creates a sensitive production secret server-side and never returns it",()=>{
  assert.match(migration,/gen_random_bytes\(48\)/);
  assert.match(migration,/\/v10\/projects\/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk\/env\?upsert=true/);
  assert.match(migration,/'key','CRON_SECRET'/);
  assert.match(migration,/'type','sensitive'/);
  assert.match(migration,/'target',jsonb_build_array\('production'\)/);
  assert.match(migration,/'secretReturned',false/);
  assert.match(migration,/v_secret := null/);
  assert.doesNotMatch(migration,/return\s+v_secret/i);
});
