"use strict";

const { randomUUID, createHash } = require("node:crypto");
const { redactDeep } = require("./redaction");

function boundedOutput(output, maxOutputBytes) {
  if (output == null) return output;
  const encoded = Buffer.from(JSON.stringify(output), "utf8");
  if (encoded.length <= maxOutputBytes) return output;
  return Object.freeze({
    truncated: true,
    byte_length: encoded.length,
    sha256: createHash("sha256").update(encoded).digest("hex"),
    message: "Tool output exceeded the inline receipt limit; use an artifact reference for large results.",
  });
}

function createToolReceipt({ tool_call_id, definition, organization_id, project_id, environment = null, action_hash = null, policy_version = null, risk = null, resource_scope = null, model_run_id = null, build_job_id = null, execution_id = randomUUID(), status, started_at, finished_at, retryable = false, artifacts = [], output = null, error = null, provenance = null, canaries = [], maxOutputBytes = 64 * 1024 }) {
  const safe = redactDeep({
    tool_call_id,
    tool: definition.name,
    tool_version: definition.version,
    status,
    organization_id,
    project_id,
    environment,
    action_hash,
    policy_version,
    risk,
    resource_scope,
    model_run_id,
    build_job_id,
    execution_id,
    artifacts,
    output: boundedOutput(output, maxOutputBytes),
    error,
    provenance,
    started_at,
    finished_at,
    retryable: retryable === true,
  }, { canaries });
  return Object.freeze(safe);
}

module.exports = { boundedOutput, createToolReceipt };
