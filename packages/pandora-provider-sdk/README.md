# Pandora Provider SDK v1

This package is the adapter authoring boundary for Pandora providers.

It deliberately does **not** provide database access, Vault access, approval authority, provider selection, or cross-provider fallback. An adapter receives a normalized capability request plus a bounded runtime transport/evidence context and returns a provider receipt.

Production registration remains governed by the Universal Capability Registry and provider manifest/conformance tables. Write capabilities must declare idempotency and evidence behavior. Provider acceptance is never treated as verified completion.
