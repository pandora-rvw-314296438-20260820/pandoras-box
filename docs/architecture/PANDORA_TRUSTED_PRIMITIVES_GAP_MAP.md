# Pandora Trusted Primitives — Live Reusability Gap Map

Baseline: `main@3ec9f18bc7d283a9f06aac2f23f5959f780fb9a8` (2026-08-28).

## Existing reusable foundations

- Security: `packages/shared-security` plus runtime policy/redaction modules. Reuse; do not fork Worker C policy.
- Pandora auth UI/client: mobile auth gate/sign-in exists, but it is Pandora-product code, not a generated-customer-app primitive.
- Provider auth: Meta MCP bearer/membership code is provider runtime, useful as a pattern but not vendorable customer auth.
- Project runtime: `supabase/functions/pandora-project-runtime` and its ledger are Worker F territory. Primitives declare requirements only.
- User administration: Pandora user-admin API/Edge Function is Control Plane administration and must never become generic generated-app admin.
- Analytics: Pandora owner analytics/PostHog integration exists, but generated-app business events need isolated project/version credentials and attribution.
- Audit/governance: ProjectOS lineage exists and must stay isolated from customer-application audit.
- Supabase migrations/RLS: hardened patterns exist; generated-app primitive migrations need separate namespaces and runtime-target guards.
- Test infrastructure: Node tests, PGlite replay and worker isolation are reusable proof patterns.

## Gaps on baseline main

1. No canonical primitive registry/capability lookup.
2. No exact-version composition manifest for customer project lineage.
3. No primitive compatibility or bounded configuration contract.
4. No authoritative rule preventing Worker I self-certification.
5. No generated-app primitive boundary separating customer modules from Pandora Control Plane auth/admin/audit.
6. No reusable customer-app implementations for Auth/RBAC/Booking/Commerce/Notifications/Analytics/CRM/Forms/Files/Search/Content/Scheduling/Settings.
7. No primitive upgrade/deprecation/customization lineage or supply-chain digest contract.
8. Worker B had no registry API and otherwise would need source inspection.

## Convergence order

1. Registry/contracts/composition/versioning/trust gate.
2. Auth + backend RBAC + security/RLS fixtures.
3. Audit + Admin.
4. Notifications + Analytics.
5. Booking concurrency/timezone proof.
6. Commerce + payments money/inventory/webhook safety.
7. CRM + Forms + Files/Search/Content/Profile/Settings.
8. Upgrade/deprecation/source-lineage engine and composed application fixtures.

A family listed in the registry is not implemented or TRUSTED merely because its contract exists.
