"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const workflow=fs.readFileSync(".github/workflows/pandora-ux-regression.yml","utf8");
const golden=fs.readFileSync("apps/pandora-mobile/test/goldens/owner_screens_visual_evidence_test.dart","utf8");
const taps=fs.readFileSync("apps/pandora-mobile/test/features/simple/pandora_picker_tap_through_test.dart","utf8");

test("picker goldens are compared to committed PNGs instead of regenerated in CI",()=>{
  assert.doesNotMatch(workflow,/--update-goldens/);
  assert.doesNotMatch(workflow,/cp build\/owner-screen-evidence\/model_picker/);
  assert.match(workflow,/Verify committed Lane E and picker goldens/);
  assert.match(golden,/matchesGoldenFile\('owner_screens\/\$\{visual\.name\}\.png'\)/);
});
test("both model and reasoning pickers have tap-through widget coverage",()=>{
  assert.match(taps,/model picker taps through to exact manual selection/);
  assert.match(taps,/reasoning picker taps through to Deep/);
  assert.match(taps,/model-picker-fixture\.mistral/);
  assert.match(taps,/reasoning-picker-deep/);
  assert.match(workflow,/pandora_picker_tap_through_test\.dart/);
});
