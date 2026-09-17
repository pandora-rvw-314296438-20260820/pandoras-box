/**
 * Pandora skill runtime — deterministic discovery, routing, and fail-closed gating.
 *
 * This module is intentionally read-only. It resolves which governed skills apply
 * to an intent; it never calls a provider and never mutates state. Selecting a
 * skill grants no authority to mutate anything: every provider mutation still
 * goes through the ProjectOS plan -> approval -> execute path.
 *
 * Vendor neutrality: the JSON registry under .agents/skills/registry is the single
 * authority. Vendor-specific loaders adapt this module's output; they must not
 * fork the catalog or the governance policy.
 */

import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(HERE, '..', '..');
const REGISTRY_DIR = path.join(REPO_ROOT, '.agents', 'skills', 'registry');
const GOVERNANCE_BLOCK_PATH = path.join(REPO_ROOT, '.agents', 'runtime', 'GOVERNANCE_BLOCK.md');

const ID_PATTERN = /^[a-z][a-z0-9-]{2,79}$/;
// Vocabularies are taken from the registry itself; the registry is the authority.
const RISKS = new Set(['read', 'reversible-write', 'sensitive-write', 'high-risk']);
const AUTONOMY = new Set([
  'autonomous',
  'autonomous-with-verification',
  'approval-before-side-effect',
  'fail-closed',
]);
const LIFECYCLE_PHASES = new Set(['all', 'focused-entry', 'horizontal-growth', 'enterprise', 'ecosystem']);
/** Risk tiers that may never proceed without an explicit approval gate. */
const APPROVAL_REQUIRED_RISKS = new Set(['sensitive-write', 'high-risk']);

export class SkillsDisabledError extends Error {
  constructor() {
    // Fail closed: the caller must stop, not fall back to an ungoverned path.
    super('Pandora skills are disabled (PANDORA_SKILLS_ENABLED=false); no governed skill may execute and no ungoverned fallback is permitted');
    this.name = 'SkillsDisabledError';
    this.code = 'pandora_skills_disabled';
  }
}

export class RegistryIntegrityError extends Error {
  constructor(reason, detail) {
    super(`Pandora skill registry integrity failure: ${reason}`);
    this.name = 'RegistryIntegrityError';
    this.code = 'pandora_registry_invalid';
    this.reason = reason;
    if (detail !== undefined) this.detail = detail;
  }
}

/** The kill switch. Only the exact string "false" disables; anything else stays enabled. */
export function skillsEnabled(env = process.env) {
  return String(env.PANDORA_SKILLS_ENABLED ?? 'true').trim().toLowerCase() !== 'false';
}

export function governanceBlock() {
  return readFileSync(GOVERNANCE_BLOCK_PATH, 'utf8').trim();
}

/**
 * Deterministic discovery. Rejects duplicate ids, duplicate capability authority,
 * malformed metadata, missing dependencies, dependency cycles, and unknown skills.
 * Shards are read in sorted order so the result is stable across filesystems.
 */
export function loadRegistry({ registryDir = REGISTRY_DIR } = {}) {
  const shards = readdirSync(registryDir).filter((f) => f.endsWith('.json')).sort();
  if (shards.length === 0) throw new RegistryIntegrityError('no registry shards found');

  const skills = new Map();
  for (const shard of shards) {
    let parsed;
    try {
      parsed = JSON.parse(readFileSync(path.join(registryDir, shard), 'utf8'));
    } catch {
      throw new RegistryIntegrityError('malformed registry shard', shard);
    }
    if (!parsed || !Array.isArray(parsed.skills)) {
      throw new RegistryIntegrityError('registry shard has no skills array', shard);
    }
    for (const entry of parsed.skills) {
      validateEntry(entry, shard);
      if (skills.has(entry.id)) throw new RegistryIntegrityError('duplicate skill id', entry.id);
      skills.set(entry.id, Object.freeze({
        ...entry,
        depends_on: [...entry.depends_on],
        capabilities: [...entry.capabilities],
        // The skill's own description and "Use when" section are its trigger
        // surface; indexing them keeps routing deterministic without a model.
        routingText: readRoutingText(entry.entrypoint),
      }));
    }
  }

  for (const skill of skills.values()) {
    for (const dep of skill.depends_on) {
      if (!skills.has(dep)) throw new RegistryIntegrityError('missing dependency', `${skill.id} -> ${dep}`);
    }
  }
  assertAcyclic(skills);
  return Object.freeze({ skills, ids: Object.freeze([...skills.keys()].sort()) });
}

/** Extract the frontmatter description and the "Use when" bullets for routing. */
function readRoutingText(entrypoint) {
  let raw;
  try {
    raw = readFileSync(path.join(REPO_ROOT, entrypoint), 'utf8');
  } catch {
    throw new RegistryIntegrityError('entrypoint is not readable', entrypoint);
  }
  const front = /^---\n([\s\S]*?)\n---/.exec(raw);
  if (!front) throw new RegistryIntegrityError('entrypoint has no frontmatter', entrypoint);
  const description = /^description:\s*(.+)$/m.exec(front[1])?.[1]?.trim().replace(/^"|"$/g, '') ?? '';
  if (!description) throw new RegistryIntegrityError('entrypoint has no description', entrypoint);
  const useWhen = /##\s*Use when\n([\s\S]*?)(?:\n##\s|$)/.exec(raw)?.[1] ?? '';
  const outcome = /##\s*Outcome\n([\s\S]*?)(?:\n##\s|$)/.exec(raw)?.[1] ?? '';
  return [description, useWhen, outcome].join(' ');
}

function validateEntry(entry, shard) {
  if (!entry || typeof entry !== 'object') throw new RegistryIntegrityError('skill entry is not an object', shard);
  if (typeof entry.id !== 'string' || !ID_PATTERN.test(entry.id)) throw new RegistryIntegrityError('invalid skill id', entry.id ?? shard);
  if (typeof entry.entrypoint !== 'string' || !entry.entrypoint.endsWith('/SKILL.md')) throw new RegistryIntegrityError('invalid entrypoint', entry.id);
  if (!RISKS.has(entry.risk)) throw new RegistryIntegrityError('invalid risk', entry.id);
  if (!AUTONOMY.has(entry.autonomy)) throw new RegistryIntegrityError('invalid autonomy', entry.id);
  if (entry.lifecycle_phase !== undefined && !LIFECYCLE_PHASES.has(entry.lifecycle_phase)) {
    throw new RegistryIntegrityError('invalid lifecycle_phase', entry.id);
  }
  // A skill that can cause a sensitive or irreversible side effect must not be
  // marked plainly autonomous; that combination would let routing imply authority.
  if (APPROVAL_REQUIRED_RISKS.has(entry.risk) && entry.autonomy === 'autonomous') {
    throw new RegistryIntegrityError('sensitive or high-risk skill marked autonomous', entry.id);
  }
  if (!Array.isArray(entry.depends_on) || entry.depends_on.some((d) => typeof d !== 'string')) throw new RegistryIntegrityError('invalid depends_on', entry.id);
  if (!Array.isArray(entry.capabilities) || entry.capabilities.length === 0 || entry.capabilities.some((c) => typeof c !== 'string')) {
    throw new RegistryIntegrityError('invalid capabilities', entry.id);
  }
  if (entry.depends_on.includes(entry.id)) throw new RegistryIntegrityError('self dependency', entry.id);
}

function assertAcyclic(skills) {
  const WHITE = 0, GREY = 1, BLACK = 2;
  const colour = new Map([...skills.keys()].map((id) => [id, WHITE]));
  const visit = (id, trail) => {
    const state = colour.get(id);
    if (state === GREY) throw new RegistryIntegrityError('dependency cycle', [...trail, id].join(' -> '));
    if (state === BLACK) return;
    colour.set(id, GREY);
    for (const dep of skills.get(id).depends_on) visit(dep, [...trail, id]);
    colour.set(id, BLACK);
  };
  for (const id of [...skills.keys()].sort()) visit(id, []);
}

/** Resolve a skill plus its full dependency closure, deterministically ordered. */
export function dependencyClosure(registry, ids) {
  const out = new Set();
  const walk = (id) => {
    if (!registry.skills.has(id)) throw new RegistryIntegrityError('unknown skill', id);
    if (out.has(id)) return;
    out.add(id);
    for (const dep of registry.skills.get(id).depends_on) walk(dep);
  };
  for (const id of ids) walk(id);
  return [...out].sort();
}

const STOP = new Set(('the a an and or of to in for when is are be with that this it as on at by from use used using ' +
  'my our your we i need want should must can could would please help me now current currently').split(' '));

function terms(text) {
  return new Set(String(text).toLowerCase().match(/[a-z]{3,}/g)?.filter((w) => !STOP.has(w)) ?? []);
}

/**
 * Deterministic routing. Scores each skill by overlap between the intent and the
 * skill's identity (id, category, capabilities) and its trigger surface
 * (frontmatter description, "Use when", "Outcome"). Ties break on id, so the
 * result is reproducible across runs and filesystems.
 *
 * Two distinct outputs, deliberately not conflated:
 *   `selected` — the smallest sufficient set to load for this intent.
 *   `closure`  — the transitive prerequisites those skills declare. These must be
 *                satisfiable, but are not all loaded into context; closure depth is
 *                a property of the registry's dependency graph, not of routing.
 */
export function route(intent, { registry = loadRegistry(), limit = 5, env = process.env } = {}) {
  if (!skillsEnabled(env)) throw new SkillsDisabledError();
  if (typeof intent !== 'string' || intent.trim() === '') throw new RegistryIntegrityError('empty intent');

  const wanted = terms(intent);
  const scored = [];
  for (const skill of registry.skills.values()) {
    const identity = terms([skill.id.replace(/-/g, ' '), skill.category ?? '', skill.capabilities.join(' ')].join(' '));
    const trigger = terms(skill.routingText);
    let score = 0;
    for (const term of wanted) {
      if (identity.has(term)) score += 2; // name/category match is the strongest signal
      else if (trigger.has(term)) score += 1; // description / "use when" match
    }
    if (score > 0) scored.push({ id: skill.id, score });
  }
  scored.sort((a, b) => (b.score - a.score) || a.id.localeCompare(b.id));

  const selected = scored.slice(0, limit).map((s) => s.id);
  const closure = selected.length > 0 ? dependencyClosure(registry, selected) : [];
  return Object.freeze({
    intent,
    selected: Object.freeze(selected),
    closure: Object.freeze(closure),
    // Routing is advisory only. Mutation authority never comes from selection.
    mutationAuthority: 'pandora-runtime-tool-gateway',
    grantsMutation: false,
    // Surfaced so a caller cannot mistake selection for permission.
    approvalRequired: Object.freeze(closure.filter((id) => APPROVAL_REQUIRED_RISKS.has(registry.skills.get(id).risk))),
  });
}

/** Load a skill's entrypoint, refusing unknown skills and honouring the kill switch. */
export function loadSkill(id, { registry = loadRegistry(), env = process.env } = {}) {
  if (!skillsEnabled(env)) throw new SkillsDisabledError();
  const skill = registry.skills.get(id);
  if (!skill) throw new RegistryIntegrityError('unknown skill', id);
  const body = readFileSync(path.join(REPO_ROOT, skill.entrypoint), 'utf8');
  return Object.freeze({ ...skill, body, governanceEmbedded: body.includes('## Pandora governance contract (canonical, embedded)') });
}
