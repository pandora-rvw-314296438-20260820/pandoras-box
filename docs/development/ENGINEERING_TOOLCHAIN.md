# Pandora engineering toolchain

This repository pins the engineering tools used to verify Pandora changes. Provider credentials and CLI login state are never committed.

## Project-scoped tools

The root devDependencies pin:

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

## CI-only security and workflow tools

The engineering toolchain workflow also installs or verifies:

- GitHub CLI
- actionlint
- ShellCheck
- Gitleaks
- Trivy

Gitleaks and Trivy run without provider credentials. Supabase, Vercel, PostHog, and GitHub authentication remain outside source control and must use the approved runtime/Vault boundary when authentication is needed.

## Adoption boundary

Biome and Knip are introduced without mass rewriting or deleting existing Pandora code. Knip is report-oriented until existing dynamic entry points are fully classified. Playwright begins with a deterministic browser-launch smoke test; product journey coverage should be expanded separately so tooling installation does not silently change Pandora behavior.
