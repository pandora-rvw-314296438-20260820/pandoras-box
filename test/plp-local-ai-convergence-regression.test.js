const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const buildScript = fs.readFileSync(
  path.join(root, '.devcontainer', 'build-phone-local-apk.sh'),
  'utf8',
);
const localAi = fs.readFileSync(
  path.join(
    root,
    'apps',
    'pandora-mobile',
    'platform',
    'android',
    'app',
    'src',
    'main',
    'kotlin',
    'com',
    'banataosystems',
    'pandora_mobile',
    'PandoraLocalAiChannel.kt',
  ),
  'utf8',
);

test('phone-local Android bootstrap is single-copy and initializes SPIR-V/JAVA deterministically', () => {
  assert.doesNotMatch(buildScript, /cmakeexport PATH/);
  assert.equal((buildScript.match(/SPIRV_CONFIG=/g) || []).length, 1);
  assert.equal((buildScript.match(/BUILD_DONE=1/g) || []).length, 1);
  assert.match(
    buildScript,
    /find \/usr -type f -name SPIRV-HeadersConfig\.cmake -print -quit/,
  );
  assert.match(buildScript, /export PANDORA_SPIRV_HEADERS_DIR=/);
  assert.match(buildScript, /export JAVA_HOME=/);
});

test('each local generation clears stale backend and accelerator verification state', () => {
  const anchor = 'lastGenerationErrorMessage = null';
  const start = localAi.indexOf(anchor);
  assert.ok(start >= 0, 'generation reset anchor missing');
  const reset = localAi.slice(start, start + 420);
  assert.match(reset, /lastGenerationBackend = null/);
  assert.match(reset, /lastGenerationGpuLayers = null/);
  assert.match(reset, /acceleratorVerifiedByGeneration = false/);
  assert.match(reset, /lastGenerationOutcome = "running"/);
});
