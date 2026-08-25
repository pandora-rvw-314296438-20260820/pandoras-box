"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.destructiveCapabilityReservationDeliveryId = destructiveCapabilityReservationDeliveryId;
exports.createDestructiveCapabilityReservationIntent = createDestructiveCapabilityReservationIntent;

const { createHash } = require("node:crypto");
const { ExecutionLedgerError } = require("./execution-ledger-client.js");
const { executionPayloadHash, stableValue } = require("./execution-payload.js");

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const ORGANIZATION_SLUG_PATTERN = /^[a-z0-9]{20}$/;

function destructiveCapabilityReservationDeliveryId(tool, args) {
    if (tool !== "supabase.delete-child-branch") {
        throw new Error("Destructive capability reservations are only defined for child-branch deletion");
    }

    const capability = args && typeof args === "object" && !Array.isArray(args)
        ? args.deletionCapability
        : undefined;

    if (!capability
        || typeof capability !== "object"
        || Array.isArray(capability)
        || capability.schemaVersion !== "supabase-child-deletion-capability-v3"
        || capability.action !== "delete-and-reconcile-child-branch"
        || typeof capability.operationNonce !== "string"
        || !SHA256_PATTERN.test(capability.operationNonce)
        || typeof capability.organizationSlug !== "string"
        || !ORGANIZATION_SLUG_PATTERN.test(capability.organizationSlug)
        || capability.accountId !== args.accountId
        || capability.parentProjectRef !== args.parentProjectRef
        || capability.branchId !== args.branchId
        || capability.childProjectRef !== args.childProjectRef) {
        throw new Error("Delete-child execution requires an exact pre-issued deletion capability");
    }

    const canonical = JSON.stringify({
        reservationDomain: "projectos-supabase-child-branch-delete-v1",
        parentProjectRef: capability.parentProjectRef,
        branchId: capability.branchId,
        childProjectRef: capability.childProjectRef,
    });

    return createHash("sha256").update(canonical, "utf8").digest("hex");
}

function createDestructiveCapabilityReservationIntent(claimedPlan) {
    if (claimedPlan.tool !== "supabase.delete-child-branch") return undefined;

    if (!UUID_PATTERN.test(claimedPlan.planId || "")
        || !UUID_PATTERN.test(claimedPlan.requestId || "")
        || !UUID_PATTERN.test(claimedPlan.intakeId || "")
        || claimedPlan.status !== "executing"
        || claimedPlan.risk !== "destructive"
        || !claimedPlan.args
        || typeof claimedPlan.args !== "object"
        || Array.isArray(claimedPlan.args)
        || !SHA256_PATTERN.test(claimedPlan.payloadHash || "")
        || claimedPlan.payloadHash !== executionPayloadHash(claimedPlan.tool, claimedPlan.args)) {
        throw new ExecutionLedgerError("Delete-child plan is missing its durable reservation binding", 409);
    }

    const capability = claimedPlan.args.deletionCapability;
    if (!capability
        || typeof capability !== "object"
        || Array.isArray(capability)
        || typeof capability.signingKeyId !== "string"
        || typeof capability.reservationKeyId !== "string"
        || typeof capability.membershipSnapshotSha256 !== "string"
        || !SHA256_PATTERN.test(capability.membershipSnapshotSha256)) {
        throw new ExecutionLedgerError("Delete-child plan capability binding is invalid", 409);
    }

    const deliveryId = destructiveCapabilityReservationDeliveryId(claimedPlan.tool, claimedPlan.args);
    const payloadBinding = {
        schemaVersion: "projectos-destructive-capability-reservation-v1",
        action: capability.action,
        capabilitySchemaVersion: capability.schemaVersion,
        signingKeyId: capability.signingKeyId,
        reservationKeyId: capability.reservationKeyId,
        accountId: capability.accountId,
        organizationSlug: capability.organizationSlug,
        parentProjectRef: capability.parentProjectRef,
        parentStatus: capability.parentStatus,
        branchId: capability.branchId,
        childProjectRef: capability.childProjectRef,
        operationNonce: capability.operationNonce,
        membershipSnapshotSha256: capability.membershipSnapshotSha256,
        issuedAt: capability.issuedAt,
        deleteAuthorizationExpiresAt: capability.deleteAuthorizationExpiresAt,
        reconciliationExpiresAt: capability.reconciliationExpiresAt,
        sourcePlanId: claimedPlan.planId,
        sourceRequestId: claimedPlan.requestId,
        sourceIntakeId: claimedPlan.intakeId,
        sourcePayloadHash: claimedPlan.payloadHash,
    };
    const payloadRedacted = {
        schemaVersion: "projectos-destructive-capability-reservation-redacted-v1",
        reservationDomain: "projectos-supabase-child-branch-delete-v1",
        targetDigest: deliveryId,
        sourcePlanId: claimedPlan.planId,
        sourceRequestId: claimedPlan.requestId,
        sourcePayloadHash: claimedPlan.payloadHash,
    };

    return {
        schemaVersion: "projectos-destructive-capability-reservation-intent-v1",
        provider: "projectos_capability_reservation",
        deliveryId,
        eventType: "supabase_child_branch_delete_reserved",
        payloadHash: createHash("sha256")
            .update(JSON.stringify(stableValue(payloadBinding)), "utf8")
            .digest("hex"),
        payloadBinding,
        payloadRedacted,
    };
}
