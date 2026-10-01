const DEFAULT_MAX_ACTIONS = 2;
const HARD_MAX_ACTIONS = 10;

export const RpaContainmentErrorCode = Object.freeze({
  invalidContract: "RPA_INVALID_CONTRACT",
  actionNotAllowed: "RPA_ACTION_NOT_ALLOWED",
  handlerMissing: "RPA_ACTION_HANDLER_MISSING",
  sessionLimitExceeded: "RPA_SESSION_LIMIT_EXCEEDED",
  evidenceRequired: "RPA_EVIDENCE_REQUIRED",
});

export class RpaContainmentError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "RpaContainmentError";
    this.code = code;
  }
}

function normalizedActionSet(actionSet) {
  if (!actionSet || typeof actionSet !== "object") {
    throw new RpaContainmentError(
      RpaContainmentErrorCode.invalidContract,
      "RPA action-set contract is required.",
    );
  }

  const actionSetKey =
    typeof actionSet.actionSetKey === "string" ? actionSet.actionSetKey.trim() : "";
  const allowedActions = Array.isArray(actionSet.allowedActions)
    ? [...new Set(actionSet.allowedActions.map((value) => String(value).trim()).filter(Boolean))]
    : [];
  const maxActionsPerSession =
    Number.isInteger(actionSet.maxActionsPerSession)
      ? actionSet.maxActionsPerSession
      : DEFAULT_MAX_ACTIONS;

  if (!actionSetKey || allowedActions.length === 0) {
    throw new RpaContainmentError(
      RpaContainmentErrorCode.invalidContract,
      "RPA action set must declare a key and at least one allowed action.",
    );
  }
  if (maxActionsPerSession < 1 || maxActionsPerSession > HARD_MAX_ACTIONS) {
    throw new RpaContainmentError(
      RpaContainmentErrorCode.invalidContract,
      "RPA session action limit is outside the containment boundary.",
    );
  }

  return Object.freeze({
    actionSetKey,
    allowedActions: Object.freeze(allowedActions),
    maxActionsPerSession,
    evidenceRequired: actionSet.evidenceRequired !== false,
  });
}

function hasEvidence(result) {
  if (!result || typeof result !== "object") return false;
  const evidence = result.evidence;
  if (typeof evidence === "string") return evidence.trim().length > 0;
  return Boolean(
    evidence &&
      typeof evidence === "object" &&
      Object.keys(evidence).length > 0,
  );
}

export function createBoundedRpaSession({ actionSet, handlers = {} }) {
  const contract = normalizedActionSet(actionSet);
  const allowed = new Set(contract.allowedActions);
  let attemptedActions = 0;

  return Object.freeze({
    contract,

    get attemptedActions() {
      return attemptedActions;
    },

    get remainingActions() {
      return Math.max(contract.maxActionsPerSession - attemptedActions, 0);
    },

    async execute(action, input = undefined) {
      const actionName = typeof action === "string" ? action.trim() : "";
      if (!allowed.has(actionName)) {
        throw new RpaContainmentError(
          RpaContainmentErrorCode.actionNotAllowed,
          `RPA action "${actionName || "unknown"}" is outside the declared allowlist.`,
        );
      }
      if (attemptedActions >= contract.maxActionsPerSession) {
        throw new RpaContainmentError(
          RpaContainmentErrorCode.sessionLimitExceeded,
          "RPA session action limit reached before provider execution.",
        );
      }

      const handler = handlers[actionName];
      if (typeof handler !== "function") {
        throw new RpaContainmentError(
          RpaContainmentErrorCode.handlerMissing,
          `No bounded handler is registered for RPA action "${actionName}".`,
        );
      }

      attemptedActions += 1;
      const result = await handler({
        action: actionName,
        input,
        attempt: attemptedActions,
        remainingActions: Math.max(
          contract.maxActionsPerSession - attemptedActions,
          0,
        ),
      });

      if (contract.evidenceRequired && !hasEvidence(result)) {
        throw new RpaContainmentError(
          RpaContainmentErrorCode.evidenceRequired,
          `RPA action "${actionName}" completed without required evidence.`,
        );
      }

      return Object.freeze({
        actionSetKey: contract.actionSetKey,
        action: actionName,
        attempt: attemptedActions,
        remainingActions: Math.max(
          contract.maxActionsPerSession - attemptedActions,
          0,
        ),
        evidence: result?.evidence ?? null,
        value: result?.value,
      });
    },
  });
}
