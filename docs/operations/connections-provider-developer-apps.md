# Pandora provider developer-app register

Snapshot: 2026-10-01. Owner signup contact: `markjohnsonbanatao888@gmail.com`.

This register covers external-client distribution. `Configured` means only that a matching server-side configuration reference exists in production Vault; it does not prove provider review, production approval, or a working client authorization. Review state is `NOT VERIFIED` unless an exact provider-dashboard or provider-API readback proves it.

## Mandatory tenant boundary

Pandora `organization_id` is the canonical client `tenant_id`. Every OAuth state, provider account, active account selection, Vault secret reference, health probe, and write approval is bound to that value. Provider account `tenant_key` and `connection_id` are also explicit. Runtime credential access requires the exact active `(tenant_id, provider, connection_id, tenant_key)` tuple; a mismatch fails closed. Client roles have no table or Vault access, and no RPC or Edge response returns a credential.

## Pandora-owned developer apps required for external self-service

| Provider developer app | Required registration / external review | Current Pandora status | Athena action |
|---|---|---|---|
| Google Workspace OAuth | Google Cloud project, external OAuth consent screen, web client and Android/iOS clients. Submit brand and sensitive-scope verification for Drive metadata and Sheets read scopes before broad external use. | No planned Google OAuth client configuration found in production Vault. Registration and verification: **NOT VERIFIED**. Implementation is source-only in the Lane A PR. | Register the production project and OAuth clients; configure verified domains, privacy policy, deletion/support pages, redirect and app/universal links; submit requested scopes for verification. |
| Meta / Facebook Login for Business and Marketing API | Meta developer app, Business portfolio ownership, Facebook Login for Business configuration, App Review / Advanced Access for requested permissions, and any required business or access verification. | Matching Meta app configuration exists in Vault and an older provider activation exists, but public-client App Review, Advanced Access, business verification, and current provider health are **NOT VERIFIED**. | Read the exact Meta dashboard status; submit only the least-privilege permissions used by the external-client flow, with test instructions and screencast. |
| Shopify public app | Shopify Partner organization and public-distribution app. Public distribution across unrelated stores requires Shopify App Review; use OAuth authorization code/token exchange and mandatory webhooks. | No Shopify app configuration found in production Vault. Registration/review: **NOT VERIFIED**. | Register a public app, development store, callback URLs and webhooks; complete review before external merchant onboarding. |
| Xero OAuth app | Xero developer app with OAuth 2.0 web credentials. App Store certification is required for a listed/certified external integration and checks tenant display, connection management, token handling, scopes, disconnect and security. | No Xero app configuration found in production Vault. Registration/certification: **NOT VERIFIED**. | Register app and callback; build with a Xero demo org; submit certification when the adapter passes tenant-isolation and disconnect tests. |
| Intuit QuickBooks Online app | Intuit Developer app with sandbox and production credentials. Production credentials require the Production Key / app-assessment questionnaire approval; marketplace distribution adds applicable security, technical and content review. | No Intuit/QuickBooks app configuration found in production Vault. Registration/production approval: **NOT VERIFIED**. | Register the Accounting app and sandbox company; complete the production questionnaire after E2E readiness. |
| DocuSign eSignature integration key | Demo developer account and integration key, then Go-Live review/promotion to an eligible production account. OAuth 2.0 and clean recent API-call evidence are required for new apps. | No DocuSign app configuration found in production Vault. Registration/Go-Live: **NOT VERIFIED**. | Register demo integration key, exercise sandbox calls, then complete Go-Live review. |
| Google Ads API | Reuse the verified Google OAuth brand/client where appropriate, plus a Google Ads manager account and developer token. Production access depends on the token access level/application. | No Google Ads configuration found in production Vault. Developer-token approval: **NOT VERIFIED**. | Create/select manager account, apply for the developer token, and keep customer login/manager IDs tenant-bound. |
| Google Maps Platform | Google Cloud project with only required Maps APIs, restricted server/browser/mobile keys, billing controls, and separate environment credentials. OAuth review applies only if user-data OAuth scopes are added. | No Google Maps configuration found in production Vault. Registration/key restrictions: **NOT VERIFIED**. | Enable the minimum APIs and create platform-restricted keys; keep billable writes behind tenant-bound step-up. |
| X API | X developer project/app and the access tier required by the final read/write scopes and volume. OAuth clients and callback URLs must be registered. | No X/Twitter configuration found in production Vault. Registration/access approval: **NOT VERIFIED**. | Register after the final scope/volume decision; do not promise write access until provider approval is read back. |
| Microsoft Entra ID / Microsoft Graph / SCIM | Multi-tenant Entra app registration, verified publisher/domain, redirect URIs, least-privilege delegated/application permissions, admin-consent workflow, and SCIM enterprise-app template if distributed broadly. | No Microsoft/Entra app configuration found in production Vault. Registration/publisher verification: **NOT VERIFIED**. | Register the multi-tenant app, verify publisher/domain, and prepare an admin-consent review packet. |
| Twilio Connect / Vonage / Maya partner app | A Pandora-owned connect/partner application is needed for one-click onboarding across unrelated client accounts; signed webhook configuration and per-client subaccount/account binding remain mandatory. | No matching production Vault configuration found for Twilio, Vonage, or Maya. Partner/app approval: **NOT VERIFIED**. | Register sandbox/developer accounts, confirm each provider's external-client distribution program, then submit partner/app review where required. |

## Tenant-owned or partner-mediated registrations

These should not share a Pandora credential across clients:

- WooCommerce: each client store issues its own REST API consumer credentials or completes that store's OAuth flow.
- Voluum: each client supplies and authorizes its own account/API access.
- AWS, GCP and Azure workload identity: create customer-specific trust/federation bindings; never use one long-lived Pandora cloud key across tenants.
- Enterprise OIDC/SAML and SCIM: each client IdP creates its own enterprise application/metadata and tenant-scoped signing or provisioning secret.
- Grab and Lalamove: customer/partner credentials and commercial onboarding are tenant-specific; show `Request activation` until the provider confirms an approved program.
- Custom OpenAPI, MCP, SFTP and email ingestion: no global provider app is assumed. Each connector is sandboxed and each credential is stored under the client tenant.
- PLDT, Smart, Globe, DITO, Ubivelox and government/regulated systems remain `Request activation` only.

## Provider references

- Google OAuth verification: https://support.google.com/cloud/answer/13463073
- Meta App Review: https://developers.facebook.com/docs/app-review/
- Shopify distribution and review: https://shopify.dev/docs/apps/launch/distribution
- Xero certification checkpoints: https://developer.xero.com/documentation/xero-app-store/app-partner-guides/certification-checkpoints/
- QuickBooks production credentials: https://developer.intuit.com/app/developer/qbo/docs/get-started/get-client-id-and-client-secret
- DocuSign Go-Live: https://www.docusign.com/blog/developers/the-trenches-go-live-failures
- Google Ads developer token: https://developers.google.com/google-ads/api/docs/api-policy/developer-token
