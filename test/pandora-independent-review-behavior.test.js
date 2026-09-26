
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const HEAD = 'a'.repeat(40);
const pull = { state: 'open', merged: false, head: { sha: HEAD }, user: { login: 'builder' } };
const baseReview = {
  id: 42,
  user: { login: 'reviewer' },
  author_association: 'COLLABORATOR',
  state: 'APPROVED',
  commit_id: HEAD,
  submitted_at: '2026-09-25T00:00:00Z',
};
const load = () => import('../supabase/functions/pandora-coordinator-gate/independent-review.mjs');
const input = (reviews = [], reviewerPermissions = []) => ({ pull, reviews, reviewerPermissions, headSha: HEAD });

test('GitHub zero-approval policy permits an exact open candidate with no review', async () => {
  const { assertReviewSafety: check, REVIEW_POLICY } = await load();
  const result = check(input());
  assert.equal(REVIEW_POLICY.requiredApprovals, 0);
  assert.equal(result.approvalRequired, false);
  assert.equal(result.requiredApprovals, 0);
  assert.equal(result.commitSha, HEAD);
  assert.equal(result.source, 'github_ruleset_zero_required_approvals');
});

test('approvals, comments and dismissed reviews are not an additional coordinator requirement', async () => {
  const { assertReviewSafety: check } = await load();
  for (const reviews of [
    [baseReview],
    [{ ...baseReview, state: 'COMMENTED' }],
    [{ ...baseReview, state: 'DISMISSED' }],
    [{ ...baseReview, commit_id: 'b'.repeat(40) }],
    [{ ...baseReview, user: { login: 'builder' } }],
  ]) {
    assert.equal(check(input(reviews)).requiredApprovals, 0);
  }
});

test('a current write-authorized CHANGES_REQUESTED review blocks PASS and merge', async () => {
  const { assertReviewSafety: check } = await load();
  const request = { ...baseReview, state: 'CHANGES_REQUESTED' };
  for (const permission of ['write', 'maintain', 'admin']) {
    assert.throws(
      () => check(input([request], [{ login: 'reviewer', permission }])),
      /QUALIFIED_REVIEW_CHANGES_REQUESTED/,
    );
  }
});

test('read-only or dismissed change requests do not create an approval gate', async () => {
  const { assertReviewSafety: check } = await load();
  const request = { ...baseReview, state: 'CHANGES_REQUESTED' };
  for (const permission of ['none', 'read', 'triage']) {
    assert.equal(check(input([request], [{ login: 'reviewer', permission }])).requiredApprovals, 0);
  }
  const dismissed = { ...baseReview, id: 43, state: 'DISMISSED', submitted_at: '2026-09-25T01:00:00Z' };
  assert.equal(check(input([request, dismissed])).requiredApprovals, 0);
});

test('latest decisive review state wins independent of provider ordering', async () => {
  const { assertReviewSafety: check } = await load();
  const request = { ...baseReview, id: 43, state: 'CHANGES_REQUESTED', submitted_at: '2026-09-25T01:00:00Z' };
  const dismissed = { ...baseReview, id: 44, state: 'DISMISSED', submitted_at: '2026-09-25T02:00:00Z' };
  assert.equal(check(input([dismissed, request])).requiredApprovals, 0);
  assert.throws(
    () => check(input([request, baseReview], [{ login: 'reviewer', permission: 'write' }])),
    /QUALIFIED_REVIEW_CHANGES_REQUESTED/,
  );
});

test('unknown permission for a current external change request fails closed', async () => {
  const { assertReviewSafety: check } = await load();
  const request = { ...baseReview, state: 'CHANGES_REQUESTED' };
  assert.throws(() => check(input([request], [])), /PERMISSION_MISSING/);
});

test('malformed decisive review identity and unbounded provider responses fail closed', async () => {
  const { assertReviewSafety: check } = await load();
  assert.throws(() => check({ ...input(), pull: { ...pull, head: { sha: 'b'.repeat(40) } } }), /IDENTITY_INVALID/);
  assert.throws(() => check(input(Array(100).fill(baseReview))), /IDENTITY_INVALID/);
  assert.throws(() => check(input([{ ...baseReview, id: 0, state: 'CHANGES_REQUESTED' }])), /RECORD_INVALID/);
  assert.throws(() => check(input([{ ...baseReview, submitted_at: 'invalid', state: 'CHANGES_REQUESTED' }])), /RECORD_INVALID/);
});

test('permission reads are limited to the latest active change requester and remain provider-identity checked', async () => {
  const { readReviewPermissions: read } = await load();
  const approval = baseReview;
  const request = { ...baseReview, id: 43, state: 'CHANGES_REQUESTED', submitted_at: '2026-09-25T01:00:00Z' };
  const dismissed = { ...baseReview, id: 44, state: 'DISMISSED', submitted_at: '2026-09-25T02:00:00Z' };
  const calls = [];
  const provider = { async getReviewerPermission(login) { calls.push(login); return { user: { login }, permission: 'write' }; } };

  assert.deepEqual(await read(provider, [approval, { ...approval, state: 'COMMENTED' }]), []);
  assert.deepEqual(calls, []);
  assert.deepEqual(await read(provider, [request]), [{ login: 'reviewer', permission: 'write' }]);
  assert.deepEqual(calls, ['reviewer']);
  assert.deepEqual(await read(provider, [request, dismissed]), []);
  assert.deepEqual(calls, ['reviewer']);

  await assert.rejects(
    () => read({ async getReviewerPermission() { return { user: { login: 'wrong' }, permission: 'admin' }; } }, [request]),
    /PERMISSION_INVALID/,
  );
});

test('review safety remains before publish fence and merge claim while approval is no longer required', () => {
  const source = fs.readFileSync('supabase/functions/pandora-coordinator-gate/index.ts', 'utf8');
  const publish = source.slice(source.indexOf('async function handlePublish'), source.indexOf('function assertMergeReady'));
  const guard = publish.indexOf('assertReviewSafety(');
  const begin = publish.indexOf('beginDecision(');
  assert.ok(guard >= 0);
  assert.ok(begin >= 0);
  assert.ok(guard < begin);
  assert.match(publish, /readReviewPermissions\(provider, reviews\)/);
  assert.doesNotMatch(publish, /INDEPENDENT_EXACT_HEAD_APPROVAL_REQUIRED/);

  const claim = source.slice(source.indexOf('async function handleClaimMerge'), source.indexOf('async function handleCompleteMerge'));
  assert.match(claim, /assertReviewSafety/);
  assert.match(claim, /listReviews/);
  assert.match(claim, /readReviewPermissions/);
  assert.match(source, /collaborators\/\$\{encodeURIComponent\(login\)\}\/permission/);
});

test('backward export follows the same zero-approval safety semantics', async () => {
  const { assertIndependentReview } = await load();
  assert.equal(assertIndependentReview(input()).requiredApprovals, 0);
});
