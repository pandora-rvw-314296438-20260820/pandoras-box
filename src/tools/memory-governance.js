"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.classifyCanonStatus = classifyCanonStatus;
exports.detectConflicts = detectConflicts;
exports.evaluateCanonicalContext = evaluateCanonicalContext;
/**
 * Trust ranking used to resolve competing approved records. Higher wins.
 * Anything not approved ranks 0 and can never win a conflict.
 */
const TRUST_RANK = {
    approved_canonical: 2,
    approved_provisional: 1,
    proposed: 0,
    untrusted: 0,
};
function classifyCanonStatus(canonStatus, approved) {
    // `approved` is Memory's own assertion. Both must agree, so a service that
    // starts reporting `approved: true` for a draft cannot widen our trust.
    if (canonStatus === 'hard_canon' && approved)
        return 'approved_canonical';
    if (canonStatus === 'soft_canon' && approved)
        return 'approved_provisional';
    if (canonStatus === 'draft')
        return 'proposed';
    return 'untrusted';
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function normalizeRecord(raw) {
    const canonStatus = raw.canon_status;
    const approved = raw.approved === true;
    return {
        id: raw.id,
        title: raw.title ?? '',
        body: raw.body ?? '',
        canonStatus,
        approved,
        trust: classifyCanonStatus(canonStatus, approved),
        memoryType: raw.memory_type ?? null,
        strength: raw.strength ?? null,
        confidence: raw.confidence ?? null,
        provenance: isRecord(raw.provenance) ? raw.provenance : null,
        sourceSummary: raw.source_summary ?? null,
        createdAt: raw.created_at ?? null,
        updatedAt: raw.updated_at ?? null,
    };
}
/**
 * A record participates in conflict detection only when it declares what it is
 * asserting. `subject_key` names the claim (for example
 * `canonical_repository`); `canonical_value` is the asserted value. Records
 * without both are carried as ordinary context and cannot silently contradict.
 */
function conflictKey(record) {
    const subject = record.provenance?.subject_key;
    const value = record.provenance?.canonical_value;
    if (typeof subject !== 'string' || !subject.trim())
        return null;
    if (typeof value !== 'string' || !value.trim())
        return null;
    return { subject: subject.trim(), value: value.trim() };
}
/**
 * Two approved records that assert different values for the same subject are a
 * conflict unless one strictly outranks the other. Ties are never broken
 * arbitrarily — they are reported so a reviewer resolves them.
 */
function detectConflicts(approved) {
    const bySubject = new Map();
    for (const record of approved) {
        const keyed = conflictKey(record);
        if (!keyed)
            continue;
        const bucket = bySubject.get(keyed.subject) ?? [];
        bucket.push({ value: keyed.value, record });
        bySubject.set(keyed.subject, bucket);
    }
    const conflicts = [];
    for (const [subject, entries] of bySubject) {
        const distinctValues = new Set(entries.map((entry) => entry.value));
        if (distinctValues.size < 2)
            continue;
        const topRank = Math.max(...entries.map((entry) => TRUST_RANK[entry.record.trust]));
        const leaders = entries.filter((entry) => TRUST_RANK[entry.record.trust] === topRank);
        const leadingValues = new Set(leaders.map((entry) => entry.value));
        // A single highest-ranked value resolves the disagreement deterministically.
        if (leadingValues.size === 1)
            continue;
        conflicts.push({
            subject,
            reason: `Approved records disagree on "${subject}" at the same trust level: ${[
                ...leadingValues,
            ]
                .sort()
                .join(' vs ')}`,
            recordIds: leaders.map((entry) => entry.record.id).sort(),
        });
    }
    return conflicts.sort((a, b) => a.subject.localeCompare(b.subject));
}
/**
 * Turn a Memory search response into a governed context package.
 *
 * Fails closed: any condition that makes approved memory unreliable — none
 * returned, a service that cannot report approval state, staleness, or an
 * unresolved conflict — yields `degraded: true` and an empty `canonical` set,
 * so a caller cannot accidentally execute on untrustworthy context.
 */
function evaluateCanonicalContext(response, options = {}) {
    const degradedReasons = [];
    const warnings = [...(response.warnings ?? [])];
    const rawRecords = response.canonical_records;
    // An older Memory deployment omits approval state entirely. Without it we
    // cannot tell canon from draft, so we refuse rather than guess.
    if (rawRecords === undefined) {
        return {
            canonical: [],
            proposed: [],
            conflicts: [],
            degraded: true,
            degradedReasons: [
                'Memory did not report approval state; records cannot be trusted as canonical.',
            ],
            fallbackAuthority: 'github_and_supabase',
            freshestRecordAt: null,
            freshnessScope: 'query_approved_records',
            warnings,
            retrievalMode: response.retrieval_mode ?? null,
        };
    }
    const records = rawRecords.map(normalizeRecord);
    const approved = records.filter((record) => record.trust === 'approved_canonical' ||
        record.trust === 'approved_provisional');
    const proposed = records.filter((record) => record.trust === 'proposed');
    if (approved.length === 0) {
        degradedReasons.push('No approved canonical records were returned for this project.');
    }
    const maxAgeMs = options.maxAgeMs ?? 86_400_000;
    const timestamps = approved
        .map((record) => (record.updatedAt ? Date.parse(record.updatedAt) : Number.NaN))
        .filter((value) => Number.isFinite(value));
    const freshest = timestamps.length > 0 ? Math.max(...timestamps) : null;
    if (approved.length > 0 && timestamps.length !== approved.length) {
        degradedReasons.push('One or more approved canonical records do not have a usable freshness timestamp.');
    }
    if (freshest !== null) {
        const now = (options.now ?? Date.now)();
        if (now - freshest > maxAgeMs) {
            degradedReasons.push('The most recent approved record is older than the configured freshness window.');
        }
    }
    const conflicts = detectConflicts(approved);
    if (conflicts.length > 0) {
        degradedReasons.push(`${conflicts.length} unresolved conflict(s) between approved records must be resolved by a reviewer.`);
    }
    const degraded = degradedReasons.length > 0;
    return {
        // Fail closed: withhold every record while degraded rather than exposing a
        // partially trustworthy set a caller might act on.
        canonical: degraded ? [] : approved,
        proposed,
        conflicts,
        degraded,
        degradedReasons,
        fallbackAuthority: 'github_and_supabase',
        // This timestamp is intentionally query-scoped. It is not a project- or namespace-wide freshness anchor.
        freshestRecordAt: freshest === null ? null : new Date(freshest).toISOString(),
        freshnessScope: 'query_approved_records',
        warnings,
        retrievalMode: response.retrieval_mode ?? null,
    };
}
//# sourceMappingURL=memory-governance.js.map
