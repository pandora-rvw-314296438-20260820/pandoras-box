const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260829125000_pandora_build_authorization_acl_v1.sql'), 'utf8');
const generator = fs.readFileSync(path.join(root, 'supabase/functions/pandora-project-source-generator/index.ts'), 'utf8');

test('build status ACL denies PUBLIC/anon and preserves authenticated owner reads', () => {
  assert.match(migration, /revoke all on function public\.pandora_project_build_status_20260829\(uuid\) from public, anon;/i);
  assert.match(migration, /grant execute on function public\.pandora_project_build_status_20260829\(uuid\) to authenticated, service_role;/i);
});

test('generated build intake records exact Worker C request_build authorization', () => {
  assert.match(generator, /pandora_commit_generated_build_intake_v2_20260829/);
  assert.match(migration, /pandora_authorize_generated_build_20260829/);
  assert.match(migration, /'request_build','1','request_build','preview','BuildExecutor'/);
  assert.match(migration, /'pandora-tool-policy\/1\.1\.0'/);
  assert.match(migration, /'LOW','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY','REQUIRED'/);
  assert.match(migration, /'tool','request_build@1','capability','build\.execute'/);
});

test('Worker D claim fails closed without matching tool call and policy action', () => {
  assert.match(migration, /join public\.pandora_policy_actions p on p\.tool_call_id=t\.id/);
  assert.match(migration, /t\.build_job_id=j\.id/);
  assert.match(migration, /t\.project_version_id=j\.target_project_version_id/);
  assert.match(migration, /p\.disposition='ALLOW'/);
  assert.match(migration, /build job lacks exact Worker C authorization/);
});

test('authorization migration contains no credential-shaped literals', () => {
  assert.doesNotMatch(migration, /github_pat_|gh[pousr]_|AIza[0-9A-Za-z_-]{20,}|BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY/);
});
