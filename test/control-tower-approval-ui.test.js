const assert = require('node:assert/strict');
const { readFile, readdir } = require('node:fs/promises');
const path = require('node:path');
const test = require('node:test');

async function files(root) {
  const entries = await readdir(root, { withFileTypes: true });
  return (await Promise.all(entries.map(async (entry) => {
    const target = path.join(root, entry.name);
    return entry.isDirectory() ? files(target) : [target];
  }))).flat();
}

test('Control Tower ordinary approval has no MFA escalation or AAL UI', async () => {
  const sources = await Promise.all((await files('apps/control-tower'))
    .filter((file) => /\.(?:js|html|css)$/.test(file))
    .map((file) => readFile(file, 'utf8')));
  const combined = sources.join('\n');
  assert.doesNotMatch(combined, /ensureAal2|challengeAndVerify|verify security|authenticator code|six-digit|aal1|aal2|totp/i);
  assert.doesNotMatch(combined, /\.auth\.mfa/);
  assert.match(combined, /Approvals remain limited to authenticated owners and admins/);
});

test('Control Tower strips every caller-controlled privileged internal header', async () => {
  const auth = await readFile('apps/control-tower/auth.js', 'utf8');
  for (const header of [
    'x-approval-token',
    'x-approver-id',
    'x-vercel-oidc-token',
    'x-vercel-sc-headers',
  ]) {
    assert.match(auth, new RegExp(`headers\\.delete\\('${header}'\\)`));
  }
});

test('Control Tower owner shell does not force sign-in when the page first loads', async () => {
  const ownerApp = await readFile('apps/control-tower/owner-app.js', 'utf8');
  const auth = await readFile('apps/control-tower/auth.js', 'utf8');
  assert.match(ownerApp, /if \(state\.session\?\.authenticated\) \{\s*refresh\(\);\s*\} else \{/);
  assert.match(ownerApp, /if \(!state\.session\?\.authenticated\) \{\s*await beginOwnerSession\(\);/);
  assert.doesNotMatch(ownerApp, /navigate\(state\.route, \{ replace: true \}\);\s*refresh\(\);\s*\}/);
  assert.match(auth, /Sign in to Pandora/);
  assert.doesNotMatch(auth, /Sign in to MCPMaster|this MCPMaster organization/);
});
