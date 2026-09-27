"use strict";

const NON_MUTATING_RELEASE_STATES = new Set([
  "idle",
  "release_authorization_required",
  "manual_reconciliation_required",
]);

function canContinueSourceBuilding(state) {
  return typeof state === "string" && NON_MUTATING_RELEASE_STATES.has(state);
}

module.exports = { canContinueSourceBuilding };
