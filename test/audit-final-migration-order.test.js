'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const dir = 'supabase/migrations';
const finalizer = '20260925090001_pandora_authorization_replay_finalizer.sql';
test('authorization finalizer follows every authoritative protected function definition', () => {
  assert.ok(fs.existsSync(path.join(dir, finalizer)));
  const protectedDefinition = /create\s+(?:or\s+replace\s+)?function\s+public\.(?:pandora_chat_capability_dispatch_native_v1|pandora_chat_universal_dispatch_v9|pandora_meta_oauth_prepare_v1|pandora_tax_guard_rule_support_mutation_v1)\s*\(/i;
  for (const name of fs.readdirSync(dir).filter((name) => name.endsWith('.sql'))) {
    if (name === finalizer) continue;
    const source = fs.readFileSync(path.join(dir, name), 'utf8');
    if (protectedDefinition.test(source)) assert.ok(name < finalizer, `Protected definition ${name} would override final authorization guards`);
  }
});
