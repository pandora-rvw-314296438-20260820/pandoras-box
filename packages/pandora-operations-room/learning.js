"use strict";
const { demand, frozen, digest } = require("./contracts");
const { rejectSecrets } = require("./provider-actions");
const ROUTES = Object.freeze({
	ci: "reliability",
	android: "mobile",
	device: "ares",
	database: "backend",
	security: "reliability",
	deployment: "release",
});
function recoveryRoute(failure) {
	demand(failure && typeof failure.domain === "string", "FAILURE_REQUIRED");
	if (
		failure.mutationMayHaveCommitted === true ||
		failure.outcomeKnown !== true
	)
		return frozen({
			state: "reconciliation_required",
			retry: false,
			lane: "release",
		});
	const lane = ROUTES[failure.domain];
	demand(lane, "FAILURE_DOMAIN_UNKNOWN");
	return frozen({
		state: "repair_required",
		retry:
			failure.retryable === true &&
			Number.isSafeInteger(failure.attempt) &&
			failure.attempt >= 0 &&
			failure.attempt < 2,
		lane,
	});
}
function learningCandidate({
	taskId,
	headSha,
	verificationRef,
	outcome,
	lesson,
	rootCause,
	fix,
	evidenceRefs,
}) {
	demand(
		["verified_success", "verified_failure"].includes(outcome),
		"VERIFIED_OUTCOME_REQUIRED",
	);
	demand(
		typeof taskId === "string" &&
			taskId.length > 0 &&
			typeof verificationRef === "string" &&
			verificationRef.length > 0,
		"VERIFICATION_REQUIRED",
	);
	demand(
		typeof lesson === "string" && lesson.length >= 20 && lesson.length <= 2000,
		"HIGH_SIGNAL_LESSON_REQUIRED",
	);
	demand(
		Array.isArray(evidenceRefs) &&
			evidenceRefs.length > 0 &&
			evidenceRefs.length <= 16,
		"EVIDENCE_REQUIRED",
	);
	const record = {
		taskId,
		headSha: headSha ?? null,
		verificationRef,
		outcome,
		lesson,
		rootCause: rootCause ?? null,
		fix: fix ?? null,
		evidenceRefs: [...evidenceRefs],
	};
	rejectSecrets(record);
	return frozen({
		...record,
		idempotencyKey: digest(record),
		recordType: outcome === "verified_failure" ? "failure_lesson" : "outcome",
		requiresReview: true,
		canonicalMemoryWritten: false,
	});
}
module.exports = { recoveryRoute, learningCandidate };
