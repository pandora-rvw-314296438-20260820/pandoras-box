# Pandora Owner API v101 — PayPal webhook source

Immutable source artifact for the PayPal webhook ingress correction. This folder is not itself a production deployment.

- Only `POST /billing/paypal/webhook` bypasses Pandora owner-session authentication; all other routes retain the existing authentication and rate-limit behavior.
- The raw UTF-8 request body is streamed with a strict 131,072-byte cap.
- Only the five PayPal signature-verification headers are forwarded.
- `public.pandora_plp_paypal_webhook_ingest_v1` verifies the signature before idempotent ingestion.
- Invalid signature/payload gets a 4xx response; verifier, RPC and processing failures get 503 to preserve provider retries.
- This PR changes no live billing state. Do not deploy until the pinned deployment shim, independent review, CI and runtime readback are complete.
- Manifest hashes are generated from the exact UTF-8 file content; the subsequent shim must use this source commit's immutable SHA.
