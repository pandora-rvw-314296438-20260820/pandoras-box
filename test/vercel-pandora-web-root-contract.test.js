import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const build = fs.readFileSync("scripts/build-vercel-pandora-web.sh", "utf8");
const config = JSON.parse(fs.readFileSync("vercel.json", "utf8"));

test("Pandora web publishes a real static root document", () => {
  assert.match(build, /ROOT_INDEX="\$\{PWD\}\/public\/index\.html"/);
  assert.match(build, /rm -f "\$ROOT_INDEX"/);
  assert.match(build, /cp "\$OUTPUT_ROOT\/index\.html" "\$ROOT_INDEX"/);
  assert.match(build, /--base-href \/pandora-web\//);
});

test("Vercel does not internally rewrite root into the Flutter namespace", () => {
  const rewrites = Array.isArray(config.rewrites) ? config.rewrites : [];
  assert.equal(
    rewrites.some(
      (route) =>
        route?.source === "/" &&
        route?.destination === "/pandora-web/index.html",
    ),
    false,
  );
});
