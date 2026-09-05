"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sanitizeMemoryHealthResponse = sanitizeMemoryHealthResponse;
exports.sanitizeMemorySearchResponse = sanitizeMemorySearchResponse;
const zod_1 = require("zod");
const NamespaceSchema = zod_1.z.enum(['real_life', 'au']);
const IdSchema = zod_1.z.string().trim().min(1).max(200);
const TimestampSchema = zod_1.z.string().trim().min(1).max(80);
const ShortTextSchema = zod_1.z.string().max(4000);
const LongTextSchema = zod_1.z.string().max(50000);
const JsonCollectionSchema = zod_1.z.union([
    zod_1.z.array(zod_1.z.unknown()).max(200),
    zod_1.z.record(zod_1.z.string().max(200), zod_1.z.unknown()),
]);
const ProfileSchema = zod_1.z.object({
    id: IdSchema,
    namespace: NamespaceSchema,
    profile_type: zod_1.z.string().trim().min(1).max(160),
    subject_key: zod_1.z.string().trim().min(1).max(500),
    title: ShortTextSchema.nullable().optional(),
    summary: LongTextSchema.nullable().optional(),
    facts: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    preferences: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    patterns: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    risks: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    open_loops: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    decisions: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    evidence_refs: zod_1.z.array(zod_1.z.unknown()).max(200).optional(),
    confidence: zod_1.z.number().min(0).max(1).nullable().optional(),
    status: zod_1.z.string().max(80).nullable().optional(),
    version: zod_1.z.number().int().min(1).nullable().optional(),
    created_at: TimestampSchema.nullable().optional(),
    updated_at: TimestampSchema.nullable().optional(),
    supersedes_profile_id: IdSchema.nullable().optional(),
    superseded_at: TimestampSchema.nullable().optional(),
}).strip();
const OpenLoopSchema = zod_1.z.object({
    id: IdSchema,
    namespace: NamespaceSchema,
    loop_type: zod_1.z.string().trim().min(1).max(160),
    subject_key: zod_1.z.string().trim().min(1).max(500),
    title: ShortTextSchema.nullable().optional(),
    description: LongTextSchema.nullable().optional(),
    severity: zod_1.z.number().int().min(0).max(10).nullable().optional(),
    status: zod_1.z.string().max(80).nullable().optional(),
    evidence_refs: zod_1.z.array(zod_1.z.unknown()).max(200).nullable().optional(),
    next_action: LongTextSchema.nullable().optional(),
    created_at: TimestampSchema.nullable().optional(),
    updated_at: TimestampSchema.nullable().optional(),
    resolved_at: TimestampSchema.nullable().optional(),
}).strip();
const ContextPackSchema = zod_1.z.object({
    id: IdSchema,
    namespace: NamespaceSchema,
    pack_type: zod_1.z.string().trim().min(1).max(160),
    title: ShortTextSchema,
    summary: LongTextSchema,
    key_points: zod_1.z.array(zod_1.z.unknown()).max(200),
    active_projects: JsonCollectionSchema.nullable().optional(),
    people_map: JsonCollectionSchema.nullable().optional(),
    decisions: JsonCollectionSchema.nullable().optional(),
    risks: JsonCollectionSchema.nullable().optional(),
    open_loops: JsonCollectionSchema.nullable().optional(),
    status: zod_1.z.string().max(80),
    created_at: TimestampSchema,
    updated_at: TimestampSchema,
}).strip();
const ContextPackV2ProjectSchema = zod_1.z.object({
    id: IdSchema,
    name: ShortTextSchema,
    projectKey: zod_1.z.string().trim().regex(/^[a-z0-9][a-z0-9._-]{1,95}$/),
}).strip();
const ContextPackV2AuthorizationSchema = zod_1.z.object({
    allowedRecordTypes: zod_1.z.array(zod_1.z.string().trim().min(1).max(96)).max(100),
    canRead: zod_1.z.literal(true),
    environment: zod_1.z.string().trim().min(1).max(80),
    principalKey: zod_1.z.string().trim().min(1).max(200),
}).strip();
const ContextPackV2DegradationSchema = zod_1.z.object({
    degraded: zod_1.z.boolean(),
    legacyUnscopedPackUsed: zod_1.z.literal(false),
    omittedCanonical: zod_1.z.number().int().min(0),
    omittedConflicts: zod_1.z.number().int().min(0),
    omittedDecisions: zod_1.z.number().int().min(0),
    omittedNegative: zod_1.z.number().int().min(0),
    omittedOpenLoops: zod_1.z.number().int().min(0),
}).strip();
const ContextPackV2FreshnessSchema = zod_1.z.object({
    asOf: TimestampSchema,
    latestCanonicalAt: TimestampSchema.nullable(),
}).strip();
const ContextPackV2CountsSchema = zod_1.z.object({
    canonicalEligible: zod_1.z.number().int().min(0),
    conflictEligible: zod_1.z.number().int().min(0),
    decisionEligible: zod_1.z.number().int().min(0),
    negativeEligible: zod_1.z.number().int().min(0),
    openLoopEligible: zod_1.z.number().int().min(0),
}).strip();
const ContextPackV2CanonicalRecordSchema = zod_1.z.object({
    id: IdSchema,
    contentHash: zod_1.z.string().trim().regex(/^[a-f0-9]{64}$/),
    correlationId: zod_1.z.string().trim().min(1).max(200),
    effectiveAt: TimestampSchema.nullable(),
    recordType: zod_1.z.string().trim().min(1).max(96),
    summary: LongTextSchema,
    title: ShortTextSchema,
    updatedAt: TimestampSchema,
}).strip();
const ContextPackV2Schema = zod_1.z.object({
    schemaVersion: zod_1.z.literal('2.0'),
    status: zod_1.z.literal('available'),
    namespace: NamespaceSchema,
    project: ContextPackV2ProjectSchema,
    authorization: ContextPackV2AuthorizationSchema,
    canonicalMemory: zod_1.z.array(ContextPackV2CanonicalRecordSchema).max(50),
    negativeKnowledge: zod_1.z.array(zod_1.z.unknown()).max(200),
    decisions: zod_1.z.array(zod_1.z.unknown()).max(200),
    openLoops: zod_1.z.array(zod_1.z.unknown()).max(200),
    conflicts: zod_1.z.array(zod_1.z.unknown()).max(200),
    counts: ContextPackV2CountsSchema,
    precedence: zod_1.z.array(zod_1.z.string().trim().min(1).max(160)).max(20),
    freshness: ContextPackV2FreshnessSchema,
    degradation: ContextPackV2DegradationSchema,
    contextSha256: zod_1.z.string().trim().regex(/^[a-f0-9]{64}$/),
    byteSize: zod_1.z.number().int().min(0).max(12 * 1024),
}).strip();
const GovernedContextPackSchema = zod_1.z.union([ContextPackSchema, ContextPackV2Schema]);
const RecentEventSchema = zod_1.z.object({
    id: IdSchema,
    source: zod_1.z.string().trim().min(1).max(160),
    source_ref: zod_1.z.string().max(2000).nullable().optional(),
    extracted_summary: LongTextSchema.nullable().optional(),
    summary: LongTextSchema.nullable().optional(),
    importance: zod_1.z.number().int().min(0).max(10).nullable().optional(),
    sensitivity: zod_1.z.enum(['low', 'medium', 'high', 'private']).nullable().optional(),
    status: zod_1.z.string().max(80),
    created_at: TimestampSchema,
    updated_at: TimestampSchema,
    confidence_score: zod_1.z.number().min(0).max(1).nullable().optional(),
    retrieval_weight: zod_1.z.number().min(0).max(1).nullable().optional(),
    retrieval_count: zod_1.z.number().int().min(0).optional(),
    positive_feedback_count: zod_1.z.number().int().min(0).optional(),
    negative_feedback_count: zod_1.z.number().int().min(0).optional(),
    superseded_by_memory_id: IdSchema.nullable().optional(),
}).strip();
const SemanticMatchSchema = zod_1.z.object({
    id: IdSchema,
    source: zod_1.z.string().max(160).optional(),
    source_ref: zod_1.z.string().max(2000).nullable().optional(),
    summary: LongTextSchema.nullable().optional(),
    extracted_summary: LongTextSchema.nullable().optional(),
    score: zod_1.z.number().min(0).max(1).optional(),
    confidence: zod_1.z.number().min(0).max(1).optional(),
    confidence_score: zod_1.z.number().min(0).max(1).nullable().optional(),
    retrieval_weight: zod_1.z.number().min(0).max(1).nullable().optional(),
    created_at: TimestampSchema.nullable().optional(),
    updated_at: TimestampSchema.nullable().optional(),
}).strip();
/**
 * Governed record shape. `canonical_records` is optional so a Memory
 * deployment that predates approval-state reporting still parses; the
 * governance layer treats its absence as a fail-closed condition rather than
 * inferring trust.
 */
const CanonicalRecordSchema = zod_1.z.object({
    id: IdSchema,
    namespace: NamespaceSchema.optional(),
    title: ShortTextSchema.nullable().optional(),
    body: LongTextSchema.nullable().optional(),
    canon_status: zod_1.z.string().trim().min(1).max(80),
    approved: zod_1.z.boolean(),
    memory_type: zod_1.z.string().max(80).nullable().optional(),
    strength: zod_1.z.string().max(80).nullable().optional(),
    confidence: zod_1.z.number().min(0).max(1).nullable().optional(),
    source_summary: LongTextSchema.nullable().optional(),
    provenance: zod_1.z.record(zod_1.z.string().max(200), zod_1.z.unknown()).nullable().optional(),
    created_at: TimestampSchema.nullable().optional(),
    updated_at: TimestampSchema.nullable().optional(),
}).strip();
const RiskWarningSchema = zod_1.z.union([ProfileSchema, OpenLoopSchema]);
const HealthResponseSchema = zod_1.z.object({
    ok: zod_1.z.boolean(),
    project: zod_1.z.string().max(160).optional(),
    status: zod_1.z.string().max(160).optional(),
}).strip();
const SearchResponseSchema = zod_1.z.object({
    ok: zod_1.z.literal(true),
    namespace: NamespaceSchema.optional(),
    current_task: zod_1.z.string().max(2000).nullable().optional(),
    adaptive_profile: zod_1.z.array(ProfileSchema).max(50).default([]),
    style_profile: zod_1.z.array(ProfileSchema).max(50).default([]),
    project_context: zod_1.z.array(ProfileSchema).max(50).default([]),
    people_context: zod_1.z.array(ProfileSchema).max(50).default([]),
    risk_warnings: zod_1.z.array(RiskWarningSchema).max(100).default([]),
    open_loops: zod_1.z.array(OpenLoopSchema).max(50).default([]),
    latest_context_pack: GovernedContextPackSchema.nullable().optional(),
    recent_events: zod_1.z.array(RecentEventSchema).max(50).default([]),
    semantic_matches: zod_1.z.array(SemanticMatchSchema).max(50).default([]),
    canonical_records: zod_1.z.array(CanonicalRecordSchema).max(50).optional(),
    approved_record_count: zod_1.z.number().int().min(0).optional(),
    requested_canon_statuses: zod_1.z.array(zod_1.z.string().max(80)).max(10).optional(),
    retrieval_mode: zod_1.z.string().max(80).optional(),
    retrieval_reasoning_summary: zod_1.z.string().max(4000).optional(),
    warnings: zod_1.z.array(zod_1.z.string().max(500)).max(100).default([]),
}).strip();
function sanitizeMemoryHealthResponse(input) {
    return HealthResponseSchema.parse(input);
}
function sanitizeMemorySearchResponse(input) {
    return SearchResponseSchema.parse(input);
}
//# sourceMappingURL=memory-response.js.map