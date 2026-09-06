"use strict";

const DEFAULT_CONNECTOR = "mcpmaster.vercel.app/pandoras-box";
const DEFAULT_VERCEL_API_BASE = "https://api.vercel.com";
const USER_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class VercelConnectUserError extends Error {
  constructor(code, message, status = 503) {
    super(message);
    this.name = "VercelConnectUserError";
    this.code = code;
    this.status = status;
  }
}

function userId(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!USER_ID_PATTERN.test(normalized)) {
    throw new VercelConnectUserError(
      "VERCEL_CONNECT_SUBJECT_INVALID",
      "The authenticated user identity cannot be used for Vercel Connect.",
      400,
    );
  }
  return normalized;
}

function workloadToken(value) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (normalized.length < 32) {
    throw new VercelConnectUserError(
      "VERCEL_CONNECT_WORKLOAD_IDENTITY_UNAVAILABLE",
      "Vercel workload identity is unavailable for this request.",
      503,
    );
  }
  return normalized;
}

function httpsUrl(value, label) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new VercelConnectUserError(
      "VERCEL_CONNECT_CONFIGURATION_INVALID",
      label + " is invalid.",
      503,
    );
  }
  if (
    parsed.protocol !== "https:"
    || parsed.username
    || parsed.password
    || parsed.hash
  ) {
    throw new VercelConnectUserError(
      "VERCEL_CONNECT_CONFIGURATION_INVALID",
      label + " must be an HTTPS URL.",
      503,
    );
  }
  return parsed;
}

async function jsonBody(response) {
  try {
    const payload = await response.json();
    return payload && typeof payload === "object" && !Array.isArray(payload)
      ? payload
      : {};
  } catch {
    return {};
  }
}

function vercelErrorCode(payload) {
  if (typeof payload?.code === "string") return payload.code;
  if (
    payload?.error
    && typeof payload.error === "object"
    && !Array.isArray(payload.error)
    && typeof payload.error.code === "string"
  ) {
    return payload.error.code;
  }
  return "";
}

class VercelConnectUserBroker {
  constructor({
    connector = DEFAULT_CONNECTOR,
    providerUserinfoUrl,
    vercelApiBase = DEFAULT_VERCEL_API_BASE,
    fetchImpl = globalThis.fetch,
  } = {}) {
    const connectorValue = typeof connector === "string" ? connector.trim() : "";
    if (
      connectorValue.length < 3
      || connectorValue.length > 300
      || /[\u0000-\u001f\u007f]/.test(connectorValue)
    ) {
      throw new Error("Vercel Connect connector is invalid");
    }
    if (typeof fetchImpl !== "function") {
      throw new Error("Vercel Connect requires fetch");
    }
    this.connector = connectorValue;
    this.providerUserinfoUrl = httpsUrl(providerUserinfoUrl, "Provider userinfo URL").toString();
    this.vercelApiBase = httpsUrl(vercelApiBase, "Vercel API base").origin;
    this.fetchImpl = fetchImpl;
  }

  async requestConnect(path, subjectId, vercelOidcToken, body = {}) {
    const response = await this.fetchImpl(
      this.vercelApiBase + "/v1/connect/" + path + "/" + encodeURIComponent(this.connector),
      {
        method: "POST",
        headers: {
          authorization: "Bearer " + workloadToken(vercelOidcToken),
          accept: "application/json",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          subject: { type: "user", id: userId(subjectId) },
          ...body,
        }),
        redirect: "error",
      },
    );
    return { response, payload: await jsonBody(response) };
  }

  async startAuthorization({ userId: subjectId, vercelOidcToken, returnUrl }) {
    const safeReturnUrl = httpsUrl(returnUrl, "Vercel Connect return URL").toString();
    const { response, payload } = await this.requestConnect(
      "authorize",
      subjectId,
      vercelOidcToken,
      { returnUrl: safeReturnUrl },
    );
    if (!response.ok || typeof payload.url !== "string") {
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_AUTHORIZATION_UNAVAILABLE",
        "Pandora could not start Vercel Connect authorization.",
        503,
      );
    }
    const authorizationUrl = httpsUrl(payload.url, "Vercel Connect authorization URL");
    return { url: authorizationUrl.toString() };
  }

  async probe({ userId: subjectId, vercelOidcToken }) {
    const safeUserId = userId(subjectId);
    const { response, payload } = await this.requestConnect(
      "token",
      safeUserId,
      vercelOidcToken,
    );
    if (!response.ok) {
      const errorCode = vercelErrorCode(payload);
      if (errorCode === "user_authorization_required") {
        throw new VercelConnectUserError(
          "VERCEL_CONNECT_USER_NOT_READY",
          "This Pandora user has not authorized the Vercel Connect provider yet.",
          409,
        );
      }
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_TOKEN_UNAVAILABLE",
        "Pandora could not obtain a Vercel Connect token.",
        503,
      );
    }
    if (typeof payload.token !== "string" || payload.token.length < 16) {
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_TOKEN_INVALID",
        "Vercel Connect returned an unusable token.",
        503,
      );
    }

    const providerResponse = await this.fetchImpl(this.providerUserinfoUrl, {
      method: "GET",
      headers: {
        authorization: "Bearer " + payload.token,
        accept: "application/json",
      },
      redirect: "error",
    });
    const providerPayload = await jsonBody(providerResponse);
    if (!providerResponse.ok || typeof providerPayload.sub !== "string") {
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_PROVIDER_PROBE_FAILED",
        "The Vercel Connect token could not be verified with the provider.",
        503,
      );
    }
    if (providerPayload.sub !== safeUserId) {
      throw new VercelConnectUserError(
        "VERCEL_CONNECT_SUBJECT_MISMATCH",
        "The Vercel Connect token subject does not match the authenticated Pandora user.",
        409,
      );
    }
    return {
      subjectId: safeUserId,
      emailVerified: providerPayload.email_verified === true,
    };
  }
}

module.exports = {
  DEFAULT_CONNECTOR,
  VercelConnectUserBroker,
  VercelConnectUserError,
};
