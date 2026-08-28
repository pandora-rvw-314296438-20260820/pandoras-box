# Worker B Intelligence Foundation — Live Gap Map

Audit base: `main` at `3ec9f18bc7d283a9f06aac2f23f5959f780fb9a8`.

## Reusable source truth
- Existing repository is an npm/TypeScript workspace and already treats `packages/` as the bounded location for reusable internal contracts.
- `packages/shared-security` provides the established package precedent.
- Supabase Edge Functions are existing server-side trust boundaries, but none on this base owns model-provider execution.
- Customer Projects/Vercel runtime is execution/runtime scope and is intentionally not imported into Pandora Intelligence.

## Gaps on audited base
- No provider-independent model contract or capability registry.
- No Gemini/OpenAI/provider adapter implementation.
- No canonical Intent Compiler or deterministic ProjectSpec validator under a Worker B boundary.
- No task-scoped context/memory engine or model router.
- No structured tool-proposal validation boundary or versioned intelligence prompt registry.
- No intelligence-specific credential-exclusion tests.
- Requested Worker A durable tables (`project_specs`, `project_intents`, `project_requirements`, `model_runs`, `build_jobs`, `tool_calls`, `project_memory`) were not present in either live Pandora Supabase project at audit time, so persistence remains behind an adapter until Worker A publishes its implemented contract.

## Security posture
- `Github_supabase` and `gemini_api_key` are present in the Pandora Supabase Vault project; values were not read into Worker B output or source.
- Model/provider credentials stay server-side and never enter model contracts or context payloads.
- Model outputs are proposals only. Tool names, arguments, paths, sizes, and ProjectSpec structure are validated before downstream authorization.
