"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const ownerApi = fs.readFileSync(
  "supabase/functions/pandora-owner-api/index.ts",
  "utf8",
);

test("Base44 Build Theatre is always present without inventing runtime state", () => {
  assert.match(ownerApi, /BUILD_THEATRE_STAGE_CONTRACT/);
  assert.match(ownerApi, /"understanding"[\s\S]*"planning"[\s\S]*"building"[\s\S]*"testing"[\s\S]*"preview_ready"/);
  assert.match(ownerApi, /"edit_requested"[\s\S]*"rebuilding"[\s\S]*"verifying"[\s\S]*"updated_preview"/);
  assert.match(ownerApi, /"preparing"[\s\S]*"deploying"[\s\S]*"verifying_live"[\s\S]*"live"/);
  assert.match(ownerApi, /source: "pandora_project_experience_projection",[\s\S]*mode: "idle"/);
  assert.match(ownerApi, /mode: "idle"[\s\S]*ownerStage: null,[\s\S]*progressPercent: null/);
  assert.match(ownerApi, /publicMessage: textValue\([\s\S]*"What do you want to build\?"/);
});

test("active Build Theatre state comes only from the canonical theatre projection", () => {
  assert.match(ownerApi, /from\("pandora_build_theatre_projection"\)/);
  assert.match(ownerApi, /source: "pandora_build_theatre_projection"/);
  assert.match(ownerApi, /progressPercent: numberValue\(theatre\.progress_percent\)/);
  assert.match(ownerApi, /ownerStage: textValue\(theatre\.owner_stage\) \|\| null/);
  assert.match(ownerApi, /buildTheatre: buildTheatreSummary\(experience\.data, theatre\.data\)/);
});

test("project detail reads both experience and theatre projections through the member context", () => {
  assert.match(ownerApi, /from\("pandora_project_experience_projection"\)/);
  assert.match(ownerApi, /from\("pandora_build_theatre_projection"\)/);
  assert.match(ownerApi, /experience\.error \|\| theatre\.error/);
  assert.doesNotMatch(ownerApi, /setTimeout\([\s\S]*buildTheatreSummary/);
  assert.doesNotMatch(ownerApi, /setInterval\([\s\S]*buildTheatreSummary/);
});
