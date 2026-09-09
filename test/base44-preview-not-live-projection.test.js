"use strict";

const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");

const migration = fs.readFileSync(
  "supabase/migrations/20260909093400_pandora_preview_not_live_projection_v1.sql",
  "utf8",
);

test("preview-only current versions cannot be labeled LIVE", () => {
  assert.match(migration, /when n\.production_version_id is not null[\s\S]*then 'LIVE'/);
  assert.match(migration, /when n\.current_version_id is not null[\s\S]*then 'REVIEW'/);
  assert.match(
    migration,
    /then case when n\.production_version_id is not null then 'LIVE' else 'REVIEW' end/,
  );
});

test("preview-only REVIEW state has truthful owner copy", () => {
  assert.match(
    migration,
    /normalized_experience_state = 'REVIEW'[\s\S]*production_version_id is null then 'Preview ready'/,
  );
  assert.match(migration, /normalized_experience_state = 'REVIEW' then 'Change verified'/);
});

test("publishability is still computed from verified preview facts but respects the Base44 rollout gate", () => {
  assert.match(migration, /candidate_verification_state = 'passed'/);
  assert.match(migration, /is_current_verified/);
  assert.match(
    migration,
    /pandora_base44_action_allowed_v1\(s\.project_id, 'publish'\)/,
  );
});

test("migration refreshes affected preview-only and Base44-enrolled projections", () => {
  assert.match(migration, /production_version_id is null/);
  assert.match(migration, /pandora_base44_rollout_projects/);
  assert.match(migration, /pandora_refresh_project_experience_projection_v1/);
});
