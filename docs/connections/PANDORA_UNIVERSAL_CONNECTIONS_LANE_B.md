# Pandora Universal Connections â Lane B

## Scope

Lane B implements P1/P2 provider definitions as data-driven Provider SDK manifests plus generic adapter metadata and partner-activation contracts. It does not add provider-specific screens and does not own the Connection Manifest schema, OAuth/PKCE broker, Vault broker, Live Connections persistence, or health monitoring.

## Runtime boundary

Every manifest uses the existing Pandora Provider SDK boundary. Its metadata is shaped for Lane A's pending Connection Manifest contract, but this sheet-only package does not import or duplicate Lane A source. Adapters receive only normalized requests and a trusted transport/evidence context. They cannot read Vault or enterprise databases directly. Credentials are represented only by opaque server-side references.

Catalog presence and a valid manifest do not mean connected. The manifests explicitly require fresh account identity, scope, and safe-probe evidence, while the Live Connections runtime remains the sole connection-status authority.

Pandora `organization_id` is the canonical external-client `tenantId`. The canonical catalog requires the exact trusted `tenantId + connectionId + tenantKey` tuple for OAuth state, Vault references, account selection, health evidence, and provider actions. Missing or mismatched trusted runtime evidence fails closed. Credentials cannot cross organizations or reach browser/mobile devices.

## Generic self-service manifests

- Communications: Twilio, Vonage.
- Payments and commerce: Maya, Shopify, WooCommerce.
- Finance: Xero, QuickBooks Online.
- Marketing: Google Ads, Voluum.
- Logistics: Grab, Lalamove.
- Documents and location: DocuSign, Google Maps / Places / Routes.
- Cloud: AWS, Google Cloud, Microsoft Azure. Workload identity is preferred; long-lived keys are not allowed by default.
- Identity and devices: enterprise IdP OIDC/SAML + SCIM, device pairing / QR.
- Intelligence: local / on-device AI.
- Long tail: custom OpenAPI, MCP, and file/SFTP/email ingestion. Unknown operations are sandboxed, classified, and read-only first.

All write capabilities require a distinct step-up scope, step-up approval, exact target preview, idempotency, and provider readback. Event providers require signed webhooks, timestamp windows, replay defense, and idempotency. The manifest scope names are the normalized Pandora permission boundary; each credential onboarding must map them to the provider's current upstream scopes and retain exact provider scope readback.

## Request activation providers

The following providers expose only the generic `Request activation` action: PLDT Enterprise, Smart, Globe Telecom, DITO, Ubivelox Philippines, and government/regulated systems. Their manifests set `publicConnectAllowed` to false.

The activation state machine collects only business onboarding metadata and requires the exact tenant tuple on creation and every transition. It rejects unexpected fields so credentials cannot be supplied in the case payload. A provider-verification transition also requires its opaque Vault reference to match the trusted tenant-bound runtime reference. Authority evidence and a provider contract are required before onboarding; an opaque Vault credential reference is required before provider verification; and account, scope, safe-probe, and provider-readback evidence are required before handoff to Live Connections. Even the terminal handoff state remains `not_connected`; only the authoritative runtime may publish a connected state.

## Activation and escalation

Self-service providers remain implemented-awaiting-credential until their developer application, sandbox, OAuth client, API project, enterprise tenant, or provider credential exists and a provider readback passes. Partner-only and regulated providers remain Request activation until contractual and authority evidence exists. Provider rejection, missing jurisdiction eligibility, ambiguous target identity, broad-only credentials, or unverifiable health must fail closed.

