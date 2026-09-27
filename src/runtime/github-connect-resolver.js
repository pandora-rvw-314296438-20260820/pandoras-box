"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.GitHubConnectResolverError = exports.GitHubConnectResolver = void 0;

const DEFAULT_API_ORIGIN = "https://api.vercel.com";
const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1_000_000;
const DEFAULT_VALIDITY_BUFFER_MS = 30_000;
const REPOSITORY_PATTERN = /^[^/\s]+\/[^/\s]+$/;
const INSTALLATION_PATTERN = /^[1-9][0-9]{0,19}$/;
const CONNECTOR_PATTERN = /^github\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

const LOGICAL_SCOPE_PERMISSIONS = Object.freeze({
  "repositories:read": ["contents:read"],
  "repositories:write": ["contents:write"],
  "contents:read": ["contents:read"],
  "contents:write": ["contents:write"],
  "issues:read": ["issues:read"],
  "issues:write": ["issues:write"],
  "pull_requests:read": ["pull_requests:read"],
  "pull_requests:write": ["pull_requests:write"],
  "workflows:read": ["actions:read"],
  "workflows:write": ["workflows:write"],
});

class GitHubConnectResolverError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "GitHubConnectResolverError";
    this.status = status;
  }
}
exports.GitHubConnectResolverError = GitHubConnectResolverError;

function uniqueStrings(values) {
  return [...new Set(values.map((value) => String(value).trim()).filter(Boolean))];
}

function githubPermissions(requiredProviderScopes, toolName) {
  const permissions = new Set();
  for (const scope of uniqueStrings(requiredProviderScopes || [])) {
    if (scope === "identity:read") {
      throw new GitHubConnectResolverError("GitHub user identity requires the legacy user-bound resolver");
    }
    const mapped = LOGICAL_SCOPE_PERMISSIONS[scope];
    if (!mapped) {
      throw new GitHubConnectResolverError("GitHub Connect scope mapping is unavailable");
    }
    for (const permission of mapped) permissions.add(permission);
  }
  if (toolName === "github.merge-pull-request") permissions.add("contents:write");
  return [...permissions].sort();
}

function validateRepositories(repositories) {
  const values = uniqueStrings(repositories || []);
  if (values.length === 0 || values.length > 20 || values.some((value) => !REPOSITORY_PATTERN.test(value))) {
    throw new GitHubConnectResolverError("GitHub Connect repository allowlist is invalid");
  }
  return values;
}

function safeConnectorUid(value) {
  const uid = String(value || "").trim();
  if (!CONNECTOR_PATTERN.test(uid)) throw new GitHubConnectResolverError("GitHub Connect connector UID is invalid");
  return uid;
}
function safeInstallationId(value) {
  const installationId = String(value || "").trim();
  if (!INSTALLATION_PATTERN.test(installationId)) {
    throw new GitHubConnectResolverError("GitHub Connect installation ID is invalid");
  }
  return installationId;
}

class GitHubConnectResolver {
  constructor(options = {}) {
    this.apiOrigin = options.apiOrigin || DEFAULT_API_ORIGIN;
    this.timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
    this.maxResponseBytes = options.maxResponseBytes || DEFAULT_MAX_RESPONSE_BYTES;
    this.fetchFn = options.fetchFn || globalThis.fetch;
    if (this.apiOrigin !== DEFAULT_API_ORIGIN) {
      throw new GitHubConnectResolverError("GitHub Connect API origin is not trusted");
    }
  }

  async resolve(vercelOidcToken, options) {
    const oidcToken = String(vercelOidcToken || "").trim();
    if (oidcToken.length < 20) {
      throw new GitHubConnectResolverError("Vercel OIDC runtime token is required");
    }
    const connectorUid = safeConnectorUid(options?.connectorUid);
    const installationId = safeInstallationId(options?.installationId);
    const allowedRepositories = validateRepositories(options?.allowedRepositories);
    const requiredProviderScopes = uniqueStrings(options?.requiredProviderScopes || []);
    const permissions = githubPermissions(requiredProviderScopes, options?.toolName);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchFn(
        `${this.apiOrigin}/v1/connect/token/${encodeURIComponent(connectorUid)}`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${oidcToken}`,
            "content-type": "application/json",
            accept: "application/json",
          },
          body: JSON.stringify({
            subject: { type: "app" },
            installationId,
            authorizationDetails: [{
              type: "github_app_installation",
              repositories: allowedRepositories,
              permissions,
            }],
            validityBufferMs: DEFAULT_VALIDITY_BUFFER_MS,
          }),
          signal: controller.signal,
          redirect: "error",
        },
      );

      const declaredLength = Number(response.headers?.get("content-length") || "0");
      if (Number.isFinite(declaredLength) && declaredLength > this.maxResponseBytes) {
        throw new GitHubConnectResolverError("GitHub Connect response is too large");
      }
      const text = await response.text();
      if (Buffer.byteLength(text, "utf8") > this.maxResponseBytes) {
        throw new GitHubConnectResolverError("GitHub Connect response is too large");
      }
      if (!response.ok) {
        throw new GitHubConnectResolverError(
          `GitHub Connect token request failed with status ${response.status}`,
          response.status,
        );
      }

      let payload;
      try {
        payload = JSON.parse(text);
      } catch {
        throw new GitHubConnectResolverError("GitHub Connect returned invalid JSON");
      }
      if (
        !payload
        || typeof payload !== "object"
        || typeof payload.token !== "string"
        || payload.token.length < 20
        || payload.connector?.uid !== connectorUid
        || String(payload.installationId || "") !== installationId
        || !Number.isFinite(payload.expiresAt)
        || payload.expiresAt <= Date.now() + DEFAULT_VALIDITY_BUFFER_MS
      ) {
        throw new GitHubConnectResolverError("GitHub Connect returned an invalid token envelope");
      }
      return {
        id: String(options?.accountId || "github-primary"),
        label: String(options?.label || "Vercel Connect GitHub App"),
        authMode: "github_app_connect",
        token: payload.token,
        allowMutations: options?.allowMutations === true,
        baseUrl: "https://api.github.com",
        login: options?.login ? String(options.login) : undefined,
        allowedRepositories,
        grantedScopes: uniqueStrings(options?.grantedScopes || []),
      };
    } catch (error) {
      if (error instanceof GitHubConnectResolverError) throw error;
      if (error instanceof Error && error.name === "AbortError") {
        throw new GitHubConnectResolverError("GitHub Connect token request timed out");
      }
      throw new GitHubConnectResolverError("GitHub Connect token request failed");
    } finally {
      clearTimeout(timeout);
    }
  }
}

exports.GitHubConnectResolver = GitHubConnectResolver;
