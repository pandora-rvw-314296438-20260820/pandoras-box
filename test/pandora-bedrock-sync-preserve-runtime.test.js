"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs");
const migration=fs.readFileSync("supabase/migrations/20261002124000_pandora_bedrock_sync_preserve_runtime_v1.sql","utf8");
test("Bedrock catalog refresh preserves runtime evidence only for an unchanged invocation target",()=>{
  assert.match(migration,/prev\.invocation_target is not distinct from target/);
  assert.match(migration,/runtime_status:=case when same_target then prev\.runtime_verification_status else 'untested' end/);
  assert.match(migration,/tested_at:=case when same_target then prev\.runtime_tested_at else null end/);
  assert.match(migration,/cost_micros:=case when same_target then prev\.probe_cost_micros else null end/);
  assert.match(migration,/cost_source:=case when same_target then prev\.probe_pricing_source_ref else null end/);
});
test("a preserved PASS becomes Routable only when fresh AWS control-plane truth is fully available",()=>{
  assert.match(migration,/same_target and tested_at is not null and st='region_available' and conversational and target is not null/);
  assert.match(migration,/if runtime_status='passed' then[\s\S]*st:='routable'/);
  assert.match(migration,/is_routable:=true/);
});
test("a changed target invalidates prior runtime and cost evidence",()=>{
  assert.match(migration,/else 'untested' end/);
  assert.match(migration,/else null end/);
  assert.match(migration,/pending_pricing_readback/);
});
test("removed models retire without fabricating a new runtime test",()=>{
  assert.match(migration,/lifecycle_status='REMOVED',runtime_state='retired'/);
  assert.match(migration,/present_in_latest_sync=false/);
  assert.doesNotMatch(migration,/update private\.pandora_bedrock_reasoning_catalog[\s\S]*runtime_tested_at=null[\s\S]*where observed_at is distinct from o/);
});
