# PLP #958: reviewed golden reconciliation

Owner decision: retain the old Pandora chat and put Model / Reasoning inside its existing left cube menu. PR #954 merged that change as 81ced6e3c900b978e28b09f6b44dd7125bbc1769, but retained earlier plus/tune/model-chip screenshots.

Provider evidence: #958 workflow 37153683719, artifact 11284244218, source fb0b0dfd84d167207e471e4bfc1e81361885ac08. Archive SHA-256: b788937940864d859bfe4dfc8951645e7068ee454445804aedfb48a5b5edf686.

Pixel comparison of all six captures localized the changes to the composer. Five images differ by 350 pixels; the manual-model image differs by 3,032 pixels. Visual inspection confirms the approved cube replaces the plus/tune controls, and the separate model chip is removed. The manual-model resting composer is intentionally identical to the automatic resting composer; selection remains available in the cube menu.

Exact PNG blobs were imported and hash-checked by one-shot Actions run 37154947469, job 111296321124. That importer created blobs only and did not move branches or mutate customer data. The temporary importer workflow is removed in the reconciliation commit. Strict pixel comparisons remain enabled; no tolerances or test skips were added. This is test-fixture synchronization with an existing owner-approved change, not another chat redesign.

Production readiness is separate: passing these screenshots does not establish authenticated PLP journey acceptance, device performance, or production deployment.
