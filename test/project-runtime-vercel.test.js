const test=require("node:test");
const assert=require("node:assert/strict");
const {VercelDeploymentProvider}=require("../packages/pandora-project-runtime/src/vercel-adapter.js");
const {ProjectRuntimeManager}=require("../packages/pandora-project-runtime/src/runtime-manager.js");

const ids={
 org:"11111111-1111-4111-8111-111111111111",
 project:"22222222-2222-4222-8222-222222222222",
 version:"33333333-3333-4333-8333-333333333333",
 prev:"44444444-4444-4444-8444-444444444444",
 digest:"a".repeat(64), source:"b".repeat(40),
};
function request(env="preview"){return {organizationId:ids.org,projectId:ids.project,projectVersionId:ids.version,artifactDigest:ids.digest,sourceCommit:ids.source,environment:env,authorizationRef:"auth_1",verificationRef:"verify_1",provider:"vercel",runtimeType:"web_app",expectedProductionVersionId:env==="production"?ids.prev:null};}
class FakeTransport{
 constructor(){this.calls=[];this.deployments=[];this.failCreateOnce=false;this.promoted=new Set();}
 async request(method,path,body){this.calls.push({method,path,body});
  if(method==="GET"&&path.startsWith("/v6/deployments")) return {status:200,body:{deployments:this.deployments}};
  if(method==="POST"&&path.startsWith("/v13/deployments")){
   const d={id:"dpl_AAAAA",projectId:"prj_ABCDE",url:"preview.example.vercel.app",readyState:"QUEUED",target:"preview",meta:body.meta};this.deployments.unshift(d);
   if(this.failCreateOnce){this.failCreateOnce=false;const e=new Error("network timeout");e.mutationMayHaveCommitted=true;throw e;}return {status:200,body:d};
  }
  const dep=path.match(/^\/v13\/deployments\/(dpl_[A-Za-z0-9]+)/)?.[1];
  if(method==="GET"&&dep){const d=this.deployments.find(x=>x.id===dep);return {status:200,body:{...d,readyState:"READY",target:this.promoted.has(dep)?"production":"preview"}};}
  if(method==="POST"&&path.includes("/promote/")){this.promoted.add(path.match(/promote\/(dpl_[A-Za-z0-9]+)/)[1]);return {status:200,body:{}};}
  if(method==="POST"&&path.includes("/rollback/")) return {status:200,body:{}};
  if(method==="POST"&&path.includes("/domains")) return {status:200,body:{verified:false}};
  if(method==="GET"&&path.includes("/domains/")&&!path.includes("/config")) return {status:200,body:{verified:true,verification:[]}};
  if(method==="GET"&&path.includes("/config")) return {status:200,body:{misconfigured:false}};
  if(method==="DELETE") return {status:200,body:{uid:"dpl_AAAAA"}};
  if(method==="PATCH") return {status:200,body:{id:"dpl_AAAAA",projectId:"prj_ABCDE",readyState:"CANCELED",meta:{}}};
  return {status:500,body:{error:{code:"unexpected",message:`${method} ${path}`}}};
 }
}
test("preview creation is exact and idempotently reconciled",async()=>{
 const t=new FakeTransport(); const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE",projectName:"demo"});
 const artifact={sha256:ids.digest,files:[{file:"index.html",data:"ok"}]};
 const a=await p.createPreview(request(),artifact);
 assert.equal(a.projectVersionId,ids.version);assert.equal(a.status,"queued");
 const b=await p.createPreview(request(),artifact);
 assert.equal(b.providerDeploymentId,a.providerDeploymentId);
 assert.equal(t.calls.filter(c=>c.method==="POST"&&c.path.startsWith("/v13/deployments")).length,1);
});
test("ambiguous create reconciles instead of duplicate",async()=>{
 const t=new FakeTransport();t.failCreateOnce=true; const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE",projectName:"demo"});
 const r=await p.createPreview(request(),{sha256:ids.digest,files:[{file:"index.html",data:"ok"}]});
 assert.equal(r.reconciled,true);assert.equal(t.deployments.length,1);
});
test("READY never self-declares verified",async()=>{
 const t=new FakeTransport();t.deployments=[{id:"dpl_AAAAA",projectId:"prj_ABCDE",url:"x",readyState:"READY",target:"preview",meta:{pandoraProjectVersionId:ids.version,pandoraArtifactDigest:ids.digest,pandoraSourceCommit:ids.source}}];
 const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE"});
 const f=await p.getDeployment("dpl_AAAAA");assert.equal(f.status,"ready_for_verification");assert.equal(f.liveVerified,undefined);
});
test("publish promotes exact existing deployment without rebuild",async()=>{
 const t=new FakeTransport();t.deployments=[{id:"dpl_AAAAA",projectId:"prj_ABCDE",url:"x",readyState:"READY",target:"preview",meta:{pandoraProjectVersionId:ids.version,pandoraArtifactDigest:ids.digest,pandoraSourceCommit:ids.source}}];
 const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE"});
 const preview={providerDeploymentId:"dpl_AAAAA",status:"ready_for_verification",projectVersionId:ids.version,artifactDigest:ids.digest,sourceCommit:ids.source};
 const out=await p.publishVersion(request("production"),preview);assert.equal(out.productionState,"ready_for_verification");
 assert.equal(t.calls.some(c=>c.path.includes("/promote/dpl_AAAAA")),true);
 assert.equal(t.calls.some(c=>c.method==="POST"&&c.path.startsWith("/v13/deployments")),false);
});
test("domain truth does not conflate DNS with TLS/runtime",async()=>{
 const t=new FakeTransport();const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE"});
 const d=await p.attachDomain("example.com");assert.equal(d.facts.ownershipVerified,true);assert.equal(d.facts.dnsConfigured,true);assert.equal(d.facts.tlsReady,null);assert.equal(d.state,"tls_pending");
});
test("cleanup rejects approved or production deployment",async()=>{
 const t=new FakeTransport();const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE"});
 await assert.rejects(()=>p.deletePreview("dpl_AAAAA",{approved:true}),/forbidden/);
 await assert.rejects(()=>p.deletePreview("dpl_AAAAA",{isProduction:true}),/forbidden/);
});
test("manager requires exact independent verification before publish",async()=>{
 const t=new FakeTransport();t.deployments=[{id:"dpl_AAAAA",projectId:"prj_ABCDE",url:"x",readyState:"READY",target:"preview",meta:{pandoraProjectVersionId:ids.version,pandoraArtifactDigest:ids.digest,pandoraSourceCommit:ids.source}}];
 const p=new VercelDeploymentProvider({transport:t,teamId:"team_ABC",projectId:"prj_ABCDE"});
 const ops=new Map();
 const store={
  assertOwnership:async()=>true,getOperation:async k=>ops.get(k),claimOperation:async o=>{ops.set(o.idempotencyKey,{...o,status:"claimed"});return{claimed:true}},
  markOperationRunning:async()=>{},completeOperation:async(k,r)=>ops.set(k,{status:"succeeded",result:r}),failOperation:async()=>{},markOperationUncertain:async()=>{},
  reconcileOperation:async()=>{throw new Error("unexpected");},getCurrentProductionVersion:async()=>ids.prev,
  getVerification:async()=>({projectVersionId:ids.version,artifactDigest:ids.digest,status:"PASS",stale:false}),
  compareAndSetProduction:async()=>{},recordDeployment:async()=>{},getRollbackEligibility:async()=>({eligible:true}),
 };
 const m=new ProjectRuntimeManager({store,provider:p});
 const preview={providerDeploymentId:"dpl_AAAAA",status:"ready_for_verification",projectVersionId:ids.version,artifactDigest:ids.digest,sourceCommit:ids.source};
 const r=await m.publishVersion(request("production"),preview);assert.equal(r.productionState,"ready_for_verification");
});

test("customer runtime edge function uses Vault-backed Vercel broker",()=>{
 const source=require("node:fs").readFileSync("supabase/functions/pandora-project-runtime/index.ts","utf8");
 assert.equal(source.includes("PANDORA_VERCEL_TOKEN"),false);
 assert.equal(source.includes("pandora_worker_f_vercel_request_20260829"),true);
 assert.equal(source.includes("SUPABASE_SERVICE_ROLE_KEY"),true);
});
