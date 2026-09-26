
const SHA40 = /^[0-9a-f]{40}$/;
const WRITE_PERMISSIONS = new Set(['write', 'maintain', 'admin']);
const DECISIVE = new Set(['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED']);
const record = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

export const REVIEW_POLICY = Object.freeze({
  requiredApprovals: 0,
  source: 'github_ruleset_zero_required_approvals',
});

export function assertReviewSafety(input) {
  const { pull, reviews, reviewerPermissions, headSha } = record(input);
  const pr = record(pull);
  const author = String(record(pr.user).login || '').toLowerCase();
  if (!SHA40.test(String(headSha || '')) || record(pr.head).sha !== headSha ||
      pr.state !== 'open' || pr.merged === true || !author || !Array.isArray(reviews) ||
      reviews.length >= 100) {
    throw new Error('REVIEW_SAFETY_IDENTITY_INVALID');
  }

  // GitHub's active ruleset requires zero approvals. The coordinator therefore
  // does not create a second approval requirement. It still blocks a current
  // CHANGES_REQUESTED review from an independent write-authorized reviewer.
  const latest = new Map();
  for (const raw of reviews) {
    const review = record(raw);
    const login = String(record(review.user).login || '').toLowerCase();
    if (!login || !DECISIVE.has(review.state)) continue;
    if (!Number.isSafeInteger(review.id) || review.id < 1 ||
        !Number.isFinite(Date.parse(review.submitted_at))) {
      throw new Error('REVIEW_SAFETY_RECORD_INVALID');
    }
    const prior = latest.get(login);
    if (!prior || Date.parse(review.submitted_at) > Date.parse(prior.submitted_at) ||
        (review.submitted_at === prior.submitted_at && review.id > prior.id)) {
      latest.set(login, review);
    }
  }

  const permissions = new Map();
  for (const entry of Array.isArray(reviewerPermissions) ? reviewerPermissions : []) {
    const permission = record(entry);
    const login = String(permission.login || '').toLowerCase();
    if (!login || permissions.has(login) ||
        !['none', 'read', 'triage', 'write', 'maintain', 'admin'].includes(permission.permission)) {
      throw new Error('REVIEW_SAFETY_PERMISSION_INVALID');
    }
    permissions.set(login, permission.permission);
  }

  const currentRequests = [...latest.values()].filter((review) => {
    const login = String(record(review.user).login || '').toLowerCase();
    return review.state === 'CHANGES_REQUESTED' && login !== author;
  });
  for (const review of currentRequests) {
    const login = String(record(review.user).login || '').toLowerCase();
    if (!permissions.has(login)) throw new Error('REVIEW_SAFETY_PERMISSION_MISSING');
    if (WRITE_PERMISSIONS.has(permissions.get(login))) {
      throw new Error('QUALIFIED_REVIEW_CHANGES_REQUESTED');
    }
  }

  return Object.freeze({
    approvalRequired: false,
    requiredApprovals: REVIEW_POLICY.requiredApprovals,
    commitSha: headSha,
    source: REVIEW_POLICY.source,
  });
}

// Older imports continue to get the owner-approved zero-approval safety policy.
export const assertIndependentReview = assertReviewSafety;

// Read current effective repository rights only for the latest active
// CHANGES_REQUESTED states. Approvals are no longer an independent gate.
export async function readReviewPermissions(provider, reviews) {
  if (!Array.isArray(reviews) || reviews.length >= 100) {
    throw new Error('REVIEW_SAFETY_IDENTITY_INVALID');
  }
  const latest = new Map();
  for (const raw of reviews) {
    const review = record(raw);
    const login = String(record(review.user).login || '').toLowerCase();
    if (!login || !DECISIVE.has(review.state)) continue;
    if (!Number.isSafeInteger(review.id) || review.id < 1 ||
        !Number.isFinite(Date.parse(review.submitted_at))) {
      throw new Error('REVIEW_SAFETY_RECORD_INVALID');
    }
    const prior = latest.get(login);
    if (!prior || Date.parse(review.submitted_at) > Date.parse(prior.submitted_at) ||
        (review.submitted_at === prior.submitted_at && review.id > prior.id)) {
      latest.set(login, review);
    }
  }
  const logins = [...latest.values()]
    .filter((review) => review.state === 'CHANGES_REQUESTED')
    .map((review) => String(record(review.user).login || '').toLowerCase());
  if (logins.length > 32 || logins.some((login) => !/^[a-z0-9][a-z0-9-]{0,99}(?:\[bot\])?$/.test(login))) {
    throw new Error('REVIEW_SAFETY_PERMISSION_UNBOUNDED');
  }
  return await Promise.all(logins.map(async (login) => {
    const value = record(await provider.getReviewerPermission(login));
    if (String(record(value.user).login || '').toLowerCase() !== login ||
        !['none', 'read', 'triage', 'write', 'maintain', 'admin'].includes(value.permission)) {
      throw new Error('REVIEW_SAFETY_PERMISSION_INVALID');
    }
    return { login, permission: value.permission };
  }));
}
