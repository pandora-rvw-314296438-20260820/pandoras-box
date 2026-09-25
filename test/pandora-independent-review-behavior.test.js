'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const HEAD = 'a'.repeat(40);
const pull = { state: 'open', merged: false, head: { sha: HEAD }, user: { login: 'builder' } };
const approval = { id: 42, user: { login: 'reviewer' }, author_association: 'COLLABORATOR', state: 'APPROVED', commit_id: HEAD, submitted_at: '2026-09-25T00:00:00Z' };
const load = () => import('../supabase/functions/pandora-coordinator-gate/independent-review.mjs');
const rights = [{login:'reviewer',permission:'write'}, {login:'security-reviewer',permission:'write'}];
const input = (reviews = [approval], reviewerPermissions = rights) => ({ pull, reviews, reviewerPermissions, headSha: HEAD });

test('accepts only provider-bound independent approval for the exact candidate', async () => {
  const { assertIndependentReview: check } = await load();
  assert.equal(check({ ...input(), reviewId: 'github-review:42', reviewerVendor: 'github:reviewer' }).commitSha, HEAD);
});
test('rejects no review, invented labels, self approval and stale approval', async () => {
  const { assertIndependentReview: check } = await load();
  for (const value of [input([]),
    { ...input(), reviewId: 'model-says-approved', reviewerVendor: 'openai-chatgpt' },
    input([{ ...approval, user: { login: 'builder' } }], [{login:'builder',permission:'admin'}]),
    input([{ ...approval, commit_id: 'b'.repeat(40) }]),
    input([{ ...approval, user: { login: 'outside-reader' } }]),
    input([{ ...approval, state: 'DISMISSED' }]),
  ]) assert.throws(() => check(value));
});
test('association never substitutes for current write permission', async () => {
  const { assertIndependentReview: check } = await load();
  for (const association of ['OWNER', 'MEMBER', 'COLLABORATOR']) {
    for (const permission of ['none', 'read', 'triage']) {
      assert.throws(() => check(input([{...approval,author_association:association}], [{login:'reviewer',permission}])));
    }
  }
  assert.throws(() => check(input([approval], [])));
  for (const permission of ['write', 'maintain', 'admin']) {
    assert.equal(check(input([{...approval,author_association:'NONE'}], [{login:'reviewer',permission}])).commitSha, HEAD);
  }
});
test('later decisive reviews supersede earlier approval even when input is reversed', async () => {
  const { assertIndependentReview: check } = await load();
  for (const state of ['CHANGES_REQUESTED', 'DISMISSED']) {
    const later = { ...approval, id: 43, state, submitted_at: '2026-09-25T01:00:00Z' };
    assert.throws(() => check(input([later, approval])));
  }
});
test('only a currently write-authorized change request blocks another approval', async () => {
  const { assertIndependentReview: check } = await load();
  const reviews = [approval, {...approval,id:43,user:{login:'security-reviewer'},state:'CHANGES_REQUESTED'}];
  assert.throws(() => check(input(reviews)), /CHANGES_REQUESTED/);
  assert.equal(check(input(reviews,[rights[0],{login:'security-reviewer',permission:'read'}])).commitSha,HEAD);
});
test('changed identity and unbounded review responses fail closed', async () => {
  const { assertIndependentReview: check } = await load();
  assert.throws(() => check({ ...input(), pull: { ...pull, head: { sha: 'b'.repeat(40) } } }));
  assert.throws(() => check(input(Array(100).fill(approval))));
});
test('permission reads are unique, provider-identity checked and fail closed', async () => {
  const { readReviewPermissions: read } = await load();
  const calls = [];
  const provider = {async getReviewerPermission(login) {calls.push(login);return {user:{login},permission:'write'};}};
  assert.deepEqual(await read(provider,[approval,approval,{...approval,user:{login:'commenter'},state:'COMMENTED'}]),[rights[0]]);
  assert.deepEqual(calls,['reviewer']);
  await assert.rejects(() => read({async getReviewerPermission(){return {user:{login:'wrong'},permission:'admin'};}},[approval]),/PERMISSION_INVALID/);
  await assert.rejects(() => read({async getReviewerPermission(){throw Error('GITHUB_API_403');}},[approval]),/403/);
});
test('review and effective permissions are checked before the publish fence and merge claim', () => {
  const source = fs.readFileSync('supabase/functions/pandora-coordinator-gate/index.ts', 'utf8');
  const publish = source.slice(source.indexOf('async function handlePublish'), source.indexOf('function assertMergeReady'));
  const guard = publish.indexOf('assertIndependentReview(');
  const begin = publish.indexOf('beginDecision(');
  assert.ok(guard >= 0, 'Independent review guard must be present');
  assert.ok(begin >= 0, 'Durable decision call must be present');
  assert.ok(guard < begin);
  assert.match(publish, /readReviewPermissions\(provider, reviews\)/);
  const claim = source.slice(source.indexOf('async function handleClaimMerge'), source.indexOf('async function handleCompleteMerge'));
  assert.match(claim, /assertIndependentReview/);
  assert.match(claim, /listReviews/);
  assert.match(claim, /readReviewPermissions/);
  assert.match(source, /collaborators\/\$\{encodeURIComponent\(login\)\}\/permission/);
});
