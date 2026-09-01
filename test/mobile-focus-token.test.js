"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const root = join(__dirname, "..");
const mobile = join(root, "apps", "pandora-mobile");
const focus = readFileSync(join(mobile, "lib", "core", "models", "project_focus_token.dart"), "utf8");
const contract = readFileSync(join(mobile, "lib", "core", "platform", "pandora_preview_contract.dart"), "utf8");
const androidPreview = readFileSync(join(mobile, "lib", "core", "platform", "pandora_android_preview.dart"), "utf8");
const iosPreview = readFileSync(join(mobile, "lib", "core", "platform", "pandora_ios_preview.dart"), "utf8");
const webPreview = readFileSync(join(mobile, "lib", "core", "platform", "pandora_web_preview_web.dart"), "utf8");
const experience = readFileSync(join(mobile, "lib", "features", "simple", "project_experience_v2.dart"), "utf8");
const api = readFileSync(join(mobile, "lib", "core", "data", "project_experience_api.dart"), "utf8");
const android = readFileSync(join(mobile, "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "MainActivity.kt"), "utf8");
const ios = readFileSync(join(mobile, "platform", "ios", "Runner", "PandoraExactPreviewView.swift"), "utf8");

test("FocusToken v2 binds selection to exact project version, component and artifact", () => {
  assert.match(focus, /class ProjectFocusToken/);
  assert.match(focus, /static const int schemaVersion = 2/);
  assert.match(focus, /componentId/);
  assert.match(focus, /semanticId/);
  assert.match(focus, /artifactDigest/);
  assert.match(focus, /sourceFile/);
  assert.match(focus, /issuedAt/);
  assert.match(focus, /expiresAt/);
  assert.match(focus, /Duration\(minutes: 15\)/);
  assert.match(focus, /isExpired/);
  assert.match(focus, /matchesVisible/);
  assert.match(api, /artifactDigest/);
  assert.match(api, /previewVersionId/);
  assert.match(api, /previewProjectId/);
  assert.match(experience, /_previewArtifactDigest/);
  assert.match(experience, /componentId: selection\.componentId/);
  assert.match(experience, /focusToken\.matchesVisible/);
  assert.match(experience, /older preview/);
});

test("all exact-preview hosts carry stable component identity and source mapping", () => {
  assert.match(contract, /componentId/);
  assert.match(androidPreview, /componentId: value\('componentId'\)/);
  assert.match(iosPreview, /componentId: value\('componentId'\)/);
  assert.match(webPreview, /componentId: value\('componentId'\)/);
  assert.match(webPreview, /data-pandora-component-id/);
  assert.match(android, /data-pandora-component-id/);
  assert.match(android, /componentId:componentId/);
  assert.match(android, /"componentId" to componentId/);
  assert.match(ios, /data-pandora-component-id/);
  assert.match(ios, /componentId:/);
  assert.match(android, /data-pandora-source-file/);
  assert.match(android, /getBoundingClientRect/);
  assert.match(android, /accessibleName/);
  assert.match(android, /semanticId/);
  assert.doesNotMatch(android, /addJavascriptInterface/);
});
