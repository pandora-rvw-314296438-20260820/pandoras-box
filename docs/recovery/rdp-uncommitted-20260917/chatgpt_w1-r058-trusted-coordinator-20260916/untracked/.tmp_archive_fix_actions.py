from pathlib import Path
p=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916\.tmp_patch_actions.py')
s=p.read_text(encoding='utf-8').replace("print('patched expiry runtime')p=", "print('patched expiry runtime')\np=")
p.write_text(s,encoding='utf-8')
print('fixed actions helper')