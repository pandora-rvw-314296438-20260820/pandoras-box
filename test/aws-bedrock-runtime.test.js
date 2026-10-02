
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assumeRoleWithVercelOidc,
  signBedrockRequest,
  signBedrockControlRequest,
  bedrockControlJson,
  converseWithBedrockTarget,
  createBedrockHealthProbe,
  converseWithBedrockModel,
  converseWithBedrock,
  BEDROCK_ROLE_ARN,
} = require("../src/providers/aws-bedrock-runtime.js");

function response(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return body;
    },
  };
}

test("STS exchange uses Vercel web identity with a 15 minute session", async () => {
  let request;
  const credentials = await assumeRoleWithVercelOidc({
    roleArn: "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2",
    webIdentityToken: "test-oidc-token",
    fetchFn: async (url, init) => {
      request = { url, init };
      return response(
        200,
        "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials>" +
          "<AccessKeyId>ASIATEST</AccessKeyId>" +
          "<SecretAccessKey>secret</SecretAccessKey>" +
          "<SessionToken>session</SessionToken>" +
          "<Expiration>2026-09-12T10:30:00Z</Expiration>" +
          "</Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>",
      );
    },
  });
  assert.equal(request.url, "https://sts.amazonaws.com/");
  assert.equal(request.init.method, "POST");
  const form = new URLSearchParams(request.init.body);
  assert.equal(form.get("Action"), "AssumeRoleWithWebIdentity");
  assert.equal(form.get("DurationSeconds"), "900");
  assert.equal(form.get("WebIdentityToken"), "test-oidc-token");
  assert.equal(credentials.accessKeyId, "ASIATEST");
  assert.equal(credentials.sessionToken, "session");
});

test("Bedrock SigV4 request is scoped to approved runtime endpoint", () => {
  const signed = signBedrockRequest({
    region: "us-east-1",
    modelId: "us.openai.gpt-6-luna",
    body: {
      messages: [{ role: "user", content: [{ text: "ping" }] }],
      inferenceConfig: { maxTokens: 16, temperature: 0 },
    },
    credentials: {
      accessKeyId: "ASIATEST",
      secretAccessKey: "secret",
      sessionToken: "session",
    },
    now: new Date("2026-09-12T10:00:00Z"),
  });
  assert.equal(
    signed.url,
    "https://bedrock-runtime.us-east-1.amazonaws.com/model/us.openai.gpt-6-luna/converse",
  );
  assert.match(
    signed.headers.authorization,
    /Credential=ASIATEST\/20260912\/us-east-1\/bedrock\/aws4_request/,
  );
  assert.equal(signed.headers["x-amz-security-token"], "session");
  assert.equal("x-amz-access-key" in signed.headers, false);
});


test("Bedrock SigV4 canonicalizes colon-bearing model IDs exactly once", () => {
  const signed = signBedrockRequest({
    region: "us-east-1",
    modelId: "amazon.nova-lite-v1:0",
    body: {
      messages: [{ role: "user", content: [{ text: "ping" }] }],
      inferenceConfig: { maxTokens: 16, temperature: 0 },
    },
    credentials: {
      accessKeyId: "ASIATEST",
      secretAccessKey: "secret",
      sessionToken: "session",
    },
    now: new Date("2026-09-12T10:00:00Z"),
  });
  assert.equal(
    signed.url,
    "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.nova-lite-v1:0/converse",
  );
  assert.match(
    signed.headers.authorization,
    /Signature=d0f0f3eff13dd6128fa6b6785b30a7e48cdd09c73109fe943e9f82ea39998bd1$/,
  );
});

test("Bedrock SigV4 rejects pre-encoded model identifiers", () => {
  assert.throws(
    () => signBedrockRequest({
      region: "us-east-1",
      modelId: "amazon.nova-lite-v1%3A0",
      body: {
        messages: [{ role: "user", content: [{ text: "ping" }] }],
        inferenceConfig: { maxTokens: 16 },
      },
      credentials: {
        accessKeyId: "ASIATEST",
        secretAccessKey: "secret",
        sessionToken: "session",
      },
      now: new Date("2026-09-12T10:00:00Z"),
    }),
    /AWS_BEDROCK_MODEL_DENIED/,
  );
});

test("Bedrock Converse omits temperature by default", async () => {
  const result = await converseWithBedrockTarget({
    modelId: "moonshotai.kimi-k3",
    invocationTarget: "us.moonshotai.kimi-k3",
    providerName: "Moonshot AI",
    prompt: "OK",
    maxTokens: 16,
    credentials: {
      accessKeyId: "ASIATEST",
      secretAccessKey: "secret",
      sessionToken: "session",
    },
    fetchFn: async (_url, init) => {
      assert.deepEqual(JSON.parse(init.body).inferenceConfig, { maxTokens: 16 });
      return {
        ok: true,
        status: 200,
        headers: { get: () => "req-no-temperature" },
        async text() {
          return JSON.stringify({
            output: { message: { content: [{ text: "OK" }] } },
            usage: { inputTokens: 1, outputTokens: 1, totalTokens: 2 },
            stopReason: "end_turn",
          });
        },
      };
    },
  });
  assert.equal(result.text, "OK");
  assert.equal(result.providerRequestId, "req-no-temperature");
});

test("Bedrock health fails closed when workload identity is unavailable", async () => {
  let fetchCalls = 0;
  const probe = createBedrockHealthProbe(
    {
      AWS_ROLE_ARN: "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2",
      AWS_REGION: "us-east-1",
      PANDORA_BEDROCK_FAST_MODEL: "openai.gpt-6-luna",
    },
    async () => {
      fetchCalls += 1;
      throw new Error("unexpected fetch");
    },
    async () => undefined,
    () => Date.parse("2026-09-12T10:00:00Z"),
  );
  const result = await probe();
  assert.equal(result.status, "degraded");
  assert.equal(result.authentication, "vercel_oidc_sts");
  assert.equal(result.reason, "aws_workload_identity_unavailable");
  assert.equal(fetchCalls, 0);
});

test("Bedrock health proves STS and Converse without returning credentials", async () => {
  const calls = [];
  const probe = createBedrockHealthProbe(
    {
      AWS_ROLE_ARN: "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2",
      AWS_REGION: "us-east-1",
      PANDORA_BEDROCK_FAST_MODEL: "openai.gpt-6-luna",
    },
    async (url, init) => {
      calls.push({ url, init });
      if (url === "https://sts.amazonaws.com/") {
        return response(
          200,
          "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials>" +
            "<AccessKeyId>ASIATEST</AccessKeyId>" +
            "<SecretAccessKey>secret</SecretAccessKey>" +
            "<SessionToken>session</SessionToken>" +
            "<Expiration>2026-09-12T10:30:00Z</Expiration>" +
            "</Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>",
        );
      }
      return response(
        200,
        JSON.stringify({
          output: { message: { content: [{ text: "PANDORA_BEDROCK_OK" }] } },
          usage: { inputTokens: 4, outputTokens: 4 },
          stopReason: "end_turn",
        }),
      );
    },
    async () => "oidc",
    () => Date.parse("2026-09-12T10:00:00Z"),
  );
  const result = await probe();
  assert.equal(result.status, "healthy");
  assert.equal(result.model, "openai.gpt-6-luna");
  assert.equal(result.invocationTarget, "us.openai.gpt-6-luna");
  assert.equal(calls.length, 2);
  assert.equal(JSON.stringify(result).includes("ASIATEST"), false);
  assert.equal(JSON.stringify(result).includes("session"), false);
});


test("Bedrock catalog maps Astra to the governed US inference profile", async () => {
  const calls = [];
  const result = await converseWithBedrockModel({
    modelId: "openai.gpt-6-astra",
    parts: [{ type: "text", text: "Return ASTRA_OK" }],
    maxTokens: 16,
    environment: {
      AWS_ROLE_ARN: "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2",
      AWS_REGION: "us-east-1",
    },
    resolveWorkloadToken: async () => "oidc",
    fetchFn: async (url, init) => {
      calls.push({url, init});
      if (url === "https://sts.amazonaws.com/") {
        const form = new URLSearchParams(init.body);
        assert.equal(form.get("RoleArn"), BEDROCK_ROLE_ARN);
        return response(
          200,
          "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials>" +
            "<AccessKeyId>ASIATEST</AccessKeyId><SecretAccessKey>secret</SecretAccessKey>" +
            "<SessionToken>session</SessionToken><Expiration>2026-09-27T08:00:00Z</Expiration>" +
          "</Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>",
        );
      }
      assert.match(url, /\/model\/us\.openai\.gpt-6-astra\/converse$/);
      return response(200, JSON.stringify({
        output:{message:{content:[{text:"ASTRA_OK"}]}},
        usage:{inputTokens:3,outputTokens:2,totalTokens:5},
        stopReason:"end_turn",
      }));
    },
  });
  assert.equal(result.text, "ASTRA_OK");
  assert.equal(result.modelId, "openai.gpt-6-astra");
  assert.equal(result.invocationTarget, "us.openai.gpt-6-astra");
  assert.equal(calls.length, 2);
});

test("legacy Vercel profile env does not override catalog authority", async () => {
  const calls = [];
  const result = await converseWithBedrock({
    prompt: "Return DEFAULT_OK",
    mode: "standard",
    maxTokens: 16,
    environment: {
      AWS_ROLE_ARN: "arn:aws:iam::792289066859:role/PandoraVercelBedrockInferenceV2",
      AWS_REGION: "us-east-1",
      PANDORA_BEDROCK_STANDARD_MODEL: "us.openai.gpt-5.6-sol",
    },
    resolveWorkloadToken: async () => "oidc",
    fetchFn: async (url, init) => {
      calls.push(url);
      if (url === "https://sts.amazonaws.com/") {
        return response(
          200,
          "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials>" +
            "<AccessKeyId>ASIATEST</AccessKeyId><SecretAccessKey>secret</SecretAccessKey>" +
            "<SessionToken>session</SessionToken><Expiration>2026-09-27T08:00:00Z</Expiration>" +
          "</Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>",
        );
      }
      assert.match(url, /\/model\/us\.openai\.gpt-6-astra\/converse$/);
      return response(200, JSON.stringify({
        output:{message:{content:[{text:"DEFAULT_OK"}]}},
        usage:{inputTokens:3,outputTokens:2,totalTokens:5},
        stopReason:"end_turn",
      }));
    },
  });
  assert.equal(result.modelId, "openai.gpt-6-astra");
  assert.equal(calls.length, 2);
});
test("arbitrary Bedrock model identifiers are rejected before STS", async () => {
  let calls = 0;
  await assert.rejects(
    () => converseWithBedrockModel({
      modelId: "arbitrary.unapproved-model",
      prompt: "no",
      resolveWorkloadToken: async () => "oidc",
      fetchFn: async () => { calls += 1; throw new Error("unexpected"); },
    }),
    /AWS_BEDROCK_MODEL_DENIED/,
  );
  assert.equal(calls, 0);
});


test("Bedrock control-plane SigV4 stays on the dedicated regional endpoint", () => {
  const signed = signBedrockControlRequest({
    region: "us-east-1",
    path: "/inference-profiles",
    query: { type: "SYSTEM_DEFINED", maxResults: 100 },
    credentials: { accessKeyId: "ASIATEST", secretAccessKey: "secret", sessionToken: "session" },
    now: new Date("2026-10-02T10:00:00Z"),
  });
  assert.match(signed.url, /^https:\/\/bedrock\.us-east-1\.amazonaws\.com\/inference-profiles\?/);
  assert.match(signed.headers.authorization, /\/us-east-1\/bedrock\/aws4_request/);
  assert.equal("x-amz-access-key" in signed.headers, false);
});

test("dynamic Bedrock probe uses one exact Converse target with supplied short-lived credentials", async () => {
  let calls = 0;
  const result = await converseWithBedrockTarget({
    modelId: "vendor.model-v1",
    invocationTarget: "us.vendor.model-v1",
    providerName: "Vendor",
    prompt: "OK",
    maxTokens: 1,
    temperature: null,
    credentials: { accessKeyId: "ASIATEST", secretAccessKey: "secret", sessionToken: "session" },
    fetchFn: async (url, init) => {
      calls += 1;
      assert.match(url, /\/model\/us\.vendor\.model-v1\/converse$/);
      assert.deepEqual(JSON.parse(init.body).inferenceConfig, { maxTokens: 1 });
      return {
        ok: true, status: 200,
        headers: { get: () => "req-1" },
        async text() { return JSON.stringify({ output:{message:{content:[{text:"OK"}]}}, usage:{inputTokens:1,outputTokens:1,totalTokens:2}, stopReason:"end_turn" }); },
      };
    },
  });
  assert.equal(calls, 1);
  assert.equal(result.usage.totalTokens, 2);
  assert.equal(result.providerRequestId, "req-1");
});
