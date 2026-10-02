"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const migration=fs.readFileSync("supabase/migrations/20261002120500_pandora_bedrock_control_trigger_v1.sql","utf8");
test("Bedrock control trigger keeps one-time material server-side and bounded",()=>{
 assert.match(migration,/security definer/);
 assert.match(migration,/SERVICE_ROLE_REQUIRED/);
 assert.match(migration,/extensions\.gen_random_bytes\(32\)/);
 assert.match(migration,/extensions\.digest\(v_token,'sha256'\)/);
 assert.match(migration,/private\.pandora_bedrock_control_tickets/);
 assert.match(migration,/https:\/\/mcpmaster\.vercel\.app\/api\/operations-inference\?operation=bedrock-control/);
 assert.match(migration,/timeout_milliseconds:=180000/);
 assert.match(migration,/v_token:=null/);
 assert.doesNotMatch(migration,/'token',v_token[\s\S]*return jsonb_build_object/);
 assert.match(migration,/'requestId',v_request_id/);
});
