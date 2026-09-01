'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'pandora-intelligence-chat', 'index.ts'), 'utf8');

test('Kimi Edge config supports a bounded deterministic canary percentage', () => {
  assert.match(source, /canaryPercent=Number\(txt\(m\.canary_percent,"0"\)\)/);
  assert.match(source, /canaryPercent<0\|\|canaryPercent>100/);
  assert.match(source, /function cohortPercent\(seed:string\)/);
  assert.match(source, /return hash%100/);
});

test('only the selected preferred-task cohort receives Kimi first', () => {
  assert.match(source, /preferredTask=kimiOk&&cfg\.preferredTasks\.includes\(task\),preferKimi=preferredTask&&cohortPercent\(seed\)<cfg\.canaryPercent/);
  assert.match(source, /if\(preferKimi\)add\("kimi",cfg\.model\);for\(const m of nextGeminiModels\(geminiModel\)\)add\("gemini",m\);if\(kimiOk&&!preferredTask\)add\("kimi",cfg\.model\)/);
});

test('cohort seed is stable per organization and thread', () => {
  assert.match(source, /candidates\(route,cfg,task,geminiModel,`\$\{c\.organizationId\}:\$\{tid\}`\)/);
});
