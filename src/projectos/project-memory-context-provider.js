"use strict";

const { PandoraPlanMemoryContextProvider } = require("../runtime/plan-memory-context.js");
const { memoryProjectKeyForProjectOsIntake } = require("../runtime/source-authority.js");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DECISION_TYPES = new Set(["project_spec", "build", "repair"]);
const MAX_RESPONSE_BYTES = 256 * 1024;

class ProjectMemoryContextError extends Error {
  constructor(message, status = 503) {
    super(message);
    this.name = "ProjectMemoryContextError";
    this.status = status;
  }
}

async function boundedJson(response) {
  const declared = Number(response.headers.get("content-length") || 0);
  if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) {
    throw new ProjectMemoryContextError("MEMORY_CONTEXT_RESPONSE_TOO_LARGE", 503);
  }
  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > MAX_RESPONSE_BYTES) {
    throw new ProjectMemoryContextError("MEMORY_CONTEXT_RESPONSE_TOO_LARGE", 503);
  }
  if (!text.trim()) throw new ProjectMemoryContextError("MEMORY_CONTEXT_EMPTY_RESPONSE", 503);
  try { return JSON.parse(text); } catch { throw new ProjectMemoryContextError("MEMORY_CONTEXT_INVALID_RESPONSE", 503); }
}

class ProjectMemoryContextProvider {
  constructor(options = {}) {
    this.supabaseUrl = String(options.supabaseUrl || "").replace(/\/$/, "");
    this.publishableKey = String(options.publishableKey || "");
    this.organizationId = String(options.organizationId || "");
    this.fetchFn = options.fetchFn || globalThis.fetch;
    this.memory = options.memoryProvider || new PandoraPlanMemoryContextProvider({ fetchFn: this.fetchFn });
  }

  async primary(path, accessToken, init = {}) {
    if (!this.supabaseUrl || !this.publishableKey || !accessToken) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_PRIMARY_CONFIG_UNAVAILABLE", 503);
    }
    const response = await this.fetchFn(`${this.supabaseUrl}${path}`, {
      ...init,
      redirect: "error",
      headers: {
        apikey: this.publishableKey,
        authorization: `Bearer ${accessToken}`,
        accept: "application/json",
        "content-type": "application/json",
        ...(init.headers || {}),
      },
      signal: AbortSignal.timeout(9000),
    });
    const parsed = await boundedJson(response);
    if (!response.ok) {
      throw new ProjectMemoryContextError(`MEMORY_CONTEXT_PRIMARY_${response.status}`, response.status === 401 || response.status === 403 ? response.status : 503);
    }
    return parsed;
  }

  async prepareIntent({ intentId, decisionType, accessToken, vercelOidcToken }) {
    if (!UUID.test(String(intentId || "")) || !DECISION_TYPES.has(decisionType)) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_REQUEST_INVALID", 400);
    }
    if (typeof vercelOidcToken !== "string" || vercelOidcToken.length < 64) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_WORKLOAD_IDENTITY_UNAVAILABLE", 503);
    }

    const intents = await this.primary(
      `/rest/v1/pandora_project_intents?id=eq.${encodeURIComponent(intentId)}&organization_id=eq.${encodeURIComponent(this.organizationId)}&select=id,organization_id,project_id`,
      accessToken,
    );
    const intent = Array.isArray(intents) ? intents[0] : null;
    if (!intent || !UUID.test(String(intent.project_id || ""))) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_INTENT_NOT_AVAILABLE", 404);
    }

    const projects = await this.primary(
      `/rest/v1/projectos_projects?id=eq.${encodeURIComponent(intent.project_id)}&organization_id=eq.${encodeURIComponent(this.organizationId)}&select=id,organization_id,project_key,status`,
      accessToken,
    );
    const project = Array.isArray(projects) ? projects[0] : null;
    if (!project || typeof project.project_key !== "string" || project.status === "archived") {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_PROJECT_NOT_AVAILABLE", 404);
    }

    const memoryProjectKey = memoryProjectKeyForProjectOsIntake(project.project_key);
    const hydrated = await this.memory.hydrate(vercelOidcToken, {
      tool: `visible_creation.${decisionType}`,
      args: { projectKey: memoryProjectKey, projectId: project.id },
    });
    const envelope = hydrated && hydrated.envelope;
    if (!envelope || typeof hydrated.contextHash !== "string") {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_HYDRATION_INVALID", 503);
    }

    const failureStatus = envelope.status === "unavailable" && envelope.failure
      ? Number(envelope.failure.status || 0)
      : 0;
    if (envelope.status === "unavailable" && ![403, 404].includes(failureStatus)) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_PROVIDER_UNAVAILABLE", 503);
    }

    const available = envelope.status === "available" || envelope.status === "empty";
    if (available && (!UUID.test(String(hydrated.memoryProjectId || "")) || hydrated.memoryProjectKey !== memoryProjectKey || !UUID.test(String(hydrated.retrievalLogId || "")))) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_LINEAGE_UNAVAILABLE", 503);
    }
    const approvedMemoryItemIds = available && Array.isArray(hydrated.approvedMemoryItemIds)
      ? hydrated.approvedMemoryItemIds.filter((value) => UUID.test(String(value))).slice(0, 50)
      : [];
    if (envelope.status === "available" && approvedMemoryItemIds.length === 0) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_APPROVED_REFS_MISSING", 503);
    }
    if (envelope.status === "empty" && approvedMemoryItemIds.length !== 0) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_EMPTY_REFS_INVALID", 503);
    }

    const receipt = await this.primary(
      "/rest/v1/rpc/pandora_record_project_memory_context_v1",
      accessToken,
      {
        method: "POST",
        body: JSON.stringify({
          p_source_intent_id: intent.id,
          p_decision_type: decisionType,
          p_memory_project_id: available ? hydrated.memoryProjectId : null,
          p_memory_project_key: memoryProjectKey,
          p_context_status: envelope.status,
          p_context_hash: hydrated.contextHash,
          p_retrieval_log_id: available ? hydrated.retrievalLogId : null,
          p_approved_memory_item_ids: approvedMemoryItemIds,
          p_context_envelope: envelope,
        }),
      },
    );
    if (!receipt || !UUID.test(String(receipt.receiptId || ""))) {
      throw new ProjectMemoryContextError("MEMORY_CONTEXT_RECEIPT_WRITE_FAILED", 503);
    }

    return {
      receiptId: receipt.receiptId,
      sourceIntentId: intent.id,
      projectId: project.id,
      decisionType,
      memoryProjectId: receipt.memoryProjectId || null,
      memoryProjectKey,
      contextStatus: envelope.status,
      contextHash: hydrated.contextHash,
      retrievalLogId: available ? hydrated.retrievalLogId : null,
      approvedMemoryItemIds,
      contextEnvelope: envelope,
    };
  }
}

module.exports = { ProjectMemoryContextProvider, ProjectMemoryContextError };
