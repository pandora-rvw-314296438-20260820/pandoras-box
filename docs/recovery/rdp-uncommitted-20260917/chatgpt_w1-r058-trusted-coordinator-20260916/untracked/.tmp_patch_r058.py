from pathlib import Path
root=Path(r'C:\Pandora\w1-r058-trusted-coordinator-20260916')
p=root/'supabase/functions/pandora-coordinator-gate/contract.mjs'
s=p.read_text(encoding='utf-8')
s=s.replace('"integrationAppId", "spreadsheetId", "authoritativeSnapshotRevision",\n  "authoritativeSnapshotSha256",', '"integrationAppId", "spreadsheetId", "authoritativeSnapshotGeneration",\n  "authoritativeSnapshotRevision", "authoritativeSnapshotSha256",')
s=s.replace('  const generation = Number(value.decisionGeneration);', '  const snapshotGeneration = Number(value.authoritativeSnapshotGeneration);\n  const generation = Number(value.decisionGeneration);')
s=s.replace('value.spreadsheetId !== SPREADSHEET_ID || !TOKEN.test(String(value.authoritativeSnapshotRevision || "")) ||', 'value.spreadsheetId !== SPREADSHEET_ID || !Number.isSafeInteger(snapshotGeneration) || snapshotGeneration < 1 ||\n    !TOKEN.test(String(value.authoritativeSnapshotRevision || "")) ||')
s=s.replace('    authoritativeSnapshotSha256: value.authoritativeSnapshotSha256,', '    authoritativeSnapshotGeneration: value.authoritativeSnapshotGeneration,\n    authoritativeSnapshotSha256: value.authoritativeSnapshotSha256,')
s=s.replace('    `Generation: ${envelope.decisionGeneration}`,', '    `Generation: ${envelope.decisionGeneration}`,\n    `Snapshot generation: ${envelope.authoritativeSnapshotGeneration}`,')
p.write_text(s,encoding='utf-8')
print('patched contract')