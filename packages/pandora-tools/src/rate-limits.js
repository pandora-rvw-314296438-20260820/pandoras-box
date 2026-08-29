"use strict";

const { PandoraToolError } = require("./errors");

function bucketKey(scope) {
  return [scope.organization_id, scope.project_id, scope.model_run_id || "-", scope.build_job_id || "-", scope.tool, scope.environment].join("|");
}

class MemoryRateLimitStore {
  constructor() { this.durability = "memory"; this.buckets = new Map(); }
  async increment(key, windowStartMs) {
    const current = this.buckets.get(key);
    if (!current || current.windowStartMs !== windowStartMs) {
      const next = { windowStartMs, count: 1 }; this.buckets.set(key, next); return { ...next };
    }
    current.count += 1; return { ...current };
  }
}

class RateLimitGuard {
  constructor(store) { this.store = store; }
  async consume(scope, { max_calls, window_ms }, now = new Date()) {
    if (!Number.isInteger(max_calls) || max_calls < 1 || !Number.isInteger(window_ms) || window_ms < 1000) throw new PandoraToolError("internal", "RATE_POLICY_INVALID", "Rate-limit policy is invalid");
    const start = Math.floor(now.getTime() / window_ms) * window_ms;
    const result = await this.store.increment(bucketKey(scope), start);
    if (result.count > max_calls) throw new PandoraToolError("rate_limit", "TOOL_RATE_LIMIT_EXCEEDED", "Tool-call rate limit exceeded", { retry_after_ms: start + window_ms - now.getTime() });
    return { remaining: max_calls - result.count, reset_at: new Date(start + window_ms).toISOString() };
  }
}

module.exports = { bucketKey, MemoryRateLimitStore, RateLimitGuard };
