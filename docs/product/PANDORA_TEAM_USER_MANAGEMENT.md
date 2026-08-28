# Pandora Team and User Management

## Product surface

The owner-facing **More → Team** screen is the canonical mobile entry point for
organization user administration. It discovers active owner/admin memberships
from the signed-in Supabase session and never asks an ordinary owner to enter an
organization UUID.

The screen provides:

- active and invited member counts;
- organization selection when the owner manages more than one organization;
- member name, email, role, and status;
- role-aware invitations;
- loading, empty, permission-denied, degraded, retry, and success states;
- pull-to-refresh and post-invitation readback.

## Runtime contract

The mobile gateway invokes the deployed `pandora-user-admin` Supabase Edge
Function with the current user JWT and an `x-organization-id` header.

- `GET /functions/v1/pandora-user-admin` lists organization members.
- `POST /functions/v1/pandora-user-admin` creates or finds the Auth account,
  sends an invitation when needed, and creates the governed membership.

The browser or APK never receives the Supabase service-role key. The Edge
Function validates the caller as an active owner/admin and invokes the
service-only membership broker. Owners can grant elevated roles; administrators
cannot grant owner or administrator authority.

## Required environment

- Supabase project: `jcyqixttuebxqqfkjonq`
- Edge Function: `pandora-user-admin`
- Optional server secret: `PANDORA_INVITE_REDIRECT_URL`
- Optional server secret: `PANDORA_ALLOWED_ORIGINS`

No credential belongs in Flutter source, GitHub documentation, or semantic
memory.
