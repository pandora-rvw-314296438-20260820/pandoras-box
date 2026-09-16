# Pandora Universal Architecture Contract v1

Status: **Frozen**  
Effective date: **2026-09-13**  
Machine contract: `docs/architecture/pandora-universal-architecture-v1.json`

## Purpose

This document freezes the neutral architecture boundary for **M0-002**. It defines how an owner request moves through Pandora without making Projects, software building, any one model provider, or any one device provider the universal control plane.

The canonical interaction is:

**You → Pandora → Pandora AI → capability router → device/cloud/models/services → Activity Theatre → verified result → Memory → learning/anticipation/optimization.**

Detailed Activity Theatre semantics, standing-authority policy, typed Memory promotion rules, model routing internals, Device Agent implementation, offline synchronization, and protected-app enforcement are owned by downstream milestones. This contract establishes the shared boundary those milestones must preserve; it does not absorb their implementation scope.

## 1. Control surface and intent

Pandora is the primary control surface. Text chat and natural-language voice enter the same runtime. Software building is one capability among many and is not the default interpretation of a general request.

Projects are optional correlation/workspace context. A project is never required merely to converse, inspect capability state, use a non-project capability, or route a request to an appropriate provider/service.

## 2. Job identity

Pandora owns universal job identity. Job identity is neutral to provider, project, device, and individual execution attempt.

A durable Pandora job is admitted when meaningful work begins. Conversation IDs and project IDs may correlate the job, but neither defines it. Execution-plan IDs, provider operation IDs, build job IDs, dispatch IDs, and device operation IDs identify attempts or sub-operations and must not be substituted for the universal Pandora job ID.

## 3. Capability and model routing

The capability router resolves what must be done before provider/model selection. Models may propose capabilities or actions, but they do not self-authorize side effects.

Selection may consider capability fit, quality, latency, reliability, cost, privacy, availability, and verified historical performance. Provider choice remains replaceable and bounded by Pandora authority.

## 4. Execution fabric

Governed execution is the default for provider-side effects. ProjectOS is the governed path for provider work, the Device Agent mediates phone capabilities, and the edge runtime owns eligible local work.

Direct provider writes are fallback-only. An ambiguous write outcome must be reconciled by provider readback before any retry. Consequential side effects require idempotency or an equivalent duplicate-side-effect guard.

## 5. Activity Theatre boundary

Activity Theatre is a Pandora-neutral runtime contract. It is not owned by a provider, project runtime, build system, or device implementation.

Public Activity Theatre output contains truthful, meaningful, interruptible execution events with durable replay identity. Build Theatre is a specialized projection of this universal event substrate; it does not define universal execution truth.

A provider/attempt reporting success does not by itself establish a completed Pandora job. Terminal Result requires a verified outcome. Public projection must never carry raw credentials, secrets, unrestricted prompts, tool arguments, or raw logs.

Detailed event taxonomy, pause/resume/control semantics, evidence-reference types, offline admission/replay semantics, and accepted-control/readback rules are frozen separately under M0-004.

## 6. Result and verification

Pandora may claim completion only after the applicable outcome is verified. Provider success alone is insufficient. When rollback is part of the action contract, rollback evidence must also be captured.

This keeps Build Theatre, Activity Theatre, provider receipts, and final user-visible result aligned to one execution truth rather than optimistic progress.

## 7. Memory handoff

Memory promotion begins after verified outcome evidence exists. Facts, patterns, policies, procedures, failures, outcomes, and provider-performance records remain distinct classes.

Inference and prediction can improve routing and anticipation, but prediction never becomes permission. New authoritative evidence supersedes stale Memory while preserving provenance/history.

## 8. Device and edge runtime

The Device Agent mediates phone capabilities and hides OEM-specific behavior behind adapters. Remote models never receive unrestricted root/device authority.

Eligible local jobs may continue offline. Pandora job/event identity must survive offline-to-cloud synchronization. Protected-app boundaries remain protected even when standing authority exists for other device actions.

## 9. Security and authority

Credentials never enter model context. Authorization scope is enforced server-side. Standing authority is bounded authority, not unlimited authority.

The universal architecture separates model reasoning from permission, provider execution from final verification, attempt identity from job identity, project context from capability eligibility, Activity Theatre truth from Build Theatre specialization, and learned prediction from authorization.

## 10. Downstream handoffs

- **M0-003** freezes standing-authority and consequential-action policy.
- **M0-004** freezes detailed universal Activity Theatre UX/event semantics on this neutral boundary.
- **M0-005** freezes typed Memory semantics and promotion rules.
- **M1** implements universal chat runtime, jobs, interruption, and reconnect.
- **M2** implements the universal Activity Theatre substrate and Build Theatre compatibility.
- **M3** implements capability/model/tool resolution and bounded fallback.
- **M4** implements Device Agent and governed phone capabilities.
- **M5** implements Memory retrieval, learning, and outcome feedback.
- **M6** implements edge runtime, offline storage/sync, and resource optimization.
- **M7** implements authority/security/protected-app controls.

## Acceptance boundary

M0-002 is accepted when the machine-readable contract, this explanatory document, and executable contract tests are reconciled against current `main`, focused/full repository checks pass, exact-head CI passes, the change is independently reviewed, merged through the governed release path (or a documented fallback if that path is unavailable), and `main` is read back independently.

Physical-device/APK behavior remains downstream release evidence under the device/acceptance milestones and is not fabricated or claimed by this architecture freeze.
