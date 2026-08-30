
'use strict';

const { assertNoCredentialMaterial } = require('../security/secret-boundary.js');
const { digestValue } = require('../lineage/ai-execution-receipt.js');

/** @type {Readonly<Record<string, number>>} */
const REASONING_RANK = Object.freeze({ low: 1, standard: 2, high: 3 });

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => requiredText(item, `${field}[${index}]`));
}

/** @param {unknown} value */
function primitiveRefs(value) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError('primitiveSelections must be an array');
  return value.map((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new TypeError(`primitiveSelections[${index}] must be an object`);
    const input = /** @type {Record<string, unknown>} */ (item);
    return Object.freeze({
      id: requiredText(input.id, `primitiveSelections[${index}].id`),
      version: requiredText(input.version, `primitiveSelections[${index}].version`),
      digest: typeof input.digest === 'string' && input.digest.trim() ? input.digest.trim() : null,
    });
  });
}

/** @param {Readonly<Record<string, unknown>>[]} skills */
function aggregateModelRequirements(skills) {
  let reasoning = 'low';
  let vision = false;
  let minContextTokens = 0;
  for (const skill of skills) {
    const requirements = skill.modelRequirements && typeof skill.modelRequirements === 'object'
      ? /** @type {Readonly<Record<string, unknown>>} */ (skill.modelRequirements)
      : {};
    const candidateReasoning = typeof requirements.reasoning === 'string' ? requirements.reasoning : 'standard';
    if ((REASONING_RANK[candidateReasoning] ?? 0) > (REASONING_RANK[reasoning] ?? 0)) reasoning = candidateReasoning;
    if (requirements.vision === true) vision = true;
    if (typeof requirements.minContextTokens === 'number' && requirements.minContextTokens > minContextTokens) minContextTokens = requirements.minContextTokens;
  }
  return Object.freeze({ reasoning, vision, minContextTokens: minContextTokens || null });
}

/** @param {Iterable<string>} values */
function sortedUnique(values) {
  return [...new Set(values)].sort();
}

class IntelligenceComposer {
  /**
   * @param {{
   *   skillRegistry:{findByCapability:(query:Record<string, unknown>)=>Readonly<Record<string, unknown>>[]},
   *   knowledgeRegistry:{findRelevant:(query:Record<string, unknown>)=>Readonly<Record<string, unknown>>[]}
   * }} options
   */
  constructor({ skillRegistry, knowledgeRegistry }) {
    if (!skillRegistry || typeof skillRegistry.findByCapability !== 'function') throw new TypeError('skillRegistry is required');
    if (!knowledgeRegistry || typeof knowledgeRegistry.findRelevant !== 'function') throw new TypeError('knowledgeRegistry is required');
    this.skillRegistry = skillRegistry;
    this.knowledgeRegistry = knowledgeRegistry;
  }

  /**
   * @param {{
   *   projectId:string,
   *   projectVersionId?:string,
   *   projectType?:string,
   *   task:string,
   *   capabilities:string[],
   *   knowledgeTopics?:string[],
   *   knowledgeQuery?:string,
   *   maxRisk?:string,
   *   projectSpec?:unknown,
   *   projectContext?:unknown,
   *   primitiveSelections?:unknown[]
   * }} input
   */
  compose(input) {
    assertNoCredentialMaterial(input);
    const projectId = requiredText(input.projectId, 'projectId');
    const task = requiredText(input.task, 'task');
    const capabilities = stringList(input.capabilities, 'capabilities');
    if (!capabilities.length) throw new TypeError('capabilities must not be empty');
    const maxRisk = input.maxRisk ?? 'PRIVILEGED';

    /** @type {Readonly<Record<string, unknown>>[]} */
    const selectedSkills = [];
    /** @type {string[]} */
    const missingCapabilities = [];
    const seenSkills = new Set();
    for (const capability of capabilities) {
      const candidates = this.skillRegistry.findByCapability({
        capabilities: [capability],
        projectType: input.projectType,
        maxRisk,
        trustedOnly: true,
      }).slice().sort((a, b) => `${String(a.skillId)}@${String(a.version)}`.localeCompare(`${String(b.skillId)}@${String(b.version)}`));
      if (!candidates.length) {
        missingCapabilities.push(capability);
        continue;
      }
      const selected = candidates[0];
      const key = `${String(selected.skillId)}@${String(selected.version)}`;
      if (!seenSkills.has(key)) {
        seenSkills.add(key);
        selectedSkills.push(selected);
      }
    }

    const skillKnowledge = selectedSkills.flatMap((skill) => Array.isArray(skill.requiredKnowledge) ? skill.requiredKnowledge.map(String) : []);
    const knowledgeTopics = sortedUnique([...stringList(input.knowledgeTopics, 'knowledgeTopics'), ...skillKnowledge]);
    const knowledge = this.knowledgeRegistry.findRelevant({
      topics: knowledgeTopics,
      query: input.knowledgeQuery ?? task,
      maxRisk,
      trustedOnly: true,
      limit: 12,
    });

    const requiredTools = sortedUnique(selectedSkills.flatMap((skill) => Array.isArray(skill.requiredTools) ? skill.requiredTools.map(String) : []));
    const requiredPrimitives = sortedUnique(selectedSkills.flatMap((skill) => Array.isArray(skill.requiredPrimitives) ? skill.requiredPrimitives.map(String) : []));
    const primitives = primitiveRefs(input.primitiveSelections);
    const projectSpecDigest = digestValue(input.projectSpec ?? null);
    const projectContextDigest = digestValue(input.projectContext ?? null);

    const result = {
      projectId,
      projectVersionId: typeof input.projectVersionId === 'string' && input.projectVersionId.trim() ? input.projectVersionId.trim() : null,
      task,
      capabilities: Object.freeze(capabilities),
      ready: missingCapabilities.length === 0,
      missingCapabilities: Object.freeze(missingCapabilities),
      skillRefs: Object.freeze(selectedSkills.map((skill) => Object.freeze({
        id: String(skill.skillId),
        version: String(skill.version),
        digest: typeof skill.sourceDigest === 'string' ? skill.sourceDigest : null,
      }))),
      knowledgeRefs: Object.freeze(knowledge.map((entry) => Object.freeze({
        id: String(entry.knowledgeId),
        version: String(entry.version),
        digest: typeof entry.sourceDigest === 'string' ? entry.sourceDigest : null,
      }))),
      primitiveRefs: Object.freeze(primitives),
      requiredTools: Object.freeze(requiredTools),
      requiredPrimitives: Object.freeze(requiredPrimitives),
      modelRequirements: aggregateModelRequirements(selectedSkills),
      projectSpecDigest,
      projectContextDigest,
      executionAuthority: 'worker_c_only',
    };
    assertNoCredentialMaterial(result);
    return Object.freeze({ ...result, compositionDigest: digestValue(result) });
  }
}

module.exports = {
  IntelligenceComposer,
  aggregateModelRequirements,
};
