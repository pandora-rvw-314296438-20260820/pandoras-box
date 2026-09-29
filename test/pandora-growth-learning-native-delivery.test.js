import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const migration=fs.readFileSync("supabase/migrations/20260929122500_growth_learning_native_delivery_v1.sql","utf8");
const worker=fs.readFileSync("api/operations-native-worker.ts","utf8");
const control=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts","utf8");

test("growth rows cannot use legacy ProjectOS delivery",()=>{
  assert.match(migration,/GROWTH_LEARNING_NATIVE_TRANSPORT_REQUIRED/);
  assert.match(migration,/coalesce\(payload->>'learning_kind',''\) <> 'growth_learning_v1'/);
  assert.match(migration,/pandora_claim_growth_learning_delivery_v1/);
  assert.match(migration,/pandora_ack_growth_learning_delivery_v1/);
});
test("native worker sends growth payload only to Pandora Memory bridge with workload OIDC",()=>{
  assert.match(worker,/action: "growth_learning_claim"/);
  assert.match(worker,/action: "growth_learning"/);
  assert.match(worker,/"x-pandora-vercel-oidc": oidc/);
  assert.match(worker,/action: "growth_learning_ack"/);
  assert.doesNotMatch(worker,/pandora-projectos-learning/);
});
test("control route exposes only fenced claim and ack RPCs",()=>{
  assert.match(control,/growth_learning_claim/);
  assert.match(control,/pandora_claim_growth_learning_delivery_v1/);
  assert.match(control,/growth_learning_ack/);
  assert.match(control,/pandora_ack_growth_learning_delivery_v1/);
});
test("ack relies on strict existing Memory response validator",()=>{
  assert.match(migration,/private\.execution_learning_response_is_valid/);
  assert.match(migration,/native_claim_token is distinct from p_claim_token/);
  assert.match(migration,/attempt_count>=5/);
});
