"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const catalog=require("../src/providers/aws-bedrock-catalog.js");

const runtime=fs.readFileSync("src/providers/aws-bedrock-runtime.js","utf8");
const migration=fs.readFileSync("supabase/migrations/20260927070752_operations_reasoning_fleet_v1.sql","utf8");
const policy=fs.readFileSync("packages/pandora-operations-inference/policy.mjs","utf8");
const vercelRuntime=fs.readFileSync("packages/pandora-operations-inference/vercel-runtime.mjs","utf8");

test("Bedrock reasoning fleet exactly matches the generated 72-model account catalog",()=>{
  assert.equal(catalog.BEDROCK_REASONING_MODELS.length,72);
  assert.equal(new Set(catalog.BEDROCK_REASONING_MODELS.map(x=>x.modelId)).size,72);
  assert.equal(catalog.getBedrockReasoningModel("openai.gpt-6-astra").invocationTarget,"us.openai.gpt-6-astra");
  assert.equal(catalog.BEDROCK_REASONING_MODELS.some(x=>/rerank|safeguard|sonic|voxtral/i.test(x.modelId)),false);
  assert.match(migration,/BEDROCK_REASONING_CATALOG_COUNT_MISMATCH/);
  assert.match(migration,/'catalog_count','72'/);
});

test("production Bedrock authority is the narrow OIDC role and not the old broad role",()=>{
  assert.equal(catalog.BEDROCK_ROLE_ARN,"arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2");
  assert.match(runtime,/return \{ roleArn: BEDROCK_ROLE_ARN, region: BEDROCK_REGION \}/);
  assert.doesNotMatch(runtime,/roleArn:\s*environment\.AWS_ROLE_ARN/);
  assert.doesNotMatch(runtime,/AdministratorAccess/);
  assert.match(migration,/PandoraVercelBedrockInferenceV2/);
});

test("Vercel inference runtime has Bedrock while Supabase authority stays separate",()=>{
  assert.match(vercelRuntime,/bedrock_converse/);
  assert.match(vercelRuntime,/BedrockNativeProvider/);
  assert.match(vercelRuntime,/converseWithBedrockModel/);
});

test("Astra ChatGPT worker is attestation-gated rather than fabricated",()=>{
  assert.match(migration,/pandora_ops_worker_model_attestations/);
  assert.match(migration,/w\.engine<>'chatgpt'/);
  assert.match(migration,/p_model<>'gpt-6-astra'/);
  assert.match(migration,/'chatgpt_worker','routing_eligible','false'/);
  assert.match(migration,/awaiting_live_model_attestation/);
  assert.doesNotMatch(migration,/insert into private\.pandora_ops_workers[\s\S]*gpt-6-astra/i);
});

test("fleet expansion preserves bounded policy and financial fences",()=>{
  assert.match(policy,/raw\.models\.length <= 128/);
  assert.match(policy,/2592000000/);
  assert.match(migration,/'maxCostMicros',5000000/);
  assert.match(migration,/INFERENCE_POLICY_RECONCILIATION_REQUIRED/);
  assert.match(migration,/'allowedProviders',jsonb_build_array\('bedrock'\)/);
});

test("new reasoning fleet does not reintroduce retired ProjectOS",()=>{
  const joined=[runtime,migration,policy,vercelRuntime,JSON.stringify(catalog.BEDROCK_REASONING_MODELS)].join("\n");
  assert.doesNotMatch(joined,/ProjectOS/i);
});
