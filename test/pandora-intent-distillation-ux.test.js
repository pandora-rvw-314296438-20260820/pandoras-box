"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const compiler = fs.readFileSync(
  path.join(process.cwd(), "supabase/functions/pandora-project-spec-compiler/index.ts"),
  "utf8",
);
const migration = fs.readFileSync(
  path.join(process.cwd(), "supabase/migrations/20260901071500_pandora_intent_distillation_naming_v1.sql"),
  "utf8",
);
const createUi = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/project_create_experience.dart"),
  "utf8",
);
const workspace = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/project_experience_v2.dart"),
  "utf8",
);
const api = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/core/data/project_experience_api.dart"),
  "utf8",
);

test("Gemini distills a project name and short owner brief", () => {
  assert.match(compiler, /metadata=\{projectName:string,intentSummary:string\}/);
  assert.match(compiler, /projectName\.length > 80/);
  assert.match(compiler, /intentSummary\.length > 280/);
  assert.match(compiler, /pandora_commit_compiled_project_spec_v2_20260901/);
});

test("initial create intent atomically persists the model name and concise summary", () => {
  assert.match(migration, /v_intent_kind = 'create'/);
  assert.match(migration, /set name=v_project_name/);
  assert.match(migration, /'intentSummary',v_intent_summary/);
  assert.match(migration, /private\.pandora_commit_compiled_project_spec_20260829/);
});

test("understanding screen does not render the raw long intent", () => {
  const understandingStart = createUi.indexOf("class ProjectUnderstandingScreen");
  assert.ok(understandingStart > 0);
  const understandingSource = createUi.slice(understandingStart);
  assert.doesNotMatch(understandingSource, /intentText/);
  assert.doesNotMatch(understandingSource, /widget\.intentText/);
  assert.match(understandingSource, /PandoraProfessionalBuildPlan\(understanding: u!\)/);
  assert.match(understandingSource, /Ready to see it become real\?/);
  assert.match(understandingSource, /starts writing the real code immediately/);
});

test("owner can rename the display project later without provider churn", () => {
  assert.match(api, /Future<String> renameProject/);
  assert.match(api, /\.update\(<String, Object\?>\{[\s\S]*'name': nextName/);
  assert.match(workspace, /title: const Text\('Rename project'\)/);
  assert.match(workspace, /api\.renameProject\(projectId: widget\.project\.id, name: nextName\)/);
  assert.doesNotMatch(api, /renameProject[\s\S]{0,1200}(github|vercel)/i);
});
