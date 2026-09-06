import { Buffer } from "node:buffer";
import { createSign } from "node:crypto";

export const PANDORA_GITHUB_APP_ID = 4785021;
export const GITHUB_API_VERSION = "2026-03-10";
export const GITHUB_API_ORIGIN = "https://api.github.com";

const MAX_PROVIDER_RESPONSE_BYTES = 256_000;
const PRIVATE_KEY_PATTERN =
  /^-----BEGIN (?:RSA )?PRIVATE KEY-----[\s\S]+-----END (?:RSA )?PRIVATE KEY-----\s*$/;

function assertInstallationId(value) {
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0) {
    throw new Error("GITHUB_APP_INSTALLATION_INVALID");
  }
  return id;
}

function assertPrivateKey(value) {
  const key = typeof value === "string" ? value.trim() : "";
  if (!PRIVATE_KEY_PATTERN.test(key)) {
    throw new Error("GITHUB_APP_PRIVATE_KEY_INVALID");
  }
  return key;
}

function jsonBase64Url(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

export function createGithubAppJwt(privateKey, nowMs = Date.now()) {
  const key = assertPrivateKey(privateKey);
  const now = Math.floor(Number(nowMs) / 1000);
  if (!Number.isSafeInteger(now) || now <= 0) {
    throw new Error("GITHUB_APP_CLOCK_INVALID");
  }

  const header = jsonBase64Url({ alg: "RS256", typ: "JWT" });
  const payload = jsonBase64Url({
    iat: now - 60,
    exp: now + 8 * 60,
    iss: PANDORA_GITHUB_APP_ID,
  });
  const signingInput = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign(key).toString("base64url");
  return `${signingInput}.${signature}`;
}

async function boundedJson(response) {
  const declared = Number(response.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_PROVIDER_RESPONSE_BYTES) {
    throw new Error("GITHUB_APP_RESPONSE_TOO_LARGE");
  }
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_PROVIDER_RESPONSE_BYTES) {
    throw new Error("GITHUB_APP_RESPONSE_TOO_LARGE");
  }
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    throw new Error("GITHUB_APP_RESPONSE_INVALID");
  }
}

function githubHeaders(token) {
  return {
    accept: "application/vnd.github+json",
    authorization: `Bearer ${token}`,
    "x-github-api-version": GITHUB_API_VERSION,
    "user-agent": "Pandora-GitHub-App/1.0",
  };
}

export async function mintGithubInstallationToken({
  privateKey,
  installationId,
  fetchFn = globalThis.fetch,
  nowMs = Date.now(),
}) {
  const id = assertInstallationId(installationId);
  const jwt = createGithubAppJwt(privateKey, nowMs);
  const response = await fetchFn(
    `${GITHUB_API_ORIGIN}/app/installations/${id}/access_tokens`,
    {
      method: "POST",
      headers: githubHeaders(jwt),
      redirect: "error",
    },
  );
  const payload = await boundedJson(response);
  if (!response.ok) throw new Error("GITHUB_APP_TOKEN_MINT_FAILED");

  const token = typeof payload.token === "string" ? payload.token.trim() : "";
  const expiresAt = typeof payload.expires_at === "string"
    ? payload.expires_at
    : "";
  if (token.length < 20 || !expiresAt || !Number.isFinite(Date.parse(expiresAt))) {
    throw new Error("GITHUB_APP_TOKEN_RESPONSE_INVALID");
  }

  return {
    token,
    expiresAt,
    permissions:
      payload.permissions && typeof payload.permissions === "object"
        ? payload.permissions
        : {},
  };
}

export async function probeGithubRepositoryWithApp({
  privateKey,
  installationId,
  repository,
  fetchFn = globalThis.fetch,
  nowMs = Date.now(),
}) {
  if (
    typeof repository !== "string" ||
    !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)
  ) {
    throw new Error("GITHUB_APP_REPOSITORY_INVALID");
  }

  const lease = await mintGithubInstallationToken({
    privateKey,
    installationId,
    fetchFn,
    nowMs,
  });
  const response = await fetchFn(
    `${GITHUB_API_ORIGIN}/repos/${repository}`,
    {
      method: "GET",
      headers: githubHeaders(lease.token),
      redirect: "error",
    },
  );
  const payload = await boundedJson(response);
  if (!response.ok) throw new Error("GITHUB_APP_REPOSITORY_PROBE_FAILED");
  if (payload.full_name !== repository) {
    throw new Error("GITHUB_APP_REPOSITORY_IDENTITY_MISMATCH");
  }

  return {
    ok: true,
    authMode: "github_app",
    appId: PANDORA_GITHUB_APP_ID,
    installationId: assertInstallationId(installationId),
    repository,
    repositoryId: Number.isSafeInteger(payload.id) ? payload.id : null,
    defaultBranch:
      typeof payload.default_branch === "string" ? payload.default_branch : null,
    tokenExpiresAt: lease.expiresAt,
  };
}
