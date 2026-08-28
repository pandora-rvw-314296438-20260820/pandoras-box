# Pandora product screen master plan

Observed: 2026-08-28  
Foundation: protected `main@cc0421f4461219bd6a9e864295d70743e8cd32dc` (CI green)  
Sources: native `apps/pandora-mobile`, Control Tower owner surfaces, `docs/build/PANDORAS_BOX_FLUTTERFLOW_FULL_BUILD.md`, `docs/roadmaps/pandora-mobile-v1/01_PRODUCT_UX.md`

This is the living inventory. It does not replace the FlutterFlow full-build instruction. It records what is implemented in canonical source versus what remains.

No literal 112-page inventory exists in canonical source. The FlutterFlow full-build is a qualitative finish instruction, not a numbered page list. Native Simple Mode currently has 18 implemented owner surfaces. Do not invent missing pages to reach 112.

## Implemented on canonical native Android (Simple Mode)

Primary tabs:

1. Home (`SimpleHomeScreen`)
2. Systems (`SystemsScreen`)
3. Ask Pandora (`AskPandoraScreen`)
4. Needs You / Approvals (`ApprovalsScreen`)
5. More (`MoreScreen`)

Flows already reachable from More / Simple Mode:

6. Build / first preview / interactive preview (`build_preview_flow.dart`)
7. Business intelligence (`OwnerIntelligenceScreen`)
8. Activity
9. Verify & Safety
10. Projects list
11. Project detail
12. Connections
13. Governed command
14. Classic owner dashboard (`HomeScreen`)
15. Developer diagnostics
16. Team / user administration
17. Settings
18. Sign-in / auth gate

Proof ladder: **implemented + tested in exact-source CI**. Not production-verified.

## UI/UX convergence implemented in the current candidate

The current convergence branch now closes the source-level owner journeys that were previously listed as incomplete:

- Ask Pandora remains the canonical center destination in the newer Simple Mode IA; Home remains the owner startup context instead of reverting to the older command-first draft.
- Project filters: Needs me / Active / Blocked / Stale / Recently changed / Production verified.
- Approval detail: risk, reversibility, rollback, missing-proof labels, expiry, and locally sanitized change summary.
- Connections: Test / Connect / Reconnect / Manage / Disconnect routed through governed Ask Pandora preparation rather than direct client-side provider mutation.
- Verify & Safety four-layer Simple Mode board with no aggregate score.
- Daily briefing assembled only from returned project, approval, connection, and activity evidence.
- Read-only offline-evidence surface using bounded cache-aware repository reads; stale/cached evidence never authorizes execution.
- Responsive large-screen NavigationRail while mobile retains bottom navigation.
- Projects and Connections are promoted into owner-facing Business & history while technical diagnostics remain behind Professional Mode.

## Remaining release/parity proof, not missing owner UI

- FlutterFlow editor page parity remains a separate external-project verification lane; do not claim editor parity from native source alone.
- Official product-mark source is present in native assets; delivery derivatives still require checksum-bound packaging verification.
- Physical Android Wi-Fi and mobile-data journey receipts remain required before production verification.
- Production deployment, rollback, Supabase parity, independent review, and owner authorization remain release evidence gates.

## Next implementation slice

After this identity/recovery PR merges to green `main`, the next product PR is the Simple Mode Safety board:

- four sections: Identity & Access, Approval & Execution, Source Authority, Runtime & Secrets
- statuses: Healthy / Needs attention / Blocked / Not checked / Not applicable
- no aggregate security score
- keep professional diagnostics behind More

That slice stays on the green recovery repository, avoids production mutation, and must pass exact-head CI before any later screen PR.

## Execution rule

Each screen PR must:

- branch from current green `main`
- keep Simple Mode as the default owner path
- leave professional/technical surfaces behind More
- pass exact-head CI
- avoid production mutation
- distinguish documented / implemented / tested / deployed / production verified
