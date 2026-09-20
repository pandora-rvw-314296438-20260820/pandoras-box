"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const migration = readFileSync(
  join(root, "supabase", "migrations", "20260911060500_pandora_chat_pandora_build_theatre_handoff_v1.sql"),
  "utf8",
);
const ask = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "features", "simple", "ask_pandora_screen.dart"),
  "utf8",
);
const theatre = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "features", "simple", "project_build_conversation.dart"),
  "utf8",
);

test("Pandora Chat stateful capability requests hand off only after Pandora intake", () => {
  assert.match(migration, /pandora_chat_capability_dispatch_core_v1/);
  assert.match(migration, /capabilityResult,authority.*pandora/s);
  assert.match(migration, /intakeId/);
  assert.match(migration, /'required', true/);
  assert.match(migration, /'projectId', v_project_id/);
  assert.match(migration, /revoke all on function public\.pandora_chat_capability_dispatch_core_v1.*authenticated/s);
});

test("mobile consumes the explicit project handoff in Universal Chat without a second command", () => {
  assert.match(ask, /intelligence\.chat` owns exactly one dispatch/);
  assert.match(ask, /handoff\?\.source == 'project_workspace_change'/);
  assert.match(ask, /experience\.loadExperience\(handoffProjectId\)/);
  assert.match(ask, /experience\.submitChange\(/);
  assert.match(ask, /experience\.understanding\(/);
  assert.match(ask, /experience\.requestBuild\(/);
  assert.match(ask, /keep this chat open while Pandora works/);
  assert.doesNotMatch(ask, /ProjectWorkspaceV2Screen\(/);
  assert.doesNotMatch(ask, /message: handoff\.request/);
  assert.doesNotMatch(ask, /intelligence-handoff/);
  assert.doesNotMatch(ask, /fake progress|simulated progress/i);
});

test("the project build conversation renders the real resilient backend stream", () => {
  assert.match(theatre, /watchResilientBuildStream/);
  assert.match(theatre, /LiveBuildTheatre/);
  assert.match(theatre, /snapshot\.requiresReplay/);
  assert.match(theatre, /Live build stream unavailable/);
  assert.match(theatre, /VERIFICATION_FAILED/);
  assert.match(theatre, /BUILD_DEADLINE_EXCEEDED/);
});
