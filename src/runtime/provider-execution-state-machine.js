"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.ProviderExecutionOutcomeError = void 0;
exports.markProviderOutcome = void 0;
exports.prepareProviderResult = void 0;
exports.prepareToolPresentation = void 0;
exports.createProviderExecutionStateMachine = createProviderExecutionStateMachine;

const { AsyncLocalStorage } = require("node:async_hooks");
const resultContract = require("./provider-result-contract.js");
const outcomeContract = require("./provider-outcome-contract.js");

const { prepareProviderResult, prepareToolPresentation } = resultContract;
const {
  ProviderExecutionOutcomeError,
  emitReconciliationEvent,
  finalizationAmbiguity,
  localPostSuccessError,
  markProviderOutcome,
  normalizedProviderError,
  operationIdentity,
  sanitizedResultSummary,
} = outcomeContract;

exports.ProviderExecutionOutcomeError = ProviderExecutionOutcomeError;
exports.markProviderOutcome = markProviderOutcome;
exports.prepareProviderResult = prepareProviderResult;
exports.prepareToolPresentation = prepareToolPresentation;

function createProviderExecutionStateMachine(options) {
  if (!options || typeof options.execute !== "function" || !options.ledger) {
    throw new TypeError("Provider execution state machine requires execute and ledger dependencies");
  }
  const storage = new AsyncLocalStorage();
  const rawExecute = options.execute;
  const rawLedger = options.ledger;
  const currentState = () => storage.getStore();

  function failureForState(state, phase, code) {
    const execution = state?.execution;
    if (!execution || !["succeeded", "ambiguous"].includes(execution.providerOutcome)) return null;
    if (execution.error instanceof ProviderExecutionOutcomeError) return execution.error;
    execution.error = execution.providerOutcome === "succeeded"
      ? localPostSuccessError(null, execution.identity, phase, code)
      : new ProviderExecutionOutcomeError({
        providerOutcome: "ambiguous",
        downstreamProcessingOutcome: phase,
        safeErrorCode: code || "provider_execution_outcome_ambiguous",
        validationCategory: "local_processing",
        retryable: execution.identity.providerIdempotencySupported,
        reconciliationRequired: true,
        status: 503,
        identity: execution.identity,
        summary: "Provider dispatch may have occurred and local processing failed; reconciliation is required",
      });
    return execution.error;
  }

  async function execute(tool, args, configuration) {
    const identity = operationIdentity(tool, args);
    const state = currentState();
    try {
      const rawResult = await rawExecute(tool, args, configuration);
      const execution = {
        providerOutcome: "succeeded",
        identity,
        error: null,
        durableFinalized: false,
      };
      if (state) state.execution = execution;
      try {
        return prepareProviderResult(rawResult);
      } catch (error) {
        execution.error = localPostSuccessError(
          error,
          identity,
          "failed",
          "provider_result_contract_error",
        );
        throw execution.error;
      }
    } catch (error) {
      // Status codes alone cannot prove that a provider did not apply a
      // mutation. Reviewed adapters must explicitly mark a proven outcome;
      // every unmarked error is conservatively ambiguous after dispatch.
      const guarded = normalizedProviderError(error, identity);
      if (state && !state.execution) {
        state.execution = {
          providerOutcome: guarded.providerOutcome || "ambiguous",
          identity,
          error: guarded,
          durableFinalized: false,
        };
      }
      throw guarded;
    }
  }

  function preparePresentation(value, phase = "response_shaping_failed") {
    try {
      return prepareToolPresentation(value);
    } catch (error) {
      throw failureForState(currentState(), phase, "response_contract_error") || error;
    }
  }

  function recordResponseFailureForState(state, error, phase = "response_delivery_failed", planId) {
    const execution = state?.execution;
    if (!execution || !["succeeded", "ambiguous"].includes(execution.providerOutcome)) return;
    const guarded = failureForState(state, phase, "response_delivery_failed");
    emitReconciliationEvent(execution, phase, planId);
    if (guarded && error && typeof error === "object" && !error.cause) {
      try {
        Object.defineProperty(error, "cause", {
          value: guarded,
          enumerable: false,
          configurable: false,
        });
      } catch {
        // Retain the original response failure.
      }
    }
  }

  const ledger = new Proxy(rawLedger, {
    get(target, property, receiver) {
      if (property !== "finishPlan") {
        const value = Reflect.get(target, property, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return async function guardedFinishPlan(token, input) {
        const execution = currentState()?.execution;
        const finishExactly = async (payload) => {
          const finalized = await target.finishPlan(token, payload);
          if (
            !finalized
            || finalized.planId !== payload.planId
            || finalized.status !== payload.status
          ) {
            throw new Error("Durable ledger returned a mismatched finalization response");
          }
          return finalized;
        };
        if (!execution) return finishExactly(input);
        if (input.status === "completed") {
          try {
            const finalized = await finishExactly({
              ...input,
              resultSummary: sanitizedResultSummary(input, execution),
            });
            execution.durableFinalized = true;
            execution.durablePlanId = input.planId;
            return finalized;
          } catch {
            execution.error = finalizationAmbiguity(execution, input.planId);
            emitReconciliationEvent(execution, "durable_completion_unknown", input.planId);
            throw execution.error;
          }
        }
        if (
          input.status === "failed"
          && ["succeeded", "ambiguous"].includes(execution.providerOutcome)
        ) {
          const guarded = execution.error
            || failureForState(currentState(), "local_processing_failed", "post_provider_local_failure");
          if (execution.durableFinalized) {
            emitReconciliationEvent(execution, "response_delivery_failed", input.planId);
            throw guarded;
          }
          try {
            const finalized = await finishExactly({
              planId: input.planId,
              // `failed` is intentionally terminal and non-success for every
              // status-only consumer. Exact provider truth remains in the
              // bounded error envelope, including reconciliationRequired and
              // mutationState. A claimed plan cannot be executed again.
              status: "failed",
              durationMs: input.durationMs,
              error: guarded.message,
            });
            execution.durableFinalized = true;
            execution.durablePlanId = input.planId;
            execution.durablePlanStatus = "failed";
          } catch {
            execution.error = finalizationAmbiguity(execution, input.planId);
            emitReconciliationEvent(execution, "durable_completion_unknown", input.planId);
            throw execution.error;
          }
          throw guarded;
        }
        try {
          const finalized = await finishExactly(input);
          execution.durableFinalized = true;
          execution.durablePlanId = input.planId;
          return finalized;
        } catch {
          execution.error = finalizationAmbiguity(execution, input.planId);
          emitReconciliationEvent(execution, "durable_completion_unknown", input.planId);
          throw execution.error;
        }
      };
    },
  });

  return Object.freeze({
    execute,
    ledger,
    preparePresentation,
    currentState,
    recordResponseFailure(error, phase, planId) {
      return recordResponseFailureForState(currentState(), error, phase, planId);
    },
    recordResponseFailureForState,
    run(operation) {
      return storage.run({ execution: null }, operation);
    },
  });
}
