'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createHash } = require('node:crypto');
const { mkdtemp, writeFile, rm, readFile } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');

const source = 'a'.repeat(40);
const candidate = 'https://mcpmaster-123abc456-mbanatao.vercel.app';
const canonical = 'https://mcpmaster.vercel.app';
const manifestName = 'pandora-web-release-manifest.txt';
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const manifest = (overrides = {}) => Object.entries({
  source_sha: source,
  app_version: '0.4.0-rc.14+21',
  flutter_version: '3.47.0',
  web_tree_sha256: 'b'.repeat(64),
  artifact_class: 'production-candidate',
  production_release: 'true',
  ...overrides,
}).map(([key, value]) => `${key}=${value}`).join('\n') + '\n';
let verifyWebRelease, validateTargetUrl, parseManifest, runCli;
test.before(async () => {
  ({ verifyWebRelease, validateTargetUrl, parseManifest, runCli } = await import('../scripts/verify-pandora-web-release.mjs'));
});

async function fixture(t) {
  const localRoot = await mkdtemp(join(tmpdir(), 'pandora-web-release-'));
  t.after(() => rm(localRoot, { recursive: true, force: true }));
  const bodies = {
    [manifestName]: Buffer.from(manifest()),
    'index.html': Buffer.from('<!doctype html><html><head><base href="/pandora-web/"></head><body>Fixture UI</body></html>'),
    'main.dart.js': Buffer.from('/* Fixture application bytes. */ console.log("fixture");\n'),
  };
  for (const [name, body] of Object.entries(bodies)) await writeFile(join(localRoot, name), body);
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    const name = url.split('/').at(-1);
    assert.ok(Object.hasOwn(bodies, name), 'only exact artifact paths may be fetched');
    assert.equal(options.redirect, 'manual');
    assert.deepEqual(Object.keys(options.headers).sort(), ['accept', 'cache-control']);
    assert.ok(options.signal instanceof AbortSignal);
    return response(url, bodies[name]);
  };
  return { localRoot, bodies, calls, fetchImpl,
    verify: (overrides = {}) => verifyWebRelease({ url: candidate, sourceSha: source, target: 'candidate', localRoot, fetchImpl, ...overrides }) };
}

function response(url, body, options = {}) {
  const type = url.endsWith('.txt') ? 'text/plain' : url.endsWith('.html') ? 'text/html' : 'application/javascript';
  const result = new Response(body, { status: options.status ?? 200,
    headers: { 'content-type': type, ...options.headers } });
  Object.defineProperty(result, 'url', { value: options.url ?? url });
  if (options.redirected) Object.defineProperty(result, 'redirected', { value: true });
  return result;
}

test('candidate and canonical verification bind all served bytes to the exact local source artifact', async (t) => {
  const f = await fixture(t);
  for (const [url, target] of [[candidate, 'candidate'], [canonical, 'canonical']]) {
    const receipt = await f.verify({ url, target });
    assert.equal(receipt.verified, true);
    assert.equal(receipt.url, url);
    assert.equal(receipt.source_sha, source);
    assert.equal(receipt.web_tree_sha256, 'b'.repeat(64));
    assert.equal(receipt.app_version, '0.4.0-rc.14+21');
    assert.equal(receipt.flutter_version, '3.47.0');
    assert.deepEqual(receipt.files, Object.entries(f.bodies).map(([name, bytes]) => ({
      url: `${url}/pandora-web/${name}`, sha256: sha256(bytes), bytes: bytes.length,
    })));
    assert.doesNotMatch(JSON.stringify(receipt), /Fixture UI|Fixture application bytes|console\.log|authorization|access_token/);
  }
  assert.equal(f.calls.length, 6);
  assert.ok(f.calls.every(({ options }) => options.signal.aborted));
});

test('a healthy canonical hostname serving an older source fails even when the candidate matches', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.verify()).verified, true);
  await assert.rejects(f.verify({ url: canonical, target: 'canonical', fetchImpl: async (url) =>
    response(url, manifest({ source_sha: 'c'.repeat(40) })) }), /MANIFEST_SOURCE_MISMATCH/);
});

test('a correct source label cannot hide a different web tree, app version or Flutter version', async (t) => {
  const f = await fixture(t);
  for (const changed of [{ web_tree_sha256: 'c'.repeat(64) }, { app_version: '0.4.1+22' }, { flutter_version: '3.48.0' }]) {
    await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, manifest(changed)) }), /REMOTE_MANIFEST_MISMATCH/);
  }
});

test('index and JavaScript hashes detect wrong bundles behind an otherwise identical manifest', async (t) => {
  const f = await fixture(t);
  for (const changed of ['index.html', 'main.dart.js']) {
    await assert.rejects(f.verify({ fetchImpl: async (url) => {
      const name = url.split('/').at(-1);
      return response(url, name === changed ? Buffer.concat([f.bodies[name], Buffer.from('different')]) : f.bodies[name]);
    } }), /REMOTE_BYTES_MISMATCH/);
  }
});

test('remote manifest byte identity includes line ordering and exact serialization', async (t) => {
  const f = await fixture(t);
  const reordered = manifest().trimEnd().split('\n').reverse().join('\n') + '\n';
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, reordered) }), /REMOTE_BYTES_MISMATCH/);
});

test('duplicate, missing, unknown and malformed manifest fields are rejected', () => {
  const invalid = [
    [manifest() + `source_sha=${source}\n`, 'DUPLICATE_KEY'],
    [manifest().replace(`source_sha=${source}\n`, ''), 'FIELD_MISSING'],
    [manifest() + 'unexpected=value\n', 'FIELD_INVALID'],
    [manifest({ web_tree_sha256: 'not-a-digest' }), 'TREE_INVALID'],
    [manifest({ app_version: 'unbounded-text' }), 'VERSION_INVALID'],
    [manifest({ flutter_version: 'unbounded-text' }), 'FLUTTER_INVALID'],
    [manifest({ artifact_class: 'test-only' }), 'RELEASE_INVALID'],
    [manifest({ production_release: 'false' }), 'RELEASE_INVALID'],
    [manifest().replace(/\n/g, '\r\n'), 'FIELD_INVALID'],
    ['<!doctype html>Login required', 'FIELD_INVALID'],
  ];
  for (const [body, error] of invalid) assert.throws(() => parseManifest(Buffer.from(body), source), new RegExp(error));
  assert.throws(() => parseManifest(Buffer.from([0xff, 0xfe]), source), /ENCODING_INVALID/);
  assert.throws(() => parseManifest(Buffer.from(manifest()), 'not-a-source'), /SOURCE_SHA_INVALID/);
});

test('duplicate remote keys fail before a receipt can be produced', async (t) => {
  const f = await fixture(t);
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, manifest() + `source_sha=${source}\n`) }), /MANIFEST_DUPLICATE_KEY/);
});

test('invalid local release metadata stops before network requests', async (t) => {
  const f = await fixture(t);
  await writeFile(join(f.localRoot, manifestName), manifest() + `source_sha=${source}\n`);
  await assert.rejects(f.verify(), /MANIFEST_DUPLICATE_KEY/);
  assert.equal(f.calls.length, 0);
});

test('malformed or unscoped URL forms cannot become verification targets', () => {
  const invalid = [
    'http://mcpmaster-123abc456-mbanatao.vercel.app',
    `${candidate}:443`, `${candidate}/login`, `${candidate}?token=fixture`, `${candidate}#fragment`,
    'https://user:fixture@mcpmaster-123abc456-mbanatao.vercel.app',
    ` ${candidate}`, `${candidate}\n`, 'https://127.0.0.1', 'file:///tmp/artifact',
    'https://mcpmaster-123abc456-mbanatao.vercel.app.attacker.invalid',
    'https://mcpmaster-mbanatao.vercel.app', 'https://another-project-123abc456-mbanatao.vercel.app',
    `${candidate}/%2e%2e/`, `${candidate}\\login`,
  ];
  for (const url of invalid) assert.throws(() => validateTargetUrl(url, 'candidate'), /TARGET_/);
  assert.throws(() => validateTargetUrl(canonical, 'candidate'), /TARGET_ORIGIN_INVALID/);
  assert.throws(() => validateTargetUrl(candidate, 'canonical'), /TARGET_ORIGIN_INVALID/);
  assert.equal(validateTargetUrl(`${candidate}/`, 'candidate'), candidate);
  assert.equal(validateTargetUrl(canonical, 'canonical'), canonical);
});

test('redirects, protected deployments, errors and unexpected response URLs fail closed', async (t) => {
  const f = await fixture(t);
  for (const status of [301, 302, 307, 308, 401, 403, 404, 500]) {
    await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, 'private response body',
      { status, headers: { location: 'https://vercel.com/login' } }) }), /REMOTE_RESPONSE_INVALID/);
  }
  for (const options of [{ redirected: true }, { url: 'https://vercel.com/login' }]) {
    await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, f.bodies[manifestName], options) }), /REMOTE_RESPONSE_INVALID/);
  }
});

test('200 login/error pages and missing bodies are never status-only release proof', async (t) => {
  const f = await fixture(t);
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, '<html>Login</html>',
    { headers: { 'content-type': 'text/html' } }) }), /REMOTE_CONTENT_TYPE_INVALID/);
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, '{"ok":true}',
    { headers: { 'content-type': 'application/json' } }) }), /REMOTE_CONTENT_TYPE_INVALID/);
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, null) }), /REMOTE_BODY_MISSING/);
  await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, '') }), /REMOTE_BODY_EMPTY/);
});

test('declared oversized or malformed lengths reject before reading response bodies', async (t) => {
  const f = await fixture(t);
  for (const length of ['16385', '999999999999999999999999', '-1', '16x', '0']) {
    await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, f.bodies[manifestName],
      { headers: { 'content-length': length } }) }), /REMOTE_SIZE_INVALID/);
  }
});

test('chunked bodies remain bounded even when Content-Length is absent or false', async (t) => {
  const f = await fixture(t);
  for (const headers of [{}, { 'content-length': '1' }]) {
    let cancelled = false;
    await assert.rejects(f.verify({ fetchImpl: async (url) => response(url, new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array(16 * 1024 + 1)); },
      cancel() { cancelled = true; },
    }), { headers }) }), /REMOTE_BODY_TOO_LARGE/);
    assert.equal(cancelled, true);
  }
});

test('the deadline bounds both request acceptance and a stalled response stream', async (t) => {
  const f = await fixture(t);
  let requestSignal;
  await assert.rejects(f.verify({ timeoutMs: 15, fetchImpl: async (_, options) => {
    requestSignal = options.signal;
    return new Promise(() => {});
  } }), /REMOTE_TIMEOUT/);
  assert.equal(requestSignal.aborted, true);
  let streamCancelled = false;
  await assert.rejects(f.verify({ timeoutMs: 15, fetchImpl: async (url) => response(url, new ReadableStream({
    cancel() { streamCancelled = true; },
  })) }), /REMOTE_TIMEOUT/);
  assert.equal(streamCancelled, true);
});

test('network error text and untrusted CLI arguments never appear in diagnostics', async (t) => {
  const f = await fixture(t);
  await assert.rejects(f.verify({ fetchImpl: async () => { throw new Error('private-response-token-fixture'); } }),
    (error) => error.message === 'REMOTE_REQUEST_FAILED');
  let stdout = '', stderr = '';
  const sink = { stdout: { write: (value) => { stdout += value; } }, stderr: { write: (value) => { stderr += value; } } };
  assert.equal(await runCli(['--validate-candidate-url', 'private-response-token-fixture'], sink), 1);
  assert.equal(stdout, '');
  assert.doesNotMatch(stderr, /private-response-token-fixture/);
  assert.equal(await runCli(['--validate-candidate-url', `${candidate}\n`], sink), 0);
  assert.equal(stdout, `${candidate}\n`);
  assert.equal(await runCli(['--validate-candidate-url', `${candidate}\n${canonical}`], sink), 1);
});

test('workflow verifies candidate bytes before binding and then verifies the canonical alias', async () => {
  const workflow = await readFile(join(__dirname, '../.github/workflows/task-146-prebuilt-vercel-deploy.yml'), 'utf8');
  const candidateStep = workflow.indexOf('- name: Verify candidate source and served artifact bytes');
  const aliasStep = workflow.indexOf('- name: Bind verified deployment to canonical production alias');
  const canonicalStep = workflow.indexOf('- name: Verify canonical source and served artifact bytes');
  const evidenceStep = workflow.indexOf('- name: Record exact deployment evidence');
  assert.ok(candidateStep > 0 && aliasStep > candidateStep && canonicalStep > aliasStep && evidenceStep > canonicalStep);
  assert.match(workflow.slice(candidateStep, aliasStep), /set -euo pipefail[\s\S]*--source-sha "\$SOURCE_SHA"[\s\S]*--target candidate/);
  assert.match(workflow.slice(aliasStep, canonicalStep), /vercel@59\.10\.0 alias set "\$DEPLOYMENT_URL" mcpmaster\.vercel\.app[\s\S]*--scope "\$VERCEL_ORG_ID"[\s\S]*--token="\$VERCEL_TOKEN"/);
  assert.match(workflow.slice(canonicalStep, evidenceStep), /--url https:\/\/mcpmaster\.vercel\.app[\s\S]*--source-sha "\$SOURCE_SHA"[\s\S]*--target canonical/);
  assert.doesNotMatch(workflow.slice(candidateStep, evidenceStep), /continue-on-error|always\(\)|\/health|--location/);
  assert.match(workflow, /test "\$\(git rev-parse HEAD\)" = "\$SOURCE_SHA"/);
  assert.match(workflow, /--prebuilt[\s\S]*--prod/);
  assert.match(workflow, /contents: read/);
});
