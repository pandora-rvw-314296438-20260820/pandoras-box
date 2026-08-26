import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ID_RE = /^[a-z0-9-]{1,64}$/;
const SHA_RE = /^[0-9a-f]{64}$/;
const REQUIRED_SECTIONS = ['Outcome','Use when','Workflow','Proof required','Stop conditions','Outputs'];
const SECRET_PATTERNS = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
  /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
  /\bsk-[A-Za-z0-9_-]{20,}\b/,
  /\bAIza[0-9A-Za-z_-]{20,}\b/,
  /\bSUPABASE_SERVICE_ROLE_KEY\s*=\s*\S+/i,
  /\b(?:TOKEN|PASSWORD|SECRET|API_KEY)\s*=\s*["']?[A-Za-z0-9_\-/.+=]{16,}["']?/,
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}
function parseFrontmatter(text, file) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) throw new Error(`${file}: missing YAML frontmatter`);
  const fields = {};
  for (const line of match[1].split('\n')) {
    const idx = line.indexOf(':');
    if (idx < 1) throw new Error(`${file}: malformed frontmatter line`);
    const key = line.slice(0, idx).trim();
    const raw = line.slice(idx + 1).trim();
    fields[key] = key === 'description' ? JSON.parse(raw) : raw;
  }
  return fields;
}
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function checkCycles(skillsById) {
  const temporary = new Set();
  const permanent = new Set();
  const visit = (id) => {
    if (permanent.has(id)) return;
    assert(!temporary.has(id), `dependency cycle detected at ${id}`);
    temporary.add(id);
    for (const dependency of skillsById.get(id).depends_on) visit(dependency);
    temporary.delete(id);
    permanent.add(id);
  };
  for (const id of skillsById.keys()) visit(id);
}

export function validatePandoraSkills({ rootDir = process.cwd(), verifyManifest = true } = {}) {
  const registryPath = path.join(rootDir, '.agents/skills/registry.json');
  const schemaPath = path.join(rootDir, '.agents/skills/registry.schema.json');
  const coveragePath = path.join(rootDir, 'docs/skills/PANDORA_SKILL_COVERAGE.json');
  const evalsPath = path.join(rootDir, 'docs/skills/PANDORA_SKILL_EVALS.json');
  for (const file of [registryPath, schemaPath, coveragePath, evalsPath]) assert(fs.existsSync(file), `missing ${path.relative(rootDir, file)}`);
  const registryIndex = readJson(registryPath);
  const schema = readJson(schemaPath);
  assert(Array.isArray(registryIndex.shards) && registryIndex.shards.length > 0, 'registry index has no shards');
  const shardSkills = [];
  const shardPathSet = new Set();
  for (const relative of registryIndex.shards) {
    assert(!shardPathSet.has(relative), `duplicate registry shard ${relative}`);
    shardPathSet.add(relative);
    assert(/^\.agents\/skills\/registry\/skills-[0-9]{2}\.json$/.test(relative), `invalid registry shard path ${relative}`);
    const shard = readJson(path.join(rootDir, relative));
    assert(shard.schema_version === '1.0.0' && Array.isArray(shard.skills) && shard.skills.length > 0, `invalid registry shard ${relative}`);
    shardSkills.push(...shard.skills);
  }
  const registry = { ...registryIndex, skills: shardSkills };
  const coverage = readJson(coveragePath);
  const evals = readJson(evalsPath);
  assert(schema.$schema?.includes('2020-12'), 'registry schema must use JSON Schema 2020-12');
  assert(registry.schema_version === '1.0.0', 'unexpected registry schema version');
  assert(registry.project_key === 'mcpmaster-pandoras-box', 'wrong project key');
  assert(registry.source_repository === 'pandora-rvw-314296438-20260820/pandoras-box', 'wrong source repository');
  assert(/^[0-9a-f]{40}$/.test(registry.source_base_sha), 'invalid source base SHA');
  assert(registry.runtime_activation === 'not_proven', 'runtime activation must remain not_proven in v1 source catalog');
  assert(registry.production_activation === 'not_authorized', 'production activation must remain not_authorized');
  assert(Array.isArray(registry.skills) && registry.skills.length > 0, 'registry has no skills');
  assert(registry.skill_count === registry.skills.length, 'registry skill_count mismatch');

  const skillsById = new Map();
  for (const skill of registry.skills) {
    assert(ID_RE.test(skill.id), `invalid skill id ${skill.id}`);
    assert(!skillsById.has(skill.id), `duplicate skill id ${skill.id}`);
    assert(Array.isArray(skill.depends_on), `${skill.id}: depends_on must be an array`);
    assert(Array.isArray(skill.capabilities) && skill.capabilities.length > 0, `${skill.id}: capabilities required`);
    const expected = `.agents/skills/${skill.id}/SKILL.md`;
    assert(skill.entrypoint === expected, `${skill.id}: entrypoint mismatch`);
    const file = path.join(rootDir, skill.entrypoint);
    assert(fs.existsSync(file), `${skill.id}: missing SKILL.md`);
    const text = fs.readFileSync(file, 'utf8');
    const fm = parseFrontmatter(text, skill.entrypoint);
    assert(Object.keys(fm).sort().join(',') === 'description,name', `${skill.id}: frontmatter must contain only name and description`);
    assert(fm.name === skill.id, `${skill.id}: frontmatter name mismatch`);
    assert(typeof fm.description === 'string' && fm.description.length > 0 && fm.description.length <= 1024, `${skill.id}: invalid frontmatter description`);
    assert(text.split('\n').length <= 500, `${skill.id}: SKILL.md exceeds 500 lines`);
    for (const section of REQUIRED_SECTIONS) assert(text.includes(`## ${section}`), `${skill.id}: missing section ${section}`);
    for (const pattern of SECRET_PATTERNS) assert(!pattern.test(text), `${skill.id}: secret-shaped content detected`);
    skillsById.set(skill.id, skill);
  }
  for (const skill of registry.skills) {
    for (const dependency of skill.depends_on) assert(skillsById.has(dependency), `${skill.id}: unknown dependency ${dependency}`);
  }
  checkCycles(skillsById);

  assert(coverage.schema_version === '1.0.0', 'unexpected coverage schema version');
  const capabilityIds = new Set();
  for (const capability of coverage.required_capabilities) {
    assert(!capabilityIds.has(capability.id), `duplicate capability ${capability.id}`);
    capabilityIds.add(capability.id);
    assert(Array.isArray(capability.skills) && capability.skills.length > 0, `${capability.id}: no mapped skills`);
    for (const id of capability.skills) {
      assert(skillsById.has(id), `${capability.id}: unknown skill ${id}`);
      assert(skillsById.get(id).capabilities.includes(capability.id), `${capability.id}: registry mapping mismatch for ${id}`);
    }
  }
  for (const skill of registry.skills) for (const capability of skill.capabilities) assert(capabilityIds.has(capability), `${skill.id}: unknown capability ${capability}`);
  assert(registry.capability_count === capabilityIds.size, 'registry capability_count mismatch');

  // Evals may claim execution only with a real, checkable execution record. This
  // keeps the original honesty guard: a status string alone never proves a run.
  assert(
    evals.status === 'specified_not_run' || evals.status === 'executed',
    `unknown eval status: ${evals.status}`,
  );
  if (evals.status === 'executed') {
    const run = evals.execution;
    assert(run && typeof run === 'object', 'executed evals must record an execution block');
    assert(fs.existsSync(path.join(rootDir, run.harness)), `eval harness missing: ${run.harness}`);
    assert(fs.existsSync(path.join(rootDir, run.runtime)), `eval runtime missing: ${run.runtime}`);
    assert(run.cases_total === evals.cases.length, 'eval execution total does not match the case denominator');
    assert(run.cases_passed === run.cases_total, 'executed evals must pass every case');
  }
  const evalIds = new Set();
  for (const item of evals.cases) {
    assert(!evalIds.has(item.id), `duplicate eval ${item.id}`);
    evalIds.add(item.id);
    assert(Array.isArray(item.expected_skills) && item.expected_skills.length > 0, `${item.id}: expected_skills required`);
    for (const id of item.expected_skills) assert(skillsById.has(id), `${item.id}: unknown expected skill ${id}`);
    assert(Array.isArray(item.must_not) && item.must_not.length > 0, `${item.id}: must_not required`);
  }

  let manifestFiles = 0;
  if (verifyManifest) {
    const manifestPath = path.join(rootDir, 'docs/skills/PANDORA_SKILL_MANIFEST.sha256');
    assert(fs.existsSync(manifestPath), 'missing skill manifest');
    const lines = fs.readFileSync(manifestPath, 'utf8').trim().split('\n').filter(Boolean);
    const seen = new Set();
    for (const line of lines) {
      const match = line.match(/^([0-9a-f]{64})  (.+)$/);
      assert(match, `malformed manifest line: ${line}`);
      const [, expectedHash, relative] = match;
      assert(SHA_RE.test(expectedHash), `invalid manifest hash for ${relative}`);
      assert(!seen.has(relative), `duplicate manifest path ${relative}`);
      seen.add(relative);
      const file = path.join(rootDir, relative);
      assert(fs.existsSync(file), `manifest path missing: ${relative}`);
      assert(sha256(file) === expectedHash, `manifest hash mismatch: ${relative}`);
      const artifactText = fs.readFileSync(file, 'utf8');
      for (const pattern of SECRET_PATTERNS) assert(!pattern.test(artifactText), `secret-shaped content detected: ${relative}`);
    }
    const expectedPaths = [
      '.agents/AGENTS.md','.agents/skills/README.md','.agents/skills/registry.json','.agents/skills/registry.schema.json','.agents/skills/registry-shard.schema.json',
      ...registry.shards,
      'docs/skills/PANDORA_SKILL_SYSTEM.md','docs/skills/PANDORA_SKILL_COVERAGE.json','docs/skills/PANDORA_SKILL_EVALS.json',
      'docs/skills/PANDORA_SKILL_ACTIVATION.json',
      '.agents/runtime/GOVERNANCE_BLOCK.md','.agents/runtime/pandora-skill-runtime.mjs',
      'scripts/validate-pandora-skills.mjs','test/pandora-skills-registry.test.js','test/pandora-skills-runtime.test.js',
      ...registry.skills.map((s) => s.entrypoint),
    ].sort();
    assert(expectedPaths.length === seen.size, `manifest path count mismatch: expected ${expectedPaths.length}, got ${seen.size}`);
    for (const relative of expectedPaths) assert(seen.has(relative), `manifest omits ${relative}`);
    manifestFiles = seen.size;
  }
  // Every skill must embed exactly one identical copy of the canonical governance
  // block, so a runtime that loads a skill in isolation still receives the contract.
  const canonicalBlock = fs.readFileSync(path.join(rootDir, '.agents/runtime/GOVERNANCE_BLOCK.md'), 'utf8').trim();
  const marker = '## Pandora governance contract (canonical, embedded)';
  const variants = new Set();
  for (const skill of registry.skills) {
    const body = fs.readFileSync(path.join(rootDir, skill.entrypoint), 'utf8');
    const at = body.indexOf(marker);
    assert(at !== -1, `skill omits embedded governance contract: ${skill.id}`);
    assert(body.indexOf(marker, at + 1) === -1, `skill embeds the governance contract twice: ${skill.id}`);
    variants.add(body.slice(at).trim());
  }
  assert(variants.size === 1, `conflicting governance contract variants: ${variants.size}`);
  assert([...variants][0] === canonicalBlock, 'embedded governance contract diverges from .agents/runtime/GOVERNANCE_BLOCK.md');

  return { skills: registry.skills.length, capabilities: capabilityIds.size, evals: evalIds.size, manifestFiles };
}

const isCli = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isCli) {
  try {
    const result = validatePandoraSkills();
    console.log(`Pandora skill validation PASS: ${result.skills} skills, ${result.capabilities} capabilities, ${result.evals} evals, ${result.manifestFiles} manifest files.`);
  } catch (error) {
    console.error(`Pandora skill validation FAIL: ${error.message}`);
    process.exitCode = 1;
  }
}
