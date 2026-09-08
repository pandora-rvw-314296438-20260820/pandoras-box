const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const { executionPayloadHash } = require('../dist/http-app.js');
const { GitHubMCPServer, githubTools } = require('../dist/tools/github.js');
const { executeTool } = require('../dist/runtime/tool-catalog.js');

const GOOD_SHA = 'a'.repeat(40);
const STALE_SHA = 'b'.repeat(40);

test('github merge tool requires an exact reviewed head SHA', () => {
  const schema = githubTools['github.merge-pull-request'].parameters;
  assert.ok(schema.required.includes('expectedHeadSha'));
  assert.equal(schema.properties.expectedHeadSha.pattern, '^[0-9a-fA-F]{40}$');
});

test('merge provider refuses missing or malformed reviewed head before network mutation', async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    throw new Error('network must not be reached');
  };
  try {
    const github = new GitHubMCPServer({ token: 'test-token', baseUrl: 'https://api.github.test' });
    await assert.rejects(
      github.mergePullRequest('owner', 'repo', 7, undefined, undefined, undefined, 'squash'),
      /expectedHeadSha must be an exact 40-character Git commit SHA/,
    );
    await assert.rejects(
      github.mergePullRequest('owner', 'repo', 7, 'not-a-sha', undefined, undefined, 'squash'),
      /expectedHeadSha must be an exact 40-character Git commit SHA/,
    );
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('merge provider sends GitHub sha guard and fails closed when provider reports stale head', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    requests.push({ url: String(url), method: options.method, body });
    if (body.sha === STALE_SHA) {
      return new Response(JSON.stringify({ message: 'Head branch was modified' }), {
        status: 409,
        statusText: 'Conflict',
        headers: { 'content-type': 'application/json' },
      });
    }
    return new Response(JSON.stringify({
      sha: 'c'.repeat(40),
      merged: true,
      message: 'Pull Request successfully merged',
    }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  try {
    const github = new GitHubMCPServer({ token: 'test-token', baseUrl: 'https://api.github.test' });
    await assert.rejects(
      github.mergePullRequest('owner', 'repo', 7, STALE_SHA, undefined, undefined, 'squash'),
      /409 Conflict/,
    );
    const result = await github.mergePullRequest('owner', 'repo', 7, GOOD_SHA, undefined, undefined, 'squash');
    assert.equal(result.merged, true);
    assert.equal(requests.length, 2);
    assert.equal(requests[0].method, 'PUT');
    assert.equal(requests[0].body.sha, STALE_SHA);
    assert.equal(requests[1].body.sha, GOOD_SHA);
    assert.equal(requests[1].body.merge_method, 'squash');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('durable merge payload hash changes when the reviewed head changes', () => {
  const base = { owner: 'owner', repo: 'repo', pullNumber: 7, mergeMethod: 'squash' };
  const first = executionPayloadHash('github.merge-pull-request', { ...base, expectedHeadSha: GOOD_SHA });
  const moved = executionPayloadHash('github.merge-pull-request', { ...base, expectedHeadSha: STALE_SHA });
  assert.notEqual(first, moved);
});

test('generic repository API cannot bypass the exact-head pull request merge control', async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    throw new Error('network must not be reached');
  };
  try {
    await assert.rejects(
      executeTool('github.write-repository-api', {
        owner: 'owner',
        repo: 'repo',
        method: 'PUT',
        pathSegments: ['pulls', '7', 'merge'],
        body: { merge_method: 'squash' },
        confirmation: 'PUT owner/repo/pulls/7/merge',
      }, {
        github: {
          id: 'fixture',
          label: 'fixture',
          baseUrl: 'https://api.github.com',
          token: 'not-used',
          allowMutations: true,
          allowedRepositories: ['owner/repo'],
          grantedScopes: ['repositories:write'],
        },
      }),
      /Pull request merges must use github\.merge-pull-request with expectedHeadSha/,
    );
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Control Tower requires and hashes the reviewed head SHA in merge plans', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'apps', 'control-tower', 'app.js'), 'utf8');
  assert.match(source, /expectedHeadSha: ""/);
  assert.match(source, /args\.expectedHeadSha = String\(b\.expectedHeadSha \|\| ""\)\.trim\(\)/);
  assert.match(source, /Reviewed head SHA/);
  assert.match(source, /Boolean\(b\.pullNumber\).*expectedHeadSha/s);
});
