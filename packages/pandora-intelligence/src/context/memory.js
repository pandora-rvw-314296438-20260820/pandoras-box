'use strict';

const { assembleContext } = require('./context-engine.js');

const MEMORY_CLASSES = Object.freeze([
  'durable_decision', 'project_preference', 'business_fact', 'prior_failure',
  'reusable_lesson', 'customer_preference', 'historical_context',
]);

/** @type {Readonly<Record<string, number>>} */
const MEMORY_PRIORITY = Object.freeze({
  durable_decision: 100,
  business_fact: 90,
  project_preference: 85,
  prior_failure: 80,
  reusable_lesson: 70,
  customer_preference: 65,
  historical_context: 40,
});

/** @param {unknown} value */
function isRecord(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }

/**
 * @param {{memories:unknown[],task:string,maxTokens:number,maxItems?:number,nowMs?:number}} input
 */
function selectMemory(input) {
  const maxItems = Number.isInteger(input.maxItems) && Number(input.maxItems) > 0 ? Number(input.maxItems) : 8;
  /** @type {Array<Record<string, unknown>>} */
  const normalized = [];
  for (const memoryValue of Array.isArray(input.memories) ? input.memories : []) {
    if (!isRecord(memoryValue)) continue;
    const memory = /** @type {Record<string, unknown>} */ (memoryValue);
    const memoryClass = typeof memory.class === 'string' ? memory.class : '';
    if (!MEMORY_CLASSES.includes(memoryClass)) continue;
    const relevance = typeof memory.relevance === 'number' && Number.isFinite(memory.relevance) ? Math.max(0, Math.min(1, memory.relevance)) : 0.5;
    normalized.push({
      id: typeof memory.id === 'string' ? memory.id : `memory:${normalized.length}`,
      kind: memoryClass === 'durable_decision' ? 'durable_decision' : 'project_memory',
      memoryClass,
      content: memory.content,
      summary: memory.summary,
      relevance: Math.min(1, relevance + Number(MEMORY_PRIORITY[memoryClass] ?? 0) / 1000),
      updatedAt: memory.updatedAt ?? null,
      authoritative: false,
    });
  }
  normalized.sort((a, b) => Number(b.relevance) - Number(a.relevance));
  const bounded = normalized.slice(0, maxItems);
  const context = assembleContext({ task: input.task, sources: bounded, maxTokens: input.maxTokens, nowMs: input.nowMs });
  return Object.freeze({ ...context, authoritative: false, source: 'memory', memoryClasses: Object.freeze(bounded.map(item => String(item.memoryClass))) });
}

module.exports = { MEMORY_CLASSES, MEMORY_PRIORITY, selectMemory };
