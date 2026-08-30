const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const runtimePath = path.join(__dirname, '..', 'supabase', 'functions', 'pandora-project-runtime', 'index.ts');

test('project runtime rate limiting stays behind the service boundary', () => {
  const source = fs.readFileSync(runtimePath, 'utf8');
  assert.match(source, /serviceClient\(\)\.rpc\("consume_runtime_rate_limit"/);
  assert.doesNotMatch(source, /context\.client\.rpc\("consume_runtime_rate_limit"/);
});
