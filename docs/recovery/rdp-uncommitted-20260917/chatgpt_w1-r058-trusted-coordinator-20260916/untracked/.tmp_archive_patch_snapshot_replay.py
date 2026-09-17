from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\migrations\20260916084500_r058_effective_sheet_snapshot_fence.sql')
s=p.read_text(encoding='utf-8')
start=s.index("  if v_fence.fence_state='promoting' then")
end=s.index("\n  v_generation:=v_fence.effective_snapshot_generation+1;", start)
block="""  select * into v_existing
  from private.pandora_coordinator_snapshot_promotions
  where promotion_nonce=p_promotion_nonce;
  if found then
    if v_existing.repository<>p_repository or v_existing.spreadsheet_id<>p_spreadsheet_id
       or v_existing.candidate_revision<>p_candidate_revision
       or v_existing.candidate_sha256<>p_candidate_sha256 then
      raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';
    end if;
    if v_existing.state='effective' then
      return jsonb_build_object(
        'mode','effective_replay','promotionId',v_existing.id,
        'snapshotGeneration',v_existing.snapshot_generation,
        'requiredRevocations',v_existing.required_revocations,
        'completedRevocations',v_existing.completed_revocations,'revocations','[]'::jsonb
      );
    end if;
    if v_existing.state='revoking' and v_fence.fence_state='promoting'
       and v_fence.active_promotion_id=v_existing.id then
      select coalesce(jsonb_agg(jsonb_build_object(
        'pullRequestNumber',pull_request_number,'checkRunId',check_run_id,'headSha',head_sha
      ) order by pull_request_number),'[]'::jsonb) into v_targets
      from private.pandora_coordinator_snapshot_revocations where promotion_id=v_existing.id;
      return jsonb_build_object(
        'mode','replay','promotionId',v_existing.id,'snapshotGeneration',v_existing.snapshot_generation,
        'requiredRevocations',v_existing.required_revocations,'completedRevocations',v_existing.completed_revocations,
        'revocations',v_targets
      );
    end if;
    raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';
  end if;
  if v_fence.fence_state<>'idle' then
    raise exception 'pandora_coordinator_repository_fence_busy' using errcode='55000';
  end if;
"""
s=s[:start]+block+s[end:]
p.write_text(s,encoding='utf-8')
print('patched snapshot replay')