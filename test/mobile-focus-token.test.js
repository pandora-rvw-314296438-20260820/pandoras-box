"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const root = join(__dirname, "..");
const focus = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "models", "project_focus_token.dart"), "utf8");
const embedded = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "platform", "pandora_embedded_preview.dart"), "utf8");
const experience = readFileSync(join(root, "apps", "pandora-mobile", "lib", "features", "simple", "project_experience_v2.dart"), "utf8");
const api = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "data", "project_experience_api.dart"), "utf8");
const android = readFileSync(join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "MainActivity.kt"), "utf8");

test("FocusToken binds selection to exact project version and verified artifact digest", () => {
  assert.match(focus, /class ProjectFocusToken/);
  assert.match(focus, /static const int schemaVersion = 2/);
  assert.match(focus, /artifactDigest/);
  assert.match(focus, /semanticId/);
  assert.match(focus, /componentId/);
  assert.match(focus, /issuedAt/);
  assert.match(focus, /expiresAt/);
  assert.match(focus, /defaultLifetime/);
  assert.match(focus, /sourceFile/);
  assert.match(focus, /matchesVisible/);
  assert.match(api, /artifactDigest/);
  assert.match(api, /previewVersionId/);
  assert.match(api, /previewProjectId/);
  assert.match(experience, /_previewArtifactDigest/);
  assert.match(experience, /focusToken\.matchesVisible/);
  assert.match(experience, /older preview/);
});

test("native selection captures semantic identity, source mapping, accessibility and bounds", () => {
  assert.match(embedded, /semanticId/);
  assert.match(embedded, /accessibleName/);
  assert.match(embedded, /sourceFile/);
  assert.match(embedded, /PandoraPreviewBounds/);
  assert.match(android, /data-pandora-id/);
  assert.match(android, /data-pandora-source-file/);
  assert.match(android, /getBoundingClientRect/);
  assert.match(android, /accessibleName/);
  assert.match(android, /semanticId/);
  assert.doesNotMatch(android, /addJavascriptInterface/);
});
