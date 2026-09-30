"use strict";

const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {test}=require("node:test");

const root=join(__dirname,"..");
const core=readFileSync(join(root,"supabase/migrations/20260930110000_pandora_universal_core_compatibility_activation_v1.sql"),"utf8");
const capability=readFileSync(join(root,"supabase/migrations/20260930111000_pandora_capability_provider_activation_v1.sql"),"utf8");
const industry=readFileSync(join(root,"supabase/migrations/20260930112000_pandora_industry_packs_onboarding_v1.sql"),"utf8");

test("activation migrations preserve architecture boundaries",()=>{
  assert.match(core,/enterprise_events_are_append_only/);
  assert.match(core,/database_cdc[\s\S]*'prohibited'/);
  assert.match(core,/outbound_only boolean not null default true check \(outbound_only\)/);
  assert.match(core,/pandora_connector_write_ready_v1/);
  assert.doesNotMatch(core,/create table[^;]*enterprise_source_connections/i);
  assert.doesNotMatch(core,/\bProjectOS\b/i);

  assert.match(capability,/selection_mode in \('AUTO','PREFERRED','REQUIRED'\)/);
  assert.match(capability,/provider_manifest_conformance_v1/);
  assert.match(capability,/write_idempotency_or_evidence_missing/);
  assert.match(capability,/provider_not_authorized/);
  assert.match(capability,/required_provider_unavailable_fail_closed/);
  assert.match(capability,/pandora_provider_selection_receipts/);
  assert.match(capability,/pending_verification_count/);
  assert.doesNotMatch(capability,/\bProjectOS\b/i);

  for(const pack of ["hospitality","restaurant","legal","trade","retail","custom"]){
    assert.match(industry,new RegExp("\\\\('"+pack+"','1\\\\.0\\\\.0'"));
  }
  assert.match(industry,/custom fields|custom extensions|pandora_custom_entity_types/i);
  assert.match(industry,/customs_entry[\s\S]*source_of_record[\s\S]*customs_authority/i);
  assert.match(industry,/enterprise_legal_evidence_items[\s\S]*original_content_sha256/i);
  assert.doesNotMatch(industry,/\bProjectOS\b/i);
});

test("provider SDK fails closed for manifest and database-boundary violations",async()=>{
  const sdk=await import("../packages/pandora-provider-sdk/index.mjs");
  assert.throws(()=>sdk.validateProviderManifest({
    providerKey:"demo",
    manifestVersion:"1.0.0",
    displayName:"Demo",
    authScheme:"oauth",
    regions:["global"],
    dataResidency:["global"],
    dataHandling:{},
    deprecationPolicy:{},
    runbookRef:"runbook:demo",
    escalationRef:"escalation:demo",
    capabilities:[{
      capabilityKey:"delivery.dispatch",
      capabilityVersion:"1.0.0",
      operationMode:"write",
      adapterVersion:"1.0.0",
      evidenceModes:[]
    }]
  }),/idempotencyStrategy|evidenceModes/);

  const manifest={
    providerKey:"demo",
    manifestVersion:"1.0.0",
    displayName:"Demo",
    authScheme:"oauth",
    regions:["global"],
    dataResidency:["global"],
    dataHandling:{classification:"test"},
    deprecationPolicy:{noticeRequired:true},
    runbookRef:"runbook:demo",
    escalationRef:"escalation:demo",
    capabilities:[{
      capabilityKey:"delivery.dispatch",
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
      "delivery.dispatch@1.0.0":async(req)=>sdk.buildProviderReceipt({
        requestId:req.requestId,
        providerKey:"demo",
        capabilityKey:req.capabilityKey,
        capabilityVersion:req.capabilityVersion,
        adapterVersion:"1.0.0",
        providerOperationId:"op-1",
        accepted:true
      })
    }
  });

  await assert.rejects(
    adapter.invoke({
      requestId:"req-1",
      idempotencyKey:"test",
      capabilityKey:"delivery.dispatch",
      capabilityVersion:"1.0.0",
      input:{}
    },{database:{}}),
    /direct_enterprise_database_access_forbidden/
  );

  const receipt=await adapter.invoke({
    requestId:"req-2",
    idempotencyKey:"test-two",
    capabilityKey:"delivery.dispatch",
    capabilityVersion:"1.0.0",
    input:{}
  },{transport:{}});
  assert.equal(receipt.accepted,true);
  assert.equal(receipt.verificationState,"pending_verification");
});
