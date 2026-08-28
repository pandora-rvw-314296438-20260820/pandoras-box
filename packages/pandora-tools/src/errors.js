"use strict";

const INTERNAL_TO_OWNER = Object.freeze({
  authorization: "Pandora is not authorized to perform this action.",
  rate_limit: "Pandora is temporarily limiting this operation.",
  timeout: "Pandora could not complete this operation in time.",
  network: "Pandora could not reach a required service.",
  conflict: "Pandora found a conflicting operation and did not continue.",
  invalid_request: "Pandora could not use this request safely.",
  provider_unavailable: "A required service is temporarily unavailable.",
  resource_missing: "Pandora could not find the required resource.",
  budget: "This operation is blocked by the current budget limit.",
  policy_denied: "Pandora blocked this action under the current safety policy.",
  approval_required: "Pandora needs approval before continuing.",
  verification_required: "Pandora needs a current verification result before continuing.",
  ambiguous_mutation: "Pandora could not safely determine whether the previous change completed.",
  internal: "Pandora could not complete this operation yet.",
});

class PandoraToolError extends Error {
  constructor(errorClass, code, internalMessage, details = undefined) {
    super(internalMessage);
    this.name = "PandoraToolError";
    this.errorClass = errorClass;
    this.code = code;
    this.details = details;
    this.ownerMessage = INTERNAL_TO_OWNER[errorClass] || INTERNAL_TO_OWNER.internal;
  }

  toOwnerSafe() {
    return { error_class: this.errorClass, code: this.code, message: this.ownerMessage };
  }
}

module.exports = { PandoraToolError, INTERNAL_TO_OWNER };
