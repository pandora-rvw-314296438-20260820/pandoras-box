"use strict";

const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {test}=require("node:test");

const migration=readFileSync(
  join(__dirname,"../supabase/migrations/20260930130000_pandora_internal_closure_v1.sql"),
  "utf8",
);

test("internal closure migration encodes required safety contracts",()=>{
  assert.match(migration,/pandora_enterprise_read_compatible_payload_v1/);
  assert.match(migration,/unsupported_version_transition/);
  assert.match(migration,/pandora_sync_loop_preflight_v1/);
  assert.match(migration,/round_trip_origin_detected/);
  assert.match(migration,/enterprise_legal_evidence_versions/);
  assert.match(migration,/legal_evidence_versions_are_append_only/);
  assert.match(migration,/pandora_capability_deprecation_report_v1/);
  assert.match(migration,/capability_has_active_dependencies/);
  assert.doesNotMatch(migration,/\bProjectOS\b/i);
});

test("provider SDK conformance runner covers auth retry evidence errors health and version",async()=>{
  const sdk=await import("../packages/pandora-provider-sdk/index.mjs");
  const {runProviderConformanceSuite}=await import("../packages/pandora-provider-sdk/conformance.mjs");

  const manifest={
    providerKey:"reference_adapter",
    manifestVersion:"1.0.0",
    displayName:"Reference Adapter",
    authScheme:"test",
    regions:["global"],
    dataResidency:["provider_managed"],
    dataHandling:{classification:"test"},
    deprecationPolicy:{noticeRequired:true},
    runbookRef:"runbook:reference",
    escalationRef:"escalation:reference",
    capabilities:[{
      capabilityKey:"message.send",
      capabilityVersion:"1.0.0",
      operationMode:"write",
      adapterVersion:"1.0.0",
      evidenceModes:["provider_receipt"],
      idempotencyStrategy:"request_id"
    }]
  };

  const adapter=sdk.defineProviderAdapter({
    manifest,
    handlers:{
      "message.send@1.0.0":async(req,runtime)=>{
        const transport=runtime.transport||{};
        if(transport.auth===false) throw new Error("auth_failed");
        if(transport.health==="down") throw new Error("provider_unavailable");
        if(transport.retryable===true){
          const error=new Error("rate_limited");
          error.retryable=true;
          throw error;
        }
        if(transport.hardFailure===true) throw new Error("provider_error");
        return sdk.buildProviderReceipt({
          requestId:req.requestId,
          providerKey:"reference_adapter",
          capabilityKey:req.capabilityKey,
          capabilityVersion:req.capabilityVersion,
          adapterVersion:"1.0.0",
          providerOperationId:"reference-operation",
          accepted:true,
          evidenceRefs:runtime.evidence||[]
        });
      }
    }
  });

  const baseRequest={
    requestId:"conformance-request",
    idempotencyKey:"conformance-idempotency",
    capabilityKey:"message.send",
    capabilityVersion:"1.0.0",
    input:{message:"fixture"}
  };

  const report=await runProviderConformanceSuite({
    adapter,
    baseRequest,
    probes:{
      auth:async(a,r)=>{try{await a.invoke(r,{transport:{auth:false}});return false;}catch(e){return {pass:e.message==="auth_failed",detail:e.message};}},
      retry:async(a,r)=>{try{await a.invoke(r,{transport:{retryable:true}});return false;}catch(e){return {pass:e.message==="rate_limited"&&e.retryable===true,detail:e.message};}},
      evidence:async(a,r)=>{
        const receipt=await a.invoke(r,{transport:{auth:true},evidence:[{type:"provider_receipt",ref:"fixture"}]});
        return {pass:receipt.accepted===true&&receipt.evidenceRefs.length===1,detail:receipt.verificationState};
      },
      error:async(a,r)=>{try{await a.invoke(r,{transport:{hardFailure:true}});return false;}catch(e){return {pass:e.message==="provider_error",detail:e.message};}},
      health:async(a,r)=>{try{await a.invoke(r,{transport:{health:"down"}});return false;}catch(e){return {pass:e.message==="provider_unavailable",detail:e.message};}}
    }
  });

  assert.equal(report.pass,true);
  assert.deepEqual(
    report.checks.map(item=>item.name),
    ["manifest","version","idempotency","database_boundary","auth","retry","evidence","error","health"]
  );

  const failing=await runProviderConformanceSuite({
    adapter,
    baseRequest,
    probes:{auth:async()=>true,retry:async()=>true,evidence:async()=>true,error:async()=>true}
  });
  assert.equal(failing.pass,false);
  assert.equal(failing.checks.find(item=>item.name==="health").pass,false);
});
