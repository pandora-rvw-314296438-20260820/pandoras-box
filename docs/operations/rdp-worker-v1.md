# Operations RDP worker v1

The Windows RDP is a first-class execution worker under the existing Operations Room lease and evidence model.

## Authority boundary

The RDP worker never becomes release, merge, spend, credential, or Memory authority. It is registered as engine `rdp` with one fixed principal and capacity one.

Initial executable profiles are deterministic machine verification only: Windows/toolchain, the canonical self-hosted GitHub runner binding, Android platform tools, and Flutter toolchain verification. Source authoring remains direct in canonical GitHub.

## Authentication

The raw worker credential remains only on the authorized RDP. Supabase Vault stores only its SHA-256 verifier. Every request is HMAC-SHA256 signed over a timestamp, UUID nonce, and body digest, then replay-fenced by the existing Operations nonce ledger.

## Execution lifecycle

RDP poll -> governed claim -> dispatch intent -> authenticated accept -> deterministic local profile -> evidence hash -> Operations handoff. Failure enters reconciliation and retains the lease. Final release verification remains independent of the RDP worker.
