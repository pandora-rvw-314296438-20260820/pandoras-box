import test from "node:test";
import assert from "node:assert/strict";
import {BedrockNativeProvider} from "../bedrock-native.mjs";
import catalog from "../../../src/providers/aws-bedrock-catalog.js";

function request(taskClass="deep_reasoning", parts=[{type:"text",text:"Return OK"}]) {
  return {
    taskClass,
    parts,
    maxOutputTokens:256,
    deadlineMs:10000,
    memoryContext:"",
  };
}

function model(modelId="openai.gpt-6-astra") {
  return {
    provider:"bedrock",
    model:modelId,
    transport:"bedrock_converse",
    executionBoundary:"cloud",
    modelRevision:null,
  };
}

test("live generated Bedrock catalog contains 72 governed reasoning models and Astra", () => {
  assert.equal(catalog.BEDROCK_REASONING_MODELS.length, 72);
  const astra=catalog.getBedrockReasoningModel("openai.gpt-6-astra");
  assert.equal(astra?.invocationTarget,"us.openai.gpt-6-astra");
  assert.equal(astra?.providerName,"OpenAI");
  assert.equal(catalog.BEDROCK_ROLE_ARN,"arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2");
  assert.equal(catalog.BEDROCK_REASONING_MODELS.some(x=>/rerank|safeguard|sonic|voxtral/i.test(x.modelId)),false);
});

test("Bedrock provider normalizes successful Astra output and usage", async () => {
  const provider=new BedrockNativeProvider({
    catalog:catalog.BEDROCK_REASONING_MODELS,
    clock:()=>1000,
    converse:async args=>({
      text:"OK",
      modelId:args.modelId,
      invocationTarget:"us.openai.gpt-6-astra",
      providerName:"OpenAI",
      usage:{inputTokens:11,outputTokens:3,totalTokens:14},
      stopReason:"end_turn",
      providerRequestId:"req-1",
    }),
  });
  assert.deepEqual(provider.preflight(request(),model()),{validated:true,executionStarted:false});
  const result=await provider.execute(request(),model());
  assert.equal(result.output,"OK");
  assert.equal(result.receipt.state,"received");
  assert.equal(result.receipt.code,null);
  assert.equal(result.receipt.usage.totalTokens,14);
  assert.match(result.receipt.providerReceipt,/^bedrock-sha256:[a-f0-9]{64}$/);
  assert.equal(result.receipt.billedCostMicros,null);
});

test("Bedrock provider rejects model IDs outside the live governed catalog", () => {
  const provider=new BedrockNativeProvider({catalog:catalog.BEDROCK_REASONING_MODELS,converse:async()=>({})});
  assert.throws(()=>provider.preflight(request(),model("not.approved")),/INFERENCE_PROVIDER_MODEL_DENIED/);
});

test("Bedrock provider requires catalog image support", () => {
  const provider=new BedrockNativeProvider({catalog:catalog.BEDROCK_REASONING_MODELS,converse:async()=>({})});
  const image=[{type:"image",mimeType:"image/png",data:"AAAA"},{type:"text",text:"describe"}];
  assert.throws(()=>provider.preflight(request("vision",image),model("deepseek.v3.2")),/INFERENCE_IMAGE_INVALID/);
  assert.doesNotThrow(()=>provider.preflight(request("vision",image),model("openai.gpt-6-astra")));
});

test("known Bedrock authorization failures become permission-denied receipts", async () => {
  const provider=new BedrockNativeProvider({
    catalog:catalog.BEDROCK_REASONING_MODELS,
    converse:async()=>{const e=new Error("denied");e.status=403;throw e;},
  });
  const result=await provider.execute(request(),model());
  assert.equal(result.output,null);
  assert.equal(result.receipt.state,"failed");
  assert.equal(result.receipt.code,"permission_denied");
  assert.equal(result.receipt.billedCostMicros,null);
});

test("unknown Bedrock transport outcomes are not converted to zero-cost failures", async () => {
  const provider=new BedrockNativeProvider({
    catalog:catalog.BEDROCK_REASONING_MODELS,
    converse:async()=>{throw new Error("socket lost");},
  });
  await assert.rejects(
    ()=>provider.execute(request(),model()),
    error=>error?.code==="INFERENCE_PROVIDER_OUTCOME_UNKNOWN"&&error?.outcomeUnknown===true,
  );
});
