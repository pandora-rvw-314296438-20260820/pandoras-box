"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { GitHubMCPServer } = require("../dist/tools/github.js");
const { prepareProviderResult } = require("../dist/runtime/provider-result-contract.js");

function response(value) {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function repoFixture() {
  return {
    id: 1,
    name: "pandoras-box",
    full_name: "pandora-rvw-314296438-20260820/pandoras-box",
    description: null,
    html_url: "https://github.com/pandora-rvw-314296438-20260820/pandoras-box",
    clone_url: "https://github.com/pandora-rvw-314296438-20260820/pandoras-box.git",
    ssh_url: "git@github.com:pandora-rvw-314296438-20260820/pandoras-box.git",
    language: null,
    stargazers_count: 0,
    forks_count: 0,
    open_issues_count: 0,
    created_at: "2026-08-20T00:00:00Z",
    updated_at: "2026-09-27T00:00:00Z",
    default_branch: "main",
    private: true,
    archived: false,
    disabled: false,
  };
}

test("GitHub repository nullable fields are omitted before provider-result validation", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => response(repoFixture());
  try {
    const github = new GitHubMCPServer({ token: "fixture", baseUrl: "https://api.github.test" });
    const result = await github.getRepository("owner", "repo");
    assert.equal(Object.hasOwn(result, "description"), false);
    assert.equal(Object.hasOwn(result, "language"), false);
    assert.doesNotThrow(() => prepareProviderResult(result));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("GitHub issue nullable fields and nested labels are JSON-safe", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => response({
    id: 2,
    number: 7,
    title: "Issue",
    body: null,
    state: "open",
    labels: [{ id: 9, name: null, color: null }],
    assignees: null,
    user: null,
    created_at: "2026-09-27T00:00:00Z",
    updated_at: "2026-09-27T00:00:00Z",
    closed_at: null,
    html_url: "https://github.com/owner/repo/issues/7",
  });
  try {
    const github = new GitHubMCPServer({ token: "fixture", baseUrl: "https://api.github.test" });
    const result = await github.getIssue("owner", "repo", 7);
    for (const key of ["body", "assignees", "user", "closed_at"]) {
      assert.equal(Object.hasOwn(result, key), false);
    }
    assert.deepEqual(result.labels, [{ id: 9 }]);
    assert.doesNotThrow(() => prepareProviderResult(result));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("GitHub pull request computing-null fields are omitted before presentation", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => response({
    id: 3,
    number: 8,
    title: "PR",
    body: null,
    state: "open",
    head: { ref: "feature", sha: "a".repeat(40) },
    base: { ref: "main", sha: "b".repeat(40) },
    user: { id: 4, login: "user", avatar_url: "https://example.invalid/avatar.png" },
    created_at: "2026-09-27T00:00:00Z",
    updated_at: "2026-09-27T00:00:00Z",
    merged_at: null,
    closed_at: null,
    html_url: "https://github.com/owner/repo/pull/8",
    mergeable: null,
    mergeable_state: "unknown",
  });
  try {
    const github = new GitHubMCPServer({ token: "fixture", baseUrl: "https://api.github.test" });
    const result = await github.getPullRequest("owner", "repo", 8);
    for (const key of ["body", "merged_at", "closed_at", "mergeable"]) {
      assert.equal(Object.hasOwn(result, key), false);
    }
    assert.doesNotThrow(() => prepareProviderResult(result));
  } finally {
    globalThis.fetch = originalFetch;
  }
});
