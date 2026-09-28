// Called only after the control gateway verifies the production Vercel OIDC identity.
const TASK = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FIELDS = ["action","requestId","taskId","generation","revision","taskSpecDigest","expectedHeadSha"];
export function routeForMergedRelease(input, projectId) {
  if (input?.action !== "operations_merged_release_reconcile") return undefined;
  if (Object.keys(input).length !== FIELDS.length || FIELDS.some(key => !Object.hasOwn(input,key))
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
