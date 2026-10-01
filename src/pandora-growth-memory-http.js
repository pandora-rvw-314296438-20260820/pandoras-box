"use strict";

const express = require("express");
const { resolveVercelWorkloadToken } = require("./runtime/vercel-workload-identity.js");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const SOURCE_ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const SOURCE_PROJECT_ID = "ee282126-3f61-4058-8c92-2fedbfcecf1f";
const MEMORY_PROJECT_ID = "7c686cbd-d968-49d5-86cc-918f5e777bd2";
const MEMORY_PROJECT_KEY = "mcpmaster-pandoras-box";
const MEMORY_BRIDGE_URL = "https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-memory-bridge";

class GrowthMemoryError extends Error {
  constructor(status, code) {
    super(code);
    this.name = "GrowthMemoryError";
    this.status = status;
    this.code = code;
  }
}

function query(parameters) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(parameters)) {
    if (value !== undefined && value !== null) search.set(key, String(value));
  }
  return search.toString();
}

function parseJson(raw) {
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

function asRecord(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function containsCredentialMaterial(value) {
  return /AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(?:ql)?:\/\/[^:\s@]+:[^@\s]+@/i
    .test(JSON.stringify(value));
}

function sanitizeTerms(value) {
  if (value === undefined || value === null) return ["facebook", "marketing", "growth"];
  if (!Array.isArray(value) || value.length < 1 || value.length > 12) {
    throw new GrowthMemoryError(400, "growth_terms_invalid");
  }
  const terms = [...new Set(value.map((entry) =>
    typeof entry === "string" ? entry.trim().toLowerCase() : ""
  ))];
  if (terms.some((term) => term.length < 3 || term.length > 64 || !/^[a-z0-9][a-z0-9._ -]*$/.test(term))) {
    throw new GrowthMemoryError(400, "growth_terms_invalid");
  }
  return terms;
}

function createPrimaryClient(environment, fetchFn) {
  const baseUrl = String(environment.SUPABASE_URL || environment.NEXT_PUBLIC_SUPABASE_URL || "").replace(/\/+$/, "");
  const serviceKey = String(environment.SUPABASE_SERVICE_ROLE_KEY || environment.SUPABASE_SECRET_KEY || "");
  if (!baseUrl || !serviceKey) throw new GrowthMemoryError(503, "growth_backend_unconfigured");

  async function serviceRequest(path, options = {}) {
    const response = await fetchFn(baseUrl + path, {
      method: options.method || "GET",
      headers: {
        apikey: serviceKey,
        authorization: "Bearer " + (options.userToken || serviceKey),
        accept: "application/json",
        ...(options.body === undefined ? {} : { "content-type": "application/json" }),
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: AbortSignal.timeout(8000),
    });
    const payload = parseJson(await response.text());
    if (!response.ok) throw new GrowthMemoryError(response.status, "growth_backend_denied");
    return payload;
  }

  return { serviceRequest };
}

function publicRecord(value) {
  const row = asRecord(value);
  return {
    memoryRecordId: row.memoryRecordId,
    memoryVersionId: row.memoryVersionId,
    reviewItemId: row.reviewItemId,
    recordSha256: row.recordSha256,
    status: row.status,
    recordType: row.recordType || null,
    title: row.title || null,
    canonStatus: row.canonStatus || null,
    summary: row.summary || null,
    confidence: row.confidence ?? null,
    evidenceRefs: Array.isArray(row.evidenceRefs) ? row.evidenceRefs.slice(0, 16) : [],
    observedAt: row.observedAt || null,
    effectiveAt: row.effectiveAt || null,
    promotionBasis: row.promotionBasis || null,
    provenanceSemanticSource: row.provenanceSemanticSource || null,
    authorizationEffect: row.authorizationEffect || "none",
  };
}

function validateMemoryPayload(payload) {
  const root = asRecord(payload);
  const data = asRecord(root.data);
  const invariants = asRecord(data.invariants);
  const rawRecords = Array.isArray(data.records) ? data.records : [];
  if (
    root.ok !== true ||
    root.action !== "growth_context" ||
    root.project_id !== MEMORY_PROJECT_ID ||
    root.project_key !== MEMORY_PROJECT_KEY ||
    data.schemaVersion !== "growth.approved-memory-context.v1" ||
    data.status !== "available" ||
    data.namespace !== "real_life" ||
    !SHA256_RE.test(String(data.querySha256 || "")) ||
    !SHA256_RE.test(String(data.contextSha256 || "")) ||
    invariants.approvedCurrentOnly !== true ||
    invariants.pendingExcluded !== true ||
    invariants.rejectedExcluded !== true ||
    invariants.revokedExcluded !== true ||
    invariants.supersededExcluded !== true ||
    invariants.retrievalDoesNotGrantExecutionAuthority !== true ||
    invariants.canAuthorizeSpend !== false ||
    invariants.canMutateCampaigns !== false ||
    invariants.canPublish !== false ||
    invariants.operationsRoomRequired !== false ||
    rawRecords.length > 50
  ) {
    throw new GrowthMemoryError(503, "growth_memory_receipt_invalid");
  }
  const records = rawRecords.map(publicRecord);
  if (records.some((row) =>
    !UUID_RE.test(String(row.memoryRecordId || "")) ||
    !/^[0-9a-f-]{36}@[0-9a-f]{64}$/i.test(String(row.memoryVersionId || "")) ||
    !UUID_RE.test(String(row.reviewItemId || "")) ||
    !SHA256_RE.test(String(row.recordSha256 || "")) ||
    row.status !== "approved_current"
  ) || containsCredentialMaterial(records)) {
    throw new GrowthMemoryError(503, "growth_memory_receipt_invalid");
  }
  return { data, invariants, records };
}

function createPandoraGrowthMemoryRouter(options = {}) {
  const router = express.Router();
  const environment = options.environment || process.env;
  const fetchFn = options.fetchFn || globalThis.fetch;
  const oidcResolver = options.resolveOidc || resolveVercelWorkloadToken;
  if (typeof fetchFn !== "function") throw new Error("fetch is required");

  router.use("/api/growth/memory-context", express.json({ limit: "24kb", type: ["application/json", "application/*+json"] }));

  router.post("/api/growth/memory-context", async (req, res) => {
    try {
      const authorization = String(req.get("authorization") || "");
      const tokenMatch = authorization.match(/^Bearer\s+(\S{20,4096})$/i);
      const organizationId = String(req.get("x-organization-id") || "").trim().toLowerCase();
      if (!tokenMatch) throw new GrowthMemoryError(401, "sign_in_required");
      if (!UUID_RE.test(organizationId) || organizationId !== SOURCE_ORGANIZATION_ID) {
        throw new GrowthMemoryError(403, "organization_access_required");
      }
      const body = asRecord(req.body);
      if (Object.keys(body).some((key) => key !== "terms")) {
        throw new GrowthMemoryError(400, "unexpected_field");
      }
      const terms = sanitizeTerms(body.terms);
      const primary = createPrimaryClient(environment, fetchFn);

      const user = asRecord(await primary.serviceRequest("/auth/v1/user", { userToken: tokenMatch[1] }));
      if (!UUID_RE.test(String(user.id || ""))) throw new GrowthMemoryError(401, "sign_in_required");

      const memberships = await primary.serviceRequest("/rest/v1/memberships?" + query({
        select: "organization_id,role,status",
        user_id: "eq." + user.id,
        organization_id: "eq." + SOURCE_ORGANIZATION_ID,
        status: "eq.active",
        limit: 1,
      }));
      const membership = Array.isArray(memberships) ? asRecord(memberships[0]) : {};
      if (!["owner", "admin"].includes(String(membership.role || ""))) {
        throw new GrowthMemoryError(403, "owner_admin_required");
      }

      const tenants = await primary.serviceRequest("/rest/v1/pandora_tracking_tenants?" + query({
        select: "id,organization_id,project_id,workspace_key,status",
        organization_id: "eq." + SOURCE_ORGANIZATION_ID,
        project_id: "eq." + SOURCE_PROJECT_ID,
        workspace_key: "eq.pandora-platform",
        status: "eq.active",
        limit: 1,
      }));
      const tenant = Array.isArray(tenants) ? asRecord(tenants[0]) : {};
      if (tenant.project_id !== SOURCE_PROJECT_ID || tenant.organization_id !== SOURCE_ORGANIZATION_ID) {
        throw new GrowthMemoryError(503, "growth_binding_unavailable");
      }

      const oidc = await oidcResolver();
      if (!oidc) throw new GrowthMemoryError(503, "growth_memory_identity_unavailable");
      const memoryResponse = await fetchFn(MEMORY_BRIDGE_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-pandora-vercel-oidc": oidc,
        },
        body: JSON.stringify({
          action: "growth_context",
          project_id: MEMORY_PROJECT_ID,
          project_key: MEMORY_PROJECT_KEY,
          terms,
          max_bytes: 8192,
        }),
        redirect: "error",
        signal: AbortSignal.timeout(8000),
      });
      const memoryPayload = parseJson(await memoryResponse.text());
      if (!memoryResponse.ok) throw new GrowthMemoryError(503, "growth_memory_unavailable");
      const verified = validateMemoryPayload(memoryPayload);
      const observedAt = Number.isFinite(Date.parse(String(verified.data.asOf || "")))
        ? new Date(String(verified.data.asOf)).toISOString()
        : new Date().toISOString();

      for (const record of verified.records) {
        await primary.serviceRequest("/rest/v1/rpc/pandora_growth_record_memory_retrieval_receipt_v1", {
          method: "POST",
          body: {
            p_organization_id: SOURCE_ORGANIZATION_ID,
            p_project_id: SOURCE_PROJECT_ID,
            p_memory_record_id: record.memoryRecordId,
            p_memory_version_id: record.memoryVersionId,
            p_review_item_id: record.reviewItemId,
            p_query_sha256: verified.data.querySha256,
            p_record_sha256: record.recordSha256,
            p_evidence_ref: "memory-context:" + verified.data.contextSha256 + ":" + record.memoryRecordId,
            p_observed_at: observedAt,
          },
        });
      }

      const response = {
        ok: true,
        schemaVersion: "pandora-growth-approved-context-v1",
        source: "pandora-memory",
        sourceProjectId: SOURCE_PROJECT_ID,
        memoryProjectId: MEMORY_PROJECT_ID,
        querySha256: verified.data.querySha256,
        contextSha256: verified.data.contextSha256,
        asOf: observedAt,
        records: verified.records,
        invariants: {
          approvedCurrentOnly: true,
          retrievalDoesNotGrantExecutionAuthority: true,
          canAuthorizeSpend: false,
          canMutateCampaigns: false,
          canPublish: false,
          operationsRoomRequired: false,
        },
      };
      if (containsCredentialMaterial(response)) throw new GrowthMemoryError(503, "growth_memory_receipt_invalid");
      res.status(200).set({
        "cache-control": "no-store, max-age=0",
        "x-content-type-options": "nosniff",
      }).json(response);
    } catch (error) {
      const status = error instanceof GrowthMemoryError ? error.status : 500;
      const code = error instanceof GrowthMemoryError ? error.code : "growth_memory_failed";
      res.status(status).set({
        "cache-control": "no-store, max-age=0",
        "x-content-type-options": "nosniff",
      }).json({ ok: false, error: code });
    }
  });

  return router;
}

module.exports = {
  createPandoraGrowthMemoryRouter,
  _growthMemoryInternals: {
    sanitizeTerms,
    validateMemoryPayload,
    SOURCE_ORGANIZATION_ID,
    SOURCE_PROJECT_ID,
    MEMORY_PROJECT_ID,
    MEMORY_PROJECT_KEY,
    MEMORY_BRIDGE_URL,
  },
};
