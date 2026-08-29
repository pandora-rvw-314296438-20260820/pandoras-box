# Pandora PostHog live-ingestion boundary — 2026-08-29

Status: implemented server-side capture boundary; production activation remains fail-closed.

## What is implemented

Pandora lifecycle telemetry now has a concrete server-side PostHog HTTP transport. It accepts only the existing canonical `pandora_*` lifecycle envelope after pseudonymization and metadata sanitization, sends only to the allowlisted US/EU PostHog ingestion hosts, enforces a bounded payload and timeout, and never returns provider response bodies or credentials in errors.

`createPandoraPostHogTelemetryFromEnv()` binds the concrete transport to the existing lifecycle telemetry contract. Telemetry is disabled by default. Enabling it requires a PostHog project token and a separate HMAC pseudonymization key. Production additionally requires `PANDORA_POSTHOG_PRODUCTION_APPROVED=true`; the transport independently rejects production envelopes when approval is absent.

Required runtime configuration:

- `PANDORA_POSTHOG_TELEMETRY_ENABLED`
- `PANDORA_POSTHOG_PROJECT_TOKEN`
- `PANDORA_POSTHOG_PSEUDONYMIZATION_KEY`
- `PANDORA_POSTHOG_HOST` (`https://us.i.posthog.com` or `https://eu.i.posthog.com`)
- `PANDORA_POSTHOG_PRODUCTION_APPROVED`

Secrets belong behind Pandora's provider/Vault boundary and must not be committed or surfaced in logs, generated applications, owner APIs, or evidence artifacts.

## Current provider truth

The currently connected PostHog project is shared with other product telemetry and has session-replay/performance settings that do not satisfy Pandora's dedicated production analytics isolation gate. It therefore must not be treated as production Pandora business measurement truth.

Production approval remains **false**. This is intentional fail-closed behavior, not an analytics-success claim. A dedicated PostHog project (or an independently approved equivalent isolation configuration) is still required before enabling production Pandora lifecycle analytics.

## Proof rules

Transport connectivity may be proven with a development-only probe event. A probe is not a customer lifecycle event and must never be counted as intent, build, verification, deployment, conversion, revenue, ROI, or customer-outcome evidence.

Canonical lifecycle events may be emitted only when the corresponding authoritative Pandora transition really occurred. Missing canonical events remain `not_measured` / `awaiting_data` in Worker H.
