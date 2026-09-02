"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const generator = fs.readFileSync(
  path.join(root, "supabase/functions/pandora-project-source-generator/index.ts"),
  "utf8",
);
const workerLogs = fs.readFileSync(
  path.join(root, "workers/pandora-builder/src/logs/log-records.mjs"),
  "utf8",
);

function sourceRules() {
  const match = generator.match(/const SOURCE_SECRET_RULES = \[([\s\S]*?)\] as const;/);
  assert.ok(match, "source secret rules must remain machine-readable");
  const sources = [...match[1].matchAll(/String\.raw`([^`]*)`/g)].map((row) => row[1]);
  assert.ok(sources.length >= 14, "expected the complete credential classifier");
  return sources.map((source) => new RegExp(source, "i"));
}

const patterns = sourceRules();
const lookbehindMatch = generator.match(/const SOURCE_SECRET_LOOKBEHIND_CHARS = (\d+);/);
assert.ok(lookbehindMatch);
const lookbehind = Number(lookbehindMatch[1]);

function containsSecret(value, knownSecrets = []) {
  const candidate = String(value ?? "");
  for (const secret of knownSecrets) {
    const normalized = typeof secret === "string" ? secret.trim() : "";
    if (normalized.length >= 8 && candidate.includes(normalized)) return true;
  }
  return patterns.some((pattern) => pattern.test(candidate));
}

function simulateLiveGate(chunks, knownSecrets = []) {
  let buffer = "";
  let emitted = "";
  for (const chunk of chunks) {
    const candidate = buffer + chunk;
    if (containsSecret(candidate, knownSecrets)) {
      return { blocked: true, emitted, buffer };
    }
    let publishLength = Math.max(0, candidate.length - lookbehind);
    if (publishLength > 0 && /[\uD800-\uDBFF]/.test(candidate[publishLength - 1])) {
      publishLength -= 1;
    }
    emitted += candidate.slice(0, publishLength);
    buffer = candidate.slice(publishLength);
  }
  return { blocked: false, emitted, buffer };
}

test("generated-source classifier covers provider, env, token, JWT, key and credential URL classes", () => {
  const unsafe = [
    'Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789',
    'const key = "sk-abcdefghijklmnopqrstuvwxyz0123456789";',
    'const gh = "github_pat_abcdefghijklmnopqrstuvwxyz012345";',
    'const legacyGh = "ghp_abcdefghijklmnopqrstuvwxyz012345";',
    'const gitlab = "glpat-abcdefghijklmnopqrstuvwxyz012345";',
    'SUPABASE_SECRET_KEY=sb_secret_abcdefghijklmnopqrstuvwxyz012345',
    'VERCEL_TOKEN=vercel_abcdefghijklmnopqrstuvwxyz012345',
    'GEMINI_API_KEY=AIzaabcdefghijklmnopqrstuvwxyz012345',
    'MOONSHOT_API_KEY=sk-abcdefghijklmnopqrstuvwxyz0123456789',
    'KIMI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz0123456789',
    'DATABASE_URL=postgresql://dbuser:dbpassword@example.invalid/app',
    'const jwt = "eyJabcdefghijklmno.eyJpqrstuvwxyzAB.eyJCDEFGHIJKLMNOP";',
    '-----BEGIN PRIVATE KEY-----',
    'https://dbuser:dbpassword@example.invalid/app',
    'const client_secret = "abcdefghijklmnopqrstuvwxyz012345";',
  ];
  for (const sample of unsafe) {
    assert.equal(containsSecret(sample), true, sample);
  }
});

test("generated-source classifier permits references and public configuration without credential literals", () => {
  const safe = [
    'const apiKey = process.env.GEMINI_API_KEY;',
    'const password = form.password;',
    'const token = "spacing-md";',
    'const url = "https://localhost:3000";',
    'const publicKey = "sb_publishable_abcdefghijklmnopqrstuvwxyz012345";',
    'const serviceRoleName = "SUPABASE_SERVICE_ROLE_KEY";',
  ];
  for (const sample of safe) {
    assert.equal(containsSecret(sample), false, sample);
  }
});

test("known in-memory provider secrets are rejected even when they do not match a token family", () => {
  const exact = "provider-opaque-secret-value-12345";
  assert.equal(containsSecret(`const value = "${exact}";`, [exact]), true);
  assert.equal(containsSecret('const value = "not-the-provider-secret";', [exact]), false);
});

test("cross-provider-chunk credential fragments are withheld before any credential bytes can be displayed", () => {
  const first = `${"x".repeat(5000)}\nconst header = "Authorization: Bearer abc`;
  const second = 'defghijklmnopqrstuvwxyz0123456789";';
  const result = simulateLiveGate([first, second]);
  assert.equal(result.blocked, true);
  assert.equal(result.emitted.includes("Authorization"), false);
  assert.equal(result.emitted.includes("Bearer"), false);
  assert.equal(result.emitted.includes("abc"), false);
  assert.ok(result.emitted.length > 0, "safe prefix should remain visibly streamable");
});

test("safe withheld bytes flush losslessly at file completion", () => {
  const source = `${"const x = 1;\n".repeat(400)}export const ready = true;\n`;
  const chunks = [source.slice(0, 3000), source.slice(3000)];
  const result = simulateLiveGate(chunks);
  assert.equal(result.blocked, false);
  assert.equal(result.emitted + result.buffer, source);
  assert.equal(containsSecret(result.buffer), false);
});

test("runtime gate scans before code_chunk emission and final source remains protected", () => {
  const scan = generator.indexOf("if (sourceContainsSecret(candidateLiveSource, state.knownSecrets))");
  const emit = generator.indexOf("await emitLiveSource(admin, state, path, safeLiveSource);");
  assert.ok(scan >= 0 && emit > scan, "secret scan must precede live emission");
  assert.ok(generator.includes("await emitLiveSource(admin, state, path, state.liveDisplayBuffer);"));
  assert.ok(generator.includes("knownSecrets: [SUPABASE_SERVICE_ROLE_KEY].filter"));
  assert.ok(generator.includes("state.knownSecrets.push(providerCredential)"));
  assert.equal(generator.includes("rollingSecretWindow"), false);
  assert.equal((generator.match(/sourceContainsSecret\(content, \[SUPABASE_SERVICE_ROLE_KEY\]\)/g) || []).length, 3);
  assert.equal((generator.match(/sourceContainsSecret\(raw, \[SUPABASE_SERVICE_ROLE_KEY\]\)/g) || []).length, 1);
});

test("worker stdout and stderr keep bounded redaction semantics instead of whole-command rejection", () => {
  assert.ok(workerLogs.includes("const redacted = redactText(text, secrets);"));
  assert.ok(workerLogs.includes("for (const chunk of splitUtf8Bounded(redacted, maxChunkBytes))"));
  assert.ok(workerLogs.includes("[REDACTED]"));
  assert.ok(workerLogs.includes("createCustomerOutputChunks"));
});
