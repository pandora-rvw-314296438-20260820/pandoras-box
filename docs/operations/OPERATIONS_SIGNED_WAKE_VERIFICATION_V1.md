# Operations signed wake and native release verification v1

This release removes the need to export the Supabase wake bearer into a tool request.

The existing Vault wake seed never leaves Supabase. A deterministic HMAC key is derived from it server-side and provisioned directly into the fixed canonical Vercel project as one sensitive production environment variable. The provisioning function returns only provider/status metadata.

Supabase pg_cron emits a fixed POST to the production native worker every minute. The request contains only a timestamp, one-time nonce, and HMAC signature. The Vercel function verifies freshness/signature, resolves genuine production Vercel OIDC, and consumes the nonce through the fixed Supabase control adapter before worker registration or task mutation. Replays fail closed.

The existing manual wake bearer remains supported for governed recovery, but this workflow does not export or forward that secret.

The native release role verifies only the fixed connector canary task. It re-reads PR #741, exact check runs, the connector-delivery migration and live RPC presence, records an Operations-native independent verification receipt, then calls the existing verification acceptance path. It does not use retired ProjectOS spec/version tables and cannot verify arbitrary tasks.

The scheduler remains paused until explicit activation. Deployment acceptance requires merged exact source, both migrations installed under their canonical versions, Vercel HMAC provisioning receipt, exact production deployment readback, signed wake receipt, native worker registration/heartbeat, task handoff, release verification, and current Operations event/task readback.
