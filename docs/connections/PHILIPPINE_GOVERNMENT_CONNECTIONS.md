# Philippine government connections

This Lane B package adds Philippine government providers through Provider SDK manifests and generic adapters. It adds no provider-specific UI. Catalog presence never means connected: a safe read produces provider-readback evidence only, and the tenant-bound Live Connections runtime remains the UI status authority.

Pandora `organization_id` is the canonical external-client `tenantId`. Every probe and activation action requires an explicit `tenantId`, `connectionId`, and provider-account `tenantKey`, plus the same tuple in trusted runtime evidence. This includes the pre-onboarding Request-activation action; an external payload cannot self-assert its tenant. A missing or mismatched field fails closed. PSGC additionally requires the trusted runtime's Vault reference to equal the request's opaque reference. Credentials cannot be shared across organizations, returned in receipts, or sent to browser/mobile devices.

## Implemented public interfaces

| Provider | Interface | Safe read | Credential policy |
| --- | --- | --- | --- |
| PSA OpenSTAT | PXWeb REST | `GET /PXWeb/api/v1/en` catalog | Anonymous |
| PSA PSGC | PSGC REST | `GET /psgc/Q2_2024/regions` | PSA-issued token, injected server-side from an opaque Vault reference |
| PHIVOLCS Hazard GIS | ArcGIS REST | Ground Shaking layer metadata with `f=pjson` | Anonymous |
| NAMRIA Geoportal | OGC WMS | WMS 1.1.1 `GetCapabilities` | Anonymous |

Every safe-read adapter uses an exact allowlisted HTTPS URL, GET only, redirect refusal, a response-size ceiling, content-shape validation, a SHA-256 body digest, and no raw-body logging. A 200 response alone is insufficient. PSGC intentionally fails unless a trusted server-side transport receives a `vault://` credential reference; the token is never placed in application code or returned evidence.

Point-in-time provider evidence from October 1, 2026 is recorded in `docs/connections/evidence/PHILIPPINE_GOVERNMENT_READBACK_2026-10-01.json`. The snapshot verifies the public endpoint response shapes for OpenSTAT, PHIVOLCS, and NAMRIA. It does not assert a tenant-bound Live Connection. PSGC remains unverified because no PSA-issued token was available.

## Request activation only

Open Data Philippines/data.gov.ph, DICT eGovPH, PAGASA, BSP reference rates, PhilGEPS, BIR, SEC, LTO, SSS, PhilHealth, Pag-IBIG Fund, DFA, NBI, and PNP expose only the generic `Request activation` action. Their catalog records contain no adapter and explicitly prohibit a public Connect action.

- data.gov.ph currently serves the web application shell at legacy CKAN `/api/3/action/...` and DKAN `/data.json` paths; that is not API readback.
- DICT's eGov API portal documents APIs but requires organization registration, administrator review, and scoped credentials.
- PAGASA documents a Ten-Day Weather Forecast REST API, but an anonymous safe read returns `Missing Token`; PAGASA's August 2026 FOI response states that access is currently limited to government agencies. It therefore remains Request activation, not public Connect.
- Public webpages, PDFs, CSV downloads, dashboards, or undocumented JSON feeds are not treated as documented public APIs.

The activation request accepts business onboarding metadata only and rejects unexpected or credential-shaped fields. It remains `not_connected`; successful contracting or accreditation must still be followed by provider verification and authoritative Live Connections readback.

## Operations

- Re-run each safe read before presenting Connected; stale evidence must degrade to Needs attention.
- Do not log URL query parameters for PSGC because the upstream API requires a token in the query string. Only the credential broker may place it at dispatch time.
- On schema drift, redirects, non-200 responses, invalid content type/shape, over-size responses, or identity mismatch, fail closed and keep the provider not connected.
- Review official documentation and residency policy before enabling any non-public dataset or write capability.
