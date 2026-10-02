"use strict";
const fs=require("node:fs");
const test=require("node:test");
const assert=require("node:assert/strict");
const sql=fs.readFileSync("supabase/migrations/20261002102000_pandora_lane_f_bedrock_live_catalog_v2.sql","utf8");

test("#907 keeps the #911/#917 constraint vocabulary on late replay",()=>{
  const guard=sql.indexOf("column_name='entitlement_status'");
  const legacyDrop=sql.indexOf("drop constraint if exists pandora_bedrock_reasoning_catalog_runtime_state_check");
  assert.ok(guard>=0);
  assert.ok(legacyDrop>guard);
  assert.match(sql,/if not exists\s*\([\s\S]*column_name='entitlement_status'[\s\S]*\) then[\s\S]*drop constraint if exists pandora_bedrock_reasoning_catalog_runtime_state_check[\s\S]*end if;/);
  assert.match(sql,/Fresh installs still receive the\s+-- original #907 constraints/i);
});
