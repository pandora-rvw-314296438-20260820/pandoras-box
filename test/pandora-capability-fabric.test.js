"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");

const {
  loadCapabilityFabric,
  validateFabric,
  listCapabilityPacks,
  searchCapabilityFabric,
  capabilityReadiness,
} = require("../src/runtime/capability-fabric.js");

test("capability fabric preserves the complete v1 denominator and never grants authority", () => {
  const catalog = listCapabilityPacks();
  assert.equal(catalog.schemaVersion, "1.0.0");
  assert.equal(catalog.catalogVersion, "1.0.0");
  assert.equal(catalog.packCount, 48);
  assert.equal(catalog.capabilityCount, 377);
  assert.equal(catalog.catalogPresenceGrantsAuthority, false);
  assert.equal(new Set(catalog.packs.map((pack) => pack.id)).size, 48);
  assert.equal(new Set(catalog.packs.flatMap((pack) => pack.capabilities)).size, 377);
  for (const pack of catalog.packs) {
    assert.equal(pack.skillBlueprints.length, 3);
    assert.ok(pack.verification.includes("provider_readback"));
    assert.equal(pack.memoryLearning, "verified_outcomes_only");
  }
});

test("active state is explicit and installable or gated packs never masquerade as executable", () => {
  assert.equal(capabilityReadiness({ packId: "engineering" }).executableNow, true);
  assert.equal(capabilityReadiness({ packId: "knowledge-memory" }).executableNow, true);
  assert.equal(capabilityReadiness({ packId: "google-workspace" }).executableNow, false);
  assert.equal(capabilityReadiness({ packId: "payments" }).executableNow, false);
  assert.ok(capabilityReadiness({ packId: "payments" }).requirements.includes("explicit_owner_authorization"));
  assert.ok(capabilityReadiness({ packId: "tax-compliance" }).requirements.includes("legal_regulatory_and_provider_requirements"));
  assert.ok(capabilityReadiness({ packId: "video-operations" }).requirements.includes("privacy_and_data_purpose_authorization"));
  assert.ok(capabilityReadiness({ packId: "government-portals" }).requirements.includes("compatible_provider_contract"));
});

test("capability and provider search is deterministic and bounded", () => {
  const meta = searchCapabilityFabric("meta ads", { limit: 5 });
  assert.ok(meta.count > 0);
  assert.equal(meta.catalogPresenceGrantsAuthority, false);
  assert.ok(meta.results.some((pack) => ["marketing", "meta-business", "ads-management"].includes(pack.id)));
  const hotel = searchCapabilityFabric("hospitality reservation guest");
  assert.equal(hotel.results[0].id, "hospitality");
  assert.throws(() => searchCapabilityFabric(""), /query is required/);
});

test("readiness resolves by capability and unknown capabilities fail closed", () => {
  assert.equal(capabilityReadiness({ capability: "git.read" }).pack.id, "engineering");
  assert.equal(capabilityReadiness({ capability: "memory.search" }).pack.id, "knowledge-memory");
  assert.throws(() => capabilityReadiness({ capability: "not.real" }), /not found/);
});

test("validator rejects authority escalation, duplicate capabilities, and denominator shrinkage", () => {
  const source = loadCapabilityFabric();
  const clone = () => JSON.parse(JSON.stringify(source));

  const authority = clone();
  authority.principles.catalogPresenceGrantsAuthority = true;
  assert.throws(() => validateFabric(authority), /never grant authority/);

  const duplicate = clone();
  duplicate.packs[1].capabilities[0] = duplicate.packs[0].capabilities[0];
  assert.throws(() => validateFabric(duplicate), /duplicate capability/);

  const shrunken = clone();
  shrunken.packs = shrunken.packs.slice(0, 5);
  assert.throws(() => validateFabric(shrunken), /denominator shrank/);
});

test("alternate catalog path is validated rather than trusted", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pandora-capability-"));
  const file = path.join(tmp, "catalog.json");
  fs.writeFileSync(file, JSON.stringify({ schemaVersion: "1.0.0", catalogVersion: "1.0.0", packs: [] }));
  assert.throws(() => loadCapabilityFabric({ catalogPath: file, reload: true }), /wrong canonical repository|denominator/);
  fs.rmSync(tmp, { recursive: true, force: true });
});
