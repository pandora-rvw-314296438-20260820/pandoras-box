from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\functions\pandora-coordinator-gate\index.ts')
s=p.read_text(encoding='utf-8')
old='''  const token = await githubInstallationToken(admin);
  const result = rec(await expireCheck(githubProvider(token), checkRunId, headSha));
  if (result.state === "expired") {
    await rpc(admin, "pandora_coordinator_gate_mark_expired_v1", {
      p_internal_key: internalKey,
      p_repository: CANONICAL_REPOSITORY,
      p_pull_request_number: pullNumber,
      p_decision_generation: state.current_generation,
      p_check_run_id: checkRunId,
    }, "GATE_EXPIRY_RECORD_FAILED");
  }
'''
new='''  const expiresAt = Date.parse(String(state.expires_at || ""));
  if (Number.isFinite(expiresAt) && expiresAt > Date.now()) {
    return { ok: true, action: "expire", pullRequestNumber: pullNumber, state: "fresh", checkRunId };
  }
  await rpc(admin, "pandora_coordinator_gate_begin_expiry_v2", {
    p_internal_key: internalKey, p_repository: CANONICAL_REPOSITORY,
    p_pull_request_number: pullNumber, p_decision_generation: state.current_generation,
    p_check_run_id: checkRunId,
  }, "GATE_EXPIRY_FENCE_FAILED");
  const token = await githubInstallationToken(admin);
  const result = rec(await expireCheck(githubProvider(token), checkRunId, headSha));
  if (result.state === "expired" || result.state === "already_invalid") {
    await rpc(admin, "pandora_coordinator_gate_mark_expired_v2", {
      p_internal_key: internalKey, p_repository: CANONICAL_REPOSITORY,
      p_pull_request_number: pullNumber, p_decision_generation: state.current_generation,
      p_check_run_id: checkRunId,
    }, "GATE_EXPIRY_RECORD_FAILED");
  }
'''
if old not in s: raise SystemExit('expiry block not found')
s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
print('patched expiry runtime')
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\functions\pandora-coordinator-gate\index.ts')
s=p.read_text(encoding='utf-8')
needle='''    if (action === "publish") {
      return reply(200, await handlePublish(admin, internalKey, body));
    }
'''
replacement='''    if (action === "promoteSnapshot") {
      return reply(200, await handleSnapshotPromotion(admin, internalKey, body));
    }
    if (action === "abortSnapshot") {
      return reply(200, await handleSnapshotAbort(admin, internalKey, body));
    }
    if (action === "readSnapshot") {
      return reply(200, { ok: true, action: "readSnapshot", state: await readEffectiveSnapshot(admin, internalKey) });
    }
    if (action === "publish") {
      return reply(200, await handlePublish(admin, internalKey, body));
    }
'''
if needle not in s: raise SystemExit('action needle not found')
s=s.replace(needle,replacement)
s=s.replace('code === "INVALID_JSON" || code === "UNKNOWN_ACTION" || code === "INVALID_PULL_REQUEST" ? 400', 'code === "INVALID_JSON" || code === "UNKNOWN_ACTION" || code === "INVALID_PULL_REQUEST" || code === "INVALID_SNAPSHOT_PROMOTION" ? 400')
p.write_text(s,encoding='utf-8')
print('patched action routing')