"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const root = join(__dirname, "..");
const edge = readFileSync(join(root, "supabase", "functions", "pandora-preview-content", "index.ts"), "utf8");
const journey = readFileSync(join(root, "apps", "pandora-mobile", "lib", "features", "simple", "project_journey_flow.dart"), "utf8");
const experience = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "data", "project_experience_api.dart"), "utf8");
const nativeIo = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "platform", "pandora_native_io.dart"), "utf8");
const androidPreview = readFileSync(join(root, "apps", "pandora-mobile", "lib", "core", "platform", "pandora_android_preview.dart"), "utf8");
const android = readFileSync(join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "MainActivity.kt"), "utf8");

test("mobile preview content is authenticated and bound to exact artifact lineage", () => {
  assert.match(edge, /SUPABASE_ANON_KEY/);
  assert.match(edge, /userClient\.auth\.getUser\(\)/);
  assert.match(edge, /\.from\("memberships"\)/);
  assert.match(edge, /\.in\("role", \["owner", "admin"\]\)/);
  assert.match(edge, /root_artifact_version_id/);
  assert.match(edge, /artifact_digest_sha256/);
  assert.match(edge, /sha256Hex\(bundleBytes\)/);
  assert.match(edge, /ARTIFACT_FILE_DIGEST_MISMATCH/);
  assert.match(edge, /ARTIFACT_ENTRYPOINT_MISSING/);
  assert.match(edge, /pandora\.mobile-preview-bundle\.v1/);
});

test("mobile journey can render the exact candidate when Vercel preview creation is unavailable", () => {
  assert.match(journey, /loadExactPreviewFiles/);
  assert.doesNotMatch(journey, /Supabase\.instance/);
  assert.match(experience, /pandora-preview-content/);
  assert.match(journey, /_activateLocalPreview\(candidate\)/);
  assert.match(journey, /_hasRenderablePreview/);
  assert.match(journey, /PandoraNativeIo\.openPreviewBundle\(files\)/);
  assert.match(journey, /onPressed: _openExactPreview/);
});

test("Android exact preview renderer stays in-memory and exposes no JavaScript bridge", () => {
  assert.match(nativeIo, /openPreviewBundle/);
  assert.match(androidPreview, /pandora\/exact_preview/);
  assert.match(androidPreview, /AndroidView\(/);
  assert.match(android, /"openPreviewBundle" -> openPreviewBundle\(call, result\)/);
  assert.match(android, /registerViewFactory/);
  assert.match(android, /PandoraExactPreviewView/);
  assert.match(android, /allowFileAccess = false/);
  assert.match(android, /allowContentAccess = false/);
  assert.match(android, /MIXED_CONTENT_NEVER_ALLOW/);
  assert.match(android, /shouldInterceptRequest/);
  assert.match(android, /https:\/\/pandora\.local\/index\.html/);
  assert.match(android, /pandora\/exact_preview_selection_/);
  assert.match(android, /elementFromPoint/);
  assert.match(android, /evaluateJavascript/);
  assert.match(androidPreview, /PandoraPreviewSelection/);
  assert.match(androidPreview, /setSelectionMode/);
  assert.doesNotMatch(android, /addJavascriptInterface/);
  assert.doesNotMatch(android, /file:\/\//);
});
