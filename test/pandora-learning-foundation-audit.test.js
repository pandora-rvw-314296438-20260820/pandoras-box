/* Synthetic, offline P0-02 fixtures; no provider or model benchmark claims. */
'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const SCRIPT = path.resolve(__dirname, '../scripts/audit-learning-foundation.mjs');
const REPOSITORY = 'pandora-rvw-314296438-20260820/pandoras-box';
const INDEX = '.agents/skills/registry.json';
const SHARD = '.agents/skills/registry/skills-01.json';
const SKILL = '.agents/skills/example-skill/SKILL.md';
let api;
let temporary;
let base;
let sequence = 0;
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('GIT_')));
Object.assign(env, { GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : os.devNull, GIT_ALLOW_PROTOCOL: '', GIT_TERMINAL_PROMPT: '0' });
function git(dir, ...args) {
  return execFileSync('git', ['-C', dir, '-c', 'core.autocrlf=false', ...args], { env, encoding: 'utf8', timeout: 10000, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
}
function write(dir, relative, content) {
  const target = path.join(dir, relative);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, typeof content === 'string' ? content : JSON.stringify(content));
}
function commit(dir) {
  git(dir, 'add', '--', '.');
  git(dir, '-c', 'user.name=Offline fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Synthetic source fixture');
  return git(dir, 'rev-parse', 'HEAD');
}
function fixture(change = () => {}) {
  const dir = path.join(temporary, `fixture-${++sequence}`);
  fs.mkdirSync(dir);
  git(dir, 'init', '-q');
  git(dir, 'remote', 'add', 'origin', `https://github.com/${REPOSITORY}.git`);
  const index = { schema_version: '1.0.0', catalog_version: '1.0.0', source_repository: REPOSITORY, source_base_sha: '1'.repeat(40), skill_count: 1, capability_count: 1, shards: [SHARD] };
  const shard = { schema_version: '1.0.0', skills: [{ id: 'example-skill', entrypoint: SKILL, capabilities: ['exact-lookup'] }] };
  const files = { [INDEX]: index, [SHARD]: shard, [SKILL]: 'PRIVATE_CONTENT_SENTINEL_NOT_FOR_INVENTORY\n' };
  change({ index, shard, files });
  for (const [relative, value] of Object.entries(files)) write(dir, relative, value);
  const sha = commit(dir);
  return { dir, sha };
}
const inspect = (f = base, rest = {}) => api.auditLearningFoundation({ repoPath: f.dir, kind: 'box', sourceSha: f.sha, ...rest });
const fails = (fn, code) => assert.throws(fn, (error) => error instanceof api.InventoryError && error.code === code);
before(async () => {
  api = await import(pathToFileURL(SCRIPT).href);
  temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pandora-foundation-audit-'));
  base = fixture();
});
after(() => { if (temporary) fs.rmSync(temporary, { recursive: true, force: true }); });

test('exact committed catalog inventory is repeatable and content addressed', () => {
  const result = inspect();
  assert.deepEqual(result, inspect());
  assert.equal(result.state, 'INVENTORY_COMPLETE');
  assert.equal(result.repository, REPOSITORY);
  assert.equal(result.sourceSha, base.sha);
  assert.match(result.treeSha, /^[0-9a-f]{40}$/);
  assert.match(result.evidenceSha256, /^[0-9a-f]{64}$/);
  assert.equal(result.catalog.skillCount, 1);
  assert.equal(result.catalog.capabilityCount, 1);
  assert.equal(result.catalog.skills[0].blobSha, git(base.dir, 'rev-parse', `${base.sha}:${SKILL}`));
});
test('inventory cannot claim runtime, test, training, or mutation authority', () => {
  const { boundaries } = inspect();
  assert.equal(boundaries.workingTreeConsulted, false);
  assert.equal(boundaries.providerState, 'NOT_CHECKED');
  assert.equal(boundaries.runtimeAcceptance, 'NOT_CHECKED');
  assert.equal(boundaries.testsExecutedByAudit, 0);
  assert.equal(boundaries.trainingRights, 'NOT_EVALUATED');
  assert.equal(boundaries.mutationAuthorized, false);
  assert.match(boundaries.sourceBinding, /not_provider_attestation/);
});
test('dirty working-tree text cannot replace exact committed source', () => {
  const first = inspect();
  write(base.dir, SKILL, 'CHANGED_UNCOMMITTED_TEXT\n');
  write(base.dir, INDEX, 'invalid working-tree JSON');
  try { assert.deepEqual(inspect(), first); }
  finally {
    write(base.dir, SKILL, git(base.dir, 'show', `${base.sha}:${SKILL}`) + '\n');
    write(base.dir, INDEX, git(base.dir, 'show', `${base.sha}:${INDEX}`));
  }
});
test('all moving or malformed source references are rejected before Git reads', () => {
  for (const sourceSha of ['main', 'HEAD', 'latest', 'a'.repeat(39), 'a'.repeat(41), '--help', 'A'.repeat(40), null, 42]) {
    fails(() => inspect(base, { sourceSha }), 'EXACT_COMMIT_REQUIRED');
  }
});
test('unknown or inherited repository kinds cannot become source targets', () => {
  for (const kind of ['other', 'toString', '__proto__', undefined]) fails(() => inspect(base, { kind }), 'INVALID_REPOSITORY_KIND');
});
test('wrong repository and credential-bearing remotes fail without URL disclosure', () => {
  const f = fixture();
  for (const url of ['https://github.com/unapproved/example.git', `https://user:DO_NOT_DISCLOSE@github.com/${REPOSITORY}.git`, `https://github.com/${REPOSITORY}.git?token=DO_NOT_DISCLOSE`]) {
    git(f.dir, 'remote', 'set-url', 'origin', url);
    fails(() => inspect(f), 'CANONICAL_REMOTE_BINDING_REQUIRED');
  }
});
test('configured canonical SSH is accepted without any network transport', () => {
  const f = fixture();
  git(f.dir, 'remote', 'set-url', 'origin', `git@github.com:${REPOSITORY}.git`);
  assert.equal(inspect(f).catalog.skillCount, 1);
});
test('a blob identity is not accepted as a commit identity', () => {
  fails(() => inspect(base, { sourceSha: git(base.dir, 'rev-parse', `${base.sha}:${INDEX}`) }), 'EXACT_COMMIT_REQUIRED');
});
test('missing Git evidence is unavailable, never an empty successful result', () => {
  fails(() => inspect(base, { sourceSha: '0'.repeat(40) }), 'GIT_EVIDENCE_UNAVAILABLE');
  fails(() => inspect(base, { repoPath: path.join(temporary, 'NON_EXISTENT_PRIVATE_PATH') }), 'GIT_EVIDENCE_UNAVAILABLE');
});
test('historical source metadata is visible but never rewritten or trusted as current', () => {
  const f = fixture(({ index }) => { index.source_repository = 'historical/example'; });
  const result = inspect(f);
  assert.equal(result.catalog.declaredSourceMatchesCanonical, false);
  assert.ok(result.findings.includes('CATALOG_HISTORICAL_OR_NONCANONICAL_SOURCE_BINDING'));
  assert.equal(result.boundaries.historicalProvenanceRewritten, false);
  assert.equal(JSON.parse(git(f.dir, 'show', `${f.sha}:${INDEX}`)).source_repository, 'historical/example');
});
test('missing exact paths are facts, not proof that the entire capability is absent', () => {
  const f = fixture(({ files }) => { delete files[INDEX]; });
  const result = inspect(f);
  assert.equal(result.catalog.state, 'source_missing_at_exact_commit');
  assert.equal(result.boundaries.missingPathIsNotProofOfMissingCapability, true);
});
test('raw skill body content does not enter inventory output', () => {
  assert.ok(!JSON.stringify(inspect()).includes('PRIVATE_CONTENT_SENTINEL_NOT_FOR_INVENTORY'));
});
test('malformed catalog JSON cannot become no-relevant-skills evidence', () => {
  const f = fixture(({ files }) => { files[INDEX] = '{ broken'; });
  fails(() => inspect(f), 'INVALID_CATALOG');
});
test('unsupported schema versions fail explicitly', () => {
  const f = fixture(({ index }) => { index.schema_version = 'future-unreviewed'; });
  fails(() => inspect(f), 'UNSUPPORTED_CATALOG_SCHEMA');
});
test('duplicate skills and missing exact entrypoint objects fail closed', () => {
  const duplicate = fixture(({ index, shard }) => { shard.skills.push({ ...shard.skills[0] }); index.skill_count = 2; });
  fails(() => inspect(duplicate), 'INVALID_OR_DUPLICATE_SKILL');
  const missing = fixture(({ files }) => { delete files[SKILL]; });
  fails(() => inspect(missing), 'SKILL_SOURCE_UNAVAILABLE');
});
test('shard traversal, duplicate shards, and excessive shard counts are bounded', () => {
  for (const shards of [['../../outside.json'], [SHARD, SHARD], Array.from({ length: 33 }, (_, i) => `.agents/skills/registry/skills-${String(i).padStart(2, '0')}.json`)]) {
    const f = fixture(({ index }) => { index.shards = shards; });
    fails(() => inspect(f), shards[0] === '../../outside.json' ? 'INVALID_CATALOG_SHARD_PATH' : 'INVALID_CATALOG_SHARDS');
  }
});
test('entrypoint traversal and non-string IDs cannot become file references', () => {
  const traversal = fixture(({ shard }) => { shard.skills[0].entrypoint = '../../outside'; });
  fails(() => inspect(traversal), 'INVALID_SKILL_ENTRYPOINT');
  const numeric = fixture(({ shard }) => { shard.skills[0].id = 7; shard.skills[0].entrypoint = '.agents/skills/7/SKILL.md'; });
  fails(() => inspect(numeric), 'INVALID_OR_DUPLICATE_SKILL');
});
test('denominator mismatch is explicit instead of silently shrinking coverage', () => {
  const f = fixture(({ index }) => { index.skill_count = 99; });
  fails(() => inspect(f), 'CATALOG_DENOMINATOR_MISMATCH');
});
test('Git replacement refs cannot substitute a different tree for the requested SHA', () => {
  const original = fixture();
  const expected = inspect(original);
  write(original.dir, 'different.txt', 'different tree');
  const replacement = commit(original.dir);
  git(original.dir, 'replace', original.sha, replacement);
  try { assert.deepEqual(inspect(original), expected); }
  finally { git(original.dir, 'replace', '-d', original.sha); }
});
test('memory inventory is separately repository-bound and does not invent a skill catalog', () => {
  const f = fixture();
  git(f.dir, 'remote', 'set-url', 'origin', 'https://github.com/pandora-rvw-314296438-20260820/pandoras-box-memory.git');
  const result = inspect(f, { kind: 'memory' });
  assert.equal(result.catalog, null);
  assert.ok(result.groups.task_aware_retrieval);
  fails(() => inspect(f), 'CANONICAL_REMOTE_BINDING_REQUIRED');
});
test('invalid time budgets cannot make execution unbounded', () => {
  for (const timeoutMs of [0, -1, Infinity, 30001, 1.5, '15000']) fails(() => inspect(base, { timeoutMs }), 'INVALID_TIME_BUDGET');
});
test('CLI argument schema rejects unknown, missing, and duplicate options', () => {
  assert.deepEqual(api.parseArguments(['--repo', 'fixture', '--kind', 'box', '--sha', base.sha]), { repoPath: 'fixture', kind: 'box', sourceSha: base.sha });
  for (const args of [[], ['--repo', 'fixture'], ['--repo', 'fixture', '--kind', 'box', '--fetch', base.sha], ['--repo', 'fixture', '--repo', 'other', '--sha', base.sha]]) assert.throws(() => api.parseArguments(args), api.InventoryError);
});
test('CLI returns an explicit sanitized error and a nonzero exit', () => {
  const result = spawnSync(process.execPath, [SCRIPT, '--repo', path.join(temporary, 'DO_NOT_DISCLOSE_PATH'), '--kind', 'box', '--sha', base.sha], { encoding: 'utf8', timeout: 15000, env });
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
  assert.deepEqual(JSON.parse(result.stderr), { state: 'INVENTORY_UNAVAILABLE', code: 'GIT_EVIDENCE_UNAVAILABLE' });
  assert.ok(!result.stderr.includes('DO_NOT_DISCLOSE_PATH'));
});
