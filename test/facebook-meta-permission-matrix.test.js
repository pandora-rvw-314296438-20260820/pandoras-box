'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const matrix = fs.readFileSync(
  'docs/operations/FACEBOOK_META_PERMISSION_MATRIX_V1.md',
  'utf8',
);

test('FB-010 matrix binds Meta app, callback and all live requested scopes', () => {
  for (const required of [
    'FB-010',
    '1657540859357214',
    '1472160808104528',
    'https://mcpmaster.vercel.app/oauth/meta/callback',
    'public_profile',
    'pages_show_list',
    'pages_read_engagement',
    'ads_read',
    'ads_management',
    'business_management',
  ]) assert.ok(matrix.includes(required), required);
});

test('FB-010 matrix preserves publication, privacy, OAuth and spend gates', () => {
  for (const required of [
    'privacy_policy_url',
    'unpublished',
    'App Review',
    'FB-011',
    'FB-046',
    'not spend authority',
    'external-customer',
  ]) assert.ok(matrix.toLowerCase().includes(required.toLowerCase()), required);
});
