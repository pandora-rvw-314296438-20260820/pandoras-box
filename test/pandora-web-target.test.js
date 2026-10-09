const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const script = path.join(root, "scripts/pandora-web-target.sh");
const build = fs.readFileSync(path.join(root, "scripts/build-vercel-pandora-web.sh"), "utf8");

function target(env) {
  const clean = { PATH: process.env.PATH, ...env };
  return spawnSync("bash", [script], { env: clean, encoding: "utf8" });
}

test("enterprise Vercel project builds the PLP Enterprise web app", () => {
  const r = target({ VERCEL_PROJECT_ID: "prj_Aa4Dz7bWERhY88Iiav0m9oakeCXx" });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, "lib/main_plp.dart\n");
});

test("other projects keep the default Pandora web app", () => {
  for (const env of [{}, { VERCEL_PROJECT_ID: "prj_other" }]) {
    const r = target(env);
    assert.equal(r.status, 0);
    assert.equal(r.stdout, "lib/main.dart\n");
  }
});

test("explicit PANDORA_WEB_TARGET wins and is allowlisted", () => {
  assert.equal(
    target({ PANDORA_WEB_TARGET: "lib/main.dart", VERCEL_PROJECT_ID: "prj_Aa4Dz7bWERhY88Iiav0m9oakeCXx" }).stdout,
    "lib/main.dart\n",
  );
  assert.equal(target({ PANDORA_WEB_TARGET: "lib/main_plp.dart" }).stdout, "lib/main_plp.dart\n");
  for (const bad of ["lib/main_eurofish.dart", "../evil.dart", "lib/main.dart;rm"]) {
    const r = target({ PANDORA_WEB_TARGET: bad });
    assert.notEqual(r.status, 0, bad);
    assert.equal(r.stdout, "");
  }
});

test("web build passes the selected target and records it in the manifest", () => {
  assert.match(build, /WEB_TARGET="\$\(bash scripts\/pandora-web-target\.sh\)"/);
  assert.match(build, /--target="\$WEB_TARGET"/);
  assert.match(build, /^web_target=\$\{WEB_TARGET\}$/m);
});
