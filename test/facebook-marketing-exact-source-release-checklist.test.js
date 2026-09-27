'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const checklist = fs.readFileSync(
  'docs/operations/FACEBOOK_MARKETING_EXACT_SOURCE_RELEASE_CHECKLIST_V1.md',
  'utf8',
);

test('FB-008 checklist binds exact source and current runtime targets', () => {
  for (const required of [
    'FB-008',
    'pandora-rvw-314296438-20260820/pandoras-box',
    '2052edd4db6f5d5fd60c19603dbb3fa9af3022ad',
    'dpl_Eiqs2w23JUT1oCEKUci2NtkXuu4Q',
    'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk',
    'jcyqixttuebxqqfkjonq',
    'ivmvufhcsezyhczzondn',
    'https://mcpmaster.vercel.app/oauth/meta/callback',
  ]) assert.ok(checklist.includes(required), required);
});

test('FB-008 checklist names tests, reviewers, authority and stop conditions', () => {
  for (const required of [
    'Pandora Node 24',
    'Engineering toolchain',
    'Operations Runtime Seams',
    'Operations Room cloud connectors',
    'Canonical release evidence',
    'THEMIS',
    'ARTEMIS',
    'Owner authorization',
    'Stop conditions',
    'Unknown is not success',
    'spend authorization',
    'tenant isolation',
    'Gitleaks',
  ]) assert.ok(checklist.toLowerCase().includes(required.toLowerCase()), required);
});

test('FB-008 checklist does not grant spend, OAuth, or client activation authority', () => {
  assert.ok(checklist.includes('does **not** authorize ad spend'));
  assert.ok(checklist.includes('does not authorize interactive Meta OAuth'));
  assert.ok(checklist.includes('or client activation'));
});
