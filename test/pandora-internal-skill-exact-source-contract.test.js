const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migration = readFileSync(
  join(__dirname, '../supabase/migrations/20260912101000_pandora_internal_skill_exact_source_allowlist_v1.sql'),
  'utf8',
);

test('Worker E keeps the existing trusted mirrors and adds only canonical Pandora skill files', () => {
  assert.match(migration, /pandora-rvw-314296438-20260820\/awesome-claude-skills/);
  assert.match(migration, /pandora-rvw-314296438-20260820\/the-book-of-secret-knowledge/);
  assert.match(migration, /pandora-rvw-314296438-20260820\/pandoras-box/);
  assert.match(migration, /\^\\\.agents\/skills\/\[A-Za-z0-9\._-\]\+\/SKILL\\\.md\$/);
  assert.match(migration, /canonical Pandora source path is outside the trusted skill allowlist/);
});

test('exact-source locator remains pinned, traversal-safe, bounded, and byte-hashed', () => {
  assert.match(migration, /\^\[0-9a-f\]\{40\}\$/);
  assert.match(migration, /p_path like '%\.\.%'/);
  assert.match(migration, /p_path like '\/%'/);
  assert.match(migration, /octet_length\(v_text\)>350000/);
  assert.match(migration, /digest\(convert_to\(v_text,'UTF8'\),'sha256'\)/);
  assert.match(migration, /raw\.githubusercontent\.com/);
});

test('Worker E exact-source helper remains database-administrator only', () => {
  assert.match(migration, /revoke all on function private\.pandora_worker_e_exact_source_v2\(text,text,text\) from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function private\.pandora_worker_e_exact_source_v2\(text,text,text\) to postgres/);
  assert.doesNotMatch(migration, /grant execute[\s\S]*to authenticated/);
  assert.doesNotMatch(migration, /grant execute[\s\S]*to service_role/);
});
