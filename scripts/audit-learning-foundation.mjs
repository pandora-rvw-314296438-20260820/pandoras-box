/** P0-02: offline exact-source inventory, never an execution or trust registry. */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { devNull } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const AUDIT_VERSION = '1.0.0';
export const REPOSITORIES = Object.freeze({
  box: 'pandora-rvw-314296438-20260820/pandoras-box',
  memory: 'pandora-rvw-314296438-20260820/pandoras-box-memory',
});
const SHA = /^[0-9a-f]{40}$/;
const ID = /^[a-z0-9-]{1,64}$/;
const INDEX = '.agents/skills/registry.json';
const MAX_BYTES = 4 * 1024 * 1024;
const GROUPS = Object.freeze({
  box: {
    skill_catalog: [INDEX, '.agents/skills/registry.schema.json', '.agents/runtime/pandora-skill-runtime.mjs', 'scripts/validate-pandora-skills.mjs', 'docs/skills/PANDORA_SKILL_MANIFEST.sha256'],
    skill_trust_projection: ['packages/pandora-intelligence/src/skills/agent-catalog-adapter.js', 'packages/pandora-intelligence/src/skills/registry.js'],
    governed_context: ['packages/pandora-intelligence/src/prompts/trusted-context-bundle.js', 'packages/pandora-intelligence/src/prompts/trusted-material-registry.js'],
    existing_routing: ['packages/pandora-intelligence/src/routing/model-router.js', 'packages/pandora-intelligence/src/routing/policy.js', 'packages/pandora-intelligence/src/routing/fallback-policy.js'],
    operations_room: ['packages/pandora-operations-room/package.json'],
    separate_router: ['packages/pandora-intelligence-router/package.json'],
  },
  memory: {
    task_aware_retrieval: ['docs/architecture/M5_002_TASK_AWARE_RETRIEVAL.md', 'scripts/verify_m5_task_aware_retrieval.py', 'supabase/migrations/20260913143500_m5_task_aware_retrieval_v1.sql', 'tests/sql/m5_task_aware_retrieval_behavior.sql'],
    approved_canon: ['docs/capabilities/evidence/MEMORY_APPROVED_CANON_RETRIEVAL_GATE_2026-09-06.md', 'supabase/migrations/20260906043655_memory_approved_canon_retrieval_gate_v1_repair.sql'],
    machine_gateway: ['supabase/functions/pandora-machine-gateway/index.ts'],
  },
});

export class InventoryError extends Error {
  constructor(code) { super(code); this.name = 'InventoryError'; this.code = code; }
}
function requireThat(ok, code) { if (!ok) throw new InventoryError(code); }
function safePath(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 512
    && !/[\\\x00-\x1f\x7f]/.test(value) && !value.startsWith('/')
    && value.split('/').every((part) => part && part !== '.' && part !== '..');
}
function parseJson(text) {
  try { const value = JSON.parse(text); requireThat(value && typeof value === 'object' && !Array.isArray(value), 'INVALID_CATALOG'); return value; }
  catch { throw new InventoryError('INVALID_CATALOG'); }
}
function sha256(value) { return createHash('sha256').update(value).digest('hex'); }

/** No fetch, checkout, credential helper, hooks, provider calls, or audited-code execution. */
export function auditLearningFoundation({ repoPath, kind, sourceSha, timeoutMs = 15000 } = {}) {
  requireThat(Object.hasOwn(REPOSITORIES, kind), 'INVALID_REPOSITORY_KIND');
  requireThat(typeof repoPath === 'string' && repoPath.length > 0, 'INVALID_REPOSITORY_PATH');
  requireThat(typeof sourceSha === 'string' && SHA.test(sourceSha), 'EXACT_COMMIT_REQUIRED');
  requireThat(Number.isInteger(timeoutMs) && timeoutMs >= 1 && timeoutMs <= 30000, 'INVALID_TIME_BUDGET');
  const repository = REPOSITORIES[kind];
  const deadline = Date.now() + timeoutMs;
  const cwd = path.resolve(repoPath);
  // Ignore inherited repository/config redirection. Never copy credentials into output.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('GIT_')));
  Object.assign(env, {
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : devNull, GIT_NO_REPLACE_OBJECTS: '1',
    GIT_NO_LAZY_FETCH: '1', GIT_ALLOW_PROTOCOL: '', GIT_TERMINAL_PROMPT: '0', GIT_OPTIONAL_LOCKS: '0',
  });
  let bytesRead = 0;
  function git(args, encoding = 'utf8') {
    const remaining = deadline - Date.now();
    requireThat(remaining > 0, 'AUDIT_TIME_BUDGET_EXHAUSTED');
    try {
      const output = execFileSync('git', ['--no-replace-objects', '-C', cwd, ...args], {
        env, encoding, timeout: remaining, maxBuffer: MAX_BYTES, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
      });
      bytesRead += Buffer.byteLength(output);
      requireThat(bytesRead <= MAX_BYTES, 'AUDIT_BYTE_BUDGET_EXHAUSTED');
      return output;
    } catch (error) {
      if (error instanceof InventoryError) throw error;
      // Never serialize Git stderr, remote URLs, absolute paths, or environment values.
      throw new InventoryError(error.code === 'ETIMEDOUT' ? 'AUDIT_TIME_BUDGET_EXHAUSTED' : 'GIT_EVIDENCE_UNAVAILABLE');
    }
  }
  const origin = git(['config', '--get-all', 'remote.origin.url']).trim();
  requireThat([
    `https://github.com/${repository}`, `https://github.com/${repository}.git`,
    `git@github.com:${repository}`, `git@github.com:${repository}.git`,
    `ssh://git@github.com/${repository}`, `ssh://git@github.com/${repository}.git`,
  ].includes(origin), 'CANONICAL_REMOTE_BINDING_REQUIRED');
  requireThat(git(['cat-file', '-t', sourceSha]).trim() === 'commit', 'EXACT_COMMIT_REQUIRED');
  const treeSha = git(['rev-parse', `${sourceSha}^{tree}`]).trim();
  requireThat(SHA.test(treeSha), 'INVALID_TREE_RECEIPT');
  const rows = git(['ls-tree', '-r', '-z', '--full-tree', sourceSha]).split('\0').filter(Boolean);
  requireThat(rows.length <= 10000, 'TREE_ENTRY_BUDGET_EXHAUSTED');
  const tree = new Map();
  for (const row of rows) {
    const match = row.match(/^(\d{6}) (blob|commit) ([0-9a-f]{40})\t([\s\S]+)$/);
    requireThat(match && safePath(match[4]) && !tree.has(match[4]), 'INVALID_TREE_RECEIPT');
    tree.set(match[4], { mode: match[1], type: match[2], blobSha: match[3] });
  }
  const receipt = (relative) => {
    const entry = tree.get(relative);
    if (!entry) return { path: relative, state: 'source_missing_at_exact_commit' };
    return { path: relative, state: entry.type === 'blob' && /^100(644|755)$/.test(entry.mode) ? 'source_present' : 'unsupported_file_mode', ...entry };
  };
  const readBlob = (relative) => {
    const entry = receipt(relative);
    requireThat(entry.state === 'source_present', 'CATALOG_SOURCE_UNAVAILABLE');
    return git(['cat-file', 'blob', entry.blobSha]);
  };
  const groups = Object.fromEntries(Object.entries(GROUPS[kind]).map(([name, paths]) => [name, paths.map(receipt)]));
  let catalog = null;
  const findings = [];
  if (kind === 'box') {
    if (!tree.has(INDEX)) {
      catalog = { state: 'source_missing_at_exact_commit' };
      findings.push('CANONICAL_CATALOG_PATH_MISSING');
    } else {
      const index = parseJson(readBlob(INDEX));
      requireThat(index.schema_version === '1.0.0', 'UNSUPPORTED_CATALOG_SCHEMA');
      requireThat(typeof index.catalog_version === 'string' && index.catalog_version.length <= 64 && index.catalog_version.length > 0, 'INVALID_CATALOG_VERSION');
      requireThat(Array.isArray(index.shards) && index.shards.length > 0 && index.shards.length <= 32 && new Set(index.shards).size === index.shards.length, 'INVALID_CATALOG_SHARDS');
      const ids = new Set();
      const capabilities = new Set();
      const skills = [];
      for (const shardPath of index.shards) {
        requireThat(typeof shardPath === 'string' && /^\.agents\/skills\/registry\/skills-[0-9]{2}\.json$/.test(shardPath), 'INVALID_CATALOG_SHARD_PATH');
        const shard = parseJson(readBlob(shardPath));
        requireThat(shard.schema_version === '1.0.0' && Array.isArray(shard.skills) && shard.skills.length > 0 && skills.length + shard.skills.length <= 1024, 'INVALID_CATALOG_SHARD');
        for (const skill of shard.skills) {
          requireThat(skill && typeof skill.id === 'string' && ID.test(skill.id) && !ids.has(skill.id), 'INVALID_OR_DUPLICATE_SKILL');
          const entrypoint = `.agents/skills/${skill.id}/SKILL.md`;
          requireThat(skill.entrypoint === entrypoint, 'INVALID_SKILL_ENTRYPOINT');
          requireThat(Array.isArray(skill.capabilities) && skill.capabilities.length > 0 && skill.capabilities.length <= 128, 'INVALID_CAPABILITIES');
          for (const capability of skill.capabilities) {
            requireThat(typeof capability === 'string' && /^[a-z0-9_.:-]{1,96}$/.test(capability), 'INVALID_CAPABILITIES');
            capabilities.add(capability);
          }
          const evidence = receipt(entrypoint);
          requireThat(evidence.state === 'source_present', 'SKILL_SOURCE_UNAVAILABLE');
          ids.add(skill.id);
          skills.push({ id: skill.id, ...evidence });
        }
      }
      requireThat(index.skill_count === skills.length && index.capability_count === capabilities.size, 'CATALOG_DENOMINATOR_MISMATCH');
      const sameRepository = index.source_repository === repository;
      if (!sameRepository) findings.push('CATALOG_HISTORICAL_OR_NONCANONICAL_SOURCE_BINDING');
      if (index.source_base_sha !== sourceSha) findings.push('CATALOG_ORIGIN_SHA_DIFFERS_FROM_AUDITED_SNAPSHOT');
      catalog = {
        state: 'source_inventory_only', catalogVersion: index.catalog_version,
        declaredSourceMatchesCanonical: sameRepository,
        declaredSourceSha: SHA.test(index.source_base_sha ?? '') ? index.source_base_sha : null,
        skillCount: skills.length, capabilityCount: capabilities.size,
        shards: [...index.shards].sort().map(receipt), skills: skills.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
      };
    }
  }
  const evidence = { repository, sourceSha, treeSha, groups, catalog, findings };
  return {
    schemaVersion: '1.0.0', auditVersion: AUDIT_VERSION, state: 'INVENTORY_COMPLETE', ...evidence,
    evidenceSha256: sha256(JSON.stringify(evidence)),
    boundaries: {
      sourceBinding: 'local_origin_configuration_plus_exact_git_objects_not_provider_attestation',
      workingTreeConsulted: false, providerState: 'NOT_CHECKED', runtimeAcceptance: 'NOT_CHECKED',
      testsExecutedByAudit: 0, trainingRights: 'NOT_EVALUATED', mutationAuthorized: false,
      historicalProvenanceRewritten: false, missingPathIsNotProofOfMissingCapability: true,
    },
  };
}

export function parseArguments(argv) {
  const options = {};
  const names = { '--repo': 'repoPath', '--kind': 'kind', '--sha': 'sourceSha' };
  requireThat(argv.length === 6, 'EXPECTED_REPO_KIND_AND_EXACT_SHA');
  for (let i = 0; i < argv.length; i += 2) {
    requireThat(Object.hasOwn(names, argv[i]) && !Object.hasOwn(options, names[argv[i]]) && typeof argv[i + 1] === 'string' && !argv[i + 1].startsWith('--'), 'INVALID_ARGUMENTS');
    options[names[argv[i]]] = argv[i + 1];
  }
  return options;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(auditLearningFoundation(parseArguments(process.argv.slice(2))), null, 2)); }
  catch (error) {
    console.error(JSON.stringify({ state: 'INVENTORY_UNAVAILABLE', code: error instanceof InventoryError ? error.code : 'UNEXPECTED_AUDIT_FAILURE' }));
    process.exitCode = 2;
  }
}
