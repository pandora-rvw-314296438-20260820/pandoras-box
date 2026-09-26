# Operations native scheduled wake v2

Pandora uses a two-layer scheduled wake because the canonical Vercel project is on Hobby and current Vercel limits Hobby Cron to daily scheduling.

## Primary wake

Supabase `pg_cron` runs `private.pandora_ops_emit_vercel_wake_v1()` every minute. The function reads a shared HMAC key from Supabase Vault, signs a fixed POST to `/api/operations-native-worker`, and sends only timestamp, nonce, and HMAC signature headers. The Vault secret itself is never sent in the request.

The Vercel function validates timestamp freshness and signature in constant time, obtains genuine production Vercel workload OIDC, then consumes the nonce through the fixed Supabase control bridge before any worker registration or task mutation. Replay within the freshness window therefore fails closed.

## Fallback wake

Vercel Cron calls the same fixed route once per day using Vercel's `CRON_SECRET` Authorization behavior. This cadence is intentionally daily for Hobby compatibility; it is a fallback, not the primary scheduler.

## Manual wake

POST with the existing bounded Supabase wake token remains supported. Only its SHA-256 digest reaches the fixed authorization RPC. This path exists for governed manual recovery and is not used by this chat because exporting the Vault secret into a tool request is prohibited.

## Provisioning

`private.pandora_ops_provision_vercel_wake_secrets_v1()` generates or reuses two server-side secrets, stores the HMAC key in Supabase Vault, and upserts both values directly to the fixed Vercel production project as sensitive environment variables. It returns only safe metadata.

After the exact production deployment is READY, `private.pandora_ops_enable_vercel_wake_schedule_v1()` installs the one-minute pg_cron job. Rollback first calls the matching disable function, then pauses Operations. The wake path itself never unpauses the workspace.

The fixed Pandora-native builder/release workers still require production Vercel OIDC. Independent release verification uses the Operations-native verification receipt ledger rather than creating retired ProjectOS spec/version records.
