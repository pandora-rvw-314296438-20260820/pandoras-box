from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\.tmp_insert_snapshot.py')
s=p.read_text(encoding='utf-8')
s=s.replace("'''block +=", "'''\nblock +=")
p.write_text(s,encoding='utf-8')
print('fixed insert helper')