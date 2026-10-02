"use strict";

const crypto = require("node:crypto");
const { BEDROCK_REGION, BEDROCK_ROLE_ARN, assumeRoleWithVercelOidc } = require("./aws-bedrock-runtime.js");
const { buildBedrockProbePlan, minimalBedrockProbeBody, normalizeBedrockCatalogSnapshot } = require("./aws-bedrock-catalog-sync.js");

function hmac(key, value, encoding) { return crypto.createHmac("sha256", key).update(value, "utf8").digest(encoding); }
function sha256(value) { return crypto.createHash("sha256").update(value, "utf8").digest("hex"); }
function rfc3986(value) { return encodeURIComponent(value).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`); }
function canonicalQuery(query) { return Object.entries(query || {}).filter(([,v]) => v !== undefined && v !== null).sort(([a],[b]) => a.localeCompare(b)).map(([k,v]) => `${rfc3986(k)}=${rfc3986(String(v))}`).join("&"); }
function signAwsRequest({ service, region, host, method, path, query = {}, body = "", credentials, now = new Date(), contentType = null }) {
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, ""), dateStamp = amzDate.slice(0,8), payloadHash = sha256(body);
  const headers = { host, "x-amz-date": amzDate, "x-amz-security-token": credentials.sessionToken };
  if (contentType) headers["content-type"] = contentType;
  const signedNames = Object.keys(headers).sort();
  const canonicalHeaders = signedNames.map((k) => `${k}:${headers[k]}\n`).join("");
  const signedHeaders = signedNames.join(";");
  const request = [method, path, canonicalQuery(query), canonicalHeaders, signedHeaders, payloadHash].join("\n");
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(request)].join("\n");
  const kDate = hmac(Buffer.from(`AWS4${credentials.secretAccessKey}`, "utf8"), dateStamp), kRegion = hmac(kDate, region), kService = hmac(kRegion, service), kSigning = hmac(kService, "aws4_request");
  const signature = crypto.createHmac("sha256", kSigning).update(stringToSign, "utf8").digest("hex");
  const authorization = `AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const url = `https://${host}${path}${canonicalQuery(query) ? `?${canonicalQuery(query)}` : ""}`;
  return { url, init: { method, headers: { ...headers, authorization }, ...(body ? { body } : {}) } };
}
async function signedJson({ service, region, host, method, path, query, body, credentials, fetchFn, now }) {
  const payload = body == null ? "" : JSON.stringify(body);
  const signed = signAwsRequest({ service, region, host, method, path, query, body: payload, credentials, now, contentType: body == null ? null : "application/json" });
  const response = await fetchFn(signed.url, signed.init);
  const raw = await response.text(); let json = {};
  try { json = raw ? JSON.parse(raw) : {}; } catch { json = {}; }
  if (!response.ok) { const error = new Error("AWS_BEDROCK_CONTROL_REQUEST_FAILED"); error.status = response.status; error.awsCode = typeof json?.message === "string" ? json.message.slice(0,240) : null; throw error; }
  return { json, response };
}
async function credentialsForControl(resolveWorkloadToken, fetchFn) {
  const token = await resolveWorkloadToken(); if (!token) throw new Error("AWS_WORKLOAD_IDENTITY_UNAVAILABLE");
  return assumeRoleWithVercelOidc({ roleArn: BEDROCK_ROLE_ARN, webIdentityToken: token, fetchFn });
}
async function mapLimit(items, limit, worker) {
  const output = new Array(items.length); let next = 0;
  async function run() { while (true) { const index = next++; if (index >= items.length) return; output[index] = await worker(items[index], index); } }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => run())); return output;
}
async function fetchBedrockCatalogTruth({ fetchFn = globalThis.fetch, resolveWorkloadToken, now = new Date() }) {
  const region = BEDROCK_REGION, host = `bedrock.${region}.amazonaws.com`, credentials = await credentialsForControl(resolveWorkloadToken, fetchFn);
  const models = (await signedJson({ service:"bedrock", region, host, method:"GET", path:"/foundation-models", credentials, fetchFn, now })).json.modelSummaries || [];
  const profiles = [];
  let nextToken = null;
  for (let page = 0; page < 20; page += 1) {
    const pageResult = await signedJson({
      service:"bedrock", region, host, method:"GET", path:"/inference-profiles",
      query:{maxResults:100,type:"SYSTEM_DEFINED",...(nextToken ? {nextToken} : {})}, credentials, fetchFn, now,
    });
    const pageProfiles = Array.isArray(pageResult.json.inferenceProfileSummaries) ? pageResult.json.inferenceProfileSummaries : [];
    profiles.push(...pageProfiles);
    nextToken = typeof pageResult.json.nextToken === "string" && pageResult.json.nextToken ? pageResult.json.nextToken : null;
    if (!nextToken) break;
    if (page === 19) throw new Error("AWS_BEDROCK_PROFILE_PAGINATION_LIMIT");
  }
  const availabilityPairs = await mapLimit(models, 8, async (model) => {
    try {
      const result = await signedJson({ service:"bedrock", region, host, method:"GET", path:`/foundation-model-availability/${rfc3986(model.modelId)}`, credentials, fetchFn, now });
      return [model.modelId, result.json];
    } catch (error) {
      return [model.modelId, { agreementAvailability:{status:"ERROR",errorMessage:error.awsCode || error.message}, authorizationStatus:"UNKNOWN", entitlementAvailability:"UNKNOWN", regionAvailability:"UNKNOWN" }];
    }
  });
  return normalizeBedrockCatalogSnapshot({ foundationModels: models, inferenceProfiles: profiles, availabilityByModel: Object.fromEntries(availabilityPairs), region, observedAt: now.toISOString() });
}
async function probeBedrockCatalog({ snapshot, fetchFn = globalThis.fetch, resolveWorkloadToken, now = new Date() }) {
  const plan = buildBedrockProbePlan(snapshot), credentials = await credentialsForControl(resolveWorkloadToken, fetchFn), region = BEDROCK_REGION, host = `bedrock-runtime.${region}.amazonaws.com`, body = minimalBedrockProbeBody();
  return mapLimit(plan, 6, async (model) => {
    const attemptedAt = new Date().toISOString();
    if (!model.invocationTarget) return { modelId:model.modelId, invocationTarget:null, success:false, httpStatus:null, reason:"invocation_target_unresolved", attemptedAt, inputTokens:0, outputTokens:0, totalTokens:0 };
    try {
      const result = await signedJson({ service:"bedrock", region, host, method:"POST", path:`/model/${rfc3986(model.invocationTarget)}/converse`, body, credentials, fetchFn, now });
      const usage = result.json?.usage || {};
      return { modelId:model.modelId, invocationTarget:model.invocationTarget, success:true, httpStatus:result.response.status, reason:null, attemptedAt, inputTokens:Number(usage.inputTokens || 0), outputTokens:Number(usage.outputTokens || 0), totalTokens:Number(usage.totalTokens || (Number(usage.inputTokens || 0)+Number(usage.outputTokens || 0))), providerRequestId:result.response.headers?.get?.("x-amzn-requestid") || null };
    } catch (error) {
      return { modelId:model.modelId, invocationTarget:model.invocationTarget, success:false, httpStatus:Number.isInteger(error.status)?error.status:null, reason:String(error.awsCode || error.message || "provider_error").slice(0,240), attemptedAt, inputTokens:0, outputTokens:0, totalTokens:0 };
    }
  });
}
module.exports = { fetchBedrockCatalogTruth, probeBedrockCatalog, signAwsRequest };
