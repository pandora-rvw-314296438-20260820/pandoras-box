"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const test=require("node:test");
const root=path.join(__dirname,"..");
const manifest=JSON.parse(fs.readFileSync(path.join(root,"docs/status/SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_20261002.json"),"utf8"));
test("2026-10-02 provider-only migration identities are represented in source",()=>{
  assert.equal(manifest.projectRef,"jcyqixttuebxqqfkjonq");
  assert.equal(manifest.repository,"pandora-rvw-314296438-20260820/pandoras-box");
  assert.equal(manifest.providerHistoryMutated,false);
  assert.equal(manifest.productionLiveSchemaReplayed,false);
  assert.equal(manifest.entries.length,manifest.remoteOnlyCount);
  assert.equal(new Set(manifest.entries.map(x=>x.version)).size,manifest.entries.length);
  for(const entry of manifest.entries){
    assert.match(entry.version,/^\\d{14}$/);
    assert.match(entry.originalSqlSha256,/^[0-9a-f]{64}$/);
    const file=path.join(root,"supabase","migrations",entry.version+"_"+entry.name+".sql");
    assert.ok(fs.existsSync(file),file);
    const source=fs.readFileSync(file,"utf8");
    if(entry.replayMode==="history_receipt_noop"){
      const executable=source.split(/\\r?\\n/).map(x=>x.trim()).filter(x=>x&&!x.startsWith("--"));
      assert.deepEqual(executable,["select 1;"],file);
      assert.match(source,/history_receipt_noop/);
    }else{
      assert.equal(entry.replayMode,"provider_exact_executable");
      assert.doesNotMatch(source,/history_receipt_noop/);
      assert.ok(source.trim().length>0);
    }
  }
});
