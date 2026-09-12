
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  'supabase/migrations/20260912092000_correct_archived_memory_repository_binding_v1.sql',
  'utf8',
);

test('archived Memory binding moves only from the obsolete owner to canonical Pandora authority', () => {
  assert.match(migration, /0306198e-38e5-4b1d-8932-efd58da3b856/);
  assert.match(migration, /project_key = 'pandoras-box-memory'/);
  assert.match(migration, /status = 'archived'/);
  assert.match(migration, /banataosystems\/pandoras-box-memory/);
  assert.match(
    migration,
    /pandora-rvw-314296438-20260820\/pandoras-box-memory/,
  );
  assert.match(migration, /repositoryAuthorityCorrection/);
  assert.match(migration, /previousRepository/);
  assert.match(migration, /sourceTask', 'CHAT-FINISH-002'/);
  assert.doesNotMatch(migration, /status\s*=\s*'active'/);
  assert.doesNotMatch(migration, /delete\s+from\s+public\.projectos_projects/i);
});

test('unexpected repository authority fails closed instead of being overwritten', () => {
  assert.match(migration, /refused unexpected Memory repository binding/);
  assert.match(migration, /elsif v_repository <> 'pandora-rvw-314296438-20260820\/pandoras-box-memory'/);
});
