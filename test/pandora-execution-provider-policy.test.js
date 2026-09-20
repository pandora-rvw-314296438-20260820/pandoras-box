'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');

test('Pandora execution authority is GitHub + Supabase + Vercel only', () => {
  const migration = read(
    'supabase',
    'migrations',
    '20260919124500_enforce_pandora_execution_provider_allowlist.sql',
  );

  for (const provider of ['github', 'supabase', 'vercel']) {
    assert.match(migration, new RegExp("\\('" + provider + "'\\s*,\\s*true"));
  }

  assert.match(migration, /check \(provider in \('github','supabase','vercel'\)\)/);
  assert.match(migration, /PANDORA_EXECUTION_PROVIDER_NOT_ALLOWED/);
  assert.match(migration, /revoke all on function/i);
  assert.match(migration, /cron\.unschedule/);
  assert.match(migration, /bitbucket/i);
});

test('active package scripts do not expose AWS or retired Windows execution', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(Object.keys(pkg.scripts).some((name) => name.startsWith('aws-')), false);
  assert.doesNotMatch(pkg.scripts['test:worker'] || '', /workers\/windows/i);
});

test('active web shell uses the owner-first Pandora surface', () => {
  const bootstrap = read('apps', 'control-tower', 'bootstrap.js');
  assert.match(bootstrap, /owner-first\.js/);
  assert.doesNotMatch(bootstrap, /app\.js|simple-language\.js/i);
});

test('active Vercel routing exposes the neutral Pandora status alias', () => {
  const vercel = read('vercel.json');
  assert.match(vercel, /\/control-tower\/pandora-status\.json/);
});

test('active GitHub security workflow uses hosted Node 24 execution', () => {
  const workflowDir = path.join(root, '.github', 'workflows');
  const names = fs.readdirSync(workflowDir).filter((name) => /\.ya?ml$/i.test(name));
  assert.equal(names.includes('pandora-security.yml'), true);
  const security = read('.github', 'workflows', 'pandora-security.yml');
  assert.match(security, /node24:/);
  assert.match(security, /node-version: '24\.x'/);
  assert.doesNotMatch(security, /\bself-hosted\b/i);
});

test('deployment adapter rejects any provider other than Vercel', () => {
  const adapter = read('packages', 'pandora-tools', 'src', 'worker-adapters.js');
  assert.match(adapter, /function vercelProvider/);
  assert.match(adapter, /EXECUTION_PROVIDER_NOT_ALLOWED/);
  assert.equal((adapter.match(/provider: vercelProvider\(trusted\.provider\)/g) || []).length, 2);
});

test('Pandora control boundary is Supabase-hosted and production-Vercel authenticated', () => {
  const edge = read('supabase', 'functions', 'pandora-control', 'index.ts');
  const policy = read('supabase', 'functions', 'pandora-control', 'identity-policy.mjs');
  assert.match(edge, /assertProductionVercelClaims/);
  assert.match(policy, /EXPECTED_ENVIRONMENT = 'production'/);
  assert.match(policy, /EXPECTED_PROJECT_NAME = 'mcpmaster'/);
});
