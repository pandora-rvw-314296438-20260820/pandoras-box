"use strict";

const path = require("node:path");
const { PandoraToolError } = require("./errors");

const SENSITIVE_SEGMENTS = new Set([
  ".git", ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".config",
]);
const SENSITIVE_FILES = new Set([
  ".env", ".npmrc", ".netrc", "id_rsa", "id_ed25519", "credentials", "credentials.json",
]);

function decodeTraversal(value) {
  let decoded = value;
  for (let i = 0; i < 3; i += 1) {
    let next;
    try {
      next = decodeURIComponent(decoded);
    } catch {
      throw new PandoraToolError("invalid_request", "PATH_ENCODING_INVALID", "Path contains invalid percent encoding");
    }
    if (next === decoded) break;
    decoded = next;
  }
  return decoded;
}

function normalizeProjectPath(input) {
  if (typeof input !== "string" || input.length < 1 || input.length > 1024) {
    throw new PandoraToolError("invalid_request", "PATH_INVALID", "Path must be a non-empty string no longer than 1024 characters");
  }
  if (input.includes("\0") || input.includes("\u0000") || input.includes("\\")) {
    throw new PandoraToolError("invalid_request", "PATH_UNSAFE", "Path contains a forbidden character or Windows separator");
  }
  const decoded = decodeTraversal(input).normalize("NFC");
  if (decoded.includes("\0") || decoded.includes("\u0000") || decoded.includes("\\") || /[\u2215\u2044\uff0f\uff3c]/u.test(decoded)) {
    throw new PandoraToolError("invalid_request", "PATH_UNSAFE", "Decoded path contains a forbidden separator or null byte");
  }
  if (decoded.startsWith("/") || decoded.startsWith("//") || /^[a-zA-Z]:/.test(decoded)) {
    throw new PandoraToolError("invalid_request", "PATH_ABSOLUTE_FORBIDDEN", "Absolute host paths are forbidden");
  }
  const segments = decoded.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    throw new PandoraToolError("invalid_request", "PATH_TRAVERSAL", "Path traversal or ambiguous segments are forbidden");
  }
  const lower = segments.map((segment) => segment.toLowerCase());
  if (lower.some((segment) => SENSITIVE_SEGMENTS.has(segment))) {
    throw new PandoraToolError("authorization", "PATH_SECRET_AREA_FORBIDDEN", "Sensitive workspace control paths are forbidden");
  }
  if (lower.some((segment) => SENSITIVE_FILES.has(segment) || segment.startsWith(".env."))) {
    throw new PandoraToolError("authorization", "PATH_SECRET_FILE_FORBIDDEN", "Secret-bearing files are forbidden");
  }
  return segments.join("/");
}

function assertAuthorizedSubpath(normalizedPath, authorizedSubpaths = [""]) {
  if (!Array.isArray(authorizedSubpaths) || authorizedSubpaths.length === 0) {
    throw new PandoraToolError("authorization", "PATH_SCOPE_MISSING", "No authorized workspace subpaths were supplied");
  }
  const allowed = authorizedSubpaths.some((prefix) => {
    if (prefix === "") return true;
    const cleanPrefix = normalizeProjectPath(prefix);
    return normalizedPath === cleanPrefix || normalizedPath.startsWith(`${cleanPrefix}/`);
  });
  if (!allowed) throw new PandoraToolError("authorization", "PATH_OUTSIDE_SCOPE", "Path is outside the authorized project subpaths");
}

function validateProjectPath(input, authorizedSubpaths = [""]) {
  const normalized = normalizeProjectPath(input);
  assertAuthorizedSubpath(normalized, authorizedSubpaths);
  return normalized;
}

function assertResolvedPathInsideWorkspace(workspaceRoot, resolvedRealPath) {
  if (typeof workspaceRoot !== "string" || typeof resolvedRealPath !== "string") {
    throw new PandoraToolError("invalid_request", "REALPATH_REQUIRED", "Workspace and resolved paths are required");
  }
  const root = path.resolve(workspaceRoot);
  const candidate = path.resolve(resolvedRealPath);
  const relative = path.relative(root, candidate);
  if (relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))) return true;
  throw new PandoraToolError("authorization", "SYMLINK_ESCAPE", "Resolved path escapes the authorized project workspace");
}

module.exports = {
  normalizeProjectPath,
  validateProjectPath,
  assertAuthorizedSubpath,
  assertResolvedPathInsideWorkspace,
};
