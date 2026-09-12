"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const migration = readFileSync(
  join(root, "supabase", "migrations", "20260911060500_pandora_chat_projectos_build_theatre_handoff_v1.sql"),
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

test("Pandora Chat stateful capability requests hand off only after ProjectOS intake", () => {
  assert.match(migration, /pandora_chat_capability_dispatch_core_v1/);
  assert.match(migration, /capabilityResult,authority.*projectos/s);
  assert.match(migration, /intakeId/);
  assert.match(migration, /'required', true/);
  assert.match(migration, /'projectId', v_project_id/);
  assert.match(migration, /revoke all on function public\.pandora_chat_capability_dispatch_core_v1.*authenticated/s);
});

test("mobile treats the ProjectOS handoff as an admission receipt, not a second command", () => {
  assert.match(ask, /intelligence\.chat` already performed the governed dispatch/);
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
