"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const base = "ops/supabase/runtime-patches/pandora-owner-api-v76-base44-build-theatre";
const manifest = JSON.parse(fs.readFileSync(base + "/manifest.json", "utf8"));
const index = fs.readFileSync(base + "/index.ts", "utf8");

test("bounded Owner API artifact is pinned to provider v76 and canonical PR #487", () => {
  assert.equal(manifest.provider.functionSlug, "pandora-owner-api");
  assert.equal(manifest.provider.baselineVersion, 76);
  assert.equal(manifest.provider.baselineSourceHash, "87b942a56305c0696e32f9f7ebc591aaef7e43238ccceb5dc9998d3a1a13700d");
  assert.equal(manifest.provider.verifyJwt, true);
  assert.equal(manifest.canonicalDelta.pullRequest, 487);
  assert.equal(manifest.canonicalDelta.mainSha, "74d7ade3465c955c8ef9f74eb99ab04047e6691f");
  assert.equal(manifest.files.filter((item) => item.changedFromProviderBaseline).length, 1);
  assert.equal(manifest.files.find((item) => item.name === "index.ts").blob, "285b10e929defc700fceb16a9e393592ffd37e2c");
});

test("bounded artifact always exposes truthful idle Build Theatre state", () => {
  assert.match(index, /BUILD_THEATRE_STAGE_CONTRACT/);
  assert.match(index, /source: "pandora_project_experience_projection",[\s\S]*mode: "idle"/);
  assert.match(index, /mode: "idle"[\s\S]*ownerStage: null,[\s\S]*progressPercent: null/);
  assert.match(index, /"What do you want to build\?"/);
});

test("active Build Theatre values come only from canonical theatre projection", () => {
  assert.match(index, /from\("pandora_build_theatre_projection"\)/);
  assert.match(index, /source: "pandora_build_theatre_projection"/);
  assert.match(index, /progressPercent: numberValue\(theatre\.progress_percent\)/);
  assert.match(index, /ownerStage: textValue\(theatre\.owner_stage\) \|\| null/);
  assert.match(index, /buildTheatre: buildTheatreSummary\(experience\.data, theatre\.data\)/);
});

test("artifact retains fail-closed JWT posture and contains no provider credential", () => {
  assert.doesNotMatch(index, /github_pat_|ghp_|sk-proj-|service_role\s*[:=]\s*["'][A-Za-z0-9._-]{20,}/i);
  assert.equal(manifest.provider.verifyJwt, true);
});
