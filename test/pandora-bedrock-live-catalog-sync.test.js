"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeCatalogRows, applyProbeResult, selectInvocationTarget } = require("../src/providers/aws-bedrock-catalog-sync.js");

const profiles = [
  { inferenceProfileId:"us.openai.gpt-test",status:"ACTIVE",models:[{modelArn:"arn:aws:bedrock:us-east-1::foundation-model/openai.gpt-test"}] },
];

test("live catalog discovers workflow scope and chooses the current invocation target", () => {
  const rows = normalizeCatalogRows({
    observedAt:"2026-10-02T10:00:00.000Z",
    models:[
      {modelId:"openai.gpt-test",modelName:"GPT Test",providerName:"OpenAI",inputModalities:["TEXT","IMAGE"],outputModalities:["TEXT"],inferenceTypesSupported:["INFERENCE_PROFILE"],modelLifecycle:{status:"ACTIVE"}},
      {modelId:"amazon.embed-test",modelName:"Embed Test",providerName:"Amazon",inputModalities:["TEXT"],outputModalities:["EMBEDDING"],inferenceTypesSupported:["ON_DEMAND"],modelLifecycle:{status:"ACTIVE"}},
      {modelId:"cohere.rerank-test",modelName:"Rerank Test",providerName:"Cohere",inputModalities:["TEXT"],outputModalities:["TEXT"],inferenceTypesSupported:["ON_DEMAND"],modelLifecycle:{status:"ACTIVE"}},
    ],
    profiles,
    availabilityById:{
      "openai.gpt-test":{authorizationStatus:"AUTHORIZED",entitlementAvailability:"AVAILABLE",regionAvailability:"AVAILABLE",agreementAvailability:{status:"AVAILABLE"}},
      "amazon.embed-test":{authorizationStatus:"AUTHORIZED",entitlementAvailability:"AVAILABLE",regionAvailability:"AVAILABLE",agreementAvailability:{status:"AVAILABLE"}},
      "cohere.rerank-test":{authorizationStatus:"AUTHORIZED",entitlementAvailability:"AVAILABLE",regionAvailability:"AVAILABLE",agreementAvailability:{status:"AVAILABLE"}},
    },
  });
  assert.equal(rows[0].invocationTarget,"us.openai.gpt-test");
  assert.deepEqual(rows[0].workflowScopes,["conversation"]);
  assert.equal(rows[0].availabilityState,"region_available");
  assert.deepEqual(rows[1].workflowScopes,["embedding"]);
  assert.deepEqual(rows[2].workflowScopes,["reranking"]);
  assert.equal(selectInvocationTarget({modelId:"x",inferenceTypesSupported:["ON_DEMAND"]},[]),"x");
});

test("only successful ACTIVE conversational probes become routable", () => {
  const base = normalizeCatalogRows({
    observedAt:"2026-10-02T10:00:00.000Z",
    models:[{modelId:"openai.gpt-test",modelName:"GPT Test",providerName:"OpenAI",inputModalities:["TEXT"],outputModalities:["TEXT"],inferenceTypesSupported:["INFERENCE_PROFILE"],modelLifecycle:{status:"ACTIVE"}}],
    profiles,
    availabilityById:{"openai.gpt-test":{authorizationStatus:"AUTHORIZED",entitlementAvailability:"AVAILABLE",regionAvailability:"AVAILABLE",agreementAvailability:{status:"AVAILABLE"}}},
  })[0];
  const good=applyProbeResult(base,{ok:true,inputTokens:1,outputTokens:1,totalTokens:2,observedAt:"2026-10-02T10:01:00.000Z"});
  assert.equal(good.availabilityState,"routable");
  assert.equal(good.routable,true);
  const failed=applyProbeResult(base,{ok:false,errorCode:"access_denied",observedAt:"2026-10-02T10:01:00.000Z"});
  assert.equal(failed.availabilityState,"runtime_tested");
  assert.equal(failed.routable,false);
  assert.equal(failed.runtimeState,"account_denied");
});

test("LEGACY can be runtime tested but never becomes selectable", () => {
  const row=normalizeCatalogRows({
    observedAt:"2026-10-02T10:00:00.000Z",
    models:[{modelId:"legacy.chat",modelName:"Legacy Chat",providerName:"Vendor",inputModalities:["TEXT"],outputModalities:["TEXT"],inferenceTypesSupported:["ON_DEMAND"],modelLifecycle:{status:"LEGACY"}}],
    profiles:[],
    availabilityById:{"legacy.chat":{authorizationStatus:"AUTHORIZED",entitlementAvailability:"AVAILABLE",regionAvailability:"AVAILABLE",agreementAvailability:{status:"AVAILABLE"}}},
  })[0];
  const tested=applyProbeResult(row,{ok:true,inputTokens:1,outputTokens:1,totalTokens:2,observedAt:"2026-10-02T10:01:00.000Z"});
  assert.equal(tested.availabilityState,"runtime_tested");
  assert.equal(tested.routable,false);
});
