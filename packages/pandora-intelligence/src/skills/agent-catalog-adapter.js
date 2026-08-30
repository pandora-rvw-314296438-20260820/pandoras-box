
'use strict';

const { normalizeSkillDefinition } = require('./registry.js');

/** @type {Readonly<Record<string, string>>} */
const AGENT_RISK_TO_TRUSTED_RISK = Object.freeze({
  read: 'READ_ONLY_DIAGNOSTIC',
  'reversible-write': 'SAFE_MUTATION',
  'sensitive-write': 'PRIVILEGED',
  'high-risk': 'DESTRUCTIVE',
});

/** @param {unknown} value @param {string} field */
function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

/** @param {unknown} value @param {string} field */
function stringList(value, field) {
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  return value.map((item, index) => requiredText(item, `${field}[${index}]`));
}

/** @param {unknown} value */
function sha256Digest(value) {
  const text = requiredText(value, 'contentDigest').toLowerCase();
  const normalized = text.startsWith('sha256:') ? text : `sha256:${text}`;
  if (!/^sha256:[0-9a-f]{64}$/.test(normalized)) throw new TypeError('contentDigest must be an exact sha256 digest');
  return normalized;
}

/**
 * Projects one entry from Pandora's existing vendor-neutral `.agents/skills`
 * source catalog into the Worker-B trust contract. This does not create a second
 * catalog and never promotes the entry: every projection starts EXPERIMENTAL and
 * still requires Worker E exact-digest evidence before TRUSTED use.
 *
 * @param {{
 *   catalog:Record<string, unknown>,
 *   entry:Record<string, unknown>,
 *   contentDigest:string,
 *   license?:string|null
 * }} input
 */
function projectAgentCatalogSkill(input) {
  if (!input || typeof input !== 'object') throw new TypeError('catalog projection input is required');
  const catalog = input.catalog;
  const entry = input.entry;
  if (!catalog || typeof catalog !== 'object' || Array.isArray(catalog)) throw new TypeError('catalog metadata is required');
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new TypeError('catalog skill entry is required');

  const schemaVersion = requiredText(catalog.schema_version, 'catalog.schema_version');
  if (schemaVersion !== '1.0.0') throw new TypeError(`unsupported catalog schema_version: ${schemaVersion}`);
  const catalogVersion = requiredText(catalog.catalog_version, 'catalog.catalog_version');
  const skillId = requiredText(entry.id, 'entry.id');
  const risk = requiredText(entry.risk, 'entry.risk');
  const riskClass = AGENT_RISK_TO_TRUSTED_RISK[risk];
  if (!riskClass) throw new TypeError(`unsupported catalog risk: ${risk}`);

  const autonomy = requiredText(entry.autonomy, 'entry.autonomy');
  const entrypoint = requiredText(entry.entrypoint, 'entry.entrypoint');
  if (entrypoint !== `.agents/skills/${skillId}/SKILL.md`) throw new TypeError('catalog entrypoint must exactly bind the skill id');

  return normalizeSkillDefinition({
    skillId,
    version: catalogVersion,
    description: `Pandora source-catalog skill (${requiredText(entry.category, 'entry.category')}; ${autonomy})`,
    capabilities: stringList(entry.capabilities, 'entry.capabilities'),
    dependsOn: stringList(entry.depends_on, 'entry.depends_on'),
    supportedProjectTypes: [],
    requiredKnowledge: [],
    requiredTools: [],
    requiredPrimitives: [],
    instructions: null,
    riskClass,
    trustState: 'EXPERIMENTAL',
    verificationProfile: 'pandora-agent-catalog-v1',
    sourceDigest: sha256Digest(input.contentDigest),
    source: {
      repository: requiredText(catalog.source_repository, 'catalog.source_repository'),
      commit: requiredText(catalog.source_base_sha, 'catalog.source_base_sha'),
      path: entrypoint,
      license: input.license == null ? null : requiredText(input.license, 'license'),
    },
    modelRequirements: { reasoning: 'standard', vision: false },
  });
}

/**
 * Registers projections into an existing Worker-B trusted-skill registry.
 * Caller supplies exact content digests from the validated Pandora skill manifest.
 * @param {{
 *   registry:{register:(input:Record<string, unknown>)=>unknown},
 *   catalog:Record<string, unknown>,
 *   entries:Record<string, unknown>[],
 *   contentDigests:Record<string,string>,
 *   license?:string|null
 * }} input
 */
function registerAgentCatalogProjections(input) {
  if (!input.registry || typeof input.registry.register !== 'function') throw new TypeError('trusted skill registry is required');
  if (!Array.isArray(input.entries)) throw new TypeError('catalog entries must be an array');
  const projected = [];
  for (const entry of input.entries) {
    const id = requiredText(entry.id, 'entry.id');
    const entrypoint = requiredText(entry.entrypoint, 'entry.entrypoint');
    const digest = input.contentDigests?.[entrypoint];
    if (!digest) throw new TypeError(`validated content digest missing for ${id}`);
    const definition = projectAgentCatalogSkill({
      catalog: input.catalog,
      entry,
      contentDigest: digest,
      license: input.license,
    });
    projected.push(input.registry.register({ ...definition }));
  }
  return Object.freeze(projected);
}

module.exports = {
  AGENT_RISK_TO_TRUSTED_RISK,
  projectAgentCatalogSkill,
  registerAgentCatalogProjections,
};
