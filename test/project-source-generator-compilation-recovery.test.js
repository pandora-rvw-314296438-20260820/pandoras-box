const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');

test('source generator retries governed ProjectSpec compilation before build generation', () => {
  assert.match(source, /pandora-project-spec-compiler/);
  assert.match(source, /pandora_project_intents/);
  assert.match(source, /pandora_project_spec_compilations/);
  assert.match(source, /state: "working", stage: "understanding"/);
  assert.match(source, /attempt_count/);

  const compilerAt = source.indexOf('pandora-project-spec-compiler');
  const retrySpecAt = source.indexOf('const retry = await admin.from("pandora_project_specs")');
  const adapterAt = source.indexOf('const adapter = chooseAdapter(rec(spec))');
  assert.ok(compilerAt > 0, 'compiler retry must exist');
  assert.ok(retrySpecAt > compilerAt, 'active ProjectSpec must be re-read after compiler success');
  assert.ok(adapterAt > retrySpecAt, 'source adapter selection must remain behind the ProjectSpec gate');
});
