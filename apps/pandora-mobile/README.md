# Pandora Mobile

Pandora Mobile is the authenticated Flutter owner and admin control surface for
Pandora / MCPMaster. Its canonical source is `banataosystems/Pandoras-box`.

## Runtime boundary

- Authentication and owner data use Supabase project
  `jcyqixttuebxqqfkjonq`.
- The only owner API base is the Supabase `pandora-owner-api` Edge Function.
- There is no fallback host. Reads and writes fail closed when that contract is
  unavailable.
- The app embeds only the public Supabase publishable key. Service-role keys,
  provider tokens, private identity material, and worker credentials are never
  mobile configuration.

Authentication uses the current Supabase user session JWT. Organization context
uses the canonical organization ID by default and may be overridden only for an
authorized environment with `PANDORA_ORGANIZATION_ID`.

## Exact-source verification

The protected `verify-exact-source` action has a dedicated mobile contract. It
always supplies:

- a required ProjectOS `projectId`;
- an exact 40-character hexadecimal commit `exactSha`;
- either `node_regression` or `supabase_migration_replay` as `jobClass`; and
- an optional `maxRuntimeSeconds` bounded to 30–1800 seconds.

The client submits this write once with an idempotency key. A timeout, HTTP 5xx,
unreadable success response, or other ambiguous result locks the form and sends
the owner to Activity; the app does not retry the write or claim execution.
Server-side authorization, plan approval, worker dispatch, evidence review, and
final verification remain authoritative.

Other supported surfaces are `GET /home`, `/projects`, `/projects/:id`,
`/connections`, `/approvals`, `/activity`, `/safety`, and `/actions`; plus
`POST /ask`, `/actions/:id/run`, and `/approvals/:id/decide`. Approval decisions
record `approve` or `reject`; they do not directly execute protected work.

## Verification build

`.github/workflows/pandora-mobile-integration.yml` is the single mobile gate. It
has read-only repository permission, checks out the exact candidate SHA, uses
pinned Flutter 3.47.0, enforces the lockfile, formats, analyzes, runs all tests
and committed golden comparisons, builds Web and a debug-signed Android APK,
checks package identity and sensitive permissions, then writes an artifact
manifest bound to that source SHA and tree.

The artifacts are validation candidates, not production releases. Their
manifest explicitly records physical-device, Wi-Fi, mobile-data, authenticated
journey, and rollback verification as false. Those gates can become true only
after a real Android device completes both network journeys against the intended
deployed backend and the evidence is read back.

For a local package checkout with Flutter 3.47.0 available:

```text
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
```
