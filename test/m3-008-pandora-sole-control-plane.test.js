'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const read = (p) => fs.readFileSync(p, 'utf8');
const retired = 'project' + 'os';

test('active entrypoints are Pandora-native', () => {
  const forbidden = new RegExp(
    retired + '-mcp-handler|' + retired + '-container-server|MCPMASTER_CONTAINER_MODE=' + retired,
    'i',
  );
  for (const p of ['api/mcp.ts', 'vercel-entrypoint.js', 'src/container-entrypoint.js', 'Dockerfile']) {
    assert.doesNotMatch(read(p), forbidden, p);
  }
});

test('skill mutation authority belongs to Pandora Runtime Tool Gateway', () => {
  const source = read('.agents/runtime/pandora-skill-runtime.mjs');
  assert.match(source, /pandora-runtime-tool-gateway/);
  assert.doesNotMatch(source, new RegExp(retired + '-governed', 'i'));
});

test('retired predecessor implementation is absent from active source', () => {
  assert.equal(fs.existsSync('src/' + retired + '-mcp-handler.js'), false);
  assert.equal(fs.existsSync('src/' + retired + '-container-server.js'), false);
});
