"use strict";
const {
	demand,
	frozen,
	digest,
	exactKeys,
	SHA,
	integer,
} = require("./contracts");
const { planAssignments } = require("./scheduler");
// Store methods are durable RPCs. No local map can issue production/resource authority.
class OperationsRuntime {
	constructor({ store, workerDispatch, clock = Date.now }) {
		demand(store?.durability === "durable", "DURABLE_STORE_REQUIRED");
		demand(typeof workerDispatch === "function", "WORKER_TRANSPORT_REQUIRED");
		this.store = store;
		this.dispatch = workerDispatch;
		this.clock = clock;
	}
	async tick(scope) {
		const snapshot = await this.store.snapshot(scope);
		const plan = planAssignments({ ...snapshot, now: this.clock() });
		const receipts = [];
		for (const assignment of plan.assignments) {
			const claim = await this.store.claim(scope, assignment);
			if (!claim?.claimed) {
				receipts.push({ taskId: assignment.taskId, state: "claim_conflict" });
				continue;
			}
			// Persist dispatch intent before the transport call. A lost acknowledgement must reconcile.
			let intent;
			try {
				intent = await this.store.beginDispatch(scope, claim);
			} catch (error) {
				await this.store.markReconciliationRequired(scope, claim, {
					code: "DISPATCH_PREPARATION_UNCONFIRMED",
				});
				receipts.push({
					taskId: claim.taskId,
					state: "reconciliation_required",
				});
				continue;
			}
			if (intent.canSend !== true) {
				receipts.push({
					taskId: claim.taskId,
					state:
						intent.acknowledged === true
							? "already_dispatched"
							: "dispatch_in_flight",
					dispatchId: intent.dispatchId,
				});
				continue;
			}
			try {
				const ack = await this.dispatch(
					frozen({
						scope: structuredClone(scope),
						claim: structuredClone(claim),
						dispatchId: intent.dispatchId,
					}),
				);
				demand(
					ack?.accepted === true &&
						ack.dispatchId === intent.dispatchId &&
						ack.workerId === claim.workerId &&
						ack.taskId === claim.taskId &&
						ack.generation === claim.generation,
					"WORKER_ACK_MISMATCH",
				);
				await this.store.acknowledgeDispatch(scope, claim, ack);
				receipts.push({
					taskId: claim.taskId,
					state: "dispatched",
					dispatchId: intent.dispatchId,
				});
			} catch (error) {
				await this.store.markReconciliationRequired(scope, claim, {
					code: "DISPATCH_OUTCOME_UNKNOWN",
					dispatchId: intent.dispatchId,
				});
				receipts.push({
					taskId: claim.taskId,
					state: "reconciliation_required",
				});
			}
		}
		return { receipts, blocked: plan.blocked };
	}
}
function validateHandoff(raw, task) {
	exactKeys(raw, [
		"taskId",
		"workerId",
		"generation",
		"headSha",
		"pullRequest",
		"tests",
		"evidenceRefs",
		"implementationComplete",
	]);
	demand(
		raw.taskId === task.id && raw.implementationComplete === true,
		"HANDOFF_SCOPE_INVALID",
	);
	integer(raw.generation, 1, Number.MAX_SAFE_INTEGER, "GENERATION_INVALID");
	demand(SHA.test(raw.headSha), "EXACT_HEAD_REQUIRED");
	demand(
		Number.isSafeInteger(raw.pullRequest) && raw.pullRequest > 0,
		"PR_REQUIRED",
	);
	demand(
		Array.isArray(raw.tests) &&
			raw.tests.length > 0 &&
			raw.tests.every(
				(t) => typeof t === "string" && t.length > 0 && t.length <= 500,
			),
		"TEST_EVIDENCE_REQUIRED",
	);
	demand(
		Array.isArray(raw.evidenceRefs) &&
			raw.evidenceRefs.length > 0 &&
			raw.evidenceRefs.every(
				(x) => typeof x === "string" && x.length > 0 && x.length <= 1000,
			),
		"EVIDENCE_REQUIRED",
	);
	return frozen({
		...structuredClone(raw),
		state: "handed_off",
		releaseVerified: false,
	});
}
function requireVerification({ task, handoff, receipt, verifier, builder }) {
	demand(
		typeof builder?.principalId === "string" &&
			builder.principalId.length > 0 &&
			builder.id === handoff.workerId &&
			handoff.taskId === task.id,
		"BUILDER_IDENTITY_REQUIRED",
	);
	demand(
		typeof verifier?.principalId === "string" &&
			verifier.principalId.length > 0 &&
			verifier.verifiedIdentity === true &&
			verifier.lane === "release" &&
			verifier.principalId !== builder.principalId &&
			verifier.id !== handoff.workerId,
		"INDEPENDENT_VERIFIER_REQUIRED",
	);
	demand(
		receipt?.verifierPrincipalId === verifier.principalId,
		"VERIFIER_RECEIPT_MISMATCH",
	);
	demand(
		receipt?.taskId === task.id &&
			receipt.headSha === handoff.headSha &&
			receipt.generation === handoff.generation &&
			receipt.verified === true &&
			typeof receipt.ref === "string" &&
			receipt.ref.length > 0,
		"VERIFICATION_SCOPE_MISMATCH",
	);
	demand(
		Array.isArray(receipt.criteria) &&
			task.acceptance.every((c) => receipt.criteria.includes(c)),
		"ACCEPTANCE_INCOMPLETE",
	);
	demand(receipt.providerReadback === true, "PROVIDER_READBACK_REQUIRED");
	if (task.risk === "production" || task.risk === "destructive")
		demand(
			receipt.approvalRef && receipt.rollbackRef,
			"PRODUCTION_PROOF_REQUIRED",
		);
	return frozen({
		taskId: task.id,
		headSha: handoff.headSha,
		receiptRef: receipt.ref,
		digest: digest(receipt),
		state: "complete",
	});
}
module.exports = { OperationsRuntime, validateHandoff, requireVerification };
