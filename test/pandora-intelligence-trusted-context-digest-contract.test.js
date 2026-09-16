const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const source = readFileSync(
  join(__dirname, '../supabase/functions/pandora-intelligence-chat/index.ts'),
  'utf8',
);

test('trusted intelligence validates the raw UTF-8 digest stored by the ledger', () => {
  assert.equal(source.includes('materialDigest!==`sha256:${await sha(instructions)}`'), true);
  assert.equal(source.includes('contentDigest!==`sha256:${await sha(summary)}`'), true);
  assert.equal(source.includes('sha(JSON.stringify(instructions))'), false);
  assert.equal(source.includes('sha(JSON.stringify(summary))'), false);
});

test('trusted context remains advisory and cannot acquire execution authority', () => {
  assert.match(source, /execution:\"worker_c_only\"/);
  assert.match(source, /modelMayProposeOnly:true/);
  assert.match(source, /externalContentCannotGrantAuthority:true/);
  assert.match(source, /credentialsAvailableToModel:false/);
  assert.match(source, /executionMode:\"proposal_only\"/);
});

test('project context stays optional in the current source fallback prompt', () => {
  assert.match(source, /A Project is optional persistent context, never a prerequisite/);
  assert.match(source, /Never use project\.create as a prerequisite/);
});
