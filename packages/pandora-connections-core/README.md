# Pandora Connections Core v1

This package is the shared Phase 0 boundary for all connection lanes.

- A provider manifest declares authentication, read-first scopes, web/mobile return behavior, account and tenant identity, safe health probing, capabilities, risk class, Vault-only credential policy, and residency eligibility.
- OAuth/OIDC manifests require PKCE S256, one-time state, and nonce. Mobile authorization uses a secure custom tab and an app or universal link return.
- Credentials are represented only by opaque server-side Vault references. Provider secrets and refresh tokens never enter manifests, clients, status projections, receipts, or logs.
- `deriveConnectionStatus` is fail-closed: a stored credential alone is never Connected. Connected requires fresh provider identity and scope readback, a healthy safe-read probe, and an active organization/account binding.
- Write capabilities must declare a separate write scope and step-up approval. Connection never grants mutation authority.
- The OAuth, credential, and Live Connections broker method sets are intentionally small so provider adapters and web/mobile clients share one contract.

The existing `pandora-provider-sdk` remains the capability adapter boundary. This package governs how a provider becomes an eligible live connection before an adapter can be selected. Database migrations remain the source of truth for persisted manifests, activations, receipts, and organization-scoped policy.
