# Pandora engineering toolchain

This repository pins the engineering tools used to verify Pandora changes. Provider credentials and CLI login state are never committed.

## Project-scoped tools

The isolated `tooling/` package pins:

- MCP Inspector
- Playwright Test
- Biome
- Supabase CLI
- Vercel CLI
- Knip
- PostHog CLI

Use:

- `npm run tooling:verify` to verify the installed toolchain.
- `npm run mcp:inspect` to prove the local read-only MCP server can initialize and list tools.
- `npm run test:e2e:smoke` for the deterministic Chromium smoke test.
- `npm run quality:biome` for the scoped Biome gate.
- `npm run quality:dead-code` for Knip reporting.
- `npm run supabase:version`, `npm run vercel:version`, and `npm run posthog:version` for provider CLI verification.
- `npm run posthog:contract` for Pandora's metadata-only PostHog privacy and transport contract.
- `npm run supabase:contract` for Supabase syntax, hardening, frozen Edge typing, migration replay, and pinned CLI verification.
- `npm run tooling:audit` for high-severity vulnerability checks inside the isolated `tooling/` dependency graph.
- `npm run providers:contract` to run the PostHog contract, Supabase contract, and isolated tooling audit together.

## CI-only security and workflow tools

The engineering toolchain workflow also installs or verifies:

- GitHub CLI
- actionlint
- ShellCheck
- Gitleaks
- Trivy

Gitleaks and Trivy run without provider credentials. The PostHog contract uses test-only fake tokens and mocked ingestion; the Supabase contract validates repository/configuration behavior without performing provider mutations. Supabase, Vercel, PostHog, and GitHub authentication remain outside source control and must use the approved runtime/Vault boundary when authentication is needed.

## Adoption boundary

Biome and Knip are introduced without mass rewriting or deleting existing Pandora code. Knip is report-oriented until existing dynamic entry points are fully classified. Playwright begins with a deterministic browser-launch smoke test; product journey coverage should be expanded separately so tooling installation does not silently change Pandora behavior.

Provider contract CI is deliberately non-mutating. It proves Pandora's PostHog privacy boundary and Supabase repository authority, but it does not enable production telemetry, write analytics events, deploy Edge Functions, alter migrations, or copy credentials into GitHub.
