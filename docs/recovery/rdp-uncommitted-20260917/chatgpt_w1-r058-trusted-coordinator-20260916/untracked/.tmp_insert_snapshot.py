from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\functions\pandora-coordinator-gate\index.ts')
s=p.read_text(encoding='utf-8')
marker='\nasync function handlePublish(admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord) {'
block='''
async function readEffectiveSnapshot(admin: ReturnType<typeof adminClient>, internalKey: string) {
  const value = await rpc(admin, "pandora_coordinator_snapshot_read_effective_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
  }, "SNAPSHOT_READ_FAILED");
  return value ? rec(value) : null;
}
function validSnapshotField(value: unknown, max: number) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}
async function handleSnapshotPromotion(
  admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord,
) {
  const candidateRevision = typeof body.candidateRevision === "string" ? body.candidateRevision.trim() : "";
  const candidateSha256 = typeof body.candidateSha256 === "string" ? body.candidateSha256.trim() : "";
  const evidenceRef = typeof body.evidenceRef === "string" ? body.evidenceRef.trim() : "";
  const providerReadAt = typeof body.providerReadAt === "string" ? body.providerReadAt.trim() : "";
  const promotionNonce = typeof body.promotionNonce === "string" ? body.promotionNonce.trim() : "";
'''
block += '''  const readMs = Date.parse(providerReadAt);
  if (!validSnapshotField(candidateRevision, 192) || !/^[0-9a-f]{64}$/.test(candidateSha256) ||
      !validSnapshotField(evidenceRef, 240) || !validSnapshotField(promotionNonce, 240) ||
      !Number.isFinite(readMs)) throw new Error("INVALID_SNAPSHOT_PROMOTION");
  const prepared = rec(await rpc(admin, "pandora_coordinator_snapshot_prepare_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_spreadsheet_id: SPREADSHEET_ID,
    p_candidate_revision: candidateRevision,
    p_candidate_sha256: candidateSha256,
    p_evidence_ref: evidenceRef,
    p_provider_read_at: providerReadAt,
    p_promotion_nonce: promotionNonce,
  }, "SNAPSHOT_PREPARE_FAILED"));
  const promotionId = String(prepared.promotionId || "");
  if (!promotionId) throw new Error("SNAPSHOT_PROMOTION_ID_MISSING");
  const targets = Array.isArray(prepared.revocations) ? prepared.revocations.map(rec) : [];
  if (targets.length > 0) {
    const provider = githubProvider(await githubInstallationToken(admin));
    for (const target of targets) {
      const checkRunId = Number(target.checkRunId);
      const pullRequestNumber = Number(target.pullRequestNumber);
      const headSha = String(target.headSha || "");
'''
block += '''      if (!Number.isSafeInteger(checkRunId) || checkRunId < 1 ||
          !Number.isSafeInteger(pullRequestNumber) || pullRequestNumber < 1 ||
          !/^[0-9a-f]{40}$/.test(headSha)) throw new Error("SNAPSHOT_REVOCATION_TARGET_INVALID");
      const revoked = rec(await revokeCheckForSnapshot(provider, checkRunId, headSha, promotionId));
      const check = rec(revoked.check);
      await rpc(admin, "pandora_coordinator_snapshot_record_revocation_v1", {
        p_internal_key: internalKey,
        p_repository: CANONICAL_REPOSITORY,
        p_promotion_id: promotionId,
        p_pull_request_number: pullRequestNumber,
        p_check_run_id: checkRunId,
        p_provider_app_id: Number(rec(check.app).id),
        p_provider_status: check.status,
        p_provider_conclusion: check.conclusion,
      }, "SNAPSHOT_REVOCATION_RECORD_FAILED");
    }
  }
  const committed = rec(await rpc(admin, "pandora_coordinator_snapshot_commit_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_promotion_id: promotionId,
  }, "SNAPSHOT_COMMIT_FAILED"));
  return { ok: true, action: "promoteSnapshot", ...committed };
}
async function handleSnapshotAbort(
  admin: ReturnType<typeof adminClient>, internalKey: string, body: JsonRecord,
) {
'''
block += '''  const promotionId = typeof body.promotionId === "string" ? body.promotionId.trim() : "";
  if (!promotionId) throw new Error("INVALID_SNAPSHOT_PROMOTION");
  const result = rec(await rpc(admin, "pandora_coordinator_snapshot_abort_v1", {
    p_internal_key: internalKey,
    p_repository: CANONICAL_REPOSITORY,
    p_promotion_id: promotionId,
  }, "SNAPSHOT_ABORT_FAILED"));
  return { ok: true, action: "abortSnapshot", ...result };
}
'''
if 'async function handleSnapshotPromotion' not in s:
    s=s.replace(marker,'\n'+block+marker)
p.write_text(s,encoding='utf-8')
print('inserted snapshot runtime')