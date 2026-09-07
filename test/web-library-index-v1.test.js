const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const root=path.resolve(__dirname,'..');
const read=(...parts)=>fs.readFileSync(path.join(root,...parts),'utf8');

const api=read('apps','meta-business-mcp','src','operator','api.js');
const index=read('apps','meta-business-mcp','src','operator','library-index.js');
const app=read('apps','control-tower','owner-app.js');
const professional=read('apps','control-tower','owner-professional.js');

test('Library route is same-origin operator read authority',()=>{
  assert.match(api,/router\.get\('\/library'/);
  assert.match(api,/libraryIndexExecutor/);
  assert.match(api,/if \(request\.method === 'GET'\)\s*return 'projectos:read'/);
  assert.match(app,/request\('\/library\?limit=100'\)/);
  assert.doesNotMatch(app,/supabase\.co|\/rest\/v1\/pandora_artifact/);
});

test('Library index uses human bearer and member-RLS tables with hard limits',()=>{
  assert.match(index,/identity\?\.accessToken/);
  assert.match(index,/SupabaseRestClient/);
  assert.match(index,/pandora_artifact_versions\?select=/);
  assert.match(index,/pandora_project_versions\?select=/);
  assert.match(index,/projectos_projects\?select=id,name,repository/);
  assert.match(index,/n>=1&&n<=100/);
  assert.match(index,/limit=200/);
});

test('Library response never includes storage internals or bytes',()=>{
  assert.doesNotMatch(index,/storage_path|source_payload|provenance_redacted|provider_deployment_id|htmlBase64|artifactBytes/i);
  assert.doesNotMatch(professional,/data:text|blob:|download=/i);
  assert.ok(professional.includes('Artifact download remains outside this bounded contract.'));
});

test('Library exposes only safe immutable metadata and release lineage',()=>{
  for(const token of ['logicalKey','artifactKind','byteSize','mediaType','sha256','lifecycleStatus','sourceCommit','artifactDigest']){
    assert.ok(index.includes(token),token);
  }
  assert.match(professional,/Immutable artifact versions/);
  assert.match(professional,/Project version lineage/);
});
