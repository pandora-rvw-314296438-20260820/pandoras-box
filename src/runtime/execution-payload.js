"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.executionPayloadHash = executionPayloadHash;
exports.stableValue = stableValue;

const { createHash } = require("node:crypto");

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, stableValue(nested)]),
    );
  }
  return value;
}

function executionPayloadHash(tool, args) {
  const canonical = JSON.stringify({ tool, args: stableValue(args) });
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}
