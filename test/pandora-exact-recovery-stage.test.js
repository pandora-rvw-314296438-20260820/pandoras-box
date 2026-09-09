const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const path = "supabase/functions/pandora-exact-recovery-stage-20260909/index.ts";
const source = fs.readFileSync(path, "utf8");

test("exact recovery staging is hard-bound to reviewed recovery evidence", () => {
  assert.match(source, /c6fb492c23aa0766effc931889bef2ac1a431cb4/);
  assert.match(source, /34318992007/);
  assert.match(source, /5efa848941be1c5f575f906254277a5f1b440036/);
  assert.match(source, /c9b8272b3c12d1baecec75eaa55d6e2bbdbdc3a1e9cf5210555a3a4690257337/);
  assert.match(source, /EXPECTED_BYTES = 7_876_284/);
  assert.match(source, /const BUCKET = "pandora-recovery"/);
  assert.match(source, /pandoras-box-c6fb492c23aa0766effc931889bef2ac1a431cb4-34318992007\.bundle/);
});

test("recovery staging uses existing internal auth and refuses arbitrary mutation scope", () => {
  assert.match(source, /x-pandora-internal-key/);
  assert.match(source, /pandora_validate_source_worker_key_20260831/);
  assert.match(source, /request\.method !== "POST"/);
  assert.doesNotMatch(source, /request\.json\(/);
  assert.doesNotMatch(source, /new URL\(request\.url\).*searchParams/);
  assert.match(source, /upsert: false/);
});

test("binary is verified before upload and after private storage readback", () => {
  const firstVerify = source.indexOf("await verifyBundle(bytes)");
  const upload = source.indexOf(".upload(OBJECT_PATH, bytes");
  const download = source.indexOf(".download(OBJECT_PATH)");
  const secondVerify = source.indexOf("await verifyBundle(storedBytes)");
  assert.ok(firstVerify > 0 && upload > firstVerify);
  assert.ok(download > upload && secondVerify > download);
  assert.match(source, /contentType: "application\/octet-stream"/);
  assert.match(source, /readbackVerified: true/);
});

test("recovery staging contains no source-controlled credential", () => {
  assert.doesNotMatch(source, /github_pat_|ghp_|sk-proj-|service_role\s*[:=]\s*["'][A-Za-z0-9._-]{20,}/i);
});
