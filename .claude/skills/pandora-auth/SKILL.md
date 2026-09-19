---
name: pandora-auth
description: "Design and review authentication and authorization — RBAC, ABAC, owner/admin/operator boundaries, OAuth and OIDC, service and workload identities, session security, and privilege escalation analysis. Load when building or changing login, roles, permissions, or access control; when reviewing an authorization model; or when a privilege boundary is unclear. Enforces fail-closed authorization and server-side checks."
---

# Pandora Authentication & Authorization

Authorization defects are the most common severe vulnerability in application software, and the least likely to be caught by tests written for the happy path.

## Separate the two questions

**Authentication** — who is this? **Authorization** — what may they do?

Conflating them produces the classic bug: a system that verifies a valid session and then treats every authenticated user as equally entitled.

## Authorization principles

**Fail closed.** Unknown role, absent claim, unmatched rule, or an error during evaluation → **deny**. Never default-allow, and never let an exception in the authorization path fall through to permitted.

**Server-side, on every path.** Hiding a UI control is presentation, not access control. Every API route, every server action, every Edge Function, every database call independently enforces authorization.

**Enforce at the lowest layer.** Application-layer checks are one forgotten line from a breach. Push tenant and row scoping into the database with RLS so it cannot be omitted.

**Deny by default on resources.** New tables and new endpoints start inaccessible and are opened deliberately. The opposite ordering means every new resource is a potential exposure until someone remembers.

**Check the object, not just the action.** "May this user update bookings?" is the wrong question. "May this user update *this* booking?" is the right one. Object-level authorization failures — changing an ID in a request to reach another user's record — are the most common real-world breach.

## Choosing a model

**RBAC** — roles map to permission sets. Right for most systems. Keep roles few and meaningful; a role explosion means the model is really attribute-based.

**ABAC** — decisions from attributes of user, resource, and context. Use when access genuinely depends on relationships ("the owner of this record", "a member of this tenant", "during business hours"). More expressive, harder to audit — adopt it when RBAC is visibly failing, not preemptively.

Most real systems are RBAC plus ownership checks. That combination is usually the honest answer.

## Owner / admin / operator / service

Pandora distinguishes these deliberately, and the distinction must exist in **enforcement**, not just in naming:

- **Owner** — authorizes what nothing else may: spending, destructive actions, production release, regulated activation.
- **Admin** — operates the system within existing authorization.
- **Operator** — runs day-to-day work; no security or spending authority.
- **Service / workload identity** — machine principals with least privilege, scoped per project, never sharing a human's credential.

Test each boundary explicitly. A role that can escalate itself, grant itself permissions, or act on behalf of a higher role is a privilege-escalation defect regardless of intent.

## Service and workload identity

Machine access uses workload identity (OIDC) rather than long-lived shared secrets where the platform supports it — Pandora's own Pandora-to-Memory connection works this way. Scope every principal to the minimum, per project. Never let a service principal inherit a human's full authority. Rotate credentials, and keep the superseded one retrievable for rollback rather than deleting it immediately.

## OAuth and OIDC

Authorization Code with PKCE for user-facing flows; never the implicit flow. Validate `state` (CSRF) and `nonce` (replay). Verify token signature, issuer, audience, and expiry — **every** time, on the server. Never trust an ID token the client parsed and sent you. Request minimum scopes.

## Sessions

HttpOnly, Secure, SameSite cookies. Rotate the session identifier on privilege change, especially at login — session fixation is otherwise trivial. Absolute and idle expiry. Server-side revocation that actually works: if you cannot revoke a session before its token expires, you cannot respond to a compromise.

## Privilege escalation review

Ask specifically: can a user modify their own role or permissions · can they act as another user · does any endpoint accept a user-supplied role, tenant, or owner ID and trust it · can a lower role reach a higher role's endpoint directly · do error messages or timing reveal the existence of resources the user cannot access · can a service principal be used to bypass a user-level check.

## Testing

Authorization is not tested until **denial** is tested. For every protected path, test: each role that should succeed, each role that should be denied, an unauthenticated request, a valid user reaching another tenant's object, and an expired or tampered token.

A suite with only positive cases has verified nothing about access control.

## Output

```
MODEL         <RBAC | ABAC | hybrid> — <why>
ROLES         <role>: <permissions> · <how enforced, at which layer>
ENFORCEMENT   <layers where checks live>
FAIL MODE     <confirmed closed at each layer>
OBJECT-LEVEL  <how per-object ownership is checked>
IDENTITIES    <service/workload principals, scopes>
SESSIONS      <lifetime, rotation, revocation>
TESTS         <positive and negative coverage per role>
FINDINGS      <escalation paths, gaps>
```

## Handoff

Database enforcement → `pandora-supabase`. Independent verification → `pandora-security-review`.
Regulated access → `pandora-regulated-activation`.
