"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const T=require("../src");

const ORG="org_proof", PROJECT="project_proof", ACTOR="actor_proof";
const now=()=>new Date("2026-08-28T12:00:00Z");
const resolver={async resolve(){return{project:{id:PROJECT,organization_id:ORG,version_id:"v18"},resource:{id:"production",project_id:PROJECT,organization_id:ORG},target_resource:"production",project_version:"v18",project_state_hash:"state18",resource_version:"v17"};}};
function durableDeps(adapter){
  const approvalStore=new T.MemoryApprovalStore(); approvalStore.durability="durable";
  const idemStore=new T.MemoryIdempotencyStore(); idemStore.durability="durable";
  const leaseStore=new T.MemoryLeaseStore(); leaseStore.durability="durable";
  const rateStore=new T.MemoryRateLimitStore(); rateStore.durability="durable";
  const lineageSink=new T.MemoryLineageSink(); lineageSink.durability="durable";
  return {resourceResolver:resolver,adapterRegistry:new T.ExecutionAdapterRegistry().register("DeploymentExecutor",adapter),approvalStore,idempotencyCoordinator:new T.IdempotencyCoordinator(idemStore),leaseManager:new T.MutationLeaseManager(leaseStore),rateLimitGuard:new T.RateLimitGuard(rateStore),lineageSink,now};
}
function proposal(overrides={}){return{tool:"request_publish",version:1,arguments:{project_id:PROJECT,environment:"production",version_id:"v18",verification_run_id:"vr18",preview_id:"preview18",artifact_digest:"a".repeat(64),target_environment:"production",request_id:"request-publish-18",idempotency_key:"idem-publish-18",...overrides},requirement_refs:["REQ-PUBLISH"]};}
function verification(overrides={}){return{verification:"PASS",publish_eligible:true,verification_run_id:"vr18",project_id:PROJECT,project_version_id:"v18",artifact_digest:"a".repeat(64),project_spec_version:"spec18",...overrides};}
function context(approval_id){return{organization_id:ORG,actor:{id:ACTOR,organization_id:ORG,capabilities:["production.publish","production.access"]},environment:"production",approval_id,verification:verification(),project_spec_version:"spec18",expected_resource_version:"v17",authorized_requirement_refs:["REQ-PUBLISH"],rate_limit:{max_calls:3,window_ms:60000},model_run_id:"model18",build_job_id:"build18"};}

async function approvedGateway(adapter){
  const deps=durableDeps(adapter); const p=proposal();
  const binding=T.approvalBindingFromAction({proposal:p,organization_id:ORG,project_id:PROJECT,actor_id:ACTOR,environment:"production",target_resource:"production",project_version:"v18",project_state_hash:"state18",risk:T.RISK_LEVELS.HIGH,policy_version:T.POLICY_VERSION});
  const grant=T.createApprovalGrant(binding,{approval_id:"approval18",approved_by:"owner18",approved_at:"2026-08-28T11:00:00Z",expires_at:"2026-08-28T13:00:00Z"});
  await deps.approvalStore.put(grant);
  return {gateway:new T.PandoraToolGateway(deps),deps,p};
}

test("publish authorization proof: exact approved verified immutable version executes once",async()=>{
  let calls=0; const {gateway,deps,p}=await approvedGateway({async execute(req){calls++;return{output:{deployment_request:T.toWorkerFDeploymentRequest(req,{source_commit:"b".repeat(40),verification_ref:"vr18",expected_production_version_id:"44444444-4444-4444-8444-444444444444"})}};}});
  const r=await gateway.handle(p,context("approval18"));
  assert.equal(r.executed,true); assert.equal(r.receipt.status,"succeeded"); assert.equal(r.receipt.action_hash,r.action_hash); assert.equal(calls,1);
  const consumed=await deps.approvalStore.get("approval18"); assert.ok(consumed.consumed_at);
  assert.deepEqual(deps.lineageSink.list().map(x=>x.kind),["tool_proposal","policy_decision","tool_execution_started","tool_execution_finished"]);
});

test("publish authorization proof: stale/wrong artifact verification never reaches executor",async()=>{
  let calls=0; const {gateway,p}=await approvedGateway({async execute(){calls++;return{output:{ok:true}};}});
  const bad={...context("approval18"),verification:verification({artifact_digest:"c".repeat(64)})};
  const r=await gateway.handle(p,bad);
  assert.equal(r.executed,false); assert.equal(r.decision.reason_code,"VERIFICATION_REQUIRED_OR_STALE"); assert.equal(calls,0);
});

test("publish authorization proof: stale project state invalidates exact approval",async()=>{
  let calls=0; const {gateway,p}=await approvedGateway({async execute(){calls++;return{output:{ok:true}};}});
  gateway.resourceResolver={async resolve(){return{project:{id:PROJECT,organization_id:ORG,version_id:"v18"},resource:{id:"production",project_id:PROJECT,organization_id:ORG},target_resource:"production",project_version:"v18",project_state_hash:"state19",resource_version:"v17"};}};
  await assert.rejects(gateway.handle(p,context("approval18")),e=>e?.code==="APPROVAL_PROJECT_STATE_STALE"); assert.equal(calls,0);
});

test("bounded safe proof: read-only tool flows proposal to receipt with no mutation authority",async()=>{
  const readResolver={async resolve(){return{project:{id:PROJECT,organization_id:ORG,version_id:"v18"},resource:{id:"project",project_id:PROJECT,organization_id:ORG},target_resource:"project",project_version:"v18",project_state_hash:"state18"};}};
  const lineage=new T.MemoryLineageSink();
  const gateway=new T.PandoraToolGateway({resourceResolver:readResolver,adapterRegistry:new T.ExecutionAdapterRegistry().register("ProjectContextExecutor",{async execute(){return{output:{id:PROJECT,status:"ready"}};}}),lineageSink:lineage,now});
  const p={tool:"get_project",version:1,arguments:{project_id:PROJECT,environment:"preview"},requirement_refs:["REQ-READ"]};
  const r=await gateway.handle(p,{organization_id:ORG,actor:{id:ACTOR,organization_id:ORG,capabilities:["project.read"]},environment:"preview",authorized_requirement_refs:["REQ-READ"]});
  assert.equal(r.executed,true); assert.equal(r.receipt.output.status,"ready"); assert.equal(r.receipt.provenance.untrusted_output,true);
});
