from pathlib import Path
root=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916')
p=root/'test'/'supabase-migration-parity.test.js'
s=p.read_text(encoding='utf-8')
old="'20260916103837_r058_effective_sheet_snapshot_fence.sql'"
new="'20260916103837_r058_effective_sheet_snapshot_fence.sql',\n  '20260916110444_r058_publication_abort_recovery.sql'"
count=s.count(old)
if count != 3: raise SystemExit(f'expected 3 fence anchors, got {count}')
s=s.replace(old,new)
p.write_text(s,encoding='utf-8')
print('migration inventory anchors patched',count)
