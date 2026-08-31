
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const source = readFileSync(
  resolve(process.cwd(), 'supabase/functions/pandora-project-runtime/index.ts'),
  'utf8',
);

test('new Pandora projects provision their Vercel runtime before create returns', () => {
  assert.match(
    source,
    /const createdProject = asRecord\(data\);\s*const provider = await ensureVercelProject\(context, createdProject\);\s*return projectResponse\(\{ \.\.\.createdProject, config: provider\.config \}\);/,
  );
  assert.match(source, /vercelDefaultDomain: defaultDomain/);
  assert.match(source, /vercelDefaultDomainStatus: "reserved"/);
  assert.match(source, /const defaultDomain = `\$\{providerName\}\.vercel\.app`;/);
});

test('Vercel stays a Pandora-controlled runtime target rather than an auto-Git deploy path', () => {
  assert.match(source, /skipGitConnectDuringLink: true/);
});

test('stable Vercel project domain becomes live only after exact production verification', () => {
  assert.match(
    source,
    /provider_project_id, provider_deployment_id, url, verification_state/,
  );
  assert.match(
    source,
    /const productionTarget = asRecord\(asRecord\(providerProject\.targets\)\.production\);/,
  );
  assert.match(
    source,
    /if \(textValue\(productionTarget\.id\) === providerDeploymentId\) \{\s*liveUrl = `https:\/\/\$\{defaultDomain\}`;\s*defaultDomainStatus = "live_verified";/,
  );
  assert.match(
    source,
    /Keep the exact verified deployment URL if Vercel project-alias readback is unavailable/,
  );
});
