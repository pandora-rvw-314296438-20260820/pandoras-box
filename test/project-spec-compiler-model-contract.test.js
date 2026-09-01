"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const source = fs.readFileSync(path.join(process.cwd(), "supabase/functions/pandora-project-spec-compiler/index.ts"), "utf8");

test("Gemini compiler prompt exactly matches the validator nested ProjectSpec contract", () => {
  assert.match(source, /project-spec-compiler-v5/);
  assert.match(source, /business=\{objective:string/);
  assert.match(source, /product=\{projectType:string,users\?:string\[\],roles\?:string\[\],workflows\?:string\[\],features\?:string\[\],screens\?:string\[\],userStories\?:string\[\],productPromise:string,audiences:string\[\],customerValue:string,ownerValue:string,coreExperiences:string\[\],firstVersionCapabilities:string\[\],primaryWorkflows:string\[\]\}/);
  assert.match(source, /acceptance=\{functional:string\[\],business\?:string\[\],successCriteria:string\[\],reviewAssurance:string\}/);
  assert.match(source, /metadata=\{projectName:string,intentSummary:string\}/);
  assert.match(source, /metadata\.projectName must be a concise owner-facing name/);
  assert.match(source, /metadata\.intentSummary must be one concise owner-readable sentence/);
  assert.match(source, /product\.productPromise, product\.audiences, product\.customerValue, product\.ownerValue/);
  assert.match(source, /acceptance\.successCriteria/);
  assert.match(source, /acceptance\.reviewAssurance/);
  assert.match(source, /Do not substitute alternate field names/);
  assert.match(source, /do not put objects inside fields defined as string arrays/i);
});