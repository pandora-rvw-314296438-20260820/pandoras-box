const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const repositoryRoot = join(__dirname, '..');
const {
  assertOperationalRepository,
  isOperationalRepository,
  repositorySourceStatus,
  sourceAuthorityPolicy,
} = require('../dist/runtime/source-authority.js');
const { buildExecutionIntakeRequest } = require('../dist/runtime/mandatory-intake.js');
const { executeTool } = require('../dist/runtime/tool-catalog.js');

test('machine policy blacklists the entire mbanatao owner namespace', () => {
  const committed = JSON.parse(
    readFileSync(join(repositoryRoot, 'SOURCE_AUTHORITY_POLICY.json'), 'utf8'),
  );
  assert.equal(committed.schema_version, '1.2.0');
  assert.equal(committed.mode, 'fail_closed');
  assert.equal(
    committed.canonical.source_repository,
    'pandora-rvw-314296438-20260820/pandoras-box',
  );
  assert.equal(committed.canonical.vercel_project_id, 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk');
  assert.equal(committed.canonical.production_origin, 'https://mcpmaster.vercel.app');
  assert.deepEqual(sourceAuthorityPolicy, committed);
  assert.ok(committed.deprecated_operational_sources.some((source) =>
    source.type === 'github_owner' &&
    source.value === 'mbanatao' &&
    source.wildcard === 'mbanatao/*' &&
    source.status === 'historical_only'));

  for (const repository of [
    'mbanatao/fong',
    'mbanatao/Memory',
    'MBANATAO/new-repository',
    '  mbanatao/Battle  ',
  ]) {
    assert.equal(repositorySourceStatus(repository), 'historical_only', repository);
    assert.equal(isOperationalRepository(repository), false, repository);
    assert.throws(
      () => assertOperationalRepository(repository, 'select'),
      /historical-only repository/i,
      repository,
    );
  }

  assert.equal(repositorySourceStatus('banataosystems/fxpass'), 'operational');
  assert.equal(isOperationalRepository('banataosystems/fxpass'), true);
  assert.equal(
    repositorySourceStatus('pandora-rvw-314296438-20260820/pandoras-box'),
    'operational',
  );
  assert.equal(repositorySourceStatus('not a repository'), 'invalid');
});

test('new ProjectOS intake rejects mbanatao repositories before network traffic', () => {
  assert.throws(
    () => buildExecutionIntakeRequest({
      requestId: '00000000-0000-4000-8000-000000000001',
      tool: 'github.create-issue',
      args: { owner: 'mbanatao', repo: 'fong', title: 'must not run' },
    }),
    /historical-only repository mbanatao\/fong/i,
  );

  const accepted = buildExecutionIntakeRequest({
    requestId: '00000000-0000-4000-8000-000000000002',
    tool: 'github.create-issue',
    args: { owner: 'banataosystems', repo: 'fxpass', title: 'allowed' },
  });
  assert.equal(accepted.repository, 'banataosystems/fxpass');
});

test('GitHub discovery excludes mbanatao while exact historical reads remain available', async () => {
  const calls = [];
  const configuration = {
    github: {
      id: 'github-test',
      token: 'test-token',
      baseUrl: 'https://api.github.com',
      allowedRepositories: ['mbanatao/fong', 'banataosystems/fxpass'],
      allowMutations: true,
      grantedScopes: ['repositories:read', 'issues:write'],
      fetch: async () => undefined,
    },
  };

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), method: options.method });
    if (String(url).endsWith('/user/repos?type=all&sort=updated&direction=desc&per_page=30')) {
      return new Response(JSON.stringify([
        { full_name: 'mbanatao/fong' },
        { full_name: 'banataosystems/fxpass' },
      ]), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    if (String(url).endsWith('/repos/mbanatao/fong')) {
      return new Response(JSON.stringify({
        id: 1,
        name: 'fong',
        full_name: 'mbanatao/fong',
        description: null,
        html_url: 'https://github.com/mbanatao/fong',
        clone_url: 'https://github.com/mbanatao/fong.git',
        ssh_url: 'git@github.com:mbanatao/fong.git',
        language: null,
        stargazers_count: 0,
        forks_count: 0,
        open_issues_count: 0,
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z',
        default_branch: 'main',
        private: false,
        archived: true,
        disabled: false,
      }), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    throw new Error(`unexpected request: ${url}`);
  };

  try {
    const repositories = await executeTool('github.list-repositories', {}, configuration);
    assert.deepEqual(repositories.map((repository) => repository.full_name), [
      'banataosystems/fxpass',
    ]);

    const historical = await executeTool(
      'github.get-repository',
      { owner: 'mbanatao', repo: 'fong' },
      configuration,
    );
    assert.equal(historical.full_name, 'mbanatao/fong');

    await assert.rejects(
      executeTool(
        'github.create-issue',
        { owner: 'mbanatao', repo: 'fong', title: 'must not run' },
        configuration,
      ),
      /historical-only repository mbanatao\/fong/i,
    );
    assert.equal(calls.filter((call) => call.method === 'POST').length, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
