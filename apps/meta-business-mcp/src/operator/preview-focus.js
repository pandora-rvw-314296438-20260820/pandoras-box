"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FocusPreviewError = void 0;
exports.createFocusPreviewExecutor = createFocusPreviewExecutor;
const node_crypto_1 = require("node:crypto");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/i;
const BASE64_RE = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const MAX_EDGE_BYTES = 3 * 1024 * 1024;
const MAX_HTML_BYTES = 2 * 1024 * 1024;

class FocusPreviewError extends Error {
  constructor(code, status, message) {
    super(message);
    this.name = "FocusPreviewError";
    this.code = code;
    this.status = status;
  }
}
exports.FocusPreviewError = FocusPreviewError;

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}
function record(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function exactKeys(value, allowed) {
  const permitted = new Set(allowed);
  return Object.keys(record(value)).every((key) => permitted.has(key));
}
function uuid(value, code = "FOCUS_PREVIEW_INVALID") {
  const normalized = text(value).toLowerCase();
  if (!UUID_RE.test(normalized)) {
    throw new FocusPreviewError(code, 400, "Pandora could not identify that exact preview.");
  }
  return normalized;
}
function decodeCanonicalBase64(value) {
  const encoded = text(value);
  if (!encoded || encoded.length % 4 !== 0 || !BASE64_RE.test(encoded)) {
    throw new FocusPreviewError("FOCUS_PREVIEW_INVALID", 503, "Pandora returned an unreadable focus preview.");
  }
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.length < 1 || bytes.length > MAX_HTML_BYTES || bytes.toString("base64") !== encoded) {
    throw new FocusPreviewError("FOCUS_PREVIEW_INVALID", 503, "Pandora returned an unreadable focus preview.");
  }
  return bytes;
}

function createFocusPreviewExecutor(options) {
  const supabaseUrl = new URL(options.supabaseUrl);
  const publishableKey = text(options.publishableKey);
  const fetchFn = options.fetchFn ?? fetch;
  if ((supabaseUrl.protocol !== "https:" && supabaseUrl.hostname !== "localhost") || !publishableKey) {
    throw new Error("Focus preview executor is not configured");
  }

  return async function executeFocusPreview(input) {
    const actor = record(input.actor);
    const identity = record(actor.identity);
    const accessToken = text(identity.accessToken);
    if (!accessToken) {
      throw new FocusPreviewError("FOCUS_PREVIEW_SESSION_INVALID", 401, "Please sign in again.");
    }
    const projectId = uuid(input.projectId);
    const body = record(input.body);
    if (!exactKeys(body, ["versionId"])) {
      throw new FocusPreviewError("FOCUS_PREVIEW_INVALID", 400, "Pandora rejected unsupported preview fields.");
    }
    const versionId = uuid(body.versionId);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    let response;
    try {
      response = await fetchFn(new URL("/functions/v1/pandora-preview-content", supabaseUrl), {
        method: "POST",
        headers: {
          accept: "application/json",
          apikey: publishableKey,
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ projectId, versionId, mode: "web_focus" }),
        redirect: "error",
        signal: controller.signal,
      });
    } catch {
      throw new FocusPreviewError("FOCUS_PREVIEW_UNAVAILABLE", 503, "Pandora could not prepare object focus right now.");
    } finally {
      clearTimeout(timeout);
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > MAX_EDGE_BYTES) {
      throw new FocusPreviewError("FOCUS_PREVIEW_INVALID", 503, "Pandora returned an oversized focus preview.");
    }
    let payload;
    try {
      payload = record(bytes.byteLength ? JSON.parse(Buffer.from(bytes).toString("utf8")) : {});
    } catch {
      throw new FocusPreviewError("FOCUS_PREVIEW_INVALID", 503, "Pandora returned an unreadable focus preview.");
    }

    if (!response.ok) {
      const status = [400, 401, 403, 404, 409, 413].includes(response.status) ? response.status : 503;
      throw new FocusPreviewError(
        text(payload.code) || "FOCUS_PREVIEW_UNAVAILABLE",
        status,
        text(payload.plainMessage) || "Pandora could not prepare object focus right now.",
      );
    }

    if (payload.kind !== "pandora.web-focus-preview.v1"
      || text(payload.projectId).toLowerCase() !== projectId
      || text(payload.versionId).toLowerCase() !== versionId
      || !SHA256_RE.test(text(payload.artifactDigest))
      || !SHA256_RE.test(text(payload.sha256))
      || text(payload.provider) !== "vercel"
      || !UUID_RE.test(text(payload.deploymentId))) {
      throw new FocusPreviewError("FOCUS_PREVIEW_IDENTITY_MISMATCH", 503, "Pandora could not verify the exact focus preview.");
    }

    const htmlBytes = decodeCanonicalBase64(payload.htmlBase64);
    if (Number(payload.byteSize) !== htmlBytes.length) {
      throw new FocusPreviewError("FOCUS_PREVIEW_IDENTITY_MISMATCH", 503, "Pandora could not verify the focus preview size.");
    }
    const htmlDigest = (0, node_crypto_1.createHash)("sha256").update(htmlBytes).digest("hex");
    if (htmlDigest !== text(payload.sha256).toLowerCase()) {
      throw new FocusPreviewError("FOCUS_PREVIEW_IDENTITY_MISMATCH", 503, "Pandora could not verify the focus preview digest.");
    }

    return {
      ok: true,
      kind: payload.kind,
      projectId,
      versionId,
      artifactDigest: text(payload.artifactDigest).toLowerCase(),
      deploymentId: text(payload.deploymentId).toLowerCase(),
      provider: "vercel",
      hostedUrl: text(payload.hostedUrl),
      byteSize: htmlBytes.length,
      sha256: text(payload.sha256).toLowerCase(),
      htmlBase64: text(payload.htmlBase64),
    };
  };
}
