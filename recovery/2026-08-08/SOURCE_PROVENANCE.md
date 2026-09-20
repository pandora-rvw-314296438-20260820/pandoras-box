# Pandora source recovery provenance

Recovered and verified on 2026-08-08 (Asia/Manila).

## MCPMaster preserved source

- Library artifact: `mcpmaster-main (3).zip`
- Library artifact size: 1,467,203 bytes
- ZIP SHA-256: `d124682c4989617611269792a9215ed6ac2a67545dc49ecbe9bfe0b834223684`
- Embedded source commit recorded in ZIP: `3bd66aa2e3e432ff60c6ebbfad39d2f5560191f8`
- Recovered regular-file count: 597
- Deterministic recovery capsule (`tar.xz`) SHA-256: `3a4ed689e86b8ede805245e87c6781d6ac1acc3fe20ad009a64c517096a36355`

## Pandora Memory preserved source

- Library artifact: `Memory-main (4)(2).zip`
- Library artifact size: 1,085,918 bytes
- ZIP SHA-256: `b0cfc83e04798887d9e889f45a1b9c8cf0e42cc51ce7f46fb3923b3a22434f2b`
- Embedded source commit recorded in ZIP: `7d4ec6cb30edb922024cf05f043807759d1fded7`
- Recovered regular-file count: 782
- Deterministic recovery capsule (`tar.xz`) SHA-256: `458e7fa22541f103d6ed22198418d38928bba9c43006136c70534f0afdefbb13`

## Secret-safety check

A high-confidence credential-pattern scan was run over both recovered trees. Matches were limited to deliberately fake credential strings inside redaction/security tests, including example `ghp_...` and `sk-...` values. No private-key block, AWS access key, Google API key, real-looking GitHub token, or populated Supabase service-role assignment was identified by this scan.

This is an initial scan, not a substitute for a dedicated secret-scanner gate before canonical promotion or deployment.

## Provenance limitation

These artifacts are independently preserved source snapshots and are valuable disaster-recovery evidence. They predate the currently observed MCPMaster production deployment (`dpl_9iftz4UgXPUJFMzFas3DeEoxTgon`) and therefore MUST NOT be represented as exact production parity without a source/deployment comparison.

The suspended `mbanatao` GitHub account is not being used as an operational dependency for this recovery.

## Promotion gates

1. Preserve the recovered archives and their hashes.
2. Restore the complete source tree under the replacement repository.
3. Run dedicated secret scanning.
4. Verify dependency install/build/tests.
5. Compare recovered source against the latest independently recoverable deployment/source evidence.
6. Repair Vercel automation access for `/mcp` without making the whole application public.
7. Verify Pandora Memory health through the real Pandora workload identity.
8. Record exact production deployment and rollback evidence.

Until all applicable gates pass, state is **recovery in progress**, not production-complete.
