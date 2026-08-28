
# Pandora Project Runtime v1

Status: implemented runtime-contract foundation. Provider execution convergence and live-provider proofs remain subsequent Worker F milestones.

## Ownership

Worker F owns provider-facing runtime execution and provider truth. Worker C authorizes runtime operations, Worker D supplies immutable build artifacts, and Worker E independently verifies runtime outcomes. Provider `READY` never means `VERIFIED`.

## Exact runtime request

The provider-independent contract requires exact `organizationId`, `projectId`, `projectVersionId`, artifact SHA-256, immutable source commit, environment, authorization reference, and verification reference. Production also carries an expected-current-version compare-and-set precondition. There is no `publish latest` contract.

Idempotency is derived from the exact action and immutable lineage. A different project version produces a different operation identity.

## Provider abstraction

`packages/pandora-project-runtime` defines deployment and application-database provider boundaries. Vercel and Supabase remain replaceable suppliers; provider response shapes are not upper-layer Pandora contracts.

Runtime types currently distinguish static sites, web applications, and mobile-support runtime. Native App Store / Play Store publication is not modeled as a Vercel production deployment.

## Deployment truth

Provider state normalizes to `requested`, `queued`, `building`, `ready_for_verification`, `failed`, or `cancelled`. Provider `READY` maps only to `ready_for_verification`. Non-terminal state is eligible for bounded reconciliation; terminal state is not blindly polled.

## Domain truth

Hostnames normalize to lowercase ASCII/punycode and reject schemes, paths, queries, fragments, ports, and whitespace. Readiness is decomposed into `verification_required`, `dns_required`, `tls_pending`, `routing_pending`, `ready`, or `failed`. Provider ownership acceptance alone cannot produce `ready`.

## Failure and ambiguity

Provider failures normalize to stable Pandora categories including authorization, rate limit, quota, timeout, network, conflict, not-found, invalid configuration, domain verification, build/deployment failure, provider outage, and ambiguous mutation.

Timeout/network failure after a mutation may have committed is `ambiguous_mutation`; the caller must reconcile provider truth before retrying.

## Secrets

Provider responses are redacted for structured credential fields, bearer credentials, provider tokens, service-role keys, and database connection credentials. Runtime provider credentials remain server-side and should be supplied by Worker C scoped credential leases when available.

## Customer projection

Simple Mode receives safe states such as `Preparing preview`, `Preview ready`, `Publishing`, `Domain needs setup`, `Live`, `Something needs attention`, and `Rolled back`; raw provider identifiers and errors stay out of owner-facing status.

## Existing foundation

The merged Projects runtime already provides project versions, Vercel deployment rows, domains, and a `pandora-project-runtime` Edge Function. Worker F preserves those customer-facing flows while converging provider logic behind these contracts and adding durable reconciliation, runtime resources/environments, exact promotion, domain truth, migration/recovery, rollback, webhook security, and provider proofs through bounded follow-up merges.

This file documents implemented truth only. Live Vercel, custom-domain, customer-Supabase, migration, and rollback success are not claimed by this contract milestone.
