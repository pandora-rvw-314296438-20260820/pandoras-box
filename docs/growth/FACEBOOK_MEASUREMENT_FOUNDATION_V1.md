# Facebook measurement foundation v1

This release supplies the missing source/runtime contracts for FB-018 through FB-024 without claiming that the measurement gate has passed.

## Current provider truth

- Approved Meta ad account: `act_993057100414281` (PHP).
- Pandora first-party Pixel: `1647985900377151`, provider-read back as **Pandora's Box — First-Party Measurement**.
- Tracking campaign `pandora-meta-main` belongs to the canonical Pandora organization/project but still has no verified Meta campaign, ad-set or ad ID.
- The only live campaign observed in the approved ad account during the current readback belongs to Battalla & Associates. It must not be bound to Pandora's platform acquisition campaign.

## Implemented

- Provider-read verification for ad account, Pixel, campaign, ad set and ad hierarchy before local provider IDs can be bound.
- Durable authoritative FB-003 outcome receipts with semantic and delivery idempotency. Monetary outcomes remain integer minor units; no currency exponent is guessed.
- Projection into the existing tracking event ledger for counts only. A paid activation is not mapped to a sale; only `payment_settled` becomes a sale and `refund_settled` becomes a refund.
- Bounded Meta cost import for a verified campaign with explicit currency/timezone binding. Missing provider rows are omitted and reported, never coerced to zero.
- Consent/privacy-gated conversion match-key registration and delivery queue. Test traffic is excluded from live delivery.
- Stable event IDs, exact provider receipt handling, retry backoff and a five-attempt dead-letter boundary.
- A dedicated growth API-key issuer that cannot grant `outcome:write` until the selected D-008 privacy policy is active.

## Holds

This source creates **no** privacy authorization row. D-008 remains a human/privacy-review decision and therefore keeps server outcome intake and provider matching fail-closed after deployment.

D-002 remains zero spend. This release does not create or activate a campaign, ad set, ad, budget or paid delivery.

FB-018 remains open until a real Pandora Meta campaign/ad hierarchy is provider-read and bound. FB-019 through FB-024 remain open until authoritative outcomes, cost reconciliation, privacy-authorized conversion delivery/dedup diagnostics and one controlled end-to-end trace are actually observed.

The Pixel creation is real provider infrastructure, not proof of event delivery or business performance.
