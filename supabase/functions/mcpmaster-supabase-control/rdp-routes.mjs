const WORKER = Object.freeze({
  workerKey: "pandora-rdp-windows-01",
  principalKey: "rdp:EC2AMAZ-SPAE2VG:operations-worker-v1",
  lanes: ["reliability", "mobile", "backend", "web"],
  capabilities: [
    "rdp.execute",
    "rdp.toolchain.verify",
    "rdp.github_runner.verify",
    "rdp.android.verify",
    "rdp.flutter.verify",
    "rdp.repo.test",
    "rdp.repo.build",
    "worker.reconcile",
  ],
  capacity: 1,
});

const TASK_PATTERN = /^OPS-RDP-[A-Za-z0-9_.:-]{1,110}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function text(input, key) {
  const value = input?.[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function integer(input, key, min = 0) {
  const value = input?.[key];
  return Number.isInteger(value) && value >= min ? value : undefined;
}

export function routeForRdpOperations(input, projectId) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;

  if (input.action === "operations_rdp_authorize") {
    const workerKey = text(input, "workerKey");
    const tokenSha256 = text(input, "tokenSha256");
    if (workerKey !== WORKER.workerKey || !/^[0-9a-f]{64}$/.test(tokenSha256 || "")) return undefined;
    return { action: input.action, rpc: "pandora_ops_rdp_authorize_v1", responseKey: "operations",
      params: { p_worker_key: workerKey, p_token_sha256: tokenSha256 } };
  }

  if (input.action === "operations_rdp_register") {
    return { action: input.action, rpc: "pandora_ops_register_rdp_worker_v1", responseKey: "operations",
      params: { p_project_id: projectId, p_worker_key: WORKER.workerKey, p_principal_key: WORKER.principalKey,
        p_lanes: WORKER.lanes, p_capabilities: WORKER.capabilities, p_capacity: WORKER.capacity,
        p_receipt_ref: "rdp:EC2AMAZ-SPAE2VG:scheduled-worker-v1" } };
  }

  if (input.action === "operations_rdp_heartbeat") {
    return { action: input.action, rpc: "pandora_ops_heartbeat_v1", responseKey: "operations",
      params: { p_project_id: projectId, p_worker_key: WORKER.workerKey, p_principal_key: WORKER.principalKey,
        p_connected: true, p_health: "ready" } };
  }

  if (input.action === "operations_rdp_claim") {
    const taskId = text(input, "taskId");
    const taskRevision = integer(input, "taskRevision");
    const controlRevision = integer(input, "controlRevision");
    if (!TASK_PATTERN.test(taskId || "") || taskRevision === undefined || controlRevision === undefined) return undefined;
    return { action: input.action, rpc: "pandora_ops_claim_v1", responseKey: "operations",
      params: { p_project_id: projectId, p_task_key: taskId, p_worker_key: WORKER.workerKey,
        p_task_revision: taskRevision, p_control_revision: controlRevision } };
  }

  if (input.action === "operations_rdp_dispatch_ack") {
    const leaseId = text(input, "leaseId");
    const dispatchId = text(input, "dispatchId");
    const taskId = text(input, "taskId");
    const generation = integer(input, "generation", 1);
    const receiptRef = text(input, "receiptRef");
    if (!UUID_PATTERN.test(leaseId || "") || !UUID_PATTERN.test(dispatchId || "") || !TASK_PATTERN.test(taskId || "")
      || generation === undefined || !receiptRef || receiptRef.length > 1000) return undefined;
    return { action: input.action, rpc: "pandora_ops_dispatch_v1", responseKey: "operations",
      params: { p_project_id: projectId, p_lease_id: leaseId, p_generation: generation,
        p_ack: { accepted: true, dispatchId, workerId: WORKER.workerKey, taskId, generation, receiptRef } } };
  }

  if (input.action === "operations_rdp_handoff") {
    const leaseId = text(input, "leaseId");
    const generation = integer(input, "generation", 1);
    if (!UUID_PATTERN.test(leaseId || "") || generation === undefined
      || !input.handoff || typeof input.handoff !== "object" || Array.isArray(input.handoff)) return undefined;
    return { action: input.action, rpc: "pandora_ops_handoff_v1", responseKey: "operations",
      params: { p_project_id: projectId, p_lease_id: leaseId, p_generation: generation,
        p_principal_key: WORKER.principalKey, p_handoff: input.handoff, p_actual_cost_micros: 0 } };
  }

  return undefined;
}
