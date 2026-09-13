"use strict";

const { TOOL_DECISIONS } = require("./contracts");
const { PandoraToolError } = require("./errors");

const TOOL_CHAIN_STATES = Object.freeze({
  COMPLETED: "completed",
  NEEDS_APPROVAL: "needs_approval",
  DENIED: "denied",
  VERIFICATION_REQUIRED: "verification_required",
  FAILED: "failed",
  CANCELLED: "cancelled",
});

class PandoraToolChainExecutor {
  constructor({ executor, maxSteps = 32 }) {
    if (!executor || typeof executor.handle !== "function") {
      throw new PandoraToolError("internal", "TOOL_CHAIN_EXECUTOR_INVALID", "Tool chain requires an authority-aware tool executor or gateway");
    }
    if (!Number.isInteger(maxSteps) || maxSteps < 1 || maxSteps > 128) {
      throw new PandoraToolError("invalid_request", "TOOL_CHAIN_LIMIT_INVALID", "Tool chain step limit is invalid");
    }
    this.executor = executor;
    this.maxSteps = maxSteps;
  }

  async run({ steps, context = {}, signal = null }) {
    if (!Array.isArray(steps) || steps.length < 1) {
      throw new PandoraToolError("invalid_request", "TOOL_CHAIN_EMPTY", "Tool chain must contain at least one step");
    }
    if (steps.length > this.maxSteps) {
      throw new PandoraToolError("invalid_request", "TOOL_CHAIN_TOO_LARGE", "Tool chain exceeds the configured step limit");
    }

    const results = [];
    for (let index = 0; index < steps.length; index += 1) {
      if (signal?.aborted === true) {
        return Object.freeze({
          state: TOOL_CHAIN_STATES.CANCELLED,
          completed_steps: results.length,
          blocked_step: index,
          results: Object.freeze(results),
        });
      }

      const step = steps[index];
      if (!step || typeof step !== "object" || Array.isArray(step) || !step.proposal) {
        throw new PandoraToolError("invalid_request", "TOOL_CHAIN_STEP_INVALID", `Tool chain step ${index} is invalid`);
      }
      const stepContext = Object.freeze({
        ...context,
        ...(step.context || {}),
      });
      const result = await this.executor.handle(step.proposal, stepContext);
      results.push(Object.freeze({ index, id: step.id || null, result }));

      if (result.receipt?.status === "failed") {
        const ambiguous = result.receipt.error?.error_class === "ambiguous_mutation";
        return Object.freeze({
          state: ambiguous ? TOOL_CHAIN_STATES.VERIFICATION_REQUIRED : TOOL_CHAIN_STATES.FAILED,
          completed_steps: index,
          blocked_step: index,
          results: Object.freeze(results),
        });
      }

      if (result.replayed === true && result.receipt?.status === "succeeded") continue;
      if (result.executed === true) continue;

      if (result.decision?.disposition === TOOL_DECISIONS.REQUIRE_APPROVAL) {
        return Object.freeze({
          state: TOOL_CHAIN_STATES.NEEDS_APPROVAL,
          completed_steps: index,
          blocked_step: index,
          results: Object.freeze(results),
        });
      }
      if (result.decision?.disposition === TOOL_DECISIONS.DENY) {
        return Object.freeze({
          state: TOOL_CHAIN_STATES.DENIED,
          completed_steps: index,
          blocked_step: index,
          results: Object.freeze(results),
        });
      }

      return Object.freeze({
        state: TOOL_CHAIN_STATES.FAILED,
        completed_steps: index,
        blocked_step: index,
        results: Object.freeze(results),
      });
    }

    return Object.freeze({
      state: TOOL_CHAIN_STATES.COMPLETED,
      completed_steps: results.length,
      blocked_step: null,
      results: Object.freeze(results),
    });
  }
}

module.exports = { TOOL_CHAIN_STATES, PandoraToolChainExecutor };
