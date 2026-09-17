from pathlib import Path
root=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916')
for rel in ['test/pandora-coordinator-gate.test.js','test/pandora-coordinator-publisher.test.js']:
    p=root/rel
    s=p.read_text(encoding='utf-8')
    s=s.replace('    spreadsheetId: "1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0",\n    authoritativeSnapshotRevision:', '    spreadsheetId: "1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0",\n    authoritativeSnapshotGeneration: 3,\n    authoritativeSnapshotRevision:')
    p.write_text(s,encoding='utf-8')
    print('patched',rel)