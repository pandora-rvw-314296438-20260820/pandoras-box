// Consumes provider-read review objects, never a model's assertion of approval.
const SHA40 = /^[0-9a-f]{40}$/;
const QUALIFIED = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
const DECISIVE = new Set(['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED']);
const record = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};

export function assertIndependentReview(input) {
  const { pull, reviews, headSha, reviewId, reviewerVendor } = record(input);
  const pr = record(pull);
  const author = String(record(pr.user).login || '').toLowerCase();
  if (!SHA40.test(String(headSha || '')) || record(pr.head).sha !== headSha ||
      pr.state !== 'open' || pr.merged === true || !author || !Array.isArray(reviews) ||
      reviews.length >= 100) {
    throw new Error('INDEPENDENT_REVIEW_IDENTITY_INVALID');
  }
  const latest = new Map();
  for (const raw of reviews) {
    const review = record(raw);
    const login = String(record(review.user).login || '').toLowerCase();
    if (!login || !DECISIVE.has(review.state)) continue;
    if (!Number.isSafeInteger(review.id) || review.id < 1 ||
        !Number.isFinite(Date.parse(review.submitted_at))) {
      throw new Error('INDEPENDENT_REVIEW_RECORD_INVALID');
    }
    const prior = latest.get(login);
    if (!prior || Date.parse(review.submitted_at) > Date.parse(prior.submitted_at) ||
        (review.submitted_at === prior.submitted_at && review.id > prior.id)) {
      latest.set(login, review);
    }
  }
  const qualified = [...latest.values()].filter((review) =>
    QUALIFIED.has(review.author_association) &&
    String(record(review.user).login).toLowerCase() !== author);
  if (qualified.some((review) => review.state === 'CHANGES_REQUESTED')) {
    throw new Error('INDEPENDENT_REVIEW_CHANGES_REQUESTED');
  }
  const approvals = qualified.filter((review) =>
    review.state === 'APPROVED' && review.commit_id === headSha);
  const bound = reviewId !== undefined || reviewerVendor !== undefined;
  const matched = approvals.find((review) => !bound ||
    (reviewId === `github-review:${review.id}` &&
     reviewerVendor === `github:${record(review.user).login}`));
  if (!matched) throw new Error('INDEPENDENT_EXACT_HEAD_APPROVAL_REQUIRED');
  return Object.freeze({
    reviewId: `github-review:${matched.id}`,
    reviewerVendor: `github:${record(matched.user).login}`,
    commitSha: headSha,
    source: 'github_provider_review',
  });
}
