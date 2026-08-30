
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync('supabase/functions/pandora-project-runtime/index.ts', 'utf8');

test('project runtime accepts full customer briefs up to compiler capacity', () => {
  assert.match(source, /objective\.length < 10 \|\| objective\.length > 50000/);
  assert.doesNotMatch(source, /objective\.length < 10 \|\| objective\.length > 6000/);
});
