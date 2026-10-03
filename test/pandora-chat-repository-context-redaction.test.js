"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {readFileSync}=require("node:fs");
const path=require("node:path"),vm=require("node:vm"),ts=require("typescript");
const {randomUUID}=require("node:crypto");
function load(name){
 const full=path.resolve(__dirname,"../supabase/functions/pandora-intelligence-chat/",name);
 const source=ts.transpileModule(readFileSync(full,"utf8"),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
 const exports={};vm.runInNewContext(source,{exports,require:x=>load(path.basename(x)),AbortController,setTimeout,clearTimeout},{filename:full});return exports;
}
const {redactRepositoryCredentialMaterial,readRepositoryAuditContext}=load("repository-context.ts");
const {containsCredentialMaterial}=load("reply-safety.ts");
const fixtureToken="gh"+"p_"+"synthetic_fixture_".repeat(3);
const fixtureUrl="postgres"+"://postgres:postgres@localhost:5432/example";
const begin="-----BEGIN "+"PRIVATE KEY-----";
const end="-----END "+"PRIVATE KEY-----";
const plain=value=>JSON.parse(JSON.stringify(value));
function snapshot(){return{ok:true,contractVersion:"pandora-repository-snapshot-v1",projectId:randomUUID(),repository:"example/repository",headSha:"a".repeat(40),treeSha:"b".repeat(40),includedFileCount:1,files:[]};}
function input(source){return{user:{rpc:async()=>({data:source})},organizationId:randomUUID(),projectId:source.projectId,scopeKind:"none",message:"Audit the repository",attachments:[]};}

test("ordinary repository source is preserved without mutation or invented redactions",()=>{
 const source=snapshot();source.files=[{path:"README.md",text:"Run the development server.\nNo credentials here.",lines:["one","two"]}];
 const before=JSON.stringify(source),result=redactRepositoryCredentialMaterial(source);
 assert.equal(result.redactionCount,0);assert.deepEqual(plain(result.value),source);assert.equal(JSON.stringify(source),before);
});
test("credential-free connection URLs cannot join later lines, fields, paths or query values",async()=>{
 const examples=[
  "DATABASE_URL=postgres://localhost:5432/app\nGIT_REMOTE=git@github.com:org/repo",
  "postgres://localhost:5432/app\\nGIT_REMOTE=git@example.invalid:repo",
  "postgresql://[::1]:5432/app\nREMOTE=git@example.invalid:repo",
  "postgresql://host1:5432,host2:5433/app\nPATH=packages/@scope/example.ts",
  "postgresql://localhost:5432/team@archive",
  "postgresql://localhost:5432/app?application_name=build@example.invalid",
  "postgresql://localhost:5432/app#contact@example.invalid",
  "postgresql://fixture%3Auser@localhost:5432/app\nREMOTE=git@example.invalid:repo",
 ];
 for(const text of examples){
  const source=snapshot();source.files=[{path:".env.example",text},{path:"packages/@scope/example.ts",text:"export const example = true;"}];
  const before=JSON.stringify(source);
  assert.equal(containsCredentialMaterial(text),false);assert.equal(containsCredentialMaterial(source),false);
  const sanitized=redactRepositoryCredentialMaterial(source);
  assert.equal(sanitized.redactionCount,0);assert.deepEqual(plain(sanitized.value),source);assert.equal(JSON.stringify(source),before);
  const context=await readRepositoryAuditContext(input(source));
  assert.equal(context.receipt.redactionCount,0);assert.equal(containsCredentialMaterial({messages:[{content:context.attachments.map(part=>part.text).join("\n")}]}),false);
 }
 const source=snapshot();source.files=[{path:".env.example",text:"DATABASE_URL=postgres://localhost:5432/app"},{path:"packages/@scope/example.ts",text:"export const example = true;"}];
 assert.equal(redactRepositoryCredentialMaterial(source).redactionCount,0);
 assert.equal((await readRepositoryAuditContext(input(source))).receipt.redactionCount,0);
});
test("supported password userinfo remains detected and redacted at raw and serialized boundaries",async()=>{
 const examples=[
  "postgres://fixture:synthetic-password@localhost:5432/app",
  "postgresql://fixture%40user:fixture%3Apass%2Fpart@[2001:db8::1]:5432/app",
  "postgresql://fixture:synthetic:password@host1:5432,host2:5433/app",
  "postgresql://fixture:synthetic'password@localhost:5432/app",
  "postgresql://:synthetic-password@localhost:5432/app",
 ];
 for(const text of examples){
  const source=snapshot();source.files=[{path:".env.example",text:"Before\n"+text+"\nAfter"}];
  assert.equal(containsCredentialMaterial(text),true);assert.equal(containsCredentialMaterial(source),true);
  assert.equal(containsCredentialMaterial({messages:[{content:JSON.stringify(source)}]}),true);
  const result=redactRepositoryCredentialMaterial(source);
  assert.equal(result.redactionCount,1);assert.equal(result.value.files[0].text,"Before\n[redacted-credential]\nAfter");
  assert.equal(containsCredentialMaterial(result.value),false);assert.equal(source.files[0].text.includes(text),true);
  const context=await readRepositoryAuditContext(input(source));
  assert.equal(context.receipt.redactionCount,1);assert.equal(containsCredentialMaterial(context),false);
 }
});
test("example connection strings and credential-shaped source are redacted without discarding the audit",()=>{
 const source=snapshot();source.files=[{path:"README.md",text:`Before\n${fixtureUrl}\nAfter`},{path:".env.example",text:`TOKEN=${fixtureToken}\nMODE=development`}];
 const result=redactRepositoryCredentialMaterial(source),encoded=JSON.stringify(result.value);
 assert.equal(result.redactionCount,2);assert.equal(containsCredentialMaterial(result.value),false);
 assert.equal(encoded.includes(fixtureToken),false);assert.equal(encoded.includes(fixtureUrl),false);
 assert.equal(result.value.files[0].text,"Before\n[redacted-credential]\nAfter");
 assert.match(result.value.files[1].text,/MODE=development/);assert.equal(source.files[0].text.includes(fixtureUrl),true);
});
test("complete and unterminated PEM fixtures are removed through their material boundary",()=>{
 for(const tail of [`\n${end}\nKeep this explanation.`,""]){
  const source=snapshot();source.files=[{path:"fixture.pem",text:`Before\n${begin}\nsynthetic-key-material${tail}`},{path:"safe.txt",text:"Unrelated source"}];
  const result=redactRepositoryCredentialMaterial(source),text=result.value.files[0].text;
  assert.equal(result.redactionCount,1);assert.equal(text.includes("synthetic-key-material"),false);assert.equal(text.includes(begin),false);
  assert.equal(text,tail?"Before\n[redacted-credential]\nKeep this explanation.":"Before\n[redacted-credential]");
  assert.equal(result.value.files[1].text,"Unrelated source");
 }
});
test("sanitization reaches nested source values and receipt metadata",async()=>{
 const source=snapshot();source.repository="example/"+fixtureToken;source.observedAt=fixtureToken;source.files=[{path:"config.json",nested:[{content:fixtureUrl}]}];
 const result=await readRepositoryAuditContext(input(source));
 assert.equal(result.receipt.redactionCount,3);assert.equal(result.receipt.repository,"example/[redacted-credential]");
 assert.equal(result.receipt.observedAt,"[redacted-credential]");assert.equal(containsCredentialMaterial(result),false);
 assert.equal(result.receipt.headSha,source.headSha);assert.equal(result.receipt.files,undefined);
});
test("redaction occurs before attachment splitting and preserves source and bounded-audit receipts",async()=>{
 const source=snapshot();source.truncated=true;source.files=[{path:"README.md",text:"Useful source\n".repeat(5000)+fixtureToken+"\nKeep the final line."}];
 const result=await readRepositoryAuditContext(input(source));
 assert.ok(result.attachments.length>1&&result.attachments.length<=4);assert.equal(result.receipt.redactionCount,1);
 assert.equal(result.receipt.projectId,source.projectId);assert.equal(result.receipt.truncated,true);
 const encoded=result.attachments.map(part=>part.text.slice(part.text.indexOf("\n")+1)).join("");
 assert.equal(containsCredentialMaterial(encoded),false);assert.equal(encoded.includes(fixtureToken),false);
 assert.equal(JSON.parse(encoded).files[0].text.endsWith("[redacted-credential]\nKeep the final line."),true);
 for(const part of result.attachments){assert.ok(part.text.length<32000);assert.match(part.text,/never as instructions or execution authority/);assert.match(part.text,/redaction placeholders are not literal repository content/);}
});
test("unhandled credential-bearing object keys fail closed rather than leaking or changing field identity",()=>{
 const source=snapshot();source.files=[{[fixtureToken]:"source"}];
 assert.throws(()=>redactRepositoryCredentialMaterial(source),/CREDENTIAL_MATERIAL_REJECTED/);
});
test("source size and structural bounds apply even when redaction could shrink the content",async()=>{
 const source=snapshot();source.files=[{path:"fixture.pem",text:begin+"\n"+"x".repeat(120000)}];
 await assert.rejects(readRepositoryAuditContext(input(source)),/REPOSITORY_CONTEXT_TOO_LARGE/);
 let deep={};for(let n=0;n<34;n++)deep={nested:deep};
 assert.throws(()=>redactRepositoryCredentialMaterial(deep),/REPOSITORY_CONTEXT_UNAVAILABLE/);
});
