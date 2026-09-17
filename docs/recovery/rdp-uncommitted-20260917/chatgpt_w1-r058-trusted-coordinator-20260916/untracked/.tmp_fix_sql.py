from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\supabase\migrations\20260916084500_r058_effective_sheet_snapshot_fence.sql')
s=p.read_text(encoding='utf-8')
s=s.replace(') returns jsonblanguage plpgsql', ') returns jsonb\nlanguage plpgsql')
s=s.replace('to service_role;create or replace function', 'to service_role;\n\ncreate or replace function')
p.write_text(s,encoding='utf-8')
print('fixed sql joins')