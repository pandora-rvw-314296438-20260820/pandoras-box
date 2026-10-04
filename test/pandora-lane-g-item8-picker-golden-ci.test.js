"use strict";
const fs=require("node:fs"),test=require("node:test"),assert=require("node:assert/strict");
const workflow=fs.readFileSync(".github/workflows/pandora-ux-regression.yml","utf8");
const taps=fs.readFileSync("apps/pandora-mobile/test/features/simple/pandora_picker_tap_through_test.dart","utf8");
const laneH=fs.readFileSync("apps/pandora-mobile/test/goldens/lane_h_chat_picker_visual_evidence_test.dart","utf8");

test("Lane H goldens are compared to committed PNGs instead of regenerated in CI",()=>{
  assert.doesNotMatch(workflow,/--update-goldens/);
  assert.match(workflow,/lane_h_landing_resting_390x844/);
  assert.match(workflow,/lane_h_keyboard_open_390x844/);
  assert.match(workflow,/lane_h_after_send_thinking_390x844/);
  assert.match(workflow,/lane_h_picker_open_390x844/);
  assert.match(workflow,/lane_h_picker_end_390x844/);
  assert.match(workflow,/lane_h_non_auto_tag_390x844/);
  assert.match(laneH,/matchesGoldenFile\('owner_screens\/\$name\.png'\)/);
});
test("unified model and reasoning picker has tap-through widget coverage",()=>{
  assert.match(taps,/model picker taps through to exact manual selection/);
  assert.match(taps,/reasoning picker taps through to Deep/);
  assert.match(taps,/model-picker-fixture\.gemma-3-4b/);
  assert.match(taps,/reasoning-picker-deep/);
  assert.match(workflow,/pandora_picker_tap_through_test\.dart/);
});
