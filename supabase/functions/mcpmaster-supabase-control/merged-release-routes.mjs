// Called only after the control gateway verifies the production Vercel OIDC identity.
const TASK = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RECONCILE_FIELDS = ["action","requestId","taskId","generation","revision","taskSpecDigest","expectedHeadSha"];
const VERIFY_SOURCE_FIELDS = ["action","taskId","generation","taskSpecDigest","expectedHeadSha","reconciliationReceiptId"];

function exactFields(input, fields) {
  return input && Object.keys(input).length === fields.length && fields.every(key => Object.hasOwn(input,key));
}

export function routeForMergedRelease(input, projectId) {
  if (input?.action === "operations_merged_release_reconcile") {
    if (!exactFields(input,RECONCILE_FIELDS)
        || !UUID.test(input.requestId || "") || !TASK.test(input.taskId || "")
        || !Number.isSafeInteger(input.generation) || input.generation < 1
        || !Number.isSafeInteger(input.revision) || input.revision < 0
        || !/^[a-f0-9]{64}$/.test(input.taskSpecDigest || "")
        || !/^[a-f0-9]{40}$/.test(input.expectedHeadSha || "")) return undefined;
    return {
      action: input.action,
      rpc: "pandora_ops_reconcile_merged_release_v1",
      responseKey: "operations",
      params: {
        p_project_id: projectId,
        p_request_id: input.requestId,
        p_task_key: input.taskId,
        p_generation: input.generation,
        p_revision: input.revision,
        p_spec_digest: input.taskSpecDigest,
        p_expected_head_sha: input.expectedHeadSha,
        p_reconciler_worker_key: "pandora-native-release-v1",
        p_reconciler_principal_key: "vercel:mcpmaster:operations-native-release-v1",
      },
    };
  }

  if (input?.action === "operations_merged_release_source_step") {
    if (!exactFields(input,["action"])) return undefined;
    return {
      action: input.action,
      rpc: "pandora_ops_merged_release_source_step_v1",
      responseKey: "operations",
      params: {
        p_project_id: projectId,
        p_worker_key: "pandora-native-release-v1",
        p_principal_key: "vercel:mcpmaster:operations-native-release-v1",
      },
    };
  }

  if (input?.action === "operations_merged_release_verify_source") {
    if (!exactFields(input,VERIFY_SOURCE_FIELDS)
        || input.taskId !== "FB-025"
        || !Number.isSafeInteger(input.generation) || input.generation < 1
        || !/^[a-f0-9]{64}$/.test(input.taskSpecDigest || "")
        || !/^[a-f0-9]{40}$/.test(input.expectedHeadSha || "")
        || !UUID.test(input.reconciliationReceiptId || "")) return undefined;
    return {
      action: input.action,
      rpc: "pandora_ops_verify_merged_release_source_v1",
      responseKey: "operations",
      params: {
        p_project_id: projectId,
        p_task_key: input.taskId,
        p_generation: input.generation,
        p_spec_digest: input.taskSpecDigest,
        p_expected_head_sha: input.expectedHeadSha,
        p_reconciliation_receipt_id: input.reconciliationReceiptId,
        p_verifier_worker_key: "pandora-native-release-v1",
        p_verifier_principal_key: "vercel:mcpmaster:operations-native-release-v1",
      },
    };
  }

  return undefined;
}
