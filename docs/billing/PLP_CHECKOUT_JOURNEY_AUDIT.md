# PLP Enterprise — conversion journey audit (Order 2)
Author: checkout worker · 2026-10-10 (PHT) · base main a75a052c · branch grok/plp-conversion-checkout

Journey audited: paid-feature encounter → value → plans/prices → select → PayPal → return → verified entitlement → paid feature.
Sources: app source (plp_enterprise_shell.dart, plp_paypal_billing_screen.dart, plp_paypal_billing_api.dart, plp_resort_workspace.dart),
owner Android walkthrough (/workspace/plp-paypal/evidence/owner-walk, 2026-10-09 21:43–22:21 PHT), sparse/merged/pr994/gate2 screenshots,
nine-screen branches (PRs #1000–#1006, closed; evidence built/, concept/, storyboard/), deployed owner-api v100 source
(entry = ops/supabase/runtime-patches/pandora-owner-api-v98-plp-billing-sandbox/index.ts @33f37ef9 + paypal-billing.mjs),
live DB function definitions and Supabase logs (project jcyqixttuebxqqfkjonq, read-only queries).

## 0. Blocking server defects found (evidence, not opinion)
| # | Defect | Evidence | Impact |
|---|--------|----------|--------|
| S1 | **Live checkout always fails.** owner-api live path calls `public.pandora_plp_billing_checkout_v1`, which inserts column `created_by` into `pandora_paypal_billing_sessions` (real column: `requested_by`) and omits NOT NULL `plan_code`, `paypal_plan_id`, `return_url`, `cancel_url`; failure branches update non-existent `error_message`/`provider_reference`. | postgres_logs 2026-10-09T19:02:11Z (Oct 10 03:02 PHT): `column "created_by" of relation "pandora_paypal_billing_sessions" does not exist`. function_edge_logs: all 8 `POST /billing/paypal/checkout` in the last 24h → **400** (mapped from BILLING_REQUEST_FAILED). 0 rows in pandora_paypal_billing_sessions, 0 subscriptions. | 100% of checkouts dead-end with "PayPal didn't respond." Nobody can pay. |
| S2 | **Reconcile cannot activate.** `pandora_plp_billing_reconcile_v1` sets session `status='provider_verified'`, which violates `pandora_paypal_billing_sessions_status_check` (allowed: created, approval_pending, active, cancel_requested, cancelled, suspended, expired, failed). The whole reconcile transaction (incl. the subscription upsert) would roll back. | pg_constraint definition vs function body. | Even after S1 is fixed, a paid subscription would never unlock. |
| S3 | **No PayPal webhook receiver deployed.** The live webhook URL (`pandora_runtime_provider_configs.webhook_url` = …/pandora-owner-api/billing/paypal/webhook) hits the v98 entry, which has no webhook route → authenticate() → 401. PayPal retries then drops. The TS handler that exists in `supabase/functions/pandora-owner-api/index.ts@33f37ef9` is not what is deployed. No cron reconcile. | grep of deployed entry; 4 webhook rows only (2026-10-08 catalog events, ignored). | Activation, renewals, suspensions, cancellations made in PayPal are never learned unless the owner presses Refresh. |
| S4 | SUSPENDED / EXPIRED provider states are not handled by reconcile (only ACTIVE/CANCELLED). | function body. | A suspended (failed-payment) subscription stays "active" until manual action. |
| S5 | owner-api billing module source is not on main (only on branch grok/plp-paypal-billing-verified @33f37ef9) — parity gap; flagged to the Order 1 worker. | git branch -r --contains 33f37ef9. | Source/deploy parity. |
Fix design for S1–S4 is in this PR (migration + edge function, NOT applied/deployed) — see §6 and PR "Approval items".

## 1. Friction points (current main, sparse tiles) — in journey order
| Step | Friction / dead end | Severity | Evidence |
|------|---------------------|----------|----------|
| Encounter | Locked workspace tap jumps straight to a page titled BILLING; nothing says *what* is locked or *why* paying helps. | High | owner-walk 07_stays_tap.png |
| Encounter | Today: lock glyph is a 14px muted icon; the 4th workspace card is clipped at the screen edge (horizontal rail with fixed 116px tiles). | Medium | 04_after_signin.png |
| Encounter | Locked PLP assistant launcher looks identical to the unlocked one (logo at .72 opacity on black; only a tiny lock) — "locked logo not dimmed". | Medium | 04, 07, 09 |
| Encounter | Today leads with a long "Resort Source · Stale" card (two paragraphs + two buttons) above the workspaces; the unlock line competes with it. | Medium | 04_after_signin.png |
| Load | **Billing shows "Couldn't load." on first open**; Retry works. Server never received the first request (no log at 14:15Z; retry logged 14:15:57Z = 200) → client transport failure, and the screen re-fetches status the gate already had. Status latency 0.85–5.3 s. | High | 07_stays_tap.png + function_edge_logs |
| Value | No value statement at all: tiles "Launch / USD 49 / month" and "Professional / USD 149 / month" without what either includes, which to choose, or that both unlock the same PLP workspaces. | High | 08/09 |
| Terms | No renewal / recurring / cancellation terms anywhere before PayPal. | High (trust/compliance) | 09_launch_selected.png |
| Select | Selecting a plan opens a second screen with only "Pay with PayPal" + "Back" — an extra tap that adds no information. | Medium | 09 |
| Handoff | Nothing explains that PayPal opens in another app/tab, that the owner approves there, and comes back. | High | 09 |
| Checkout | Every checkout fails server-side (S1) and the client shows the generic "PayPal didn't respond." with no next step. | Blocker | logs |
| Return | **No `#/enterprise/paypal-return` / `#/enterprise/paypal-cancel` route**: PayPal returns land on Today; the owner must find Billing again and press Refresh. Android returns to a web page (mcpmaster) and the app does nothing on resume. | High | plpPaypalReturnUrls + no route |
| Verify | Activation requires a manual Refresh (S3 means no webhook). "Finish in PayPal · not active yet" is the only pending copy. | High | sparse-final/02-waiting.png |
| After | After activation the owner stays on Billing; the Stays page they originally wanted is never reopened. | Medium | shell _setGate |
| Fail/cancel | Cancelled-in-PayPal and failed checkouts are indistinguishable from "waiting"; no "try again" path other than Retry tile. | Medium | source |
| Analytics | No funnel events exist for billing; OwnerAnalytics (PostHog) is compiled out unless PANDORA_POSTHOG_HOST/KEY are defined — no build defines them. | Medium | rg PANDORA_POSTHOG |

## 2. Candidate comparison
| Criterion | A. Sparse tiles (main #995) | B. Nine-screen editorial (#1000–#1006) | C. Chosen: value-first unlock (2 screens + PayPal + confirm) |
|---|---|---|---|
| Screens before PayPal | 2 (plans → select) | 4–5 (entry → status → plans → plan diff → handoff curtain) | 2 (landing → review) |
| Taps locked-feature → PayPal | 3 (feature, plan, Pay) | 5–6 | 3 (feature, Continue, Continue to PayPal) — recommended plan preselected |
| Value explained before price | No | No (status/renewal first) | Yes — what unlocks, incl. the feature they tapped |
| Recurring + cancel terms | No | Partly ("Billed monthly through PayPal") | Yes, on landing (1 line) and review (full) |
| Recommended plan | No | No | Yes, with evidence-based reason |
| PayPal handoff explained | No | Yes (dark curtain, good) | Yes (review step, reuses the curtain idea in PLP style) |
| Return / confirm | Manual (no route) | "Confirming with PayPal" screen (good) | Return route + resume + auto-verify with bounded polling |
| Back to intended feature | No | No | Yes, after server-verified activation |
| Identity | PLP cream/serif tiles ✔ but sparse | Roboto display type, divider lines, slider — off-brand per owner rules | PLP cream, serif tracked titles, thin warm borders, bronze outline icons |
| Management (active) | 4 tiles ✔ concise | rich but long | Keep A's active management tiles (they are fine), polish copy |
Decision: **C**. Keep from A: PLP page frame, management tiles, single unlock rule, idempotency, return URL allowlist. Keep from B: the PayPal-handoff explanation and the "Confirming with PayPal" state. Drop from B: status hero before value, plan slider, divider lines, 9-screen length. Net: the unpaid owner goes locked feature → 1 value landing → 1 review → PayPal → auto-confirm → back in the feature.

## 3. Recommended plan — evidence
`pandora_service_plans` (live): Launch USD 49/mo — core AI, 1,000 assistant requests & 1M tokens/mo, standard support. Professional USD 149/mo — 5,000 requests & 5M tokens/mo, priority support, plus Pandora developer/auditor mode & advanced build workflows (Pandora-core features, not PLP workspaces).
The PLP gate is binary: ANY active, PayPal-verified subscription unlocks every PLP workspace and the assistant (pandora_plp_entitlement_v1). Therefore **Launch is recommended** for a single resort ("Unlocks everything in PLP"); Professional is presented as "more assistant capacity + priority support". No fabricated badges, urgency, or testimonials.

## 4. Terms shown (true to the current system)
- "USD 49 per month, billed by PayPal. Renews monthly until you cancel." (PayPal plan is a monthly regular cycle.)
- "Cancel anytime in Billing — no further charges. Access ends when the cancellation is confirmed." (reconcile sets ends_on=current_date on CANCELLED; entitlement requires state=active.) Product decision proposed: keep access until the paid period ends (approval item).
- "PayPal opens to approve. Come back here — PLP unlocks only after PayPal confirms."

## 5. Known defects → disposition in this PR
| Defect | Fix |
|---|---|
| Billing "Couldn't load." first open | Shell seeds the screen with the status it already read; initial load retries transient failures (timeout/transport/5xx) with backoff before showing an error; request timeout 15 s. |
| No #/enterprise/paypal-return route | Web: shell parses the return/cancel fragment at start, opens the confirm state; Android: confirm on app resume while a handoff is open. |
| Locked logo not dimmed | Locked launcher rendered greyscale at reduced opacity with lock badge. |
| Clipped 4th card | Today workspaces render as a wrapping 3-column grid (all visible, none clipped). |
| Wordy Resort Source card | One status line + one action; long explanation removed. |
