import { appendFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const API_ROOT = "https://api.github.com";
const MAX_API_BYTES = 2_000_000;
const MAX_PAGES = 10;
const FULL_SHA = /^[0-9a-f]{40}$/;
const ZERO_SHA = "0".repeat(40);
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const REVIEW_PATH = /^docs\/reviews\/[A-Za-z0-9_.-]+\.md$/;
const REPORT_REF = /^[A-Za-z0-9][A-Za-z0-9._\/-]{0,254}$/;
const REVIEW_MARKER = /<!--\s*projectos-external-review-issue\s*:\s*([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#(\d+)\s*-->/gi;
const REPORT_LINK = /https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/pull\/(\d+)/g;
const REPORT_TITLE = /^projectos-report-head: ([0-9a-f]{40})$/;
const TRUSTED_REVIEWER = "google-labs-jules";
const TRUSTED_REVIEWER_USER_ID = 161369871;
const TRUSTED_REVIEW_APP_ID = 842251;
const SAFE_REPORT_EVENTS = new Set([
  "assigned",
  "committed",
  "commented",
  "connected",
  "cross-referenced",
  "demilestoned",
  "deployed",
  "deployment_environment_changed",
  "disconnected",
  "labeled",
  "locked",
  "mentioned",
  "milestoned",
  "referenced",
  "review_dismissed",
  "review_request_removed",
  "review_requested",
  "reviewed",
  "subscribed",
  "unassigned",
  "unlabeled",
  "unlocked",
  "unsubscribed",
]);

function normalizeLogin(value) {
  return typeof value === "string"
    ? value.trim().toLowerCase().replace(/\[bot\]$/, "")
    : "";
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function summary(lines) {
  const target = process.env.GITHUB_STEP_SUMMARY;
  if (target) appendFileSync(target, `${lines.join("\n")}\n`, "utf8");
}

function pathName(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    throw new Error("GitHub pagination returned an invalid URL");
  }
}

function nextPagePath(linkHeader, expectedUrl) {
  if (!linkHeader) return undefined;
  const next = String(linkHeader)
    .split(",")
    .map((entry) => entry.trim().match(/^<([^>]+)>;\s*rel="([^"]+)"$/))
    .find((match) => match?.[2].split(/\s+/).includes("next"));
  if (!next) return undefined;
  const url = new URL(next[1]);
  assert(url.origin === API_ROOT, "GitHub pagination escaped the API origin");
  assert(pathName(url.pathname) === pathName(expectedUrl.pathname), "GitHub pagination changed the API endpoint");
  const expectedNames = new Set(expectedUrl.searchParams.keys());
  for (const name of url.searchParams.keys()) {
    assert(expectedNames.has(name) || ["page", "per_page", "after", "before"].includes(name), `GitHub pagination added the ${name} query`);
  }
  for (const [name, value] of expectedUrl.searchParams) {
    if (["page", "per_page", "after", "before"].includes(name)) continue;
    assert(url.searchParams.getAll(name).length === 1 && url.searchParams.get(name) === value, `GitHub pagination changed the ${name} query`);
  }
  return `${url.pathname}${url.search}`;
}

async function githubPage(path) {
  assert(typeof path === "string" && path.startsWith("/") && !path.startsWith("//"), "GitHub API path is invalid");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(`${API_ROOT}${path}`, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        "user-agent": "Pandoras-Box-Exact-External-Review/1.0",
      },
      redirect: "error",
      signal: controller.signal,
    });
    const declared = Number(response.headers.get("content-length") || "0");
    assert(!Number.isFinite(declared) || declared <= MAX_API_BYTES, `GitHub API response too large for ${path}`);
    const text = await response.text();
    assert(Buffer.byteLength(text, "utf8") <= MAX_API_BYTES, `GitHub API response too large for ${path}`);
    assert(response.ok, `GitHub API ${response.status} for ${path}`);
    return {
      value: JSON.parse(text),
      link: response.headers.get("link") || "",
    };
  } finally {
    clearTimeout(timer);
  }
}

async function github(path) {
  return (await githubPage(path)).value;
}

async function paginate(path) {
  const separator = path.includes("?") ? "&" : "?";
  let next = `${path}${separator}per_page=100`;
  const expectedUrl = new URL(`${API_ROOT}${path}`);
  const seen = new Set();
  const values = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    assert(!seen.has(next), `GitHub pagination looped for ${path}`);
    seen.add(next);
    const response = await githubPage(next);
    assert(Array.isArray(response.value), `Expected a GitHub list from ${path}`);
    values.push(...response.value);
    next = nextPagePath(response.link, expectedUrl);
    if (!next) return values;
  }
  throw new Error(`GitHub pagination exceeded ${MAX_PAGES} pages for ${path}`);
}

function oneMarker(body) {
  const matches = [...String(body || "").matchAll(REVIEW_MARKER)];
  assert(matches.length === 1, "target body must contain exactly one external-review issue marker");
  const repository = matches[0][1];
  const issueNumber = Number(matches[0][2]);
  assert(REPOSITORY.test(repository), "external-review issue repository is invalid");
  assert(Number.isInteger(issueNumber) && issueNumber > 0, "external-review issue number is invalid");
  return { repository, issueNumber };
}

function exactStructuredValue(source, key, pattern) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const matches = [...String(source || "").matchAll(new RegExp(
    `^\\s*${escaped}\\s*:\\s*(${pattern.source})\\s*$`,
    "gim",
  ))];
  assert(matches.length === 1, `${key} must appear exactly once`);
  return matches[0][1];
}

function assertExactReviewIssue(issue, target, targetTree, repository) {
  assert(!issue?.pull_request && issue?.state === "open", "external-review reference must be one open issue");
  assert(
    exactStructuredValue(issue.body, "projectos-target", /[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#\d+/)
      === `${repository}#${target.number}`,
    "external-review issue target is not exact",
  );
  assert(
    exactStructuredValue(issue.body, "projectos-target-base", /[0-9a-f]{40}/) === target.base.sha,
    "external-review issue base is not exact",
  );
  assert(
    exactStructuredValue(issue.body, "projectos-target-head", /[0-9a-f]{40}/) === target.head.sha,
    "external-review issue head is not exact",
  );
  assert(
    exactStructuredValue(issue.body, "projectos-target-tree", /[0-9a-f]{40}/) === targetTree,
    "external-review issue tree is not exact",
  );
}

function instant(value, label) {
  const timestamp = Date.parse(String(value || ""));
  assert(Number.isFinite(timestamp), `${label} timestamp is invalid`);
  return timestamp;
}

function latestTrustedReport(comments) {
  const reviewerComments = comments
    .filter((comment) => normalizeLogin(comment.user?.login) === TRUSTED_REVIEWER)
    .sort((left, right) => {
      const byTime = String(right.created_at || "").localeCompare(String(left.created_at || ""));
      return byTime || Number(right.id || 0) - Number(left.id || 0);
    });
  assert(reviewerComments.length > 0, "final Jules comment is missing");
  const comment = reviewerComments[0];
  assert(comment.user?.id === TRUSTED_REVIEWER_USER_ID, "final Jules comment user is not exact");
  assert(comment.user?.type === "Bot", "final Jules comment user type is not exact");
  assert(comment.performed_via_github_app?.id === TRUSTED_REVIEW_APP_ID, "final Jules comment is not authenticated by App 842251");
  assert(comment.performed_via_github_app?.slug === TRUSTED_REVIEWER, "final Jules comment App slug is not exact");
  assert(comment.updated_at === comment.created_at, "final Jules comment was edited");
  const links = [...String(comment.body || "").matchAll(REPORT_LINK)];
  assert(links.length === 1, "final Jules comment must contain exactly one report PR link");
  const affirmative = `Ready for a review! A [PR](https://github.com/${links[0][1]}/pull/${Number(links[0][2])}) has been created.`;
  assert(String(comment.body || "") === affirmative, "final Jules comment is not the exact creation attestation");
  return {
    comment,
    repository: links[0][1],
    number: Number(links[0][2]),
  };
}

function assertReportRef(value) {
  assert(REPORT_REF.test(value || ""), "report head ref is invalid");
  assert(!value.includes("..") && !value.includes("//") && !value.includes("@{"), "report head ref is unsafe");
  assert(!value.endsWith(".") && !value.endsWith("/"), "report head ref is unsafe");
}

function assertReportPull(report, reference, target, repository) {
  assert(Number.isInteger(report.number) && report.number === reference.number, "report PR number changed");
  assert(report.state === "open" && report.draft === false, "report PR must remain open and non-draft");
  assert(report.base?.sha === target.base.sha, "report PR base is not the target PR exact base");
  assert(report.base?.ref === target.base.ref, "report PR base ref differs from the target PR base ref");
  assert(String(report.base?.repo?.full_name || "").toLowerCase() === repository.toLowerCase(), "report base repository is not exact");
  assert(String(report.head?.repo?.full_name || "").toLowerCase() === repository.toLowerCase(), "report head repository is not exact");
  assert(FULL_SHA.test(report.head?.sha || ""), "report head is invalid");
  assertReportRef(report.head?.ref);
  assert(report.commits === 1, "report PR must expose exactly one commit");
  assert(report.changed_files === 1, "report PR must expose exactly one changed file");
  const title = String(report.title || "");
  const titleMatch = title.match(REPORT_TITLE);
  assert(titleMatch?.[0] === title && titleMatch[1] === report.head.sha, "initial report PR title must be exactly projectos-report-head: <exact report head SHA>");
}

async function loadReportEvidence(reportOwner, reportRepo, reference) {
  const report = await github(`/repos/${reportOwner}/${reportRepo}/pulls/${reference.number}`);
  assert(FULL_SHA.test(report.head?.sha || ""), "report head is invalid");
  assertReportRef(report.head?.ref);
  const encodedRef = encodeURIComponent(report.head.ref);
  const activityRef = encodeURIComponent(`refs/heads/${report.head.ref}`);
  const [reportIssue, reportFiles, reportCommits, reportCommit, reportRef, timeline, activity] = await Promise.all([
    github(`/repos/${reportOwner}/${reportRepo}/issues/${reference.number}`),
    paginate(`/repos/${reportOwner}/${reportRepo}/pulls/${reference.number}/files`),
    paginate(`/repos/${reportOwner}/${reportRepo}/pulls/${reference.number}/commits`),
    github(`/repos/${reportOwner}/${reportRepo}/commits/${report.head.sha}`),
    github(`/repos/${reportOwner}/${reportRepo}/git/ref/heads/${encodedRef}`),
    paginate(`/repos/${reportOwner}/${reportRepo}/issues/${reference.number}/timeline`),
    paginate(`/repos/${reportOwner}/${reportRepo}/activity?ref=${activityRef}&direction=asc&time_period=year`),
  ]);
  return { report, reportIssue, reportFiles, reportCommits, reportCommit, reportRef, timeline, activity };
}

function assertOneCommit(commit, headSha, baseSha, label) {
  assert(commit?.sha === headSha, `${label} SHA differs from the report head`);
  assert(Array.isArray(commit.parents) && commit.parents.length === 1 && commit.parents[0]?.sha === baseSha, `${label} parent differs from the exact target base`);
  assert(FULL_SHA.test(commit.commit?.tree?.sha || ""), `${label} tree is invalid`);
  assert(normalizeLogin(commit.author?.login) === TRUSTED_REVIEWER, `${label} author is not Google Jules`);
  assert(commit.author?.id === TRUSTED_REVIEWER_USER_ID, `${label} author user is not exact`);
  assert(normalizeLogin(commit.committer?.login) === TRUSTED_REVIEWER, `${label} committer is not Google Jules`);
  assert(commit.committer?.id === TRUSTED_REVIEWER_USER_ID, `${label} committer user is not exact`);
}

function assertReportEvidence(evidence, reference, target, repository) {
  const { report, reportIssue, reportFiles, reportCommits, reportCommit, reportRef, timeline, activity } = evidence;
  assertReportPull(report, reference, target, repository);
  assert(reportIssue.number === report.number && Boolean(reportIssue.pull_request), "report issue view is not the exact pull request");
  assert(reportIssue.performed_via_github_app?.id === TRUSTED_REVIEW_APP_ID, "report PR creation is not authenticated by App 842251");
  assert(reportIssue.performed_via_github_app?.slug === TRUSTED_REVIEWER, "report PR creation App slug is not Google Jules");
  assert(reportIssue.title === report.title && reportIssue.created_at === report.created_at && reportIssue.state === report.state, "report PR and App-authenticated issue snapshots differ");
  assert(reportFiles.length === 1, "report PR must change exactly one file");
  const reportPath = reportFiles[0]?.filename;
  assert(REVIEW_PATH.test(reportPath || ""), "report file path is invalid");
  assert(reportFiles[0]?.status === "added", "report file must be newly added");

  assert(reportCommits.length === 1, "report PR must have exactly one live commit");
  assertOneCommit(reportCommits[0], report.head.sha, target.base.sha, "report PR commit");
  assertOneCommit(reportCommit, report.head.sha, target.base.sha, "report commit object");
  assert(reportCommits[0].commit.tree.sha === reportCommit.commit.tree.sha, "report commit tree identities differ");

  const expectedRef = `refs/heads/${report.head.ref}`;
  assert(reportRef?.ref === expectedRef, "live report ref name differs from the PR head ref");
  assert(reportRef?.object?.type === "commit" && reportRef.object.sha === report.head.sha, "live report ref differs from the PR head commit");

  for (const event of timeline) {
    assert(SAFE_REPORT_EVENTS.has(event?.event), `report PR history contains unsafe ${event?.event} event`);
  }
  const committed = timeline.filter((event) => event?.event === "committed");
  assert(committed.length === 1, "report PR timeline must contain exactly one committed event");
  assert(committed[0].sha === report.head.sha, "report timeline commit differs from the PR head");
  assert(Array.isArray(committed[0].parents) && committed[0].parents.length === 1 && committed[0].parents[0]?.sha === target.base.sha, "report timeline commit parent differs from the exact target base");
  assert(committed[0].tree?.sha === reportCommit.commit.tree.sha, "report timeline tree differs from the live commit tree");

  assert(activity.length === 1, "report ref must have exactly one repository activity");
  const creation = activity[0];
  assert(creation.activity_type === "branch_creation", "report ref activity must be its single branch creation");
  assert(creation.ref === expectedRef, "report ref activity names a different ref");
  assert(creation.before === ZERO_SHA && creation.after === report.head.sha, "report ref creation does not bind zero to the exact report head");

  const activityAt = instant(creation.timestamp, "report ref creation");
  const reportAt = instant(report.created_at, "report PR creation");
  const commentAt = instant(reference.comment.created_at, "final Jules comment");
  assert(activityAt <= reportAt && reportAt <= commentAt, "report creation chronology is invalid");
  assert(commentAt - reportAt <= 5 * 60 * 1000, "final Jules creation attestation is too far from report PR creation");
  return reportPath;
}

async function targetPullRequest(owner, repo, eventSha) {
  const explicit = Number(process.env.TARGET_PR_NUMBER || "0");
  if (Number.isInteger(explicit) && explicit > 0) {
    return github(`/repos/${owner}/${repo}/pulls/${explicit}`);
  }
  const associated = await paginate(`/repos/${owner}/${repo}/commits/${eventSha}/pulls`);
  assert(associated.length === 1, "event source must be associated with exactly one pull request");
  return associated[0];
}

export async function main() {
  const token = process.env.GITHUB_TOKEN;
  const eventSha = process.env.EVENT_SOURCE_SHA;
  const repository = process.env.GITHUB_REPOSITORY;
  const eventName = process.env.GITHUB_EVENT_NAME;
  assert(Boolean(token), "ephemeral GitHub workflow token is unavailable");
  assert(FULL_SHA.test(eventSha || ""), "event source is not a full SHA");
  assert(REPOSITORY.test(repository || ""), "workflow repository is invalid");
  assert(["pull_request", "push", "merge_group", "workflow_dispatch"].includes(eventName), "unsupported review event");

  const [owner, repo] = repository.split("/");
  const target = await targetPullRequest(owner, repo, eventSha);
  assert(Number.isInteger(target.number) && target.number > 0, "target pull request number is invalid");
  const targetFiles = await paginate(`/repos/${owner}/${repo}/pulls/${target.number}/files`);
  const reportOnly = targetFiles.length === 1 && REVIEW_PATH.test(targetFiles[0]?.filename || "");
  if (eventName === "pull_request" && reportOnly) {
    summary([
      "### ProjectOS external review",
      "",
      "Report-only PR exemption: exactly one `docs/reviews` artifact.",
    ]);
    return;
  }

  assert(FULL_SHA.test(target.head?.sha || ""), "target pull request head is invalid");
  assert(FULL_SHA.test(target.base?.sha || ""), "target pull request base is invalid");
  const [eventCommit, targetCommit] = await Promise.all([
    github(`/repos/${owner}/${repo}/commits/${eventSha}`),
    github(`/repos/${owner}/${repo}/commits/${target.head.sha}`),
  ]);
  const eventTree = eventCommit.commit?.tree?.sha;
  const targetTree = targetCommit.commit?.tree?.sha;
  assert(FULL_SHA.test(eventTree || "") && FULL_SHA.test(targetTree || ""), "event or target tree is invalid");
  if (eventName === "pull_request") {
    assert(target.head.sha === eventSha, "target head moved or pull-request event is stale");
  } else {
    assert(eventTree === targetTree, "event source tree differs from the independently reviewed target tree");
  }

  const marker = oneMarker(target.body);
  assert(marker.repository.toLowerCase() === repository.toLowerCase(), "review issue repository must match target repository");
  const [reviewOwner, reviewRepo] = marker.repository.split("/");
  const issue = await github(`/repos/${reviewOwner}/${reviewRepo}/issues/${marker.issueNumber}`);
  assertExactReviewIssue(issue, target, targetTree, repository);
  const comments = await paginate(`/repos/${reviewOwner}/${reviewRepo}/issues/${marker.issueNumber}/comments`);
  const reference = latestTrustedReport(comments);
  assert(reference.repository.toLowerCase() === marker.repository.toLowerCase(), "report repository must match review issue repository");

  const [reportOwner, reportRepo] = reference.repository.split("/");
  const evidence = await loadReportEvidence(reportOwner, reportRepo, reference);
  const reportPath = assertReportEvidence(evidence, reference, target, repository);
  const { report, reportFiles, reportCommit } = evidence;

  const encodedPath = reportPath.split("/").map(encodeURIComponent).join("/");
  const file = await github(`/repos/${reportOwner}/${reportRepo}/contents/${encodedPath}?ref=${report.head.sha}`);
  assert(file.type === "file" && file.encoding === "base64", "report content is not a base64 file");
  assert(file.sha === reportFiles[0]?.sha, "report content blob differs from the PR file record");
  assert(Number(file.size) > 0 && Number(file.size) <= 262_144, "report file size is invalid");
  const content = Buffer.from(String(file.content || "").replace(/\s/g, ""), "base64").toString("utf8");
  assert(Buffer.byteLength(content, "utf8") === Number(file.size), "report content size does not match GitHub metadata");
  assert(
    exactStructuredValue(content, "projectos-target", /[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#\d+/)
      === `${repository}#${target.number}`,
    "report does not name the exact target PR",
  );
  assert(
    exactStructuredValue(content, "projectos-target-base", /[0-9a-f]{40}/) === target.base.sha,
    "report does not name the exact target base",
  );
  assert(
    exactStructuredValue(content, "projectos-target-head", /[0-9a-f]{40}/) === target.head.sha,
    "report does not name the exact target head",
  );
  assert(
    exactStructuredValue(content, "projectos-target-tree", /[0-9a-f]{40}/) === targetTree,
    "report does not name the exact target tree",
  );
  assert(/Google\s+Jules|Jules\s*\/\s*Gemini/i.test(content), "report does not state Google Jules identity");
  const nonblank = content.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const verdicts = nonblank.filter((line) => /^\s*projectos-verdict\s*:/i.test(line));
  assert(
    verdicts.length === 1 && /^projectos-verdict: (pass|changes-requested|blocked)$/.test(verdicts[0]),
    "report must contain exactly one exact projectos verdict",
  );
  assert(verdicts[0] === "projectos-verdict: pass", `review verdict is ${verdicts[0]?.slice("projectos-verdict: ".length) || "invalid"}`);
  assert(nonblank.at(-1) === verdicts[0], "review verdict must be the final nonblank report line");

  // Re-read every mutable identity immediately before success. The report body is
  // content-addressed by the commit that these repeated invariants bind.
  const [targetAgain, issueAgain, commentsAgain] = await Promise.all([
    github(`/repos/${owner}/${repo}/pulls/${target.number}`),
    github(`/repos/${reviewOwner}/${reviewRepo}/issues/${marker.issueNumber}`),
    paginate(`/repos/${reviewOwner}/${reviewRepo}/issues/${marker.issueNumber}/comments`),
  ]);
  assert(targetAgain.head?.sha === target.head.sha && targetAgain.base?.sha === target.base.sha, "target PR moved during external-review verification");
  const markerAgain = oneMarker(targetAgain.body);
  assert(markerAgain.repository.toLowerCase() === marker.repository.toLowerCase() && markerAgain.issueNumber === marker.issueNumber, "external-review marker changed during verification");
  assertExactReviewIssue(issueAgain, targetAgain, targetTree, repository);
  const referenceAgain = latestTrustedReport(commentsAgain);
  assert(referenceAgain.comment.id === reference.comment.id, "final Jules comment changed during verification");
  assert(referenceAgain.repository.toLowerCase() === reference.repository.toLowerCase() && referenceAgain.number === reference.number, "Jules report reference changed during verification");
  const evidenceAgain = await loadReportEvidence(reportOwner, reportRepo, referenceAgain);
  assertReportEvidence(evidenceAgain, referenceAgain, targetAgain, repository);
  assert(evidenceAgain.report.head.sha === report.head.sha, "report head changed during verification");
  assert(evidenceAgain.reportCommit.commit.tree.sha === reportCommit.commit.tree.sha, "report tree changed during verification");

  summary([
    "### ProjectOS external review",
    "",
    "Status: PASS",
    "",
    `- Event source: \`${eventSha}\``,
    `- Exact reviewed tree: \`${targetTree}\``,
    `- Target: ${repository}#${target.number}`,
    `- Target head: \`${target.head.sha}\``,
    `- Jules report PR: ${reference.repository}#${reference.number}`,
    `- Report head: \`${report.head.sha}\``,
    "- Jules App: `842251`",
    "- Verdict: pass",
  ]);
}

const directPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : "";
if (import.meta.url === directPath) {
  main().catch((error) => {
    const message = error instanceof Error ? error.message : "external review verification failed";
    summary(["### ProjectOS external review", "", "Status: FAIL", "", `- ${message}`]);
    console.error(message);
    process.exitCode = 1;
  });
}
