# Pandora User Administration

## Purpose

Pandora owners and administrators can add people to one organization without exposing Supabase database or service-role credentials to a client.

The implementation follows the product rule that Simple and Professional modes may change presentation, but never permissions. Supabase Auth and organization memberships remain the source of truth.

## Live provider state

- Supabase project: `jcyqixttuebxqqfkjonq`
- Edge Function: `pandora-user-admin`
- Active function version at packaging: `2`
- Gateway JWT verification: enabled
- Active deployed bundle SHA-256: `20f0191ba4a1b7a7fd7c12ba371020edac04eeb58c2688854d87eff5e23122be`

## Client contract

Base path:

```text
/functions/v1/pandora-user-admin
```

Every request requires:

```text
Authorization: Bearer <signed-in Supabase user access token>
x-organization-id: <selected organization UUID>
```

Browser clients must also originate from the configured allowlist. Native clients do not send a browser `Origin` header.

### List organization users

```http
GET /functions/v1/pandora-user-admin/members
```

The response contains the selected organization's memberships and bounded Auth identity details needed by the Team screen.

### Add or invite a user

```http
POST /functions/v1/pandora-user-admin/invite
Content-Type: application/json

{
  "email": "person@example.com",
  "displayName": "Person Name",
  "timezone": "Asia/Manila",
  "role": "member"
}
```

Canonical roles are `owner`, `admin`, `operator`, `member`, and `viewer`.

- An active owner may grant any canonical role.
- An active administrator may grant only `operator`, `member`, or `viewer`.
- Existing confirmed Auth accounts are activated immediately.
- New or unconfirmed accounts remain `invited` until email confirmation.
- Email confirmation activates all invited organization memberships for that user.
- A duplicate request with the same role is idempotent.
- A duplicate request with a conflicting role returns a conflict instead of silently changing authority.

## Security boundary

1. The Supabase gateway validates the user JWT.
2. The Edge Function independently resolves the user and exact organization membership.
3. Only an active owner or administrator continues.
4. The service-role key exists only in the Edge Function runtime.
5. The database mutation RPC is executable only by `service_role` and rejects calls whose JWT role is not `service_role`.
6. The RPC rechecks the actor's active organization role before writing.
7. Membership writes are serialized by organization/user pair and append a redacted hash-chained audit event.
8. Emails, access tokens, refresh tokens, and service credentials are never written to the audit payload.

## UI wiring

The canonical Team screen should:

1. Load the selected organization ID and current Supabase access token from the authenticated app session.
2. Call `GET /members` on entry and after successful invitations.
3. Show name/email, role, and `invited` or `active` state.
4. Present an Add person sheet with email, optional display name, and a role picker bounded by the current user's role.
5. Treat `403` as a permission boundary, `409` as an existing/conflicting membership, `429` as bounded throttling, and `5xx` as a retryable service failure.
6. Never embed or request the Supabase service-role key.

## Validation completed against the live database

All tests used transaction-local rollback and left no persistent test user, membership, or audit record.

- owner add-user contract;
- duplicate idempotency;
- administrator role-grant restriction;
- service-role-only broker restriction;
- invited-state creation;
- email-confirmation activation;
- redacted audit-chain writes;
- post-test zero-residue verification.
