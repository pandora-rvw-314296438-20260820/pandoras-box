const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..'),read=file=>fs.readFileSync(path.join(root,file),'utf8');
const api=read('apps/meta-business-mcp/src/operator/api.js');
const change=read('apps/meta-business-mcp/src/operator/project-change.js');
const auth=read('apps/control-tower/auth.js');
const data=read('apps/control-tower/owner-data.js');
const preview=read('apps/control-tower/owner-preview-focus.js');
const workspace=read('apps/control-tower/owner-project-workspace.js');
const app=read('apps/control-tower/owner-app.js');
const first=read('apps/control-tower/owner-first.js');
const index=read('apps/control-tower/index.html');

test('web preview is authenticated and sandboxed while privileged build functions stay server-only',()=>{
  assert.match(auth,/pandora-preview-content/);
  assert.doesNotMatch(auth,/ALLOWED_EDGE_FUNCTIONS[^\n]+pandora-project-spec-compiler/);
  assert.doesNotMatch(auth,/ALLOWED_EDGE_FUNCTIONS[^\n]+pandora-project-source-generator/);
  assert.match(app,/hydrateExactWorkspacePreview/);
  assert.match(preview,/setAttribute\('sandbox', 'allow-scripts'\)/);
  assert.match(preview,/new MessageChannel\(\)/);
  assert.match(preview,/connect-src 'none'/);
  assert.doesNotMatch([auth,preview,app].join('\n'),/Github_supabase|SUPABASE_SERVICE_ROLE|PRIVATE KEY|gemini_api_key|openai_api_key|moonshot_api_key/i);
});
test('FocusToken v2 is checked on the server against exact visible artifact lineage',()=>{
  assert.match(change,/schemaVersion!==2/);
  assert.match(change,/15\*60\*1000/);
  assert.match(change,/pandora_project_versions/);
  assert.match(change,/artifact_digest_sha256/);
  assert.match(change,/candidate_verification_state/);
  assert.match(change,/FOCUS_TOKEN_STALE/);
  assert.match(change,/Apply the owner change specifically to this exact selected object/);
});
test('project change is owner-admin and projectos execute scoped',()=>{
  assert.match(api,/createProjectChangeHandler/);
  assert.match(api,/projects\\/\\[0-9a-f-\\]\\+\\/change/);
  assert.match(api,/projectos:execute/);
  assert.match(api,/EXECUTOR_ROLE_REQUIRED/);
  assert.match(change,/Only an owner or admin may change a project/);
});
test('durable change lineage is intent to exact active spec to governed build admission',()=>{
  assert.match(change,/pandora_project_intents/);
  assert.match(change,/intent_kind:"change"/);
  assert.match(change,/pandora-project-spec-compiler/);
  assert.match(change,/source_intent_id/);
  assert.match(change,/pandora-project-source-generator/);
  assert.match(app,/admitProjectChange/);
  assert.match(app,/waitForProjectChangeResolution/);
});
test('old preview remains visible until exact verified candidate is hydrated',()=>{
  assert.match(app,/candidate_verification_state/);
  assert.match(app,/previewBundle\?\.versionId === candidate/);
  assert.match(app,/Your previous verified result remains current/);
  assert.match(workspace,/data-owner-preview-host/);
  assert.match(workspace,/Focus object/);
});
test('focus assets retain the canonical revision',()=>{
  const revision='web-focus-loop-v1-20260907-1';
  assert.ok(first.includes(revision));assert.ok(first.indexOf('owner-preview-focus.js')<first.indexOf('owner-project-workspace.js'));assert.ok(index.includes(revision));assert.ok(data.includes('focusToken: null'));
});
