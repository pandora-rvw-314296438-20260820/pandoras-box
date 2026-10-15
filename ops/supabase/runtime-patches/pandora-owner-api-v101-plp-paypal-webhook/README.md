# Pandora Owner API v101 — PayPal webhook deployment shim

Candidate deployment bundle for Supabase Edge Function `pandora-owner-api`. This PR does not deploy.

Required order: review and merge source artifact PR #1013 using a merge commit so immutable source commit `8e53712b2f12a64de03c2b30bbd4f0f8a2943c98` remains available; independently review and merge this shim PR; then deploy exactly these files as `pandora-owner-api` with `index.ts` as entrypoint and `deno.json` as import map. Keep `verify_jwt=false` because the source implements owner authentication and verifies webhook transmission signatures through the database.

The source index SHA-256 is `dc472ac017c87c8e669fcd6b408af7616c8b72c1c093f3c52c31c879eaca9224` (source PR #1013). Live PayPal Client ID/Secret pairing and `paypal_webhook_id` remain separate secure configuration checks. Do not release without independent review, green CI, and exact deployed source readback.
