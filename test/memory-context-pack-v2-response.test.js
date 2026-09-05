"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { sanitizeMemorySearchResponse } = require("../dist/tools/memory-response.js");

function governedPack() {
  return {
    schemaVersion: "2.0",
    status: "available",
    namespace: "real_life",
    project: {
      id: "7c686cbd-d968-49d5-86cc-918f5e777bd2",
      name: "Pandoras Box",
      projectKey: "mcpmaster-pandoras-box",
    },
    authorization: {
      allowedRecordTypes: ["project_fact"],
      canRead: true,
      environment: "production",
      principalKey: "projectos-mcpmaster-production",
    },
    canonicalMemory: [{
      id: "0d174b3a-4389-4c15-ae34-fb1f471733e4",
      contentHash: "a".repeat(64),
      correlationId: "corr-1",
      effectiveAt: "2026-09-05T16:00:00.000Z",
      recordType: "project_fact",
      summary: "Bounded canonical summary.",
      title: "Canonical fact",
      updatedAt: "2026-09-05T16:00:00.000Z",
    }],
    negativeKnowledge: [],
    decisions: [],
    openLoops: [],
    conflicts: [],
    counts: {
      canonicalEligible: 1,
      conflictEligible: 0,
      decisionEligible: 0,
      negativeEligible: 0,
      openLoopEligible: 0,
    },
    precedence: ["authorization", "conflicts", "canonicalMemory"],
    freshness: {
      asOf: "2026-09-05T16:50:00.000Z",
      latestCanonicalAt: "2026-09-05T16:00:00.000Z",
    },
    degradation: {
      degraded: false,
      legacyUnscopedPackUsed: false,
      omittedCanonical: 0,
      omittedConflicts: 0,
      omittedDecisions: 0,
      omittedNegative: 0,
      omittedOpenLoops: 0,
    },
    contextSha256: "b".repeat(64),
    byteSize: 4096,
  };
}

function searchPayload(pack = governedPack()) {
  return {
    ok: true,
    namespace: "real_life",
    current_task: null,
    adaptive_profile: [],
    style_profile: [],
    project_context: [],
    people_context: [],
    risk_warnings: [],
    open_loops: [],
    latest_context_pack: pack,
    recent_events: [],
    semantic_matches: [],
    canonical_records: [],
    approved_record_count: 0,
    requested_canon_statuses: ["hard_canon", "soft_canon"],
    retrieval_mode: "project_scoped_keyword_recency",
    retrieval_reasoning_summary: "Exact-project governed response.",
    warnings: [],
  };
}

test("Memory response sanitizer accepts governed ContextPack v2 without dropping authority fields", () => {
  const parsed = sanitizeMemorySearchResponse(searchPayload());
  assert.equal(parsed.latest_context_pack.schemaVersion, "2.0");
  assert.equal(parsed.latest_context_pack.project.projectKey, "mcpmaster-pandoras-box");
  assert.equal(parsed.latest_context_pack.authorization.canRead, true);
  assert.equal(parsed.latest_context_pack.degradation.legacyUnscopedPackUsed, false);
  assert.equal(parsed.latest_context_pack.canonicalMemory.length, 1);
});

test("Memory response sanitizer rejects a v2 pack that permits legacy unscoped fallback", () => {
  const pack = governedPack();
  pack.degradation.legacyUnscopedPackUsed = true;
  assert.throws(() => sanitizeMemorySearchResponse(searchPayload(pack)), { name: "ZodError" });
});

test("Memory response sanitizer rejects v2 pack without read authorization", () => {
  const pack = governedPack();
  pack.authorization.canRead = false;
  assert.throws(() => sanitizeMemorySearchResponse(searchPayload(pack)), { name: "ZodError" });
});
