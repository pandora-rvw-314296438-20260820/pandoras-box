const EXPECTED_PROJECT_NAME = "mcpmaster";
const EXPECTED_ENVIRONMENT = "production";

const TRUSTED_PRODUCTION_IDENTITIES = Object.freeze([
  Object.freeze({
    ownerId: "team_3yw1CN59ce4pj5SwyQGCAqN3",
    projectId: "prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk",
    owner: "mbanatao",
  }),
]);

function trustedIdentity(payload) {
  return TRUSTED_PRODUCTION_IDENTITIES.find((identity) => (
    payload.owner_id === identity.ownerId
    && payload.project_id === identity.projectId
  ));
}

/**
 * Validate the signed Vercel identity before any private control data is read.
 *
 * Only the project serving https://mcpmaster.vercel.app is trusted. Preview,
 * development, retired-project, arbitrary-project, and mixed-identity claims
 * are rejected.
 */
export function assertProductionVercelClaims(payload, audiences) {
  if (payload.environment !== EXPECTED_ENVIRONMENT) {
    throw new Error("environment not allowed");
  }

  if (payload.project !== EXPECTED_PROJECT_NAME) {
    throw new Error("invalid Vercel project claim");
  }

  if (typeof payload.owner !== "string" || payload.owner.length === 0) {
    throw new Error("missing owner");
  }

  const identity = trustedIdentity(payload);
  if (!identity) {
    throw new Error("wrong Vercel project");
  }

  if (payload.owner !== identity.owner) {
    throw new Error("invalid owner");
  }

  const expectedSubject = `owner:${identity.owner}:project:${EXPECTED_PROJECT_NAME}:environment:${EXPECTED_ENVIRONMENT}`;
  if (payload.sub !== expectedSubject) {
    throw new Error("invalid subject");
  }

  if (!Array.isArray(audiences) || !audiences.includes(`https://vercel.com/${identity.owner}`)) {
    throw new Error("invalid audience");
  }
}

export const trustedProductionIdentityCount = TRUSTED_PRODUCTION_IDENTITIES.length;
