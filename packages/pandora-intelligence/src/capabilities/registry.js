'use strict';

const {
  COST_CLASSES,
  LATENCY_CLASSES,
  RELIABILITY_CLASSES,
} = require('../contracts/model.js');

const CAPABILITY_KEYS = Object.freeze([
  'reasoning',
  'coding',
  'multimodal',
  'imageUnderstanding',
  'structuredOutput',
  'toolCalling',
  'longContext',
  'classification',
  'summarization',
  'copywriting',
]);

class ModelCapabilityRegistry {
  constructor() {
    /** @type {Map<string, Readonly<Record<string, unknown>>>} */
    this.models = new Map();
  }

  /** @param {Record<string, unknown>} declaration */
  register(declaration) {
    const normalized = normalizeDeclaration(declaration);
    const key = `${normalized.provider}:${normalized.modelId}`;
    if (this.models.has(key)) {
      throw new Error(`model capability already registered: ${key}`);
    }
    this.models.set(key, normalized);
    return normalized;
  }

  /** @param {string} provider @param {string} modelId */
  get(provider, modelId) {
    return this.models.get(`${provider}:${modelId}`) ?? null;
  }

  /**
   * @param {{required?: string[], outputMode?: string, minContext?: number}} requirements
   */
  findCompatible(requirements = {}) {
    const required = requirements.required ?? [];
    return [...this.models.values()].filter((model) => {
      const capabilities = /** @type {Record<string, boolean>} */ (
        model.capabilities
      );
      if (!required.every((key) => capabilities[key] === true)) return false;

      const outputModes = /** @type {string[]} */ (model.outputModes);
      if (requirements.outputMode && !outputModes.includes(requirements.outputMode)) {
        return false;
      }
      if (
        requirements.minContext &&
        Number(model.maxContextTokens) < requirements.minContext
      ) {
        return false;
      }
      return model.enabled !== false;
    });
  }

  list() {
    return [...this.models.values()];
  }
}

/** @param {Record<string, unknown>} input */
function normalizeDeclaration(input) {
  if (typeof input.provider !== 'string' || input.provider.trim() === '') {
    throw new TypeError('provider is required');
  }
  if (typeof input.modelId !== 'string' || input.modelId.trim() === '') {
    throw new TypeError('modelId is required');
  }
  if (!Number.isInteger(input.maxContextTokens) || Number(input.maxContextTokens) <= 0) {
    throw new TypeError('maxContextTokens must be positive');
  }
  if (!LATENCY_CLASSES.includes(String(input.latencyClass))) {
    throw new TypeError('invalid latencyClass');
  }
  if (!COST_CLASSES.includes(String(input.costClass))) {
    throw new TypeError('invalid costClass');
  }
  if (!RELIABILITY_CLASSES.includes(String(input.reliabilityClass))) {
    throw new TypeError('invalid reliabilityClass');
  }
  if (!Array.isArray(input.outputModes) || input.outputModes.length === 0) {
    throw new TypeError('outputModes is required');
  }

  /** @type {Record<string, unknown>} */
  const sourceCapabilities =
    input.capabilities && typeof input.capabilities === 'object'
      ? /** @type {Record<string, unknown>} */ (input.capabilities)
      : {};

  /** @type {Record<string, boolean>} */
  const capabilities = {};
  for (const key of CAPABILITY_KEYS) {
    capabilities[key] = sourceCapabilities[key] === true;
  }

  return Object.freeze({
    provider: input.provider,
    modelId: input.modelId,
    capabilities: Object.freeze(capabilities),
    latencyClass: input.latencyClass,
    costClass: input.costClass,
    reliabilityClass: input.reliabilityClass,
    maxContextTokens: input.maxContextTokens,
    outputModes: Object.freeze(input.outputModes.map(String)),
    enabled: input.enabled !== false,
    metadata: Object.freeze(
      input.metadata && typeof input.metadata === 'object' ? input.metadata : {},
    ),
  });
}

module.exports = {
  CAPABILITY_KEYS,
  ModelCapabilityRegistry,
  normalizeDeclaration,
};
