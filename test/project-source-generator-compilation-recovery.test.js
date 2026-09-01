const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');

test('source generator compiles ProjectSpec before admitting a live source stream', () => {
  assert.match(source, /pandora-project-spec-compiler/);
  assert.match(source, /pandora_project_intents/);
  assert.match(source, /pandora_project_spec_compilations/);
  assert.match(source, /state: "working", stage: "understanding"/);
  assert.match(source, /attempt_count/);

  const compilerAt = source.lastIndexOf('pandora-project-spec-compiler');
  const retrySpecAt = source.indexOf('const retry = await admin.from("pandora_project_specs")');
  const admissionAt = source.indexOf('pandora_admit_authorized_build_service_v1');
  const dispatchAt = source.indexOf('runtime.waitUntil(runGenerationInBackground');
  const backgroundAdapterAt = source.indexOf('const adapter = chooseAdapter(input.spec)');

  assert.ok(compilerAt > 0, 'compiler retry must exist');
  assert.ok(retrySpecAt > compilerAt, 'active ProjectSpec must be re-read after compiler success');
  assert.ok(admissionAt > retrySpecAt, 'durable BuildJob/stream/queue admission must not occur before ProjectSpec admission');
  assert.ok(dispatchAt > admissionAt, 'optional background source generation must start only after durable admission');
  assert.ok(!source.includes('pandora_build_stream_sessions").insert'), 'Edge request must not create the authoritative stream session directly');
  assert.ok(backgroundAdapterAt > 0, 'background generation must choose its adapter from the admitted ProjectSpec');
});
