# Physical Android release authority

Status: **implemented but externally unconfigured; fail closed**.

The canonical Wi-Fi and mobile-data journey is not complete until an authority
outside this repository and outside the candidate Supabase runtime verifies the
physical device's enrolled Ed25519 signature and issues a one-shot JWT for the
exact receipt request. No issuer endpoint, JWT signing key, device private key,
or reusable ingest credential is stored in this repository.

The authority JWT must be accepted by Supabase JWT verification and contain:

- `role` and `aud`: `projectos_physical_android_ingest`
- `iss`: `pandora-physical-android-authority-v1`
- `purpose`: `canonical_physical_android_capture`
- exact `organization_id`, `observer_id`, `observer_key_fingerprint`,
  `request_id`, `network`, `provider_observation_index`, and `device_id_hash`
- `request_sha256`: SHA-256 of the canonical device signature basis, a literal
  `|`, and the device signature in base64
- unique `jti`, plus `iat`, `nbf`, and `exp`; lifetime is at most two minutes

The external authority must return one indistinguishable authentication failure
for unknown observer, repository scope, key mismatch, and signature failure. It
must rate-limit before expensive identity/signature work. The repository-side
gateway also applies a durable organization/purpose limit before receipt capture.

PostgREST revalidates the caller-supplied JWT. The database then checks every
claim, atomically consumes `(issuer, jti)`, binds the exact owner plan, durable
dispatch, Worker-01 result, independent reviewer proof, source/tree/deployment,
GitHub artifact and APK digests, device hash, and journey steps, and appends an
immutable receipt. Wi-Fi is observation 1; mobile data is observation 2 and must
follow it with identical bindings. A raw `service_role` call has no capture
permission and cannot satisfy release authority.

Until the external authority is provisioned and two real receipts are captured,
canonical status must report the physical Android journey as unverified.
