"use strict";
const { demand, frozen } = require("./contracts");
class SupabaseOperationsStore {
	constructor(client) {
		demand(typeof client?.rpc === "function", "SUPABASE_CLIENT_REQUIRED");
		this.client = client;
		this.durability = "durable";
	}
	async call(name, scope, args = {}) {
		demand(
			scope &&
				typeof scope.organizationId === "string" &&
				typeof scope.projectId === "string",
			"SCOPE_REQUIRED",
		);
		const r = await this.client.rpc(name, {
			p_organization_id: scope.organizationId,
			p_project_id: scope.projectId,
			...args,
		});
		if (r.error)
			throw Object.assign(new Error("OPERATIONS_STORE_FAILURE"), {
				code: r.error.code,
			});
		return r.data;
	}
	async snapshot(scope) {
		return this.call("pandora_ops_snapshot_v1", scope);
	}
	async claim(scope, a) {
		return this.call("pandora_ops_claim_v1", scope, {
			p_task_key: a.taskId,
			p_worker_key: a.workerId,
			p_task_revision: a.taskRevision,
			p_control_revision: a.controlRevision,
		});
	}
	async beginDispatch(scope, c) {
		return this.call("pandora_ops_dispatch_v1", scope, {
			p_lease_id: c.leaseId,
			p_generation: c.generation,
			p_ack: null,
		});
	}
	async acknowledgeDispatch(scope, c, a) {
		return this.call("pandora_ops_dispatch_v1", scope, {
			p_lease_id: c.leaseId,
			p_generation: c.generation,
			p_ack: a,
		});
	}
	async markReconciliationRequired(scope, c, info) {
		return this.call("pandora_ops_reconcile_required_v1", scope, {
			p_lease_id: c.leaseId,
			p_generation: c.generation,
			p_reason: info.code,
		});
	}
}
module.exports = { SupabaseOperationsStore };
