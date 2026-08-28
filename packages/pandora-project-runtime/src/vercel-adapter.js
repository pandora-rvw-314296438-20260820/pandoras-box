"use strict";

const {
  DeploymentProvider,
  assertExactLineage,
  deploymentStateFromProvider,
  domainStateFromFacts,
  normalizeDeploymentRequest,
  normalizeDomain,
  normalizeProviderError,
  operationIdempotencyKey,
  redactProviderData,
} = require("./index.js");

const TEAM_ID = /^team_[A-Za-z0-9]+$/;
const PROJECT_ID = /^prj_[A-Za-z0-9]+$/;
const DEPLOYMENT_ID = /^dpl_[A-Za-z0-9]+$/;

function required(value, field, pattern) {
  if (typeof value !== "string" || !value.trim() || (pattern && !pattern.test(value.trim()))) {
    throw new Error(`${field} is invalid`);
  }
  return value.trim();
}

function appendQuery(path, params) {
  const url = new URL(`https://api.vercel.com${path}`);
  for (const [key, value] of Object.entries(params || {})) {
    if (value !== null && value !== undefined && value !== "") url.searchParams.set(key, String(value));
  }
  return `${url.pathname}${url.search}`;
}

function retryAfterMs(response) {
  const seconds = Number(response?.headers?.["retry-after"] ?? response?.retryAfter);
  return Number.isFinite(seconds) && seconds >= 0 ? seconds * 1000 : null;
}

function providerError(response, mutationMayHaveCommitted = false) {
  const body = response?.body || {};
  const err = new Error(body?.error?.message || body?.message || `Vercel request failed (${response?.status || "unknown"})`);
  err.status = response?.status;
  err.code = body?.error?.code || body?.code;
  err.providerCode = err.code;
  err.retryAfterMs = retryAfterMs(response);
  err.mutationMayHaveCommitted = mutationMayHaveCommitted;
  return err;
}

function assertOk(response, mutationMayHaveCommitted = false) {
  if (!response || typeof response.status !== "number") {
    const err = new Error("Vercel transport returned no status");
    err.mutationMayHaveCommitted = mutationMayHaveCommitted;
    throw err;
  }
  if (response.status < 200 || response.status >= 300) throw providerError(response, mutationMayHaveCommitted);
  return response.body || {};
}

function exactMeta(request, operationId) {
  return {
    pandoraOperationId: operationId,
    pandoraProjectId: request.projectId,
    pandoraProjectVersionId: request.projectVersionId,
    pandoraArtifactDigest: request.artifactDigest,
    pandoraSourceCommit: request.sourceCommit,
    pandoraRuntimeEnvironment: request.environment,
  };
}

function normalizeDeploymentFact(body, request = null) {
  const providerDeploymentId = required(body?.id || body?.uid, "provider deployment id", DEPLOYMENT_ID);
  const providerState = body.readyState || body.state || "QUEUED";
  const fact = {
    provider: "vercel",
    providerProjectId: body.projectId || body.project?.id || null,
    providerDeploymentId,
    immutableUrl: body.url ? `https://${String(body.url).replace(/^https?:\/\//, "")}` : null,
    providerState,
    status: deploymentStateFromProvider(providerState),
    target: body.target || null,
    readyAt: body.ready ? new Date(body.ready).toISOString() : null,
    meta: redactProviderData(body.meta || {}),
  };
  if (request) {
    fact.projectVersionId = request.projectVersionId;
    fact.artifactDigest = request.artifactDigest;
    fact.sourceCommit = request.sourceCommit;
  } else {
    const meta = body.meta || {};
    fact.projectVersionId = meta.pandoraProjectVersionId || null;
    fact.artifactDigest = meta.pandoraArtifactDigest || null;
    fact.sourceCommit = meta.pandoraSourceCommit || null;
  }
  return Object.freeze(fact);
}

class VercelDeploymentProvider extends DeploymentProvider {
  constructor({ transport, teamId, projectId = null, projectName = null }) {
    super("vercel");
    if (!transport || typeof transport.request !== "function") throw new Error("server-side Vercel transport is required");
    this.transport = transport;
    this.teamId = required(teamId, "teamId", TEAM_ID);
    this.projectId = projectId ? required(projectId, "projectId", PROJECT_ID) : null;
    this.projectName = projectName ? required(projectName, "projectName", /^[a-z0-9][a-z0-9-]{0,99}$/) : null;
  }

  async _request(method, path, body = null, mutationMayHaveCommitted = false) {
    try {
      const response = await this.transport.request(method, path, body);
      return { response, body: assertOk(response, mutationMayHaveCommitted) };
    } catch (error) {
      if (mutationMayHaveCommitted) error.mutationMayHaveCommitted = true;
      const normalized = normalizeProviderError(error);
      error.normalizedProviderError = normalized;
      throw error;
    }
  }

  async createProjectRuntime({ name, framework = null, idempotencyRef }) {
    const projectName = required(name, "project runtime name", /^[a-z0-9][a-z0-9-]{0,99}$/);
    required(idempotencyRef, "idempotencyRef", /^[a-f0-9]{64}$/);
    const path = appendQuery("/v11/projects", { teamId: this.teamId });
    try {
      const { body } = await this._request("POST", path, { name: projectName, framework, buildCommand: null }, true);
      this.projectId = required(body.id, "Vercel project id", PROJECT_ID);
      this.projectName = body.name || projectName;
      return Object.freeze({ provider: "vercel", providerProjectId: this.projectId, providerProjectName: this.projectName });
    } catch (error) {
      const kind = error.normalizedProviderError?.kind;
      if (!["conflict", "ambiguous_mutation"].includes(kind)) throw error;
      const { body } = await this._request("GET", appendQuery(`/v9/projects/${encodeURIComponent(projectName)}`, { teamId: this.teamId }));
      this.projectId = required(body.id, "Vercel project id", PROJECT_ID);
      this.projectName = body.name || projectName;
      return Object.freeze({ provider: "vercel", providerProjectId: this.projectId, providerProjectName: this.projectName, reconciled: true });
    }
  }

  async findDeploymentByOperation(operationId) {
    required(operationId, "operationId", /^[a-f0-9]{64}$/);
    if (!this.projectId) throw new Error("provider project must be resolved before deployment reconciliation");
    const path = appendQuery("/v6/deployments", { teamId: this.teamId, projectId: this.projectId, limit: 100 });
    const { body } = await this._request("GET", path);
    const deployments = Array.isArray(body.deployments) ? body.deployments : [];
    const match = deployments.find(item => item?.meta?.pandoraOperationId === operationId);
    return match ? normalizeDeploymentFact(match) : null;
  }

  async createPreview(input, artifact) {
    const request = normalizeDeploymentRequest(input);
    if (request.environment !== "preview") throw new Error("createPreview requires preview environment");
    if (!this.projectId) throw new Error("provider project is required");
    if (!artifact || artifact.sha256 !== request.artifactDigest || !Array.isArray(artifact.files) || artifact.files.length === 0) {
      throw new Error("exact approved artifact is required");
    }
    const operationId = operationIdempotencyKey("create_preview", request);
    const prior = await this.findDeploymentByOperation(operationId);
    if (prior) {
      assertExactLineage(request, prior);
      return Object.freeze({ ...prior, operationId, reconciled: true });
    }
    const body = {
      name: this.projectName || undefined,
      project: this.projectId,
      target: "preview",
      files: artifact.files,
      meta: exactMeta(request, operationId),
    };
    try {
      const result = (await this._request("POST", appendQuery("/v13/deployments", { teamId: this.teamId }), body, true)).body;
      return Object.freeze({ ...normalizeDeploymentFact(result, request), operationId });
    } catch (error) {
      if (error.normalizedProviderError?.kind !== "ambiguous_mutation") throw error;
      const reconciled = await this.findDeploymentByOperation(operationId);
      if (!reconciled) throw error;
      assertExactLineage(request, reconciled);
      return Object.freeze({ ...reconciled, operationId, reconciled: true });
    }
  }

  async getDeployment(providerDeploymentId, request = null) {
    const id = required(providerDeploymentId, "providerDeploymentId", DEPLOYMENT_ID);
    const { body } = await this._request("GET", appendQuery(`/v13/deployments/${id}`, { teamId: this.teamId }));
    const fact = normalizeDeploymentFact(body, request);
    if (request) assertExactLineage(request, fact);
    return fact;
  }

  async publishVersion(input, previewFact) {
    const request = normalizeDeploymentRequest(input);
    if (request.environment !== "production") throw new Error("publishVersion requires production environment");
    if (!this.projectId) throw new Error("provider project is required");
    if (!previewFact || previewFact.status !== "ready_for_verification") throw new Error("only a provider-ready exact preview may be promoted");
    assertExactLineage(request, previewFact);
    const deploymentId = required(previewFact.providerDeploymentId, "providerDeploymentId", DEPLOYMENT_ID);
    const operationId = operationIdempotencyKey("publish_version", request);
    const path = appendQuery(`/v10/projects/${this.projectId}/promote/${deploymentId}`, { teamId: this.teamId });
    try {
      await this._request("POST", path, { meta: { pandoraOperationId: operationId } }, true);
    } catch (error) {
      if (error.normalizedProviderError?.kind !== "ambiguous_mutation") throw error;
      const reconciled = await this.getDeployment(deploymentId);
      if (reconciled.target !== "production") throw error;
    }
    const promoted = await this.getDeployment(deploymentId);
    if (promoted.target !== "production") {
      const err = new Error("provider has not confirmed production promotion");
      err.code = "PRODUCTION_PROMOTION_NOT_CONFIRMED";
      throw err;
    }
    return Object.freeze({ ...promoted, projectVersionId: request.projectVersionId, artifactDigest: request.artifactDigest, sourceCommit: request.sourceCommit, operationId, productionState: "ready_for_verification" });
  }

  async cancelDeployment(providerDeploymentId) {
    const id = required(providerDeploymentId, "providerDeploymentId", DEPLOYMENT_ID);
    const { body } = await this._request("PATCH", appendQuery(`/v12/deployments/${id}/cancel`, { teamId: this.teamId }), null, true);
    return normalizeDeploymentFact(body);
  }

  async rollback(input, targetFact) {
    const request = normalizeDeploymentRequest(input);
    if (request.environment !== "production") throw new Error("rollback requires production environment");
    if (!this.projectId) throw new Error("provider project is required");
    if (!targetFact) throw new Error("rollback target is required");
    assertExactLineage(request, targetFact);
    const deploymentId = required(targetFact.providerDeploymentId, "providerDeploymentId", DEPLOYMENT_ID);
    await this._request("POST", appendQuery(`/v1/projects/${this.projectId}/rollback/${deploymentId}`, { teamId: this.teamId }), null, true);
    const fact = await this.getDeployment(deploymentId);
    return Object.freeze({ ...fact, projectVersionId: request.projectVersionId, artifactDigest: request.artifactDigest, sourceCommit: request.sourceCommit, productionState: "ready_for_verification" });
  }

  async deletePreview(providerDeploymentId, { isProduction = false, approved = false } = {}) {
    if (isProduction || approved) throw new Error("active or approved deployment cleanup is forbidden");
    const id = required(providerDeploymentId, "providerDeploymentId", DEPLOYMENT_ID);
    const { body } = await this._request("DELETE", appendQuery(`/v13/deployments/${id}`, { teamId: this.teamId }), null, true);
    return Object.freeze({ providerDeploymentId: body.uid || id, status: "deleted" });
  }

  async attachDomain(domain) {
    if (!this.projectId) throw new Error("provider project is required");
    const normalized = normalizeDomain(domain);
    const path = appendQuery(`/v10/projects/${this.projectId}/domains`, { teamId: this.teamId });
    try {
      await this._request("POST", path, { name: normalized }, true);
    } catch (error) {
      if (!["conflict", "ambiguous_mutation"].includes(error.normalizedProviderError?.kind)) throw error;
    }
    return this.inspectDomain(normalized);
  }

  async inspectDomain(domain) {
    if (!this.projectId) throw new Error("provider project is required");
    const normalized = normalizeDomain(domain);
    const projectPath = appendQuery(`/v9/projects/${this.projectId}/domains/${encodeURIComponent(normalized)}`, { teamId: this.teamId });
    const configPath = appendQuery(`/v6/domains/${encodeURIComponent(normalized)}/config`, { teamId: this.teamId });
    const [{ body: projectDomain }, { body: config }] = await Promise.all([
      this._request("GET", projectPath),
      this._request("GET", configPath),
    ]);
    const facts = {
      ownershipVerified: projectDomain.verified === true,
      dnsConfigured: config.misconfigured === false,
      tlsReady: null,
      routingReady: config.misconfigured === false,
      runtimeHealthy: null,
    };
    return Object.freeze({
      provider: "vercel",
      domain: normalized,
      providerProjectId: this.projectId,
      facts,
      state: domainStateFromFacts(facts),
      verification: redactProviderData(projectDomain.verification || []),
    });
  }

  async reconcile(record) {
    if (!record?.providerDeploymentId) throw new Error("deployment reconciliation requires provider deployment id");
    return this.getDeployment(record.providerDeploymentId);
  }
}

module.exports = {
  VercelDeploymentProvider,
  appendQuery,
  exactMeta,
  normalizeDeploymentFact,
};
