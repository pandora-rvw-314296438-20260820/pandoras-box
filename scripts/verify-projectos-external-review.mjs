import { appendFileSync } from "node:fs";

const API_ROOT = "https://api.github.com";
const MAX_API_BYTES = 2_000_000;
const MAX_PAGES = 10;
const FULL_SHA = /^[0-9a-f]{40}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const REVIEW_PATH = /^docs\/reviews\/[A-Za-z0-9_.-]+\.md$/;
const REVIEW_MARKER = /<!--\s*projectos-external-review-issue\s*:\s*([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#(\d+)\s*-->/gi;
const REPORT_LINK = /https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/pull\/(\d+)/g;
const TRUSTED_REVIEWER = "google-labs-jules";

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

async function github(path) {
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
    return JSON.parse(text);
  } finally {
    clearTimeout(timer);
  }
}

async function paginate(path) {
  const values = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const separator = path.includes("?") ? "&" : "?";
    const batch = await github(`${path}${separator}per_page=100&page=${page}`);
    assert(Array.isArray(batch), `Expected a GitHub list from ${path}`);
    values.push(...batch);
    if (batch.length < 100) return values;
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

function latestTrustedReport(comments) {
  const reports = comments
    .filter((comment) => normalizeLogin(comment.user?.login) === TRUSTED_REVIEWER)
    .map((comment) => {
      const links = [...String(comment.body || "").matchAll(REPORT_LINK)];
      if (links.length !== 1) return undefined;
      return {
        comment,
        repository: links[0][1],
        number: Number(links[0][2]),
      };
    })
    .filter(Boolean)
    .sort((left, right) => String(right.comment.created_at || "")
      .localeCompare(String(left.comment.created_at || "")));
  assert(reports.length > 0, "latest trusted Jules report link is missing");
  return reports[0];
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

async function main() {
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
  assert(!issue.pull_request, "external-review reference must be an issue");
  const comments = await paginate(`/repos/${reviewOwner}/${reviewRepo}/issues/${marker.issueNumber}/comments`);
  const reference = latestTrustedReport(comments);
  assert(reference.repository.toLowerCase() === marker.repository.toLowerCase(), "report repository must match review issue repository");

  const [reportOwner, reportRepo] = reference.repository.split("/");
  const report = await github(`/repos/${reportOwner}/${reportRepo}/pulls/${reference.number}`);
  assert(FULL_SHA.test(report.head?.sha || ""), "report head is invalid");
  const [reportFiles, reportCommit] = await Promise.all([
    paginate(`/repos/${reportOwner}/${reportRepo}/pulls/${reference.number}/files`),
    github(`/repos/${reportOwner}/${reportRepo}/commits/${report.head.sha}`),
  ]);
  assert(report.base?.sha === target.base.sha, "report PR base is not the target PR exact base");
  assert(normalizeLogin(reportCommit.author?.login) === TRUSTED_REVIEWER, "report head author is not Google Jules");
  assert(normalizeLogin(reportCommit.committer?.login) === TRUSTED_REVIEWER, "report head committer is not Google Jules");
  assert(reportFiles.length === 1, "report PR must change exactly one file");
  const reportPath = reportFiles[0]?.filename;
  assert(REVIEW_PATH.test(reportPath || ""), "report file path is invalid");

  const encodedPath = reportPath.split("/").map(encodeURIComponent).join("/");
  const file = await github(`/repos/${reportOwner}/${reportRepo}/contents/${encodedPath}?ref=${report.head.sha}`);
  assert(file.type === "file" && file.encoding === "base64", "report content is not a base64 file");
  assert(Number(file.size) > 0 && Number(file.size) <= 262_144, "report file size is invalid");
  const content = Buffer.from(String(file.content || "").replace(/\s/g, ""), "base64").toString("utf8");
  assert(Buffer.byteLength(content, "utf8") === Number(file.size), "report content size does not match GitHub metadata");
  assert(content.includes(`${repository}#${target.number}`), "report does not name the exact target PR");
  assert(content.includes(target.head.sha), "report does not name the exact target head");
  assert(content.includes(targetTree), "report does not name the exact target tree");
  assert(/Google\s+Jules|Jules\s*\/\s*Gemini/i.test(content), "report does not state Google Jules identity");
  const verdicts = [...content.matchAll(/^\s*projectos-verdict\s*:\s*(pass|fail|changes-requested|blocked)\s*$/gim)];
  assert(verdicts.length === 1, "report must contain exactly one projectos verdict");
  assert(verdicts[0][1].toLowerCase() === "pass", `review verdict is ${verdicts[0][1].toLowerCase()}`);

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
    "- Verdict: pass",
  ]);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : "external review verification failed";
  summary(["### ProjectOS external review", "", "Status: FAIL", "", `- ${message}`]);
  console.error(message);
  process.exitCode = 1;
});
