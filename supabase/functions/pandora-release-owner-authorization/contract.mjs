const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const DEPLOYMENT_ID = /^dpl_[A-Za-z0-9]+$/;
const REQUEST_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{15,127}$/;
const CANONICAL_REPOSITORY = "banataosystems/Pandoras-box";

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected) {
  if (!isRecord(value)) return false;
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return actual.length === wanted.length &&
    actual.every((key, index) => key === wanted[index]);
}

function validTimestamp(value, now = new Date()) {
  if (typeof value !== "string") return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && Math.abs(parsed - now.getTime()) <= 5 * 60 * 1000;
}

const OWNER_AUTHORIZATION_KEYS = Object.freeze([
  "action",
  "authorizedAt",
  "organizationId",
  "productionDeploymentId",
  "repository",
  "requestId",
  "reviewReceiptId",
  "reviewReceiptSha256",
  "schemaVersion",
  "sourceSha",
]);

function validateOwnerAuthorizationRequest(value, now = new Date()) {
  if (!exactKeys(value, OWNER_AUTHORIZATION_KEYS) ||
    value.schemaVersion !== 1 || value.action !== "authorize_canonical_release" ||
    !UUID.test(value.organizationId) ||
    value.repository !== CANONICAL_REPOSITORY ||
    !SHA40.test(value.sourceSha) ||
    !DEPLOYMENT_ID.test(value.productionDeploymentId) ||
    !UUID.test(value.reviewReceiptId) ||
    !SHA256.test(value.reviewReceiptSha256) ||
    !REQUEST_ID.test(value.requestId) ||
    !validTimestamp(value.authorizedAt, now)) {
    throw new Error("INVALID_OWNER_AUTHORIZATION");
  }
  return value;
}

export {
  OWNER_AUTHORIZATION_KEYS,
  validateOwnerAuthorizationRequest,
};
