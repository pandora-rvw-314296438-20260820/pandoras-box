'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const HEAD = 'a'.repeat(40);
const pull = { state: 'open', merged: false, head: { sha: HEAD }, user: { login: 'builder' } };
const approval = { id: 42, user: { login: 'reviewer' }, author_association: 'COLLABORATOR', state: 'APPROVED', commit_id: HEAD, submitted_at: '2026-09-25T00:00:00Z' };
const load = () => import('../supabase/functions/pandora-coordinator-gate/independent-review.mjs');
const input = (reviews = [approval]) => ({ pull, reviews, headSha: HEAD });

test('accepts only provider-bound independent approval for the exact candidate', async () => {
  const { assertIndependentReview: check } = await load();
  assert.equal(check({ ...input(), reviewId: 'github-review:42', reviewerVendor: 'github:reviewer' }).commitSha, HEAD);
});
test('rejects no review, invented labels, self approval and stale approval', async () => {
  const { assertIndependentReview: check } = await load();
  for (const value of [
    input([]),
    { ...input(), reviewId: 'model-says-approved', reviewerVendor: 'openai-chatgpt' },
    input([{ ...approval, user: { login: 'builder' } }]),
    input([{ ...approval, commit_id: 'b'.repeat(40) }]),
    input([{ ...approval, author_association: 'NONE' }]),
    input([{ ...approval, state: 'DISMISSED' }]),
  ]) assert.throws(() => check(value));
});
test('later decisive reviews supersede earlier approval even when input is reversed', async () => {
  const { assertIndependentReview: check } = await load();
  for (const state of ['CHANGES_REQUESTED', 'DISMISSED']) {
    const later = { ...approval, id: 43, state, submitted_at: '2026-09-25T01:00:00Z' };
    assert.throws(() => check(input([later, approval])));
  }
});
test('a qualified change request blocks another reviewers approval', async () => {
  const { assertIndependentReview: check } = await load();
  assert.throws(() => check(input([approval, { ...approval, id: 43, user: { login: 'security-reviewer' }, state: 'CHANGES_REQUESTED' }])), /CHANGES_REQUESTED/);
});
test('changed PR identity and unbounded review responses fail closed', async () => {
  const { assertIndependentReview: check } = await load();
  assert.throws(() => check({ ...input(), pull: { ...pull, head: { sha: 'b'.repeat(40) } } }));
  assert.throws(() => check(input(Array(100).fill(approval))));
});
test('review verification precedes the durable publish fence and is repeated at merge claim', () => {
  const source = fs.readFileSync('supabase/functions/pandora-coordinator-gate/index.ts', 'utf8');
  const publish = source.slice(source.indexOf('async function handlePublish'), source.indexOf('function assertMergeReady'));
  assert.ok(publish.indexOf('assertIndependentReview(') < publish.indexOf('beginDecision('));
  const claim = source.slice(source.indexOf('async function handleClaimMerge'), source.indexOf('async function handleCompleteMerge'));
  assert.match(claim, /assertIndependentReview/);
  assert.match(claim, /listReviews/);
});
