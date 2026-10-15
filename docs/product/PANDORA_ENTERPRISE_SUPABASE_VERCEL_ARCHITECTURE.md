# Pandora Enterprise — Supabase + Vercel Architecture

## Responsibilities

- **Bubble.io:** responsive UI, navigation, dashboards, forms, tenant switcher and prototype workflows.
- **Supabase:** authoritative control-plane data, authentication, PostgreSQL, RLS and approved asset storage.
- **Vercel:** server-side API/integration runtime that validates identity, roles and tenant scope, calls approved services, records audit events, handles webhooks and returns safe JSON to Bubble.

Flow: `User → Bubble → Vercel API → Supabase or approved product API → verification + audit → Bubble`.

## Separate data planes

**Pandora Enterprise control plane:** tenant registry, tenant memberships/roles, product templates and versions, enabled modules, entitlements, provisioning jobs, integration metadata, platform settings and audit records.

**Recommendation:** use a dedicated Supabase project for the new Pandora Enterprise control plane. Confirm organization, region and cost before creating it. Until then, keep the Bubble prototype on labelled demo data. Do not add new production tables to the existing Pandora core or Memory projects just to start the UI.

**PLP operational plane:** the existing PLP app and its current Supabase/Vercel booking/payment services remain the authority for stays and verified payments. Verify the actual project, schema and API contracts before integrating; do not guess a project ref, migrate data or reimplement PayPal/deposit verification in Bubble. Start read-only.

**Pandora Memory:** `pandoras-box-memory` remains the separate governed project-memory/evidence service, not storage for hotel guests, restaurant orders, trade data or legal matters.

**Future verticals:** shared tenant-scoped tables may use strict RLS where appropriate; high-sensitivity customers or legal matters may require separate data projects. Do not assume all verticals should share one database.

## Vercel API

Create a separate `pandora-enterprise-api` project once the API source and contracts exist. Do not repurpose or relink existing `mcpmaster` or PLP production deployments.

Start with:
- `GET /api/health` — safe readiness only.
- `GET /api/me` — validated identity and roles.
- `GET /api/tenants`, `GET /api/tenants/:tenantId`.
- `GET /api/product-templates`.
- `GET /api/tenants/:tenantId/modules`.
- `GET /api/tenants/:tenantId/activity`.
- `GET /api/provisioning/:jobId`.
- `GET /api/integrations/status` — non-secret metadata only.
- `POST /api/tenants` — later, after server-side role checks, idempotency and audit exist.
- `/api/plp/*` — later, narrow read adapters after verifying PLP's existing contracts.

Creating a tenant record does not mean an external Supabase project, Vercel deployment, domain or operational database was created. Provisioning must record actual per-step states, verified outcomes, idempotency, retry and recovery behavior.

## Supabase security

- Use one source of identity for the control plane; recommended Supabase Auth, not a second password store in Bubble.
- Every tenant-owned row references its tenant. Enforce membership/role checks in Vercel and Supabase RLS.
- Enable RLS and least-privilege SQL grants on every exposed tenant-owned table. Test that tenant A cannot read or mutate tenant B.
- Separate platform roles (`platform_owner`, `platform_admin`, `platform_support`, `platform_auditor`) from tenant roles (`tenant_owner`, `tenant_manager`, `tenant_staff`, `tenant_auditor`).
- Support has no automatic tenant-data access. Cross-tenant support requires a recorded reason, narrow scope/expiry and audit event.
- Service-role/secret keys stay in Vercel server-only environment variables. Never put them in Bubble workflows, custom states, URLs, browser logs or source control.
- Store only secret references and non-secret integration metadata. Redact provider errors; include safe correlation IDs.
- The Vault-backed `mbanatao_github_pat` belongs to the governed internal GitHub write path, not Bubble.

## Bubble API Connector

1. Define an API group for the Vercel Pandora Enterprise API; add a separate PLP read group only after approved.
2. Keep Development/Preview/Production base URLs separate.
3. Initialize GET/read-only calls first; Bubble API initialization can execute a call, so never initialize real production writes/deletes/payments.
4. Every endpoint validates the caller, tenant membership, role and requested operation. A static key is not user-level authorization.
5. Use stable JSON responses, clear HTTP errors, pagination and correlation IDs.
6. Do not implement writes until authorization, idempotency, audit, pre/post verification and rollback are defined and tested.

## Environment values

Use Vercel environment settings, separated by environment. Variable *names* may include `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or current publishable-key equivalent), server-only `SUPABASE_SERVICE_ROLE_KEY` (or current secret-key equivalent) and `PLP_API_BASE_URL`. Names only—never commit actual values.

## Delivery order

1. Build Bubble with mock data.
2. Confirm organization/region/cost and create isolated non-production Supabase control-plane project.
3. Add reviewed tenant/membership/template/entitlement/provisioning/audit migrations; implement and test RLS and tenant A/B isolation.
4. Build the separate Vercel API and deploy to Preview; start with health, identity, tenants/templates read routes.
5. Connect Bubble Development to Preview; test auth, switching, roles, module gating, errors and isolation.
6. Verify actual PLP Vercel/Supabase bindings and API contracts; connect read-only views first and preserve booking/payment.
7. Add provisioning stepwise with durable jobs, idempotency, verified readback and recovery.
8. Promote only after security, API, responsive, source/deployment and recovery verification.

## Acceptance

Bubble is the UI; Supabase persists/control-gates tenants; Vercel validates privileged requests; no cross-tenant access; vertical template defines modules; PLP payment remains verified by its trusted server; demo activity is labelled Demo; existing deployments are not repointed or replaced.

## References
- Bubble API Connector: https://manual.bubble.io/core-resources/api/the-api-connector
- Supabase Auth: https://supabase.com/docs/guides/auth
- Supabase RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
- Vercel Functions: https://vercel.com/docs/functions
- Vercel environment variables: https://vercel.com/docs/environment-variables
