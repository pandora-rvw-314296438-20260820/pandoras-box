"use strict";

const fs = require("node:fs");
const path = require("node:path");

const CATALOG_PATH = path.resolve(__dirname, "..", "..", "config", "pandora-capability-fabric-v1.json");
const ALLOWED_STATUSES = new Set([
  "active",
  "active_internal",
  "staged_source",
  "installable",
  "owner_gate",
  "privacy_gate",
  "regulated_gate",
  "provider_contract_required",
]);
const ACTIVE_STATUSES = new Set(["active", "active_internal"]);
const ID_PATTERN = /^[a-z][a-z0-9-]{1,79}$/;
const CAPABILITY_PATTERN = /^[a-z][a-z0-9.-]{1,119}$/;

let cached;

function fail(message) {
  throw new Error(`Pandora capability fabric invalid: ${message}`);
}

function loadCapabilityFabric(options = {}) {
  if (cached && !options.reload && !options.catalogPath) return cached;
  const catalogPath = options.catalogPath || CATALOG_PATH;
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  } catch {
    fail("catalog cannot be read as JSON");
  }
  validateFabric(parsed);
  const normalized = Object.freeze({
    ...parsed,
    packs: Object.freeze(parsed.packs.map((pack) => Object.freeze({
      ...pack,
      capabilities: Object.freeze([...pack.capabilities]),
      providers: Object.freeze(pack.providers.map((provider) => Object.freeze({ ...provider }))),
      skillBlueprints: Object.freeze([...pack.skillBlueprints]),
      verification: Object.freeze([...pack.verification]),
    }))),
  });
  if (!options.catalogPath) cached = normalized;
  return normalized;
}

function validateFabric(fabric) {
  if (!fabric || typeof fabric !== "object" || Array.isArray(fabric)) fail("root must be an object");
  if (fabric.schemaVersion !== "1.0.0" || fabric.catalogVersion !== "1.0.0") fail("unsupported version");
  if (fabric.canonicalRepository !== "pandora-rvw-314296438-20260820/pandoras-box") fail("wrong canonical repository");
  if (fabric.principles?.catalogPresenceGrantsAuthority !== false) fail("catalog must never grant authority");
  if (fabric.principles?.credentialsInCatalog !== false) fail("catalog must prohibit credentials");
  if (fabric.principles?.verifiedLearningOnly !== true) fail("verified learning invariant missing");
  if (!Array.isArray(fabric.packs) || fabric.packs.length < 40) fail("capability pack denominator shrank");

  const ids = new Set();
  const capabilities = new Set();
  for (const pack of fabric.packs) {
    if (!pack || typeof pack !== "object" || Array.isArray(pack)) fail("pack must be an object");
    if (!ID_PATTERN.test(pack.id || "") || ids.has(pack.id)) fail(`invalid or duplicate pack id: ${pack.id}`);
    ids.add(pack.id);
    if (!ALLOWED_STATUSES.has(pack.status)) fail(`invalid status for ${pack.id}`);
    if (!Array.isArray(pack.capabilities) || pack.capabilities.length < 1) fail(`missing capabilities for ${pack.id}`);
    for (const capability of pack.capabilities) {
      if (!CAPABILITY_PATTERN.test(capability) || capabilities.has(capability)) {
        fail(`invalid or duplicate capability: ${capability}`);
      }
      capabilities.add(capability);
    }
    if (!Array.isArray(pack.providers) || !pack.providers.every((p) => (
      p && typeof p.provider === "string" && p.provider.length > 0 && p.status === "discover_or_verify"
    ))) fail(`provider contract invalid for ${pack.id}`);
    if (!Array.isArray(pack.skillBlueprints) || pack.skillBlueprints.length !== 3) {
      fail(`skill blueprint contract invalid for ${pack.id}`);
    }
    if (!Array.isArray(pack.verification) || !pack.verification.includes("provider_readback")) {
      fail(`provider readback verification missing for ${pack.id}`);
    }
    if (pack.memoryLearning !== "verified_outcomes_only") fail(`memory policy invalid for ${pack.id}`);
  }
  if (capabilities.size < 350) fail("capability denominator shrank");
  return { packCount: ids.size, capabilityCount: capabilities.size };
}

function publicPack(pack) {
  return {
    id: pack.id,
    name: pack.name,
    status: pack.status,
    executableNow: ACTIVE_STATUSES.has(pack.status),
    capabilities: [...pack.capabilities],
    providers: pack.providers.map((p) => ({ ...p })),
    riskFloor: pack.riskFloor,
    skillBlueprints: [...pack.skillBlueprints],
    verification: [...pack.verification],
    rollback: pack.rollback,
    memoryLearning: pack.memoryLearning,
  };
}

function listCapabilityPacks() {
  const fabric = loadCapabilityFabric();
  const capabilityCount = fabric.packs.reduce((sum, pack) => sum + pack.capabilities.length, 0);
  return {
    schemaVersion: fabric.schemaVersion,
    catalogVersion: fabric.catalogVersion,
    packCount: fabric.packs.length,
    capabilityCount,
    catalogPresenceGrantsAuthority: false,
    packs: fabric.packs.map(publicPack),
  };
}

function normalizeQuery(value) {
  return String(value || "").trim().toLowerCase().replace(/[^a-z0-9.-]+/g, " ");
}

function searchCapabilityFabric(query, options = {}) {
  const needle = normalizeQuery(query);
  if (!needle) throw Object.assign(new Error("query is required"), { status: 400 });
  const limit = Number.isInteger(options.limit) ? Math.min(Math.max(options.limit, 1), 50) : 20;
  const terms = needle.split(/\s+/).filter(Boolean);
  const fabric = loadCapabilityFabric();
  const scored = fabric.packs.map((pack) => {
    const haystack = normalizeQuery([
      pack.id,
      pack.name,
      pack.status,
      ...pack.capabilities,
      ...pack.providers.map((p) => p.provider),
      ...pack.skillBlueprints,
    ].join(" "));
    const score = terms.reduce((sum, term) => sum + (haystack.includes(term) ? 1 : 0), 0);
    return { pack, score };
  }).filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score || a.pack.id.localeCompare(b.pack.id))
    .slice(0, limit);
  return {
    query: String(query).trim(),
    count: scored.length,
    catalogPresenceGrantsAuthority: false,
    results: scored.map(({ pack, score }) => ({ ...publicPack(pack), score })),
  };
}

function capabilityReadiness(input = {}) {
  const fabric = loadCapabilityFabric();
  const packId = typeof input.packId === "string" ? input.packId.trim() : "";
  const capability = typeof input.capability === "string" ? input.capability.trim() : "";
  let pack;
  if (packId) pack = fabric.packs.find((item) => item.id === packId);
  if (!pack && capability) pack = fabric.packs.find((item) => item.capabilities.includes(capability));
  if (!pack) throw Object.assign(new Error("capability pack was not found"), { status: 404 });

  const executableNow = ACTIVE_STATUSES.has(pack.status);
  const requirements = [];
  if (!executableNow) requirements.push("verify_or_install_provider_connection");
  if (pack.status === "owner_gate") requirements.push("explicit_owner_authorization");
  if (pack.status === "privacy_gate") requirements.push("privacy_and_data_purpose_authorization");
  if (pack.status === "regulated_gate") requirements.push("legal_regulatory_and_provider_requirements");
  if (pack.status === "provider_contract_required") requirements.push("compatible_provider_contract");

  return {
    pack: publicPack(pack),
    executableNow,
    authorityGrantedByCatalog: false,
    requirements,
    executionContract: fabric.universalPolicy.writes,
    unknownOutcomeContract: fabric.universalPolicy.unknownOutcome,
    verificationContract: [...pack.verification],
  };
}

module.exports = {
  CATALOG_PATH,
  loadCapabilityFabric,
  validateFabric,
  listCapabilityPacks,
  searchCapabilityFabric,
  capabilityReadiness,
};
