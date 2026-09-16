export const EXTERNAL_EXPERIENCE_WRITE_DISABLED =
  "EXTERNAL_EXPERIENCE_WRITE_DISABLED";

const WRITE_ROUTES = [
  ["project.create", /^\/projects$/],
  ["preview.create", /^\/projects\/[^/]+\/previews$/],
  ["project.undo", /^\/projects\/[^/]+\/undo$/],
  ["project.rollback", /^\/projects\/[^/]+\/rollback$/],
  ["project.publish", /^\/projects\/[^/]+\/publish$/],
  ["production.verify", /^\/projects\/[^/]+\/production-verification$/],
];

export function externalExperienceWriteOperationForRequest(method, route) {
  if (String(method || "").toUpperCase() !== "POST") return null;
  const normalizedRoute = String(route || "");
  for (const [operation, pattern] of WRITE_ROUTES) {
    if (pattern.test(normalizedRoute)) return operation;
  }
  return null;
}

export class ExternalExperienceWriteDisabledError extends Error {
  constructor() {
    super(EXTERNAL_EXPERIENCE_WRITE_DISABLED);
    this.name = "ExternalExperienceWriteDisabledError";
    this.status = 403;
    this.retryable = false;
    this.outcomeKnown = true;
  }
}

export async function enforceExternalExperienceWriteRequest({
  origin,
  method,
  route,
  firstPartyOrigins,
  decide,
}) {
  const operation = externalExperienceWriteOperationForRequest(method, route);
  if (!operation) return { operation: null, checked: false };
  if (!origin || firstPartyOrigins.has(origin)) {
    return { operation, checked: false };
  }

  let allowed = false;
  try {
    allowed = (await decide(origin, operation)) === true;
  } catch {
    allowed = false;
  }
  if (!allowed) throw new ExternalExperienceWriteDisabledError();
  return { operation, checked: true };
}
