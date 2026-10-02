"use strict";
const fs=require("node:fs");
const test=require("node:test");
const assert=require("node:assert/strict");

const runtime=fs.readFileSync("src/providers/aws-bedrock-runtime.js","utf8");
const projection=fs.readFileSync("supabase/migrations/20261003024500_pandora_bedrock_probe_truth_v1.sql","utf8");

test("Bedrock runtime signs raw model IDs and canonicalizes the URI exactly once",()=>{
  assert.match(runtime,/const rawModelId = String\(modelId \|\| ""\)/);
  assert.match(runtime,/const wirePath = modelPath\(rawModelId\)/);
  assert.match(runtime,/const canonicalPath = canonicalAwsPath\(wirePath\)/);
  assert.match(runtime,/url: `https:\/\/\$\{host\}\$\{wirePath\}`/);
  assert.match(runtime,/temperature = null/);
});

test("implementation-caused probe failures are projected as unverified, not access denied",()=>{
  assert.match(projection,/signature we calculated does not match/);
  assert.match(projection,/doesn''t support the temperature field/);
  assert.match(projection,/then 'unverified'/);
  assert.match(projection,/Unverified — Pandora runtime re-probe required/);
  const implIndex=projection.indexOf("Unverified — Pandora runtime re-probe required");
  const generic403=projection.indexOf("when c.runtime_verification_status='failed' and c.probe_http_status=403 then 'Access denied'");
  assert.ok(implIndex>=0&&generic403>implIndex);
  assert.match(projection,/c\.routable=true[\s\S]*c\.runtime_verification_status='passed'/);
});
