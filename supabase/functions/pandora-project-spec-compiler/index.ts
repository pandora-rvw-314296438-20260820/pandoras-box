import "jsr:@supabase/functions-js@2.4.5/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.57.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const MODEL = Deno.env.get("PANDORA_PROJECT_SPEC_MODEL") || "gemini-3.5-flash-lite";
const COMPILER_VERSION = "project-spec-compiler-v5";
const MAX_BODY_BYTES = 2048;
const MAX_MODEL_TEXT_BYTES = 262144;

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function exactKeys(value: JsonRecord, expected: string[]) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length && actual.every((key, i) => key === wanted[i]);
}

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

async function readBody(req: Request) {
  const declared = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) throw new Error("INVALID_REQUEST");
  const text = await req.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) throw new Error("INVALID_REQUEST");
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { throw new Error("INVALID_REQUEST"); }
  const body = record(parsed);
  if (!exactKeys(body, ["intentId"]) || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(body.intentId || ""))) {
    throw new Error("INVALID_REQUEST");
  }
  return { intentId: String(body.intentId) };
}

function userClient(authorization: string) {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error("SERVICE_UNAVAILABLE");
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
}

function adminClient() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error("SERVICE_UNAVAILABLE");
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function tokenCount(value: unknown) {
  const parsed = Number(value ?? 0);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0;
}

function stringArray(value: unknown, field: string, required = false) {
  if (value == null) {
    if (required) throw new Error("INVALID_STRUCTURED_OUTPUT");
    return [] as string[];
  }
  if (!Array.isArray(value) || value.length > 50) throw new Error("INVALID_STRUCTURED_OUTPUT");
  const out = value.map((item) => text(item));
  if (out.some((item) => !item || item.length > 10000)) throw new Error("INVALID_STRUCTURED_OUTPUT");
  if (required && !out.length) throw new Error("INVALID_STRUCTURED_OUTPUT");
  return out;
}

function namedArray(value: unknown, relationship = false) {
  if (value == null) return;
  if (!Array.isArray(value) || value.length > 50) throw new Error("INVALID_STRUCTURED_OUTPUT");
  for (const item of value) {
    const row = record(item);
    if (!text(row.name) || text(row.name).length > 500) throw new Error("INVALID_STRUCTURED_OUTPUT");
    if (relationship && (!text(row.from) || !text(row.to))) throw new Error("INVALID_STRUCTURED_OUTPUT");
  }
}

function allowedKeys(value: JsonRecord, allowed: string[]) {
  const permitted = new Set(allowed);
  if (Object.keys(value).some((key) => !permitted.has(key))) {
    throw new Error("INVALID_STRUCTURED_OUTPUT");
  }
}

function requiredProposalText(value: unknown, max: number) {
  const normalized = text(value);
  if (!normalized || normalized.length > max) throw new Error("INVALID_STRUCTURED_OUTPUT");
  return normalized;
}

function validateCandidate(value: unknown) {
  const root = record(value);
  const allowed = new Set(["version", "business", "product", "data", "integrations", "design", "deployment", "acceptance", "metadata"]);
  if (!Object.keys(root).length || Object.keys(root).some((key) => !allowed.has(key))) throw new Error("INVALID_STRUCTURED_OUTPUT");
  if (root.version !== "1.0") throw new Error("INVALID_STRUCTURED_OUTPUT");

  const business = record(root.business);
  if (!text(business.objective) || text(business.objective).length > 5000) throw new Error("INVALID_STRUCTURED_OUTPUT");
  for (const key of ["expectedOutcome", "successMetric", "baseline", "target"]) {
    if (business[key] != null && (typeof business[key] !== "string" || text(business[key]).length > 5000)) throw new Error("INVALID_STRUCTURED_OUTPUT");
  }
  stringArray(business.constraints, "business.constraints");

  const product = record(root.product);
  allowedKeys(product, [
    "projectType", "users", "roles", "workflows", "features", "screens", "userStories",
    "productPromise", "audiences", "customerValue", "ownerValue", "coreExperiences",
    "firstVersionCapabilities", "primaryWorkflows",
  ]);
  if (!["website", "web_application", "mobile_application", "system", "api", "automation", "other"].includes(text(product.projectType))) {
    throw new Error("INVALID_STRUCTURED_OUTPUT");
  }
  for (const key of ["users", "roles", "workflows", "features", "screens", "userStories"]) stringArray(product[key], `product.${key}`);
  requiredProposalText(product.productPromise, 1200);
  requiredProposalText(product.customerValue, 1200);
  requiredProposalText(product.ownerValue, 1200);
  stringArray(product.audiences, "product.audiences", true);
  stringArray(product.coreExperiences, "product.coreExperiences", true);
  stringArray(product.firstVersionCapabilities, "product.firstVersionCapabilities", true);
  stringArray(product.primaryWorkflows, "product.primaryWorkflows", true);

  const data = record(root.data);
  namedArray(data.entities);
  namedArray(data.relationships, true);
  const integrations = record(root.integrations);
  for (const key of ["payment", "messaging", "analytics", "externalApis", "providerRequirements"]) stringArray(integrations[key], `integrations.${key}`);
  const design = record(root.design);
  for (const key of ["brandRequirements", "accessibility", "platforms"]) stringArray(design[key], `design.${key}`);
  const platforms = stringArray(design.platforms, "design.platforms");
  if (platforms.some((item) => !["web", "ios", "android", "desktop", "server"].includes(item))) throw new Error("INVALID_STRUCTURED_OUTPUT");
  if (design.responsive != null && typeof design.responsive !== "boolean") throw new Error("INVALID_STRUCTURED_OUTPUT");

  const metadata = record(root.metadata);
  const projectName = text(metadata.projectName);
  const intentSummary = text(metadata.intentSummary);
  if (!projectName || projectName.length > 80 || projectName.split(/\s+/).length > 8) throw new Error("INVALID_STRUCTURED_OUTPUT");
  if (!intentSummary || intentSummary.length > 280) throw new Error("INVALID_STRUCTURED_OUTPUT");

  const acceptance = record(root.acceptance);
  allowedKeys(acceptance, ["functional", "business", "successCriteria", "reviewAssurance"]);
  stringArray(acceptance.functional, "acceptance.functional", true);
  stringArray(acceptance.business, "acceptance.business");
  stringArray(acceptance.successCriteria, "acceptance.successCriteria", true);
  requiredProposalText(acceptance.reviewAssurance, 1200);

  const serialized = JSON.stringify(root);
  if (new TextEncoder().encode(serialized).byteLength > MAX_MODEL_TEXT_BYTES || /AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i.test(serialized)) {
    throw new Error("INVALID_STRUCTURED_OUTPUT");
  }
  return root;
}

async function sha256(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function modelRequest(intent: JsonRecord, project: JsonRecord) {
  const kind = text(record(project.config).customerJourney && record(record(project.config).customerJourney).buildKind) || "help_me_decide";
  const system = [
    "Compile the customer request into one ProjectSpec JSON object.",
    "Return JSON only. Do not add markdown or commentary.",
    "Use version 1.0 and exactly these top-level sections: version, business, product, data, integrations, design, deployment, acceptance, metadata.",
    "Use exactly these nested shapes: business={objective:string,expectedOutcome?:string,successMetric?:string,baseline?:string,target?:string,constraints?:string[]}; product={projectType:string,users?:string[],roles?:string[],workflows?:string[],features?:string[],screens?:string[],userStories?:string[],productPromise:string,audiences:string[],customerValue:string,ownerValue:string,coreExperiences:string[],firstVersionCapabilities:string[],primaryWorkflows:string[]}; data={entities?:{name:string}[],relationships?:{name:string,from:string,to:string}[]}; integrations={payment?:string[],messaging?:string[],analytics?:string[],externalApis?:string[],providerRequirements?:string[]}; design={brandRequirements?:string[],accessibility?:string[],platforms?:string[],responsive?:boolean}; deployment={} or an owner-readable JSON object; acceptance={functional:string[],business?:string[],successCriteria:string[],reviewAssurance:string}; metadata={projectName:string,intentSummary:string}.",
    "For design.platforms use only web, ios, android, desktop, or server. Do not substitute alternate field names and do not put objects inside fields defined as string arrays.",
    "product.projectType must be website, web_application, mobile_application, system, api, automation, or other.",
    "acceptance.functional and acceptance.successCriteria must each contain at least one observable criterion.",
    "product.productPromise, product.audiences, product.customerValue, product.ownerValue, product.coreExperiences, product.firstVersionCapabilities, product.primaryWorkflows, acceptance.successCriteria, and acceptance.reviewAssurance are required owner-facing proposal fields. Keep them concise, specific, non-duplicative, and grounded only in the customer request.",
    "metadata.projectName must be a concise owner-facing name, ideally 2-6 words and no more than 60 characters. Name the thing being built; do not repeat the raw request or start with verbs such as Build, Create, Make, Design, or Develop.",
    "metadata.intentSummary must be one concise owner-readable sentence, no more than 240 characters, stating what Pandora will build without implementation jargon.",
    "Do not invent measured business results, credentials, provider secrets, deployed URLs, guaranteed outcomes, or unsupported claims.",
    "Write the ProjectSpec so its owner-facing fields can double as a polished product proposal. Be concrete, commercially aware, and specific to this customer's domain without sounding like generic AI copy.",
    "business.objective should express the core product outcome in plain language. business.expectedOutcome, when used, should explain why the product is worth having without inventing metrics.",
    "product.customerValue and product.ownerValue must describe plausible benefits, not fabricated performance claims. product.productPromise must state what the product will reliably enable without guarantees Pandora cannot verify.",
    "product.features, product.workflows, product.screens, and product.userStories should describe tangible capabilities and customer-visible experiences rather than implementation tasks. Prefer 4-8 strong, non-duplicative items when the intent supports them.",
    "acceptance.business should state believable owner-visible success conditions. acceptance.functional should state observable working-product behavior.",
    "Make the proposal feel considered and desirable: emphasize control, convenience, clarity, speed, reduced friction, direct customer experience, or other benefits only when they genuinely follow from the request.",
    "Prefer owner-readable requirements and infer technical details only when needed to satisfy the stated result."
  ].join(" ");
  const prompt = `Project name: ${text(project.name).slice(0, 300)}\nRequested project kind: ${kind.slice(0, 80)}\nCustomer intent:\n${text(intent.intent_text).slice(0, 50000)}`;
  return {
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      responseMimeType: "application/json",
      temperature: 0.15,
      maxOutputTokens: 8192,
    },
  };
}

function providerText(envelope: JsonRecord) {
  const status = Number(envelope.status || 0);
  if (status < 200 || status >= 300) throw new Error(status === 429 || status >= 500 ? "PROVIDER_UNAVAILABLE" : "PROVIDER_REJECTED");
  const body = record(envelope.body);
  const candidates = Array.isArray(body.candidates) ? body.candidates : [];
  const first = record(candidates[0]);
  const content = record(first.content);
  const parts = Array.isArray(content.parts) ? content.parts : [];
  const output = parts.map((part) => text(record(part).text)).filter(Boolean).join("");
  if (!output || new TextEncoder().encode(output).byteLength > MAX_MODEL_TEXT_BYTES) throw new Error("INVALID_STRUCTURED_OUTPUT");
  return output;
}

async function markFailed(admin: ReturnType<typeof adminClient>, intentId: string, claimToken: string, code: string) {
  try {
    await admin.rpc("pandora_fail_project_spec_compilation_20260829", {
      p_source_intent_id: intentId,
      p_claim_token: claimToken,
      p_safe_error_code: /^[A-Z0-9_]{3,80}$/.test(code) ? code : "COMPILATION_FAILED",
    });
  } catch { /* fail closed; stale claim becomes retryable after lease timeout */ }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ ok: false, state: "rejected" }, 405);
  const authorization = req.headers.get("authorization") || "";
  if (!/^Bearer\s+\S+$/i.test(authorization)) return response({ ok: false, state: "rejected" }, 401);
  let claimToken = "";
  let intentId = "";
  try {
    ({ intentId } = await readBody(req));
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(MODEL)) throw new Error("MODEL_CONFIGURATION_INVALID");

    const user = userClient(authorization);
    const { data: auth, error: authError } = await user.auth.getUser();
    if (authError || !auth.user) throw new Error("SIGN_IN_REQUIRED");
    const { data: intent, error: intentError } = await user
      .from("pandora_project_intents")
      .select("id,organization_id,project_id,requester_id,intent_kind,intent_text")
      .eq("id", intentId)
      .maybeSingle();
    if (intentError || !intent) throw new Error("INTENT_NOT_AVAILABLE");
    const { data: project, error: projectError } = await user
      .from("projectos_projects")
      .select("id,name,objective,config")
      .eq("id", intent.project_id)
      .eq("organization_id", intent.organization_id)
      .maybeSingle();
    if (projectError || !project) throw new Error("PROJECT_NOT_AVAILABLE");

    const admin = adminClient();
    const { data: claimData, error: claimError } = await admin.rpc("pandora_claim_project_spec_compilation_20260829", { p_source_intent_id: intentId });
    if (claimError) throw new Error("COMPILATION_CLAIM_FAILED");
    const claim = record(claimData);
    const state = text(claim.state);
    if (state === "succeeded") return response({ ok: true, state: "ready" });
    if (state === "running" || state === "waiting") return response({ ok: true, state: "working" }, 202);
    if (state === "failed") return response({ ok: false, state: "blocked" }, 409);
    claimToken = text(claim.claimToken);
    if (!claimToken) throw new Error("COMPILATION_CLAIM_FAILED");

    const requestId = crypto.randomUUID();
    let requestDigest = "";
    let responseDigest = "";
    let inputTokens = 0;
    let outputTokens = 0;
    let totalTokens = 0;
    let modelRevision = MODEL;
    let candidate: JsonRecord | null = null;
    let structuredOutputAttempt = 0;
    for (let attempt = 1; attempt <= 3; attempt++) {
      structuredOutputAttempt = attempt;
      const attemptRequest = modelRequest(record(intent), record(project));
      if (attempt > 1) {
        const instruction = record(attemptRequest.systemInstruction);
        const parts = Array.isArray(instruction.parts) ? instruction.parts : [];
        const first = record(parts[0]);
        attemptRequest.systemInstruction = {
          parts: [{
            text: `${text(first.text)} Previous output failed strict ProjectSpec validation. Return only the exact required JSON shape with no extra fields and no alternate nested types.`,
          }],
        };
        attemptRequest.generationConfig.temperature = 0;
      }
      const attemptRequestDigest = await sha256(JSON.stringify(attemptRequest));
      const { data: modelData, error: modelError } = await admin.rpc("pandora_worker_b_gemini_request_20260829", {
        p_model: MODEL,
        p_body: attemptRequest,
      });
      if (modelError) throw new Error("PROVIDER_UNAVAILABLE");
      const modelEnvelope = record(modelData);
      const outputText = providerText(modelEnvelope);
      const providerBody = record(modelEnvelope.body);
      const usage = record(providerBody.usageMetadata);
      const attemptInputTokens = tokenCount(usage.promptTokenCount);
      const attemptOutputTokens = tokenCount(usage.candidatesTokenCount);
      const attemptTotalTokens = Math.max(tokenCount(usage.totalTokenCount), attemptInputTokens, attemptOutputTokens);
      inputTokens += attemptInputTokens;
      outputTokens += attemptOutputTokens;
      totalTokens += attemptTotalTokens;
      let parsed: unknown;
      try {
        parsed = JSON.parse(outputText);
        candidate = validateCandidate(parsed);
      } catch (error) {
        if (!(error instanceof Error) || error.message !== "INVALID_STRUCTURED_OUTPUT" || attempt === 3) throw error;
        continue;
      }
      requestDigest = attemptRequestDigest;
      responseDigest = await sha256(outputText);
      modelRevision = text(providerBody.modelVersion) || MODEL;
      break;
    }
    if (!candidate) throw new Error("INVALID_STRUCTURED_OUTPUT");
    const digest = await sha256(JSON.stringify(candidate));
    const { data: committed, error: commitError } = await admin.rpc("pandora_commit_compiled_project_spec_v2_20260901", {
      p_source_intent_id: intentId,
      p_claim_token: claimToken,
      p_candidate: candidate,
      p_compiler_provider: "gemini",
      p_compiler_model: MODEL,
      p_compiler_version: COMPILER_VERSION,
      p_compiler_provenance: { request_id: requestId, transport: "vault_server_boundary", structured_output: true, structured_output_attempts: structuredOutputAttempt },
      p_content_sha256: digest,
      p_model_request_id: requestId,
      p_model_request_sha256: requestDigest,
      p_model_response_sha256: responseDigest,
      p_model_input_tokens: inputTokens,
      p_model_output_tokens: outputTokens,
      p_model_total_tokens: totalTokens,
      p_model_revision: modelRevision,
    });
    if (commitError || text(record(committed).state) !== "succeeded") throw new Error("COMMIT_FAILED");
    const committedSpec = record(committed);
    const projectSpecId = text(committedSpec.projectSpecId);
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(projectSpecId)) throw new Error("COMMIT_FAILED");
    const { data: primitiveResolution, error: primitiveResolutionError } = await admin.rpc(
      "pandora_worker_i_resolve_project_spec_primitives_20260831",
      { p_project_spec_id: projectSpecId, p_require_trusted: false },
    );
    if (primitiveResolutionError) throw new Error("PRIMITIVE_SELECTION_UNAVAILABLE");
    const primitiveState = text(record(primitiveResolution).state);
    if (!["READY", "BLOCKED"].includes(primitiveState)) throw new Error("PRIMITIVE_SELECTION_UNAVAILABLE");
    return response({ ok: true, state: "ready", primitiveSelectionState: primitiveState });
  } catch (error) {
    const code = error instanceof Error ? error.message : "COMPILATION_FAILED";
    if (claimToken && intentId) await markFailed(adminClient(), intentId, claimToken, code);
    const status = code === "SIGN_IN_REQUIRED" ? 401 : code === "INVALID_REQUEST" ? 400 : code === "INTENT_NOT_AVAILABLE" || code === "PROJECT_NOT_AVAILABLE" ? 404 : code === "PROVIDER_UNAVAILABLE" ? 503 : code === "PROVIDER_REJECTED" || code === "INVALID_STRUCTURED_OUTPUT" ? 422 : 503;
    return response({ ok: false, state: status === 503 ? "waiting" : "blocked", error: { code } }, status);
  }
});
