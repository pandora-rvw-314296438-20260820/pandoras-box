"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const test=require("node:test");
const root=path.join(__dirname,"..");
const manifest=JSON.parse(fs.readFileSync(path.join(root,"docs/status/SUPABASE_REMOTE_MIGRATION_HISTORY_PARITY_20261002_RECEIPTS.json"),"utf8"));
test("provider migration identities are represented by non-replaying receipts",()=>{
  assert.equal(manifest.providerHistoryMutated,false);
  assert.equal(manifest.productionLiveSchemaReplayed,false);
  assert.equal(manifest.providerSqlBodiesCopied,false);
  assert.equal(manifest.schemaEffectParityProven,false);
  assert.equal(manifest.entries.length,manifest.remoteOnlyCount);
  for(const entry of manifest.entries){
    const file=path.join(root,"supabase","migrations",entry.version+"_"+entry.name+".sql");
    assert.ok(fs.existsSync(file),file);
    const src=fs.readFileSync(file,"utf8");
    const executable=src.split(/\r?\n/).map(x=>x.trim()).filter(x=>x&&!x.startsWith("--"));
    assert.deepEqual(executable,["select 1;"],file);
    assert.match(src,/history_receipt_noop/);
    assert.match(entry.originalSqlSha256,/^[0-9a-f]{64}$/);
  }
});
