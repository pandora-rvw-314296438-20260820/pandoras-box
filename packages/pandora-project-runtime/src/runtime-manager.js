"use strict";

const {
  assertExactLineage,
  assertProductionPrecondition,
  normalizeDeploymentRequest,
  normalizeDomain,
  operationIdempotencyKey,
} = require("./index.js");

class ProjectRuntimeManager {
  constructor({ store, provider }) {
    if (!store || typeof store.getOperation !== "function" || typeof store.claimOperation !== "function") throw new Error("durable runtime store is required");
    if (!provider) throw new Error("deployment provider is required");
    this.store = store;
    this.provider = provider;
  }

  async _owned(request, providerProjectId = null) {
    const owned = await this.store.assertOwnership({
      organizationId: request.organizationId,
      projectId: request.projectId,
      provider: request.provider,
      providerProjectId,
    });
    if (owned !== true) throw new Error("runtime resource ownership validation failed");
  }

  async _operation(action, input, fn, target = null) {
    const request = normalizeDeploymentRequest(input);
    const idempotencyKey = operationIdempotencyKey(action, { ...request, target });
    const existing = await this.store.getOperation(idempotencyKey);
    if (existing?.status === "succeeded") return existing.result;
    if (existing && ["claimed", "running", "uncertain"].includes(existing.status)) {
      return this.store.reconcileOperation(existing, { request, provider: this.provider });
    }
    const claim = await this.store.claimOperation({
      idempotencyKey,
      action,
      organizationId: request.organizationId,
      projectId: request.projectId,
      projectVersionId: request.projectVersionId,
      authorizationRef: request.authorizationRef,
      verificationRef: request.verificationRef,
      provider: request.provider,
      environment: request.environment,
    });
    if (!claim?.claimed) return this.store.reconcileOperation(claim, { request, provider: this.provider });
    try {
      await this.store.markOperationRunning(idempotencyKey);
      const result = await fn(request, idempotencyKey);
      await this.store.completeOperation(idempotencyKey, result);
      return result;
    } catch (error) {
      if (error?.normalizedProviderError?.kind === "ambiguous_mutation") {
        await this.store.markOperationUncertain(idempotencyKey, error.normalizedProviderError);
      } else {
        await this.store.failOperation(idempotencyKey, error?.normalizedProviderError || { kind: "provider_unavailable" });
      }
      throw error;
    }
  }

  async createPreview(input, artifact) {
    return this._operation("create_preview", input, async request => {
      await this._owned(request, this.provider.projectId);
      const result = await this.provider.createPreview(request, artifact);
      assertExactLineage(request, result);
      await this.store.recordDeployment(request, result);
      return result;
    });
  }

  async reconcileDeployment(record) {
    await this.store.assertRecordOwnership(record);
    const fact = await this.provider.reconcile(record);
    await this.store.recordProviderCheck(record.id, fact);
    return fact;
  }

  async publishVersion(input, previewFact) {
    return this._operation("publish_version", input, async request => {
      await this._owned(request, this.provider.projectId);
      const current = await this.store.getCurrentProductionVersion(request.projectId);
      assertProductionPrecondition(current, request);
      const verification = await this.store.getVerification(request.verificationRef);
      if (!verification || verification.projectVersionId !== request.projectVersionId || verification.artifactDigest !== request.artifactDigest || String(verification.status || "").toUpperCase() !== "PASS" || verification.stale === true) {
        throw new Error("fresh independent verification for exact artifact is required");
      }
      assertExactLineage(request, previewFact);
      const result = await this.provider.publishVersion(request, previewFact);
      assertExactLineage(request, result);
      await this.store.compareAndSetProduction({
        projectId: request.projectId,
        expectedVersionId: request.expectedProductionVersionId,
        newVersionId: request.projectVersionId,
        providerDeploymentId: result.providerDeploymentId,
      });
      await this.store.recordDeployment(request, result);
      return result;
    });
  }

  async rollback(input, targetFact) {
    return this._operation("rollback", input, async request => {
      await this._owned(request, this.provider.projectId);
      const eligibility = await this.store.getRollbackEligibility(request.projectVersionId);
      if (!eligibility?.eligible) throw new Error("target version is not rollback eligible");
      const result = await this.provider.rollback(request, targetFact);
      await this.store.compareAndSetProduction({
        projectId: request.projectId,
        expectedVersionId: request.expectedProductionVersionId,
        newVersionId: request.projectVersionId,
        providerDeploymentId: result.providerDeploymentId,
      });
      return result;
    });
  }

  async attachDomain({ input, domain }) {
    const target = normalizeDomain(domain);
    return this._operation("attach_domain", input, async request => {
      await this._owned(request, this.provider.projectId);
      const fact = await this.provider.attachDomain(domain);
      await this.store.recordDomain(request, fact);
      return fact;
    }, target);
  }
}

module.exports = { ProjectRuntimeManager };
