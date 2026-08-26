# Pandora Team and User Management

## Product surface

The owner-facing **More → Team** screen is the canonical mobile entry point for organization user administration.

It provides active and invited member counts, organization selection, member name/email/role/status, role-aware invitations, loading and failure states, pull-to-refresh, and post-invitation readback.

## Runtime contract

The mobile gateway invokes the JWT-protected `pandora-user-admin` Supabase Edge Function with the current signed-in user token and an `x-organization-id` header.

- `GET /functions/v1/pandora-user-admin/members` lists organization members.
- `POST /functions/v1/pandora-user-admin/invite` creates or finds the Auth account, sends an invitation when needed, and creates the governed membership.

The APK never receives the Supabase service-role key. The Edge Function validates the caller as an active owner or administrator and invokes the service-only membership broker. Owners can grant elevated roles; administrators cannot grant owner or administrator authority.

## Canonical environment

- Supabase project: `jcyqixttuebxqqfkjonq`
- Organization: `2270b266-59da-4c39-bfd9-9f8d08352af0`
- Edge Function: `pandora-user-admin`

No credential belongs in Flutter source or repository documentation.
