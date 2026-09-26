"use strict";
const { demand, digest, frozen } = require("../pandora-operations-room/contracts");
const { SupabaseOperationsStore } = require("../pandora-operations-room/postgres-store");
const { bounded, failure } = require("./http.cjs");
class NativeDeliveryJournal {
  #client;
  #scope;
  constructor({ client, scope }) {
    demand(typeof client?.rpc === "function" && typeof scope?.organizationId === "string" &&
      typeof scope?.projectId === "string", "JOURNAL_NATIVE_SCOPE_REQUIRED");
    this.#client = client;
    this.#scope = frozen({ organizationId: scope.organizationId, projectId: scope.projectId });
    this.durability = "durable";
  }
  async #call(operation, envelope, { requestDigest = null, receipt = null } = {}) {
    demand(envelope.organizationId === this.#scope.organizationId &&
      envelope.projectId === this.#scope.projectId, "JOURNAL_SCOPE_DENIED");
    const result = await bounded(() => this.#client.rpc("pandora_ops_connector_delivery_v1", {
      p_operation: operation, p_organization_id: this.#scope.organizationId,
      p_project_id: this.#scope.projectId, p_envelope: envelope,
      p_envelope_digest: digest(envelope), p_request_digest: requestDigest, p_receipt: receipt,
    }));
    if (result?.error) throw failure(/^OPS_CONNECTOR_[A-Z_]+$/.test(result.error.message || "")
      ? result.error.message : "JOURNAL_NATIVE_FAILURE");
    demand(result?.data && typeof result.data === "object", "JOURNAL_READBACK_INVALID");
    return result.data;
  }
  prepare(envelope, requestDigest) { return this.#call("prepare", envelope, { requestDigest }); }
  recordDelivery(envelope, receipt) { return this.#call("delivered", envelope, { receipt }); }
  markUnknown(envelope) { return this.#call("unknown", envelope); }
  read(envelope) { return this.#call("read", envelope); }
  authorizeSend(envelope) { return this.#call("admit", envelope); }
  async readAcknowledgement(envelope) { return (await this.read(envelope)).acknowledgement; }
  acknowledge(envelope, authenticatedReceipt) {
    return this.#call("acknowledge", envelope, { receipt: authenticatedReceipt });
  }
}
// Preserve the already-merged scheduler, but fence a genuine delayed ACK racing its catch path.
class ConnectorOperationsStore extends SupabaseOperationsStore {
  async markReconciliationRequired(scope, claim, info) {
    return this.call("pandora_ops_connector_reconcile_v1", scope, {
      p_lease_id: claim.leaseId, p_generation: claim.generation, p_reason: info.code,
    });
  }
}
module.exports = { NativeDeliveryJournal, ConnectorOperationsStore };
