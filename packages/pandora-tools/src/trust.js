"use strict";

const { PandoraToolError } = require("./errors");

function assertRequirementRefsAuthorized(proposal, authorizedRequirementRefs = null) {
  if (authorizedRequirementRefs == null) return true;
  const allowed = new Set(authorizedRequirementRefs);
  for (const ref of proposal.requirement_refs || []) {
    if (!allowed.has(ref)) throw new PandoraToolError("policy_denied", "REQUIREMENT_REF_NOT_AUTHORIZED", "Tool proposal references a requirement outside the current ProjectSpec");
  }
  return true;
}

function assertTrustedStateOrigin(state, expectedIssuer) {
  if (!state || state.authoritative !== true || state.issuer !== expectedIssuer) {
    throw new PandoraToolError("policy_denied", "TRUSTED_STATE_REQUIRED", "Authoritative system state is required for this operation");
  }
  return true;
}

module.exports = { assertRequirementRefsAuthorized, assertTrustedStateOrigin };
