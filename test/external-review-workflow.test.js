"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { readFileSync, readdirSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { pathToFileURL } = require("node:url");

const root = join(__dirname, "..");
const workflowDirectory = join(root, ".github/workflows");
const verifierPath = join(root, "scripts/verify-projectos-external-review.mjs");
const verifier = readFileSync(verifierPath, "utf8");
const workflows = readdirSync(workflowDirectory, { withFileTypes: true })
  .filter((entry) => entry.isFile() && /\.ya?ml$/i.test(entry.name))
  .map((entry) => ({
    name: entry.name,
    source: readFileSync(join(workflowDirectory, entry.name), "utf8"),
  }));
const releaseContract = JSON.parse(readFileSync(
  join(root, "docs/releases/canonical/release-evidence.source.json"),
  "utf8",
));

const repository = "banataosystems/Pandoras-box";
const targetHead = "a".repeat(40);
const targetBase = "b".repeat(40);
const targetTree = "c".repeat(40);
const reportHead = "d".repeat(40);
const reportTree = "e".repeat(40);
const reportBlob = "f".repeat(40);
const reportRef = "jules/report-200";
const reportPath = "docs/reviews/pr-137.md";
const jules = {
  login: "google-labs-jules[bot]",
  id: 161369871,
  type: "Bot",
};

function commit(sha = reportHead) {
  return {
    sha,
    parents: [{ sha: targetBase }],
    commit: { tree: { sha: reportTree } },
    author: { ...jules },
    committer: { ...jules },
  };
}

function createFixture() {
  const reportContent = [
    "Google Jules independent review",
    `projectos-target: ${repository}#137`,
    `projectos-target-base: ${targetBase}`,
    `projectos-target-head: ${targetHead}`,
    `projectos-target-tree: ${targetTree}`,
    "projectos-verdict: pass",
  ].join("\n");
  const state = {
    target: {
      number: 137,
      body: `candidate\n<!-- projectos-external-review-issue: ${repository}#146 -->`,
      head: { sha: targetHead },
      base: { sha: targetBase, ref: "main", repo: { full_name: repository } },
    },
    targetFiles: [{ filename: "src/main.js" }],
    targetCommit: { sha: targetHead, commit: { tree: { sha: targetTree } } },
    issue: {
      number: 146,
      state: "open",
      body: [
        `projectos-target: ${repository}#137`,
        `projectos-target-base: ${targetBase}`,
        `projectos-target-head: ${targetHead}`,
        `projectos-target-tree: ${targetTree}`,
      ].join("\n"),
    },
    comments: [
      {
        id: 10,
        user: { ...jules },
        performed_via_github_app: { id: 842251, slug: "google-labs-jules" },
        created_at: "2026-08-24T01:00:00Z",
        updated_at: "2026-08-24T01:00:00Z",
        body: "Jules is on it.",
      },
      {
        id: 11,
        user: { ...jules },
        performed_via_github_app: { id: 842251, slug: "google-labs-jules" },
        created_at: "2026-08-24T01:05:02Z",
        updated_at: "2026-08-24T01:05:02Z",
        body: `Ready for a review! A [PR](https://github.com/${repository}/pull/200) has been created.`,
      },
    ],
    report: {
      number: 200,
      state: "open",
      draft: false,
      title: `projectos-report-head: ${reportHead}`,
      created_at: "2026-08-24T01:05:01Z",
      user: { login: "banataosystems", id: 314296438 },
      base: { sha: targetBase, ref: "main", repo: { full_name: repository } },
      head: {
        sha: reportHead,
        ref: reportRef,
        repo: { full_name: repository },
      },
      commits: 1,
      changed_files: 1,
    },
    reportIssue: {
      number: 200,
      title: `projectos-report-head: ${reportHead}`,
      created_at: "2026-08-24T01:05:01Z",
      state: "open",
      pull_request: { url: `https://api.github.com/repos/${repository}/pulls/200` },
      performed_via_github_app: { id: 842251, slug: "google-labs-jules" },
    },
    reportFiles: [{ filename: reportPath, sha: reportBlob, status: "added" }],
    reportCommits: [commit()],
    reportCommit: commit(),
    liveRef: {
      ref: `refs/heads/${reportRef}`,
      object: { type: "commit", sha: reportHead },
    },
    timeline: [
      {
        event: "committed",
        sha: reportHead,
        parents: [{ sha: targetBase }],
        tree: { sha: reportTree },
      },
      {
        id: 12,
        event: "commented",
        actor: { ...jules },
        performed_via_github_app: { id: 842251 },
      },
    ],
    reportComments: [
      {
        id: 12,
        user: { ...jules },
        performed_via_github_app: { id: 842251 },
        created_at: "2026-08-24T01:05:02Z",
        updated_at: "2026-08-24T01:05:02Z",
        body: "👋 Jules, reporting for duty!",
      },
    ],
    activity: [
      {
        activity_type: "branch_creation",
        ref: `refs/heads/${reportRef}`,
        before: "0".repeat(40),
        after: reportHead,
        timestamp: "2026-08-24T01:05:00Z",
        actor: { login: "banataosystems", id: 314296438 },
      },
    ],
    file: {
      type: "file",
      encoding: "base64",
      sha: reportBlob,
      size: Buffer.byteLength(reportContent),
      content: Buffer.from(reportContent).toString("base64"),
    },
    routes: {},
  };
  return state;
}

function routeKind(url) {
  const path = decodeURIComponent(url.pathname);
  const prefix = `/repos/${repository}`;
  if (path === `${prefix}/pulls/137`) return "target";
  if (path === `${prefix}/pulls/137/files`) return "targetFiles";
  if (path === `${prefix}/commits/${targetHead}`) return "targetCommit";
  if (path === `${prefix}/issues/146`) return "issue";
  if (path === `${prefix}/issues/146/comments`) return "comments";
  if (path === `${prefix}/pulls/200`) return "report";
  if (path === `${prefix}/issues/200`) return "reportIssue";
  if (path === `${prefix}/pulls/200/files`) return "reportFiles";
  if (path === `${prefix}/pulls/200/commits`) return "reportCommits";
  if (path.startsWith(`${prefix}/commits/`)) return "reportCommit";
  if (path === `${prefix}/git/ref/heads/${reportRef}`) return "liveRef";
  if (path === `${prefix}/issues/200/comments`) return "reportComments";
  if (path === `${prefix}/issues/200/timeline`) return "timeline";
  if (path === `${prefix}/activity`) return "activity";
  if (path === `${prefix}/contents/${reportPath}`) return "file";
  return "missing";
}

async function runFixture(mutate = () => {}) {
  const state = createFixture();
  mutate(state);
  const counts = new Map();
  const previousFetch = global.fetch;
  const previousEnvironment = new Map();
  for (const [name, value] of Object.entries({
    GITHUB_TOKEN: "test-token",
    EVENT_SOURCE_SHA: targetHead,
    GITHUB_REPOSITORY: repository,
    GITHUB_EVENT_NAME: "pull_request",
    TARGET_PR_NUMBER: "137",
    GITHUB_STEP_SUMMARY: undefined,
  })) {
    previousEnvironment.set(name, process.env[name]);
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  global.fetch = async (input) => {
    const url = new URL(String(input));
    const kind = routeKind(url);
    const count = (counts.get(kind) || 0) + 1;
    counts.set(kind, count);
    let result;
    if (state.routes[kind]) {
      result = state.routes[kind]({ count, state, url });
    } else if (kind === "timeline" && !url.searchParams.has("page")) {
      const next = new URL(url);
      next.searchParams.set("page", "2");
      result = { body: state.timeline, link: `<${next.href}>; rel="next"` };
    } else if (kind === "timeline") {
      result = { body: [] };
    } else if (kind === "activity" && url.searchParams.get("time_period") !== "year") {
      result = { body: { message: "year bound missing" }, status: 422 };
    } else if (kind === "activity" && !url.searchParams.has("after")) {
      const next = new URL(url);
      next.searchParams.set("after", "cursor-1");
      result = { body: [], link: `<${next.href}>; rel="next"` };
    } else if (kind === "activity") {
      result = { body: state.activity };
    } else if (kind === "missing") {
      result = { body: { message: "not found" }, status: 404 };
    } else {
      result = { body: state[kind] };
    }
    const body = JSON.stringify(result.body);
    const headers = {
      "content-type": "application/json",
      "content-length": String(Buffer.byteLength(body)),
    };
    if (result.link) headers.link = result.link;
    return new Response(body, { status: result.status || 200, headers });
  };

  try {
    const module = await import(pathToFileURL(verifierPath).href);
    await module.main();
  } finally {
    global.fetch = previousFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

test("candidate-controlled workflows cannot produce the trusted external-review context", () => {
  assert.ok(workflows.length > 0);
  for (const { name, source } of workflows) {
    assert.doesNotMatch(
      source,
      /^\s{2}["']?(?:external-review|Vercel Agent Review|vercel-agent-review)["']?:\s*(?:#.*)?$/mi,
      name,
    );
    assert.doesNotMatch(
      source,
      /^\s+name:\s*["']?(?:external-review|Vercel Agent Review)["']?\s*(?:#.*)?$/mi,
      name,
    );
    assert.doesNotMatch(source, /\b(?:checks|statuses)\s*:\s*["']?write["']?\b/i, name);
    assert.doesNotMatch(
      source,
      /\b(?:createCheckRun|createCommitStatus)\b|\b(?:checks|statuses)\.(?:create|update)\b|\/check-runs\b|\/statuses(?:\/|\b)/i,
      name,
    );
    assert.doesNotMatch(source, /verify-projectos-external-review\.mjs/, name);
  }

  const requirement = releaseContract.requiredChecks.find(
    (check) => check.name === "external-review",
  );
  assert.deepEqual(requirement, {
    name: "external-review",
    authority: "TRUSTED_EXTERNAL_REVIEW_PROVIDER",
    producer: "pandora_main_gate_github_app",
    providerContext: "external-review",
    appId: 4658204,
    command: null,
    status: "pending_external_receipt",
    receipt: null,
  });
});

test("the non-authoritative review inspector still binds evidence to an exact PR head", () => {
  execFileSync(process.execPath, ["--check", verifierPath], { cwd: root, stdio: "pipe" });
  assert.match(verifier, /target\.head\.sha === eventSha/);
  assert.match(verifier, /TRUSTED_REVIEWER = "google-labs-jules"/);
  assert.match(verifier, /TRUSTED_REVIEW_APP_ID = 842251/);
  assert.match(verifier, /performed_via_github_app\?\.id === TRUSTED_REVIEW_APP_ID/);
  assert.match(verifier, /\^projectos-report-head: \(\[0-9a-f\]\{40\}\)\$/);
  assert.match(verifier, /SAFE_REPORT_EVENTS/);
  assert.match(verifier, /report PR creation is not authenticated by App 842251/);
  assert.match(verifier, /time_period=year/);
  assert.match(verifier, /report PR timeline must contain exactly one committed event/);
  assert.match(verifier, /report ref must have exactly one repository activity/);
  assert.match(verifier, /loadReportEvidence\(reportOwner, reportRepo, referenceAgain\)/);
  assert.match(verifier, /exactStructuredValue\(content, "projectos-target-head"/);
  assert.match(verifier, /exactStructuredValue\(content, "projectos-target-tree"/);
  assert.match(verifier, /verdicts\[0\] === "projectos-verdict: pass"/);
  assert.match(verifier, /nonblank\.at\(-1\) === verdicts\[0\]/);
  assert.match(verifier, /eventName === "pull_request" && reportOnly/);
});

test("the inspector accepts only an App-authenticated, immutable, exact-head Jules report", async () => {
  await runFixture();
});

test("the inspector rejects post-attestation sibling substitution", async () => {
  await assert.rejects(runFixture((state) => {
    const sibling = "1".repeat(40);
    state.report.head.sha = sibling;
    state.reportCommits = [commit(sibling)];
    state.reportCommit = commit(sibling);
    state.liveRef.object.sha = sibling;
    state.timeline[0].sha = sibling;
    state.activity[0].after = sibling;
  }), /initial report PR title must be exactly/);
});

test("the inspector requires exact Jules completion text and a terminal verdict", async () => {
  await assert.rejects(runFixture((state) => {
    state.comments[1].body = ` ${state.comments[1].body}`;
  }), /exact creation attestation/);

  await assert.rejects(runFixture((state) => {
    const content = `${Buffer.from(state.file.content, "base64").toString("utf8")}\nAdditional text after the verdict.`;
    state.file.size = Buffer.byteLength(content);
    state.file.content = Buffer.from(content).toString("base64");
  }), /final nonblank report line/);
});

test("the inspector fails closed for every report-history mutation", async () => {
  const cases = [
    ["wrong App", (state) => { state.comments[1].performed_via_github_app.id = 8329; }, /App 842251/],
    ["wrong creation App", (state) => { state.reportIssue.performed_via_github_app.id = 8329; }, /creation is not authenticated by App 842251/],
    ["wrong creation App slug", (state) => { state.reportIssue.performed_via_github_app.slug = "attacker"; }, /App slug is not Google Jules/],
    ["mismatched issue snapshot", (state) => { state.reportIssue.title = "changed"; }, /snapshots differ/],
    ["edited final comment", (state) => { state.comments[1].updated_at = "2026-08-24T01:06:00Z"; }, /comment was edited/],
    ["renamed title", (state) => { state.timeline.push({ event: "renamed" }); }, /unsafe renamed/],
    ["force push", (state) => { state.timeline.push({ event: "head_ref_force_pushed" }); }, /unsafe head_ref_force_pushed/],
    ["head deletion", (state) => { state.timeline.push({ event: "head_ref_deleted" }); }, /unsafe head_ref_deleted/],
    ["head restoration", (state) => { state.timeline.push({ event: "head_ref_restored" }); }, /unsafe head_ref_restored/],
    ["base change", (state) => { state.timeline.push({ event: "base_ref_changed" }); }, /unsafe base_ref_changed/],
    ["closed", (state) => { state.timeline.push({ event: "closed" }); }, /unsafe closed/],
    ["reopened", (state) => { state.timeline.push({ event: "reopened" }); }, /unsafe reopened/],
    ["merged", (state) => { state.timeline.push({ event: "merged" }); }, /unsafe merged/],
    ["draft conversion", (state) => { state.timeline.push({ event: "converted_to_draft" }); }, /unsafe converted_to_draft/],
    ["ready transition", (state) => { state.timeline.push({ event: "ready_for_review" }); }, /unsafe ready_for_review/],
    ["unknown event", (state) => { state.timeline.push({ event: "future_mutation" }); }, /unsafe future_mutation/],
    ["extra committed event", (state) => { state.timeline.push({ ...state.timeline[0] }); }, /exactly one committed event/],
    ["extra live commit", (state) => { state.reportCommits.push(commit("1".repeat(40))); }, /exactly one live commit/],
    ["extra ref activity", (state) => {
      state.activity.push({
        activity_type: "push",
        ref: `refs/heads/${reportRef}`,
        before: reportHead,
        after: "1".repeat(40),
        timestamp: "2026-08-24T01:05:01Z",
        actor: { login: "banataosystems", id: 314296438 },
      });
    }, /exactly one repository activity/],
    ["live ref replacement", (state) => { state.liveRef.object.sha = "1".repeat(40); }, /live report ref differs/],
    ["extra title SHA", (state) => { state.report.title += ` ${"1".repeat(40)}`; }, /initial report PR title/],
    ["wrong exact parent", (state) => { state.reportCommit.parents[0].sha = "1".repeat(40); }, /parent differs/],
  ];
  for (const [name, mutate, expected] of cases) {
    await assert.rejects(runFixture(mutate), expected, name);
  }
});

test("the inspector repeats mutable invariants immediately before success", async () => {
  await assert.rejects(runFixture((state) => {
    const original = structuredClone(state.report);
    const moved = structuredClone(state.report);
    moved.head.sha = "1".repeat(40);
    moved.title = `projectos-report-head: ${moved.head.sha}`;
    state.routes.report = ({ count }) => ({ body: count === 1 ? original : moved });
  }), /App-authenticated issue snapshots differ|report PR commit SHA differs|report head changed during verification/);

  await assert.rejects(runFixture((state) => {
    const original = structuredClone(state.comments);
    const changed = structuredClone(state.comments);
    changed[1].id = 13;
    changed[1].created_at = "2026-08-24T01:05:03Z";
    changed[1].updated_at = "2026-08-24T01:05:03Z";
    state.routes.comments = ({ count }) => ({ body: count === 1 ? original : changed });
  }), /final Jules comment changed during verification/);
});

test("the inspector rejects pagination that changes the exact activity query", async () => {
  await assert.rejects(runFixture((state) => {
    state.routes.activity = ({ state: current, url }) => {
      if (url.searchParams.has("after")) return { body: current.activity };
      const next = new URL(url);
      next.searchParams.set("ref", "refs/heads/attacker/ref");
      next.searchParams.set("after", "cursor-1");
      return { body: [], link: `<${next.href}>; rel="next"` };
    };
  }), /pagination changed the ref query/);
});

test("the inspector bounds complete pagination", async () => {
  await assert.rejects(runFixture((state) => {
    state.routes.timeline = ({ state: current, url }) => {
      const page = Number(url.searchParams.get("page") || "1");
      const next = new URL(url);
      next.searchParams.set("page", String(page + 1));
      return {
        body: page === 1 ? current.timeline : [],
        link: `<${next.href}>; rel="next"`,
      };
    };
  }), /pagination exceeded 10 pages/);
});

test("all repository-owned required checks test the synthetic integration SHA", () => {
  const workflowPaths = [
    ".github/workflows/projectos-security.yml",
    ".github/workflows/canonical-release-evidence.yml",
    ".github/workflows/windows-worker-contract.yml",
    ".github/workflows/pandora-mobile-integration.yml",
  ];
  for (const relativePath of workflowPaths) {
    const source = readFileSync(join(root, relativePath), "utf8");
    assert.doesNotMatch(source, /github\.event\.pull_request\.head\.sha/, relativePath);
    assert.match(source, /\$\{\{ github\.sha \}\}/, relativePath);
    assert.match(
      source,
      /^\s{2}merge_group:\s*\r?\n\s{4}types: \[checks_requested\]\s*$/m,
      relativePath,
    );
  }
});
