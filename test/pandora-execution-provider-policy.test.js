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
    assert.match(migration, new RegExp(`\\('${provider}'\\s*,\\s*true`));
  }

  assert.match(migration, /check \(provider in \('github','supabase','vercel'\)\)/);
  assert.match(migration, /PANDORA_EXECUTION_PROVIDER_NOT_ALLOWED/);
  assert.match(migration, /projectos_%/);
  assert.match(migration, /bitbucket/);
});

test('active package scripts do not expose AWS or retired Windows execution', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(Object.keys(pkg.scripts).some((name) => name.startsWith('aws-')), false);
  assert.doesNotMatch(pkg.scripts['test:worker'] || '', /workers\/windows/i);
});

test('active web shell never loads ProjectOS', () => {
  const index = read('apps', 'control-tower', 'index.html');
  const bootstrap = read('apps', 'control-tower', 'bootstrap.js');

  assert.doesNotMatch(index, /projectos/i);
  assert.doesNotMatch(bootstrap, /projectos|app\.js|simple-language\.js/i);
  assert.match(bootstrap, /owner-first\.js/);
  assert.equal(
    fs.existsSync(path.join(root, 'apps', 'control-tower', 'projectos-live-fetch.js')),
    false,
  );
});

test('active Vercel routing contains no ProjectOS alias', () => {
  const vercel = read('vercel.json');
  assert.doesNotMatch(vercel, /projectos/i);
});

test('active GitHub workflows contain no ProjectOS workflow and no self-hosted runner', () => {
  const workflowDir = path.join(root, '.github', 'workflows');
  const names = fs.readdirSync(workflowDir).filter((name) => /\.ya?ml$/i.test(name));

  assert.equal(names.some((name) => /projectos/i.test(name)), false);
  for (const name of names) {
    assert.doesNotMatch(read('.github', 'workflows', name), /\bself-hosted\b/i);
  }
});

test('deployment adapter rejects any provider other than Vercel', () => {
  const adapter = read('packages', 'pandora-tools', 'src', 'worker-adapters.js');
  assert.match(adapter, /function vercelProvider/);
  assert.match(adapter, /EXECUTION_PROVIDER_NOT_ALLOWED/);
  assert.equal((adapter.match(/provider: vercelProvider\(trusted\.provider\)/g) || []).length, 2);
});

test('ProjectOS Edge Function source is not an active deployable function', () => {
  assert.equal(
    fs.existsSync(path.join(root, 'supabase', 'functions', 'projectos-control', 'index.ts')),
    false,
  );
});
