# Pandora Enterprise — GitHub App, PostHog and PayPal Integration Plan

## Architecture

Bubble is the interface. Supabase stores the authoritative tenant/configuration/entitlement records and enforces database access rules. Vercel is the server-side API and webhook boundary. GitHub App, PostHog and PayPal are provider integrations, not replacements for the control plane.

Request path: Bubble → authenticated Vercel API → Supabase or provider API → verification/audit → Bubble.

## Integration responsibilities

| Provider | Purpose | Authoritative records |
|---|---|---|
| GitHub App | Repository access, template/source automation, optional tenant-specific repository provisioning | GitHub owns repository/install state; Supabase stores non-secret installation/repository references and audit state. |
| PostHog | Product adoption, onboarding funnels, safe module-usage and aggregate tenant analytics | Analytics only. Supabase/Vercel remain authoritative for permissions, audit, provisioning and entitlements. |
| PayPal | Tenant businesses paying for Pandora plans/modules | PayPal provides payment/subscription evidence; Vercel verifies it; Supabase stores the resulting subscription state and entitlements. |

## GitHub App

- Create a separate GitHub App for tenant-level connections; do not use a tenant-provided PAT field. Tenants select the account/organization and repositories they authorize. Request minimum permissions and use short-lived installation tokens limited to approved repositories.
- Keep the existing Vault-backed `mbanatao_github_pat` exclusively inside the existing governed internal Pandora repository-writer path. Never expose it to Bubble, browser state, tenant settings or client logs. Do not change canonical source policy.
- Store only tenant ID, installation ID, repository IDs, allowed permissions, connection status, last verification and audit references in Supabase—not private keys or access tokens.
- Default to a shared multi-tenant runtime and maintained templates. Create dedicated tenant repositories/deployments only when the provisioned product or explicit isolation requirement calls for them. Repository creation is not deployment or activation; verify each step separately.
- The connected GitHub integration returned no manageable GitHub App installations during this review. Treat the App setup as planned, not live.

## PostHog

- Separate Development/Preview and Production projects.
- Use tenant/group analytics with pseudonymous tenant identifiers and coarse properties such as vertical, template version, plan tier and environment. PostHog Group Analytics supports measuring onboarding and engagement at company/account level.
- Suggested events: `tenant_created`, `template_selected`, `onboarding_started`, `onboarding_completed`, `module_enabled`, `provisioning_step_completed`, `provisioning_step_failed`, `github_installation_connected`, `integration_health_changed`, `subscription_checkout_started`, `subscription_activated`, `subscription_payment_failed`, `subscription_cancelled`, `feature_used`.
- Emit lifecycle events from Vercel only after the corresponding operation has been verified. A button click can be tracked as an attempt, not as proof of successful external work.
- Do not send guest names/emails, legal client/matter content, trade documents, payment credentials, provider secrets, raw request bodies or sensitive free-text errors. Use safe categories and pseudonymous IDs. Consider a separate project or disabled capture for high-sensitivity verticals such as law.
- PostHog does not authorize users, unlock paid modules or replace the audit ledger. Never expose personal/admin API keys in Bubble; only use a client-appropriate project token if browser capture is explicitly approved.

## PayPal tenant subscriptions

- Provide one central billing/entitlement service for businesses subscribing to Pandora plans. Supabase stores the tenant, plan, provider subscription reference, lifecycle state, billing period, last verified time and processed webhook/event reference as appropriate.
- Keep Pandora SaaS subscriptions separate from PLP guest booking/deposit payments. Isolate products/plans, references, webhook processing and reconciliation so a guest payment can never unlock a tenant subscription.
- The PLP Revenue/Billing UI may remain the tenant-facing billing experience while the subscription/entitlement authority is centralized. Preserve the approved PLP billing redesign; do not create a second conflicting state machine or double-bill the PLP pilot.
- Vercel creates/reads subscriptions and receives webhooks. Verify PayPal webhook signatures, validate the expected subscription/tenant, deduplicate/replay-protect events, write an audit record, and only then update entitlements in Supabase. Relevant lifecycle events include subscription activated, updated, cancelled, suspended, expired and payment failed.
- A browser return URL is only a handoff and never proves that a subscription is active. Keep paid modules locked until server-side API/webhook evidence verifies the subscription state.
- Keep PayPal secrets and webhook verification values in approved server-side secret storage. Do not store card/bank credentials. Validate the full lifecycle in sandbox before considering production.

## Pandora Enterprise Integrations Hub

Create separate sections for platform-owned and tenant-scoped connections. Show provider, scope, environment, authorized capabilities, state, selected repository/project references, last verified time, safe error category and audit history. Never display raw credentials. Platform administrators own global policies; tenant administrators can manage only allowed connections within their own tenant. Log connect/disconnect, permission changes, revocations and billing-plan changes.

## Suggested server routes

These are proposed contracts, not existing endpoints:

- `GET /api/integrations/status`
- `POST /api/integrations/github/install/callback`
- `POST /api/webhooks/github` — verify provider signature/secret and installation scope.
- `POST /api/webhooks/paypal` — verify signature and idempotently process valid events.
- `POST /api/billing/paypal/subscriptions` — later, authenticated and idempotent.
- `GET /api/tenants/:tenantId/entitlements`
- Optional Vercel-side PostHog event capture for verified backend lifecycle events.

Every route must authenticate the caller, validate tenant membership/role and redact unsafe errors. Bubble must not call privileged provider APIs directly.

## Build sequence

1. Build the Integrations Hub with visibly labelled Demo / Not connected cards.
2. Register and security-review the GitHub App; test install, repository selection, permission minimization and revocation.
3. Define PostHog event taxonomy, privacy review, tenant/group properties and environment separation.
4. Implement PayPal tenant subscriptions in sandbox, including duplicate/out-of-order webhook delivery, failed payment, cancellation and expiration.
5. Connect Bubble Development to authenticated Vercel Preview APIs only.
6. Test tenant A/B isolation, audit trails, entitlement gating, provider revocation and recoverable failure cases.
7. Promote only after provider readback and independent end-to-end validation.

## Bubble AI prompt stages

**Stage A — Integrations Hub:** add platform-level and tenant-level connections for GitHub App, PostHog and PayPal. Show provider, environment, scope, capabilities, status, last verification and audit. Use Demo / Not connected. Never show credentials.

**Stage B — GitHub App:** prepare a tenant-authorized GitHub App install and selected-repository flow. Do not add a raw PAT field. Keep the existing Vault-backed PAT within the governed internal writer. In demo mode, do not create real repos or deploy.

**Stage C — PostHog:** prepare a stable event taxonomy, separate environments and pseudonymous tenant/group analytics. Exclude guest PII, legal matter data, trade documents, payment credentials and sensitive free text. Analytics is not authorization, audit or billing state.

**Stage D — PayPal:** prepare the tenant subscription/billing UI and lifecycle states. Activation/entitlements are driven only by verified PayPal server-side evidence. Separate this billing from PLP guest booking/deposit payments. No real payments in demo mode.

**Stage E — Integration QA:** test permission boundaries, GitHub install revocation, analytics redaction, duplicate/out-of-order PayPal webhooks and the rule that paid modules remain locked until verified. Do not claim integrations are live without end-to-end provider readback.

## References

- GitHub Apps vs OAuth Apps: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps
- GitHub Apps API: https://docs.github.com/en/rest/apps/apps
- PostHog Group Analytics: https://posthog.com/docs/product-analytics/group-analytics
- PostHog privacy: https://posthog.com/docs/privacy
- PayPal subscription webhooks: https://developer.paypal.com/subscriptions/webhooks
- PayPal webhook verification: https://developer.paypal.com/api/rest/webhooks/rest/

Status: architecture/documentation only. This change does not install a GitHub App, create a PostHog project, configure PayPal, create Supabase/Vercel resources or alter live customer systems.