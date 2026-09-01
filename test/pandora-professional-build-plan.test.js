"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const plan = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/professional_build_plan.dart"),
  "utf8",
);
const createUi = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/project_create_experience.dart"),
  "utf8",
);
const conversation = fs.readFileSync(
  path.join(process.cwd(), "apps/pandora-mobile/lib/features/simple/project_build_conversation.dart"),
  "utf8",
);

test("professional plan is grounded in the compiled ProjectSpec projection", () => {
  assert.match(plan, /understanding\.intentSummary/);
  assert.match(plan, /understanding\.businessSummary/);
  assert.match(plan, /understanding\.targetUsers/);
  assert.match(plan, /understanding\.projectType/);
  assert.match(plan, /understanding\.requirements\.take\(7\)/);
  assert.match(plan, /understanding\.objectives\.take\(3\)/);
});

test("professional plan presents an attractive but truthful product proposal", () => {
  assert.match(plan, /PANDORA’S BUILD PLAN/);
  assert.match(plan, /Why this is worth building/);
  assert.match(plan, /Your first working version/);
  assert.match(plan, /Success looks like/);
  assert.match(plan, /What happens when you tap Build it/);
  assert.match(plan, /writes the real source code for this plan/);
  assert.match(plan, /compiles and checks the working version/);
  assert.match(plan, /before anything is published/);
  assert.doesNotMatch(plan, /guaranteed|increase revenue|boost sales|10x|instant success/i);
});

test("the proposal is shown before build and preserved in conversation history", () => {
  assert.match(createUi, /PandoraProfessionalBuildPlan\(understanding: u!\)/);
  assert.match(createUi, /Ready to see it become real\?/);
  assert.match(createUi, /starts writing the real code immediately/);
  assert.doesNotMatch(createUi, /requirements\.take\(4\)/);
  assert.match(conversation, /PandoraProfessionalBuildPlan\([\s\S]*understanding: widget\.understanding,[\s\S]*showDeliveryPromise: false/);
  assert.doesNotMatch(conversation, /class _PandoraProposal extends StatelessWidget/);
});
