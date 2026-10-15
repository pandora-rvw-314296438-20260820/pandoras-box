# Pandora Enterprise — Bubble.io Build Brief

Build a mobile-first premium multi-tenant business platform in Bubble. Pandora Enterprise Admin is the central control plane that creates and manages multiple business tenants. PLP Pandora Enterprise is the first tenant template for luxury hotels and resorts. Future vertical templates: Restaurants, Import–Export, Law, and Offices/General Business.

## Repository authority
- Canonical Pandora product/governance: https://github.com/pandora-rvw-314296438-20260820/pandoras-box. Its README and source policy designate it canonical and keep mbanatao/* sources historical-only. Do not recreate ProjectOS as the frontend.
- Canonical Pandora Memory: https://github.com/pandora-rvw-314296438-20260820/pandoras-box-memory. A separate Next.js service with namespace isolation and governed memory/evidence workflows; use it as an evidence/service contract reference, not a frontend bundle. Do not store customer operational records or credentials in project memory.
- PLP tenant app: https://github.com/besfeng23/Plp. React/Vite, Vercel functions, Supabase-backed booking/payment flows. Its Resort Command admin covers reservations, guests, concierge, availability and OTA/channel workflows. Connected GitHub identity is read-only on this repository. Preserve production-sensitive booking/payment services.
- Prototype phase: no live booking, payment or OTA mutations. A browser return URL is never payment proof.

## Visual direction
Match the supplied screenshots: black/near-black shell, white/soft-grey typography, restrained muted gold/bronze accent, Pandora mark/name, search, collapsible nav, Activity, Recent chats, gated System/Developer group, tenant switcher, fixed New chat/Ask Pandora composer. Mobile drawer ~75% screen width with dark overlay; desktop full sidebar. Keep PLP pages premium, quiet and resort-oriented.

## Central admin pages
Overview; Tenants (filterable directory); Create Tenant wizard; Tenant Detail; Business Products/templates; Provisioning; Plans & Entitlements; Users & Access; Integrations; Audit & Verification; Platform Settings; Activity/Ask Pandora. The central admin is above tenant workspaces, not a PLP page. Tenant creation captures name, slug, vertical, owner, plan, enabled modules, branding/theme, domain and template version. Provisioning/action status must say Demo until actually connected and verified.

## PLP hotel/resort template
Today/Overview; Stays & Reservations; Rooms & Availability; Guests/Guest Profiles; Operations (concierge, staff tasks, housekeeping readiness); Revenue (payment reconciliation view and subscription status); Experiences; Team & Access; Distribution (OTA channels, mapping, readiness, dry run, conflict review); Activity; Settings. Keep mutations in trusted existing server paths, never Bubble client workflows.

## Other vertical templates
Restaurants: reservations/waitlist, tables, orders, menu, inventory, suppliers, sales, staff, locations. Import–Export: counterparties, purchase/sales orders, shipments, documents, customs milestones, inventory, compliance, receivables/payables. Law: clients, matters, deadlines, documents, tasks, conflict-check placeholder, time entries, billing; strict matter-level access. Offices: teams, tasks, projects, assets, appointments, invoices, documents. Shared components are fine; keep tenant and vertical data/workflows isolated. Only show enabled modules for the current tenant.

## Initial Bubble data types
Tenant (name, slug, vertical, status, logo/theme, owner, plan, domain, region, created_by, template_version); TenantMembership; PlatformRole; ProductTemplate; TenantModule; ProvisioningJob; Entitlement; IntegrationConnection (non-secret metadata only); AuditEvent; Conversation; ActivityEvent. PLP objects such as Stay, Room, GuestProfile, ConciergeTask, AvailabilityBlock, PaymentRecord, ChannelConnection, ChannelMapping, SyncRun and SyncConflict start as demo or read-only placeholders until API/schema contracts are verified. Every tenant-owned record must reference a Tenant.

## Authorization and safety
Separate platform roles (platform_owner/admin/support/auditor) from tenant roles (owner/manager/staff/auditor). Platform admins manage templates, tenant catalogue and global policies. Support is scoped/audited and does not automatically access tenant business records. Tenant users see only their tenant and allowed modules. Cross-tenant support requires explicit reason, bounded access and audit event. Use Bubble Privacy Rules plus backend/server authorization; hidden UI is not security. Sensitive tenant status, entitlement, export and provisioning operations require confirmation, idempotency and audit. Never put GitHub PATs, Supabase service-role keys, PayPal secrets or OAuth tokens into Bubble client fields, page code, logs, screenshots or source files.

## Reusable elements
PandoraShell, PlatformSidebar, TenantHeader, TenantSwitcher, PageHeader, MetricTile, StatusPill, EmptyState, AskPandoraComposer, AuditRow, ProvisioningTimeline, TenantCard, TemplateCard, ConfirmActionModal. Option sets: BusinessVertical, TenantStatus, PlatformRoleType, TenantRoleType, ProvisioningState, EntitlementStatus, ModuleKey, IntegrationStatus.

## Build order and acceptance
1. Build responsive shell from screenshots.
2. Build Overview, Tenants list/detail and Create Tenant. A created demo tenant appears in list and opens.
3. Build PLP tenant shell and Today dashboard with clearly labelled sample data.
4. Add other vertical demo templates.
5. Add types, privacy rules and demo workflows.
6. Test phone/tablet/desktop, tenant switching, module gating, all primary navigation and tenant isolation.
7. Only after accepting prototype, verify exact backend contracts and connect approved read-only server-side endpoints. Add writes only after authorization, idempotency, audit, pre/post verification and rollback are defined and tested.

## Access facts
The Vault entry mbanatao_github_pat exists in the canonical Pandora Supabase project; only metadata/existence was checked, not the secret value. Connected identity can write to canonical Pandora repositories but direct GitHub connector branch writes return 403, so use the existing governed Vault-backed write route rather than bypassing it. This brief is documentation only; no Bubble app or live integration has been created.