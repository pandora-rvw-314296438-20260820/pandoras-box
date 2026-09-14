"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const main = readFileSync(
  join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "MainActivity.kt"),
  "utf8",
);
const agent = readFileSync(
  join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "PandoraDeviceAgentChannel.kt"),
  "utf8",
);
const manifestGenerator = readFileSync(
  join(root, "apps", "pandora-mobile", "tool", "configure_validation_android.py"),
  "utf8",
);
const nativeIo = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "platform", "pandora_native_io.dart"),
  "utf8",
);
test("scoped reads use Android document pickers and strict bounded text decoding", () => {
  assert.match(main, /Intent\(Intent\.ACTION_OPEN_DOCUMENT\)/);
  assert.match(main, /Intent\.CATEGORY_OPENABLE/);
  for (const mime of ["text/plain", "text/markdown", "text/csv", "application/json"]) {
    assert.ok(main.includes(`"${mime}"`), `missing allowlisted MIME ${mime}`);
  }
  assert.match(main, /maxDocumentBytes = 32 \* 1024/);
  assert.match(main, /CodingErrorAction\.REPORT/);
  assert.match(main, /DOCUMENT_TYPE_UNSUPPORTED/);
  assert.match(main, /DOCUMENT_ENCODING_UNSUPPORTED/);
  assert.doesNotMatch(main, /takePersistableUriPermission/);
});

test("scoped writes always use an explicit system save destination", () => {
  assert.match(main, /Intent\(Intent\.ACTION_CREATE_DOCUMENT\)/);
  assert.match(main, /putExtra\(Intent\.EXTRA_TITLE, name\)/);
  assert.match(main, /bytes\.size > 16 \* 1024 \* 1024/);
  assert.match(main, /isSafeDocumentName\(name\)/);
  assert.match(main, /isSafeMimeType\(mimeType\)/);
  assert.match(nativeIo, /saveBinaryDocument/);
});
test("files.scoped_access is available without broad storage authority", () => {
  assert.match(
    agent,
    /"files\.scoped_access",\s*"public_app",\s*"available"/s,
  );
  assert.match(agent, /Storage Access Framework/);
  assert.match(nativeIo, /pickTextAttachment/);
  assert.match(nativeIo, /pickPhoto/);
  for (const forbidden of [
    "MANAGE_EXTERNAL_STORAGE",
    "READ_EXTERNAL_STORAGE",
    "WRITE_EXTERNAL_STORAGE",
    "READ_MEDIA_IMAGES",
    "READ_MEDIA_VIDEO",
  ]) {
    assert.ok(!manifestGenerator.includes(`android.permission.${forbidden}`), `${forbidden} must not be generated`);
  }
  assert.doesNotMatch(main, /requestPermissions\s*\(/);
});
