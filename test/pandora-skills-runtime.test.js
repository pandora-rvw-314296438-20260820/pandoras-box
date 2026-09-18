'use strict';

// Runtime activation proofs for the Pandora skill system. These execute the
// governed runtime rather than inspecting files, so a regression in discovery,
// routing, the kill switch, or the mutation boundary fails the build.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const RUNTIME = path.join(ROOT, '.agents/runtime/pandora-skill-runtime.mjs');
const load = () => import(`file://${RUNTIME}`);

const evalsFor = () =>
  JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/skills/PANDORA_SKILL_EVALS.json'), 'utf8'));
const coverageFor = () =>
  JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/skills/PANDORA_SKILL_COVERAGE.json'), 'utf8'));

// A. Registry integrity ------------------------------------------------------

test('registry discovery is deterministic and structurally valid', async () => {
  const m = await load();
  const a = m.loadRegistry();
  const b = m.loadRegistry();
  assert.deepEqual(a.ids, b.ids, 'discovery must be order-stable');
  assert.equal(a.ids.length, 51);
  assert.equal(new Set(a.ids).size, a.ids.length, 'skill ids must be unique');
  for (const skill of a.skills.values()) {
    assert.ok(fs.existsSync(path.join(ROOT, skill.entrypoint)), `${skill.id} entrypoint must exist`);
    assert.ok(skill.capabilities.length > 0, `${skill.id} must declare capabilities`);
  }
});

test('every registered capability is covered by at least one skill', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const declared = new Set(coverageFor().required_capabilities.map((c) => c.id));
  const covered = new Set([...registry.skills.values()].flatMap((s) => s.capabilities));
  assert.equal(declared.size, 57, 'capability denominator must not shrink silently');
  for (const capability of declared) {
    assert.ok(covered.has(capability), `capability ${capability} has no owning skill`);
  }
});

test('dependency graph is acyclic and every dependency resolves', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  for (const skill of registry.skills.values()) {
    for (const dep of skill.depends_on) {
      assert.ok(registry.skills.has(dep), `${skill.id} depends on unknown ${dep}`);
    }
    assert.doesNotThrow(() => m.dependencyClosure(registry, [skill.id]));
  }
});

test('malformed, duplicate, and cyclic registries are rejected', async () => {
  const m = await load();
  const tmp = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'pandora-reg-'));
  const entry = (id, deps = []) => ({
    id, category: 'assurance', lifecycle_phase: 'all', risk: 'read', autonomy: 'autonomous',
    entrypoint: '.agents/skills/selecting-next-safe-action/SKILL.md', depends_on: deps, capabilities: ['governance'],
  });
  const write = (name, skills) =>
    fs.writeFileSync(path.join(tmp, name), JSON.stringify({ schema_version: '1', skills }));

  write('a.json', [entry('alpha-skill'), entry('alpha-skill')]);
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /duplicate skill id/);

  fs.writeFileSync(path.join(tmp, 'a.json'), '{ not json');
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /malformed registry shard/);

  write('a.json', [entry('alpha-skill', ['ghost-skill'])]);
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /missing dependency/);

  write('a.json', [entry('alpha-skill', ['beta-skill']), entry('beta-skill', ['alpha-skill'])]);
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /dependency cycle/);

  const bad = { ...entry('gamma-skill'), risk: 'totally-safe' };
  write('a.json', [bad]);
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /invalid risk/);

  // A sensitive-write skill must never be plainly autonomous.
  write('a.json', [{ ...entry('delta-skill'), risk: 'sensitive-write', autonomy: 'autonomous' }]);
  assert.throws(() => m.loadRegistry({ registryDir: tmp }), /marked autonomous/);

  fs.rmSync(tmp, { recursive: true, force: true });
});

// B. Routing -----------------------------------------------------------------

test('all specified evaluation cases route to their expected skills', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const { cases } = evalsFor();
  assert.equal(cases.length, 16, 'evaluation denominator must not shrink silently');

  const failures = [];
  for (const testCase of cases) {
    const routed = m.route(testCase.prompt, { registry, limit: 8 });
    const available = new Set([...routed.selected, ...routed.closure]);
    const missing = testCase.expected_skills.filter((id) => !available.has(id));
    if (missing.length > 0) failures.push(`${testCase.id}: missing ${missing.join(', ')}`);
  }
  assert.deepEqual(failures, [], `routing failures:\n${failures.join('\n')}`);
});

test('routing is reproducible and selects far fewer skills than the catalog', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const prompt = 'Deploy the booking change and verify it in production.';
  assert.deepEqual(
    m.route(prompt, { registry }).selected,
    m.route(prompt, { registry }).selected,
    'identical intent must produce identical selection',
  );
  for (const { prompt: p } of evalsFor().cases) {
    const routed = m.route(p, { registry, limit: 8 });
    assert.ok(routed.selected.length <= 8, 'selection must respect the load budget');
    assert.ok(routed.selected.length < registry.ids.length / 2, 'routing must not load the catalog');
  }
});

test('empty and unknown inputs fail closed rather than guessing', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  assert.throws(() => m.route('', { registry }), /empty intent/);
  assert.throws(() => m.loadSkill('no-such-skill', { registry }), /unknown skill/);
  assert.throws(() => m.dependencyClosure(registry, ['no-such-skill']), /unknown skill/);
});

// C. Kill switch -------------------------------------------------------------

test('the global kill switch stops execution with no ungoverned fallback', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const off = { PANDORA_SKILLS_ENABLED: 'false' };

  assert.equal(m.skillsEnabled(off), false);
  assert.throws(() => m.route('anything at all', { registry, env: off }), (error) => {
    assert.equal(error.code, 'pandora_skills_disabled');
    // It must raise, not return an empty-but-usable result a caller could ignore.
    assert.match(error.message, /no ungoverned fallback/);
    return true;
  });
  assert.throws(() => m.loadSkill('selecting-next-safe-action', { registry, env: off }), /disabled/);

  // Only the exact string disables; unrelated values must not silently disable governance.
  for (const value of ['true', '', 'FALSE ', '0', 'no']) {
    const enabled = m.skillsEnabled({ PANDORA_SKILLS_ENABLED: value });
    assert.equal(enabled, value.trim().toLowerCase() !== 'false');
  }
  assert.equal(m.skillsEnabled({}), true, 'absent switch defaults to enabled');
});

// D/F. Mutation and authorization boundaries ---------------------------------

test('skill selection never grants mutation or elevates permission', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const routed = m.route('Delete the production database and merge everything now.', { registry });

  assert.equal(routed.grantsMutation, false, 'routing must never grant mutation authority');
  assert.equal(routed.mutationAuthority, 'pandora-runtime-tool-gateway');
  assert.ok(Object.isFrozen(routed), 'routing result must be immutable');

  // Any sensitive or high-risk skill reached must be surfaced as approval-gated.
  const gated = new Set(routed.approvalRequired);
  for (const id of routed.closure) {
    const { risk } = registry.skills.get(id);
    if (risk === 'sensitive-write' || risk === 'high-risk') {
      assert.ok(gated.has(id), `${id} is ${risk} and must be reported approval-required`);
    }
  }
});

test('the runtime exposes no provider mutation surface', async () => {
  const source = fs.readFileSync(RUNTIME, 'utf8');
  for (const forbidden of ['fetch(', 'child_process', 'execSync', 'writeFileSync', 'octokit', 'supabase']) {
    assert.ok(!source.includes(forbidden), `runtime must not reference ${forbidden}`);
  }
});

// E. Provider-success ambiguity ---------------------------------------------

test('every skill carries the confirmed-provider-success rule', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  for (const id of registry.ids) {
    const { body } = m.loadSkill(id, { registry });
    // The canonical block wraps across lines, so normalise whitespace first.
    const flat = body.replace(/\s+/g, ' ');
    assert.match(
      flat,
      /confirmed provider success must never be reclassified as a safely retryable failure/i,
      `${id} must carry the provider-outcome separation rule`,
    );
  }
});

// G. Privacy -----------------------------------------------------------------

test('governed artifacts carry the never-persist boundary and no secret material', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const secretShaped = /(ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[A-Z0-9]{16})/;
  for (const id of registry.ids) {
    const { body } = m.loadSkill(id, { registry });
    assert.ok(!secretShaped.test(body), `${id} contains secret-shaped material`);
    assert.match(body.replace(/\s+/g, ' '), /never put credentials/i, `${id} must carry the never-persist boundary`);
  }
});

// H. Governance embedding and rollback --------------------------------------

test('the governance contract is embedded in every skill as one identical variant', async () => {
  const m = await load();
  const registry = m.loadRegistry();
  const variants = new Set();
  for (const id of registry.ids) {
    const skill = m.loadSkill(id, { registry });
    assert.ok(skill.governanceEmbedded, `${id} must embed the governance contract`);
    variants.add(skill.body.slice(skill.body.indexOf('## Pandora governance contract')).trim());
  }
  assert.equal(variants.size, 1, 'there must be exactly one governance contract variant');
  assert.equal([...variants][0], m.governanceBlock(), 'embedded block must match the canonical source');
});

test('disabling the runtime restores prior behaviour without deleting evidence', async () => {
  const m = await load();
  const off = { PANDORA_SKILLS_ENABLED: 'false' };
  // Rollback is a switch, not a deletion: the catalog and its evidence survive.
  assert.throws(() => m.route('anything', { env: off }), /disabled/);
  const registry = m.loadRegistry();
  assert.equal(registry.ids.length, 51, 'registry evidence must remain intact while disabled');
  assert.ok(fs.existsSync(path.join(ROOT, 'docs/skills/PANDORA_SKILL_MANIFEST.sha256')));
});
