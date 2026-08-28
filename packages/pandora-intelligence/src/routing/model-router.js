'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');

/** @type {Readonly<Record<string, number>>} */
const RELIABILITY_RANK = Object.freeze({ high: 3, standard: 2, experimental: 1 });
/** @type {Readonly<Record<string, number>>} */
const COST_RANK = Object.freeze({ low: 1, medium: 2, high: 3 });

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
/** @param {unknown} value @param {string} field */
function requiredText(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }

class ModelRouter {
  /** @param {{registry:{findCompatible:(requirements:{required?:string[],outputMode?:string,minContext?:number})=>Readonly<Record<string,unknown>>[]}, adapters?:Record<string,{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}>}} options */
  constructor({ registry, adapters = {} }) {
    if (!registry || typeof registry.findCompatible !== 'function') throw new TypeError('model capability registry is required');
    this.registry = registry;
    /** @type {Map<string,{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}>} */
    this.adapters = new Map();
    for (const [provider, adapter] of Object.entries(adapters)) this.registerAdapter(provider, adapter);
  }

  /** @param {string} provider @param {{execute:(request:Record<string,unknown>,declaration:Record<string,unknown>)=>Promise<unknown>}} adapter */
  registerAdapter(provider, adapter) {
    const name = requiredText(provider, 'provider');
    if (!adapter || typeof adapter.execute !== 'function') throw new TypeError('provider adapter.execute is required');
    this.adapters.set(name, adapter);
    return this;
  }

  /** @param {Record<string,unknown>} request @param {{preferredProvider?:string,preferredModel?:string,minContext?:number}} options */
  candidates(request, options = {}) {
    assertNoCredentialMaterial(request);
    const required = Array.isArray(request.requiredCapabilities) ? request.requiredCapabilities.map(String) : [];
    const compatible = this.registry.findCompatible({ required, outputMode: String(request.outputMode ?? 'structured'), minContext: options.minContext });
    const filtered = compatible.filter(model => this.adapters.has(String(model.provider)));
    filtered.sort((a, b) => score(b, options) - score(a, options));
    return filtered;
  }

  /** @param {Record<string,unknown>} request @param {{preferredProvider?:string,preferredModel?:string,minContext?:number}} options */
  async execute(request, options = {}) {
    assertNoCredentialMaterial(request);
    const candidates = this.candidates(request, options);
    if (!candidates.length) {
      throw Object.assign(new Error('no compatible model provider is available'), { code: 'unsupported_capability' });
    }
    /** @type {unknown[]} */
    const failures = [];
    for (const declaration of candidates) {
      const provider = String(declaration.provider);
      const adapter = this.adapters.get(provider);
      if (!adapter) continue;
      try {
        const result = await adapter.execute(request, declaration);
        assertNoCredentialMaterial(result);
        if (!isRecord(result)) throw new Error('provider adapter returned an invalid normalized result');
        const normalized = /** @type {Record<string, unknown>} */ (result);
        return Object.freeze({ ...normalized, routedProvider: provider, routedModel: String(declaration.modelId), fallbackUsed: failures.length > 0, attempts: failures.length + 1 });
      } catch (error) {
        failures.push(error);
        const failure = /** @type {Record<string, unknown>} */ (isRecord(error) ? error : {});
        const retryable = failure.retryable === true;
        if (!retryable) throw error;
      }
    }
    const last = failures[failures.length - 1];
    if (last) throw last;
    throw new Error('model routing failed without a provider result');
  }
}

/** @param {Readonly<Record<string,unknown>>} model @param {{preferredProvider?:string,preferredModel?:string}} options */
function score(model, options) {
  let value = 0;
  if (options.preferredProvider && model.provider === options.preferredProvider) value += 1000;
  if (options.preferredModel && model.modelId === options.preferredModel) value += 2000;
  value += (RELIABILITY_RANK[String(model.reliabilityClass)] ?? 0) * 100;
  value -= (COST_RANK[String(model.costClass)] ?? 9) * 10;
  if (model.latencyClass === 'interactive') value += 5;
  return value;
}

module.exports = { ModelRouter, score };
