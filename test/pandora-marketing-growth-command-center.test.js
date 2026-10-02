"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const test=require("node:test");
const sql=fs.readFileSync("supabase/migrations/20260930012000_marketing_growth_direct_workspace_v2.sql","utf8");
const screen=fs.readFileSync("apps/pandora-mobile/lib/features/enterprise/marketing_growth_workspace_screen.dart","utf8");
const shell=fs.readFileSync("apps/pandora-mobile/lib/app/pandora_chat_shell.dart","utf8");

test("growth command center is tenant-scoped read-only owner/admin truth",()=>{
  assert.match(sql,/auth\.uid\(\)/);
  assert.match(sql,/v_role not in \('owner','admin'\)/);
  assert.match(sql,/workspace_key='pandora-platform'/);
  assert.match(sql,/operationsRoomRequired',false/);
  assert.match(sql,/directGithubSource',true/);
  assert.doesNotMatch(sql,/pandora_ops_tasks|pandora_ops_events|pandora_ops_human_gates/);
  assert.match(sql,/r\.is_test is false/);
  assert.match(sql,/testTrafficIncludedInBusinessKpis',false/);
  assert.match(sql,/campaignMutationGranted',false/);
  assert.match(sql,/spendAuthorized',false/);
  assert.match(sql,/revoke all on function[\s\S]*from public,anon/);
  assert.doesNotMatch(sql,/access_token|refresh_token|user_token|page_token/);
});

test("growth workspace exposes real sections under the shared Pandora composer",()=>{
  for(const key of [
    "marketing-growth-open-approvals",
    "pandora_marketing_growth_command_center_v2"
  ]) assert.ok(screen.includes(key), key);
  assert.doesNotMatch(screen,/AskPandoraScreen|marketing-growth-command-bar|Message Pandora about Marketing & Growth/);
  assert.match(screen,/test traffic never becomes a business KPI/i);
  assert.match(shell,/MarketingGrowthWorkspaceScreen\(/);
  assert.match(shell,/workspace\.key ==\s*'pandora-marketing-growth'/);
  assert.match(shell,/PandoraSharedConversationScope/);
});

test("growth UI makes unknown and authority boundaries explicit",()=>{
  assert.match(screen,/No verified business outcomes yet/);
  assert.match(screen,/No verified business experiment data yet/);
  assert.match(screen,/Not authorized/);
  assert.match(screen,/Pending, rejected or superseded learning is never treated as current evidence/);
  assert.doesNotMatch(screen,/ROAS winner|guaranteed winner/i);
});
