from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\migrations\20260916084500_r058_effective_sheet_snapshot_fence.sql')
s=p.read_text(encoding='utf-8')
marker='create or replace function public.pandora_coordinator_gate_begin_decision_v2('
block="""alter table private.pandora_coordinator_repository_fence\n  drop constraint if exists pandora_coordinator_repository_fence_fence_state_check;\nalter table private.pandora_coordinator_repository_fence\n  add constraint pandora_coordinator_repository_fence_fence_state_check\n  check (fence_state in ('idle','promoting','publishing','merging'));\nalter table private.pandora_coordinator_repository_fence\n  add column if not exists active_publication_decision_id uuid references private.pandora_coordinator_gate_decisions(id),\n  add column if not exists active_merge_claim_id uuid,\n  add column if not exists active_merge_pull_request_number integer;\n\n"""
if block not in s:
    s=s.replace(marker,block+marker)
needle="""    raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';\n  end if;\n\n  v_generation:=v_fence.effective_snapshot_generation+1;"""
replacement="""    raise exception 'pandora_coordinator_snapshot_promotion_conflict' using errcode='23505';\n  end if;\n  if v_fence.fence_state<>'idle' then\n    raise exception 'pandora_coordinator_repository_fence_busy' using errcode='55000';\n  end if;\n\n  v_generation:=v_fence.effective_snapshot_generation+1;"""
s=s.replace(needle,replacement)
s=s.replace('p_authoritative_snapshot_generation bigint,  p_authoritative_snapshot_revision text,','p_authoritative_snapshot_generation bigint,\n  p_authoritative_snapshot_revision text,')
p.write_text(s,encoding='utf-8')
print('patched fence prelude')