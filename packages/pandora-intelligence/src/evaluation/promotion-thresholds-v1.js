'use strict';

const VERSION = 'pandora-kimi-promotion-thresholds-v1';
const BASE = Object.freeze({
  minSampleCount: 30,
  minQuality: 0.90,
  minReliability: 0.98,
  minVerifierPassRate: 0.95,
  maxFallbackRate: 0.05,
  securityRegressions: 0,
});

const BY_TASK_CLASS = Object.freeze({
  coding: Object.freeze({ ...BASE, minQuality: 0.95, minReliability: 0.99, maxLatencyMs: 45000, maxEstimatedCostUsd: 0.20 }),
  long_context: Object.freeze({ ...BASE, minQuality: 0.92, maxLatencyMs: 90000, maxEstimatedCostUsd: 0.50 }),
  structured_output: Object.freeze({ ...BASE, minQuality: 0.95, minStructuredOutputValidity: 0.995, maxLatencyMs: 30000, maxEstimatedCostUsd: 0.15 }),
  multimodal: Object.freeze({ ...BASE, minSampleCount: 20, minQuality: 0.92, maxLatencyMs: 60000, maxEstimatedCostUsd: 0.35 }),
  verification: Object.freeze({ ...BASE, minQuality: 0.97, minReliability: 0.995, minVerifierPassRate: 0.98, maxLatencyMs: 60000, maxEstimatedCostUsd: 0.30 }),
  failure_recovery: Object.freeze({ ...BASE, minQuality: 0.95, minReliability: 0.99, maxLatencyMs: 45000, maxEstimatedCostUsd: 0.20 }),
});

module.exports = Object.freeze({ VERSION, BASE, BY_TASK_CLASS });
