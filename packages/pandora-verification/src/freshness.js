
"use strict";

const { CHECK_REGISTRY } = require("./registry");

const DEFAULT_FRESHNESS_WINDOWS_MS = Object.freeze({
  exact_source: null,
  exact_artifact: null,
  exact_source_and_artifact: null,
  exact_migration_set: null,
  exact_source_and_environment: 60 * 60 * 1000,
  exact_deployment: 30 * 60 * 1000,
  exact_spec_and_deployment: 30 * 60 * 1000,
  exact_schema_state: 30 * 60 * 1000,
  exact_production_deployment: 10 * 60 * 1000,
});

function freshnessWindowForCheck(checkId, overrides = {}) {
  const definition = CHECK_REGISTRY[checkId];
  if (!definition) throw new Error(`unknown verification check: ${checkId}`);
  const value = Object.prototype.hasOwnProperty.call(overrides, definition.freshnessScope)
    ? overrides[definition.freshnessScope]
    : DEFAULT_FRESHNESS_WINDOWS_MS[definition.freshnessScope];
  if (value == null) return null;
  if (!Number.isFinite(value) || value <= 0) throw new Error(`invalid freshness window for ${definition.freshnessScope}`);
  return value;
}

function freshnessExpiry(checkId, recordedAt, overrides = {}) {
  const windowMs = freshnessWindowForCheck(checkId, overrides);
  if (windowMs == null) return null;
  const start = new Date(recordedAt).getTime();
  if (!Number.isFinite(start)) throw new Error("recordedAt must be a valid timestamp");
  return new Date(start + windowMs).toISOString();
}

function isExpired(result, now = Date.now()) {
  if (!result?.expires_at) return false;
  const expiry = new Date(result.expires_at).getTime();
  return !Number.isFinite(expiry) || expiry <= now;
}

function evaluateFreshness(requiredChecks, results, now = Date.now()) {
  const required = new Set(requiredChecks ?? []);
  const expired = (results ?? [])
    .filter((result) => required.has(result.check_id) && result.status === "PASS" && isExpired(result, now))
    .map((result) => result.check_id);
  return Object.freeze({
    state: expired.length ? "expired" : "current",
    expired_checks: Object.freeze([...new Set(expired)]),
    evaluated_at: new Date(now).toISOString(),
  });
}

module.exports = { DEFAULT_FRESHNESS_WINDOWS_MS, freshnessWindowForCheck, freshnessExpiry, isExpired, evaluateFreshness };
