"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const pandoraMcp = fs.readFileSync("src/pandora-mcp-handler.js", "utf8");
const control = fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts", "utf8");
const activeGuidance = [
  ".claude/skills/pandora-mcp-discovery/SKILL.md",
  ".claude/skills/pandora-control-tower/SKILL.md",
  ".claude/skills/pandora-governed-execution/SKILL.md",
  ".claude/skills/pandora-governance-contract/references/risk-classification.md",
].map((path) => fs.readFileSync(path, "utf8")).join("\n");
const historicalHandler = fs.readFileSync("src/projectos-mcp-handler.js", "utf8");
const retirementMigration = fs.readFileSync(
  "supabase/migrations/20260914050000_pandora_projectos_retirement_v1.sql",
  "utf8",
);

test("active Pandora MCP rejects rather than maps retired ProjectOS tool names", () => {
  assert.doesNotMatch(pandoraMcp, /PROJECTOS_TOOL_ALIASES|PROJECTOS_PLAN_TOOL_PREFIX|canonicalToolName\(name\)/);
  assert.match(pandoraMcp, /name\.startsWith\("projectos_"\)/);
  assert.match(pandoraMcp, /ProjectOS tool aliases are retired; use canonical Pandora tool names/);
  assert.match(pandoraMcp, /pandora_tool_catalog/);
});

test("production Supabase control exposes no ProjectOS checkpoint or event route", () => {
  for (const token of [
    "projectos_checkpoint_save",
    "projectos_checkpoint_get",
    "projectos_event_list",
    "projectos_event_verify",
    "save_projectos_checkpoint",
    "get_projectos_checkpoint",
    "list_projectos_events",
    "verify_projectos_event_chain",
  ]) assert.equal(control.includes(token), false, token);
});

test("active agent guidance uses Pandora-native governance tool names", () => {
  assert.doesNotMatch(activeGuidance, /projectos_(tool_catalog|list_plans|list_audit|verify_audit)/);
  assert.match(activeGuidance, /pandora_tool_catalog/);
});

test("historical ProjectOS provenance remains preserved", () => {
  assert.match(historicalHandler, /projectos_tool_catalog/);
  assert.match(retirementMigration, /projectos/i);
});
