"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const source = fs.readFileSync(path.join(process.cwd(), "supabase/functions/pandora-project-spec-compiler/index.ts"), "utf8");

test("Gemini compiler prompt exactly matches the validator nested ProjectSpec contract", () => {
  assert.match(source, /project-spec-compiler-v2/);
  assert.match(source, /business=\{objective:string/);
  assert.match(source, /product=\{projectType:string,users\?:string\[\],roles\?:string\[\],workflows\?:string\[\],features\?:string\[\]/);
  assert.match(source, /acceptance=\{functional:string\[\],business\?:string\[\]\}/);
  assert.match(source, /Do not substitute alternate field names/);
  assert.match(source, /do not put objects inside fields defined as string arrays/i);
});
