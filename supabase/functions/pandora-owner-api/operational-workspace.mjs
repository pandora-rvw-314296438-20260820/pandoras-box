"use strict";

const IMPORT_EVIDENCE_TYPE = "operational_import_preview";
const CONFLICT_EVIDENCE_TYPE = "operational_conflict";
const RESOLUTIONS = new Set(["keep_canonical", "use_provider_truth", "remap", "ignore"]);

function asRecord(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function text(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}
function providerToken(value) {
  const token = text(value).toLowerCase().replace(/[^a-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "");
  if (!/^[a-z][a-z0-9_-]{1,63}$/.test(token)) throw new Error("INVALID_OPERATIONAL_PROVIDER");
  return token;
}
function resourceToken(value) {
  const token = text(value).toLowerCase().replace(/[^a-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "");
  if (!/^[a-z][a-z0-9_-]{1,63}$/.test(token)) throw new Error("INVALID_OPERATIONAL_RESOURCE_TYPE");
  return token;
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (!value || typeof value !== "object") return value;
  const output = {};
  for (const key of Object.keys(value).sort()) output[key] = stable(value[key]);
  return output;
}
async function sha256(value) {
  const source = typeof value === "string" ? value : JSON.stringify(stable(value));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function severityRank(value) {
  return { critical: 4, high: 3, medium: 2, low: 1 }[value] || 0;
}
function normalizeMapping(value) {
  const item = asRecord(value);
  return {
    id: text(item.id),
    provider: text(item.provider),
    resourceType: text(item.resourceType ?? item.resource_type),
    externalId: text(item.externalId ?? item.external_id),
    externalName: text(item.externalName ?? item.external_name) || null,
    environment: text(item.environment) || null,
    canonicalUrl: text(item.canonicalUrl ?? item.canonical_url) || null,
    bindingState: text(item.bindingState ?? item.binding_state, "not_checked"),
    verifiedAt: item.verifiedAt ?? item.verified_at ?? null,
    updatedAt: item.updatedAt ?? item.updated_at ?? null,
  };
}
function normalizeImportObjects(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) throw new Error("INVALID_OPERATIONAL_IMPORT");
  return value.map((raw, index) => {
    const item = asRecord(raw);
    const externalId = text(item.externalId ?? item.external_id);
    if (!externalId || externalId.length > 500) throw new Error("INVALID_OPERATIONAL_IMPORT");
    const name = text(item.name);
    const targetRef = text(item.targetRef ?? item.target_ref);
    return {
      index,
      kind: resourceToken(item.kind ?? item.resourceType ?? item.resource_type),
      externalId,
      name: name ? name.slice(0, 240) : null,
      targetRef: targetRef ? targetRef.slice(0, 128) : null,
      attributes: asRecord(item.attributes),
    };
  });
}
async function redactedImportObject(item) {
  return {
    index: item.index,
    kind: item.kind,
    externalId: item.externalId,
    name: item.name,
    targetRef: item.targetRef,
    attributeCount: Object.keys(item.attributes).length,
    attributesDigest: await sha256(item.attributes),
  };
}

export function deriveOperationalConflicts({ mappings = [], runtimes = [], domains = [], storedConflicts = [] } = {}) {
  const conflicts = [];
  const normalizedMappings = mappings.map(normalizeMapping);
  for (const mapping of normalizedMappings) {
    if (mapping.bindingState === "verified") continue;
    const severe = new Set(["missing", "quarantined"]).has(mapping.bindingState);
    conflicts.push({
      id: `derived:mapping:${mapping.id || mapping.provider + ":" + mapping.resourceType + ":" + mapping.externalId}`,
      kind: "resource_binding",
      severity: severe ? "high" : "medium",
      title: `${mapping.provider || "Provider"} mapping needs review`,
      summary: `${mapping.resourceType || "resource"} is ${mapping.bindingState.replace(/_/g, " ")}.`,
      recommendation: "Reconcile provider truth against the canonical project resource before mutation.",
      source: "derived",
      resolvable: false,
      mappingId: mapping.id || null,
    });
  }
  for (const rawRuntime of runtimes) {
    const runtime = asRecord(rawRuntime);
    const provider = text(runtime.provider);
    const externalId = text(runtime.provider_project_id ?? runtime.providerProjectId);
    if (!provider || !externalId) continue;
    const providerMappings = normalizedMappings.filter((mapping) => mapping.provider === provider);
    if (providerMappings.length && !providerMappings.some((mapping) => mapping.externalId === externalId)) {
      conflicts.push({
        id: `derived:runtime:${text(runtime.id, text(runtime.environment, externalId))}`,
        kind: "runtime_binding_mismatch",
        severity: "high",
        title: `${provider} runtime points somewhere else`,
        summary: `Runtime ${text(runtime.environment, "environment")} uses ${externalId}, which is not one of this project's recorded ${provider} resources.`,
        recommendation: "Verify the exact provider project identity before publish, rollback, or configuration changes.",
        source: "derived",
        resolvable: false,
        mappingId: null,
      });
    }
  }
  for (const rawDomain of domains) {
    const domain = asRecord(rawDomain);
    if (domain.verified === true) continue;
    const host = text(domain.domain);
    if (!host) continue;
    conflicts.push({
      id: `derived:domain:${text(domain.id, host)}`,
      kind: "domain_not_verified",
      severity: domain.primary_domain === true ? "high" : "medium",
      title: `${host} is not verified`,
      summary: "Pandora has a domain record but no current verified ownership/routing proof.",
      recommendation: "Re-run domain verification before treating this address as live.",
      source: "derived",
      resolvable: false,
      mappingId: null,
    });
  }
  for (const raw of storedConflicts) {
    const row = asRecord(raw);
    const payload = asRecord(row.payload_redacted);
    conflicts.push({
      id: text(row.id),
      kind: text(payload.kind, "import_conflict"),
      severity: text(payload.severity, "medium"),
      title: text(payload.title, "Imported data needs review"),
      summary: text(payload.summary, "A staged import conflicts with current project truth."),
      recommendation: text(payload.recommendation, "Review both identities before continuing."),
      source: "staged_import",
      resolvable: true,
      mappingId: text(payload.mappingId) || null,
      importFingerprint: text(payload.importFingerprint) || null,
      observedAt: row.observed_at ?? null,
    });
  }
  const seen = new Set();
  return conflicts.filter((item) => {
    const key = `${item.kind}|${item.summary}|${item.mappingId || ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((left, right) => severityRank(right.severity) - severityRank(left.severity));
}

export async function previewExternalImport({ projectId, sourceProvider, objects, mappings = [] }) {
  const provider = providerToken(sourceProvider);
  const normalized = normalizeImportObjects(objects);
  const safeObjects = await Promise.all(normalized.map(redactedImportObject));
  safeObjects.sort((a, b) => `${a.kind}|${a.externalId}|${a.targetRef || ""}`.localeCompare(`${b.kind}|${b.externalId}|${b.targetRef || ""}`));
  safeObjects.forEach((item, index) => {
    item.index = index;
  });
  const fingerprint = await sha256({ schemaVersion: 1, projectId: text(projectId), sourceProvider: provider, objects: safeObjects });
  const current = mappings.map(normalizeMapping);
  const creates = [];
  const updates = [];
  const noops = [];
  const conflicts = [];

  for (const item of safeObjects) {
    const exact = current.find((mapping) => mapping.provider === provider && mapping.resourceType === item.kind && mapping.externalId === item.externalId);
    if (exact) {
      noops.push({ index: item.index, mappingId: exact.id, externalId: item.externalId });
      continue;
    }
    if (item.targetRef) {
      const target = current.find((mapping) => mapping.id === item.targetRef);
      if (!target) {
        conflicts.push({ kind: "target_not_found", severity: "high", title: "Requested mapping target was not found", summary: `${item.kind} ${item.externalId} refers to missing mapping ${item.targetRef}.`, recommendation: "Refresh the project map and choose an existing exact target.", mappingId: item.targetRef, objectIndex: item.index });
        continue;
      }
      if (target.provider !== provider || target.resourceType !== item.kind) {
        conflicts.push({ kind: "target_scope_mismatch", severity: "high", title: "Requested mapping target has a different scope", summary: `${item.kind} ${item.externalId} cannot replace ${target.provider}/${target.resourceType}.`, recommendation: "Map only matching provider/resource types or stage a separate migration.", mappingId: target.id, objectIndex: item.index });
        continue;
      }
      if (target.bindingState !== "verified") {
        conflicts.push({ kind: "target_not_verified", severity: "high", title: "Requested mapping target is not verified", summary: `${target.provider} ${target.resourceType} is currently ${target.bindingState}.`, recommendation: "Reconcile the existing mapping before replacing its external identity.", mappingId: target.id, objectIndex: item.index });
        continue;
      }
      updates.push({ index: item.index, mappingId: target.id, fromExternalId: target.externalId, toExternalId: item.externalId });
      continue;
    }
    const candidates = current.filter((mapping) => mapping.provider === provider && mapping.resourceType === item.kind);
    if (candidates.length === 0) {
      creates.push({ index: item.index, externalId: item.externalId, kind: item.kind });
      continue;
    }
    conflicts.push({ kind: "ambiguous_mapping_change", severity: "high", title: "Pandora will not guess which mapping to replace", summary: `${item.kind} ${item.externalId} differs from ${candidates.length} existing ${provider} mapping${candidates.length === 1 ? "" : "s"}.`, recommendation: "Choose the exact target mapping and stage the import again.", mappingId: null, objectIndex: item.index });
  }

  return {
    schemaVersion: 1,
    projectId: text(projectId),
    sourceProvider: provider,
    fingerprint,
    objects: safeObjects,
    changes: { creates, updates, noops },
    conflicts,
    executionReady: conflicts.length === 0,
    executionMode: "plan_first",
    externalMutationExecuted: false,
  };
}

export async function loadOperationalWorkspace(admin, organizationId, projectId) {
  const [resources, runtimes, domains, evidence] = await Promise.all([
    admin.from("projectos_project_resources").select("id, provider, resource_type, external_id, external_name, environment, canonical_url, binding_state, verified_at, updated_at").eq("organization_id", organizationId).eq("project_id", projectId).order("provider").order("resource_type"),
    admin.from("pandora_runtime_environments").select("id, environment, provider, provider_project_id, status, verification_state, last_reconciled_at, updated_at").eq("organization_id", organizationId).eq("project_id", projectId).order("environment"),
    admin.from("pandora_project_domains").select("id, domain, status, verified, primary_domain, updated_at").eq("organization_id", organizationId).eq("project_id", projectId).order("primary_domain", { ascending: false }).limit(50),
    admin.from("projectos_evidence").select("id, evidence_type, provider, external_id, status, verdict, payload_redacted, observed_at, invalidated_at").eq("organization_id", organizationId).eq("project_id", projectId).in("evidence_type", [IMPORT_EVIDENCE_TYPE, CONFLICT_EVIDENCE_TYPE]).is("invalidated_at", null).order("observed_at", { ascending: false }).limit(100),
  ]);
  if (resources.error || runtimes.error || domains.error || evidence.error) throw new Error("BACKEND_READ_FAILED");
  const mappings = (resources.data || []).map(normalizeMapping);
  const evidenceRows = evidence.data || [];
  const conflicts = deriveOperationalConflicts({
    mappings,
    runtimes: runtimes.data || [],
    domains: domains.data || [],
    storedConflicts: evidenceRows.filter((row) => row.evidence_type === CONFLICT_EVIDENCE_TYPE),
  });
  const imports = evidenceRows.filter((row) => row.evidence_type === IMPORT_EVIDENCE_TYPE).map((row) => {
    const payload = asRecord(row.payload_redacted);
    return {
      id: text(row.id),
      fingerprint: text(row.external_id),
      provider: text(row.provider),
      status: text(row.verdict, text(row.status, "observed")),
      objectCount: Number(payload.objectCount || 0),
      createCount: Number(payload.createCount || 0),
      updateCount: Number(payload.updateCount || 0),
      noopCount: Number(payload.noopCount || 0),
      conflictCount: Number(payload.conflictCount || 0),
      executionReady: payload.executionReady === true,
      observedAt: row.observed_at ?? null,
    };
  });
  const highConflictCount = conflicts.filter((item) => ["high", "critical"].includes(item.severity)).length;
  return {
    summary: {
      mappingCount: mappings.length,
      verifiedMappingCount: mappings.filter((item) => item.bindingState === "verified").length,
      conflictCount: conflicts.length,
      highConflictCount,
      stagedImportCount: imports.length,
      needsYou: highConflictCount > 0,
    },
    mappings,
    conflicts,
    imports,
    runtimes: runtimes.data || [],
    domains: domains.data || [],
  };
}

async function findEvidenceByExternalId(admin, organizationId, projectId, provider, evidenceType, externalId) {
  const result = await admin.from("projectos_evidence").select("id, external_id, payload_redacted, observed_at").eq("organization_id", organizationId).eq("project_id", projectId).eq("provider", provider).eq("evidence_type", evidenceType).eq("external_id", externalId).is("invalidated_at", null).maybeSingle();
  if (result.error) throw new Error("OPERATIONAL_WRITE_FAILED");
  return result.data || null;
}

export async function stageOperationalImport(admin, organizationId, projectId, actorId, body) {
  const input = asRecord(body);
  const workspace = await loadOperationalWorkspace(admin, organizationId, projectId);
  const preview = await previewExternalImport({ projectId, sourceProvider: input.sourceProvider ?? input.provider, objects: input.objects, mappings: workspace.mappings });
  let previewEvidence = await findEvidenceByExternalId(admin, organizationId, projectId, preview.sourceProvider, IMPORT_EVIDENCE_TYPE, preview.fingerprint);
  if (!previewEvidence) {
    const inserted = await admin.from("projectos_evidence").insert({
      organization_id: organizationId,
      project_id: projectId,
      evidence_type: IMPORT_EVIDENCE_TYPE,
      provider: preview.sourceProvider,
      external_id: preview.fingerprint,
      status: preview.executionReady ? "observed" : "blocked",
      verdict: preview.executionReady ? "READY_FOR_REVIEW" : "REVIEW_REQUIRED",
      payload_redacted: {
        schemaVersion: preview.schemaVersion,
        fingerprint: preview.fingerprint,
        objectCount: preview.objects.length,
        createCount: preview.changes.creates.length,
        updateCount: preview.changes.updates.length,
        noopCount: preview.changes.noops.length,
        conflictCount: preview.conflicts.length,
        executionReady: preview.executionReady,
        requestedBy: actorId,
        objects: preview.objects,
        changes: preview.changes,
      },
    }).select("id, external_id, payload_redacted, observed_at").single();
    if (inserted.error) {
      previewEvidence = await findEvidenceByExternalId(admin, organizationId, projectId, preview.sourceProvider, IMPORT_EVIDENCE_TYPE, preview.fingerprint);
      if (!previewEvidence) throw new Error("OPERATIONAL_WRITE_FAILED");
    } else previewEvidence = inserted.data;
  }
  for (let index = 0; index < preview.conflicts.length; index += 1) {
    const conflict = preview.conflicts[index];
    const conflictExternalId = `${preview.fingerprint}.${index}`;
    const existing = await findEvidenceByExternalId(admin, organizationId, projectId, preview.sourceProvider, CONFLICT_EVIDENCE_TYPE, conflictExternalId);
    if (existing) continue;
    const inserted = await admin.from("projectos_evidence").insert({
      organization_id: organizationId,
      project_id: projectId,
      evidence_type: CONFLICT_EVIDENCE_TYPE,
      provider: preview.sourceProvider,
      external_id: conflictExternalId,
      status: "blocked",
      verdict: "OPEN",
      payload_redacted: { ...conflict, importFingerprint: preview.fingerprint, object: preview.objects.find((item) => item.index === conflict.objectIndex) || null },
    });
    if (inserted.error && inserted.error.code !== "23505") throw new Error("OPERATIONAL_WRITE_FAILED");
  }
  return { ...preview, evidenceId: text(previewEvidence?.id), persisted: true };
}

export async function resolveOperationalConflict(admin, organizationId, projectId, actorId, conflictId, body) {
  const input = asRecord(body);
  const resolution = text(input.resolution).toLowerCase();
  const rationale = text(input.rationale);
  if (!RESOLUTIONS.has(resolution) || rationale.length < 3 || rationale.length > 2000) throw new Error("INVALID_OPERATIONAL_RESOLUTION");
  const current = await admin.from("projectos_evidence").select("id, provider, external_id, payload_redacted, invalidated_at").eq("organization_id", organizationId).eq("project_id", projectId).eq("id", conflictId).eq("evidence_type", CONFLICT_EVIDENCE_TYPE).is("invalidated_at", null).maybeSingle();
  if (current.error) throw new Error("OPERATIONAL_WRITE_FAILED");
  if (!current.data) throw new Error("OPERATIONAL_CONFLICT_NOT_FOUND");
  const payload = asRecord(current.data.payload_redacted);
  const decision = await admin.from("projectos_decisions").insert({
    organization_id: organizationId,
    project_id: projectId,
    decision_type: "operational_conflict_resolution",
    statement: `Resolve ${text(payload.kind, "operational conflict")} as ${resolution.replace(/_/g, " ")}.`,
    rationale,
    confidence: 1,
    source: "operator",
    created_by: actorId,
  }).select("id, decision_type, statement, rationale, created_at").single();
  if (decision.error) throw new Error("OPERATIONAL_WRITE_FAILED");
  const invalidated = await admin.from("projectos_evidence").update({ invalidated_at: new Date().toISOString(), invalidation_reason: `resolved:${resolution}` }).eq("organization_id", organizationId).eq("project_id", projectId).eq("id", conflictId).is("invalidated_at", null);
  if (invalidated.error) throw new Error("OPERATIONAL_WRITE_FAILED");
  return { conflictId, resolution, decision: decision.data, externalMutationExecuted: false, executionMode: resolution === "ignore" ? "none" : "plan_first" };
}

export async function operationalAttentionCount(admin, organizationId) {
  const [conflicts, degraded] = await Promise.all([
    admin.from("projectos_evidence").select("id").eq("organization_id", organizationId).eq("evidence_type", CONFLICT_EVIDENCE_TYPE).eq("status", "blocked").is("invalidated_at", null).limit(500),
    admin.from("projectos_project_resources").select("id").eq("organization_id", organizationId).neq("binding_state", "verified").limit(500),
  ]);
  if (conflicts.error || degraded.error) throw new Error("BACKEND_READ_FAILED");
  return (conflicts.data || []).length + (degraded.data || []).length;
}

export const operationalEvidenceTypes = Object.freeze({ importPreview: IMPORT_EVIDENCE_TYPE, conflict: CONFLICT_EVIDENCE_TYPE });
