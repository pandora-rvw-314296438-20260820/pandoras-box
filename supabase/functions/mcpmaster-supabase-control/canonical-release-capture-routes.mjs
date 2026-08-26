const CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const SHA_PATTERN = /^[0-9a-f]{40}$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const ARTIFACT_ID_PATTERN = /^[1-9][0-9]{0,19}$/;
const DEPLOYMENT_ID_PATTERN = /^dpl_[A-Za-z0-9]{1,128}$/;
const GITHUB_ARTIFACT_URL =
  "https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/artifacts/";

function exactKeys(input, expected) {
  const actual = Object.keys(input).sort();
  const canonical = [...expected].sort();
  return actual.length === canonical.length
    && actual.every((key, index) => key === canonical[index]);
}

function stringField(input, key) {
  const value = input[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

export function routeForCanonicalReleaseCapture(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;

  if (input.action === "canonical_supabase_receipt_capture") {
    if (!exactKeys(input, [
      "action",
      "repository",
      "sourceSha",
      "sourceTreeSha",
      "sourceChainSha256",
      "sourceArtifactSha256",
      "sourceArtifactExternalId",
      "sourceArtifactUrl",
      "expectedVersionChainSha256",
    ])) return undefined;
    const repository = stringField(input, "repository");
    const sourceSha = stringField(input, "sourceSha");
    const sourceTreeSha = stringField(input, "sourceTreeSha");
    const sourceChainSha256 = stringField(input, "sourceChainSha256");
    const sourceArtifactSha256 = stringField(input, "sourceArtifactSha256");
    const sourceArtifactExternalId = stringField(input, "sourceArtifactExternalId");
    const sourceArtifactUrl = stringField(input, "sourceArtifactUrl");
    const expectedVersionChainSha256 = stringField(input, "expectedVersionChainSha256");
    if (
      repository !== CANONICAL_REPOSITORY
      || !SHA_PATTERN.test(sourceSha || "")
      || !SHA_PATTERN.test(sourceTreeSha || "")
      || !SHA256_PATTERN.test(sourceChainSha256 || "")
      || !SHA256_PATTERN.test(sourceArtifactSha256 || "")
      || !ARTIFACT_ID_PATTERN.test(sourceArtifactExternalId || "")
      || sourceArtifactUrl !== GITHUB_ARTIFACT_URL + sourceArtifactExternalId
      || !SHA256_PATTERN.test(expectedVersionChainSha256 || "")
    ) return undefined;
    return {
      action: "canonical_supabase_receipt_capture",
      rpc: "capture_canonical_supabase_release_receipt",
      responseKey: "supabaseReceipt",
      params: {
        p_repository: repository,
        p_source_sha: sourceSha,
        p_source_tree_sha: sourceTreeSha,
        p_source_chain_sha256: sourceChainSha256,
        p_source_artifact_sha256: sourceArtifactSha256,
        p_source_artifact_external_id: sourceArtifactExternalId,
        p_source_artifact_url: sourceArtifactUrl,
        p_expected_version_chain_sha256: expectedVersionChainSha256,
      },
    };
  }

  if (input.action === "canonical_vercel_rehearsal_capture") {
    if (!exactKeys(input, [
      "action",
      "repository",
      "candidateSourceSha",
      "phase",
      "candidateDeploymentId",
      "rollbackDeploymentId",
      "rollbackSourceSha",
    ])) return undefined;
    const repository = stringField(input, "repository");
    const candidateSourceSha = stringField(input, "candidateSourceSha");
    const phase = stringField(input, "phase");
    const candidateDeploymentId = stringField(input, "candidateDeploymentId");
    const rollbackDeploymentId = stringField(input, "rollbackDeploymentId");
    const rollbackSourceSha = stringField(input, "rollbackSourceSha");
    if (
      repository !== CANONICAL_REPOSITORY
      || !SHA_PATTERN.test(candidateSourceSha || "")
      || !SHA_PATTERN.test(rollbackSourceSha || "")
      || candidateSourceSha === rollbackSourceSha
      || !["rollback_transition", "rollback_restoration"].includes(phase || "")
      || !DEPLOYMENT_ID_PATTERN.test(candidateDeploymentId || "")
      || !DEPLOYMENT_ID_PATTERN.test(rollbackDeploymentId || "")
      || candidateDeploymentId === rollbackDeploymentId
    ) return undefined;
    return {
      action: "canonical_vercel_rehearsal_capture",
      rpc: "capture_canonical_vercel_rehearsal_receipt",
      responseKey: "vercelRehearsalReceipt",
      params: {
        p_repository: repository,
        p_candidate_source_sha: candidateSourceSha,
        p_phase: phase,
        p_candidate_deployment_id: candidateDeploymentId,
        p_rollback_deployment_id: rollbackDeploymentId,
        p_rollback_source_sha: rollbackSourceSha,
      },
    };
  }

  return undefined;
}
