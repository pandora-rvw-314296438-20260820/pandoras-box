# Pandora AI coding CLI toolchain

Pandora's Box supports four opt-in developer coding agents:

- OpenAI Codex CLI, installed from the official npm package `@openai/codex`.
- Anthropic Claude Code, installed from Anthropic's official native installer.
- Google Gemini CLI, installed from the official npm package `@google/gemini-cli`.
- xAI Grok Build, installed from xAI's official native installer.

## Install

From the repository root:

```bash
npm run agents:install
```

Verify an existing installation without changing it:

```bash
npm run agents:verify
```

The installer supports Linux/macOS and Windows. It downloads native installers only from `https://claude.ai/` and `https://x.ai/`, and uses npm only for the official Codex and Gemini packages.

## Authentication and secrets

Installation does not authenticate any agent and does not write provider credentials into this repository. Authenticate each CLI through its vendor-supported interactive login or an approved runtime credential path.

Repository rules remain unchanged:

- Never commit API keys, PATs, private keys, OAuth tokens, cookies, or generated auth state.
- Pandora production provider routing is separate from these developer CLIs.
- GitHub and Vercel privileged credentials remain Vault-backed.
- Gemini credentials stay in the approved secret store and must not be copied into source, GitHub metadata, logs, or client code.

## GitHub verification

`.github/workflows/ai-coding-cli-toolchain.yml` performs a real install-and-version smoke test on an ephemeral GitHub Actions runner. It requires no provider secrets because it does not run authenticated model requests.

Upstream installation sources:

- OpenAI Codex: https://developers.openai.com/codex/
- Claude Code: https://docs.claude.com/en/docs/claude-code/quickstart
- Gemini CLI: https://github.com/google-gemini/gemini-cli
- Grok Build: https://x.ai/build
