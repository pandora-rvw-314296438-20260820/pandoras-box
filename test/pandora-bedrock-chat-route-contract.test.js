"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const edge=fs.readFileSync("supabase/functions/pandora-intelligence-chat/index.ts","utf8");
const helper=fs.readFileSync("supabase/functions/pandora-intelligence-chat/bedrock.ts","utf8");
const api=fs.readFileSync("api/operations-inference.ts","utf8");
const bridge=fs.readFileSync("src/providers/aws-bedrock-chat-http.js","utf8");
const sql=fs.readFileSync("supabase/migrations/20261003033000_pandora_bedrock_chat_bridge_v1.sql","utf8");
test("manual and Auto chat routes admit provider-verified Bedrock models",()=>{
  assert.match(edge,/bedrockRoutingConfig/);assert.match(edge,/provider:"bedrock"/);assert.match(edge,/provider==="bedrock"/);
  assert.match(edge,/requestedProvider:effectiveSelection.provider/);assert.match(edge,/requestedModel:effectiveSelection.model/);
  assert.match(edge,/executedProvider:result.provider/);assert.match(edge,/executedModel:result.model/);
  assert.match(edge,/fallbackMode==="strict"\?false/);assert.match(helper,/pandora_bedrock_chat_request_v1/);
  assert.match(sql,/c.routable=true/);assert.match(sql,/c.runtime_verification_status='passed'/);assert.match(sql,/c.lifecycle_status='ACTIVE'/);
});
test("Bedrock execution stays behind one-time ticket and existing Vercel OIDC signer",()=>{
  assert.match(api,/bedrock-chat/);assert.match(bridge,/pandora_claim_bedrock_chat_ticket_v1/);assert.match(bridge,/converseWithBedrockTarget/);
  assert.match(bridge,/temperature:null/);assert.match(bridge,/resolveVercelWorkloadToken/);
  assert.match(sql,/delete from private.pandora_bedrock_chat_tickets[\s\S]*returning \* into v_row/);
  assert.doesNotMatch(edge,/bedrock-runtime\.us-east-1\.amazonaws\.com/);
});
test("image turns only admit Bedrock catalog rows that advertise IMAGE input",()=>{
  assert.match(edge,/bcfg.imageModels:bcfg.allowedModels/);assert.match(sql,/'IMAGE'=any\(c.input_modalities\)/);
});


test("Bedrock ticket claim uses Vercel OIDC control gateway instead of Vercel Supabase service-role env",()=>{
  const control=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts","utf8");
  assert.match(bridge,/mcpmaster-supabase-control/);
  assert.match(bridge,/action:"bedrock_chat_ticket_claim"/);
  assert.match(bridge,/resolveVercelWorkloadToken/);
  assert.doesNotMatch(bridge,/SUPABASE_"\+"SERVICE_ROLE_KEY|loadOperatorPublicConfig/);
  assert.match(control,/bedrock_chat_ticket_claim/);
  assert.match(control,/pandora_claim_bedrock_chat_ticket_v1/);
  assert.match(control,/includeOrganization:\s*false/);
  assert.match(control,/route\.includeOrganization !== false/);
});
