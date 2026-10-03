'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
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

test('workflow stages without domains, verifies bytes, promotes, binds and verifies the canonical alias', async () => {
  const workflow = await readFile(join(__dirname, '../.github/workflows/task-146-prebuilt-vercel-deploy.yml'), 'utf8');
  const stageStep = workflow.indexOf('- name: Stage prebuilt production output without domain assignment');
  const candidateStep = workflow.indexOf('- name: Verify candidate source and served artifact bytes');
  const promoteStep = workflow.indexOf('- name: Promote verified candidate to production');
  const aliasStep = workflow.indexOf('- name: Bind verified deployment to canonical production alias');
  const canonicalStep = workflow.indexOf('- name: Verify canonical source and served artifact bytes');
  const evidenceStep = workflow.indexOf('- name: Record exact deployment evidence');
  assert.ok(stageStep > 0 && candidateStep > stageStep && promoteStep > candidateStep
    && aliasStep > promoteStep && canonicalStep > aliasStep && evidenceStep > canonicalStep);
  assert.match(workflow.slice(stageStep, candidateStep), /vercel@59\.10\.0 deploy[\s\S]*--prebuilt[\s\S]*--prod\s*\\\n\s*--skip-domain/);
  assert.doesNotMatch(workflow.slice(stageStep, candidateStep), /vercel@59\.10\.0 (?:promote|alias)/);
  assert.match(workflow.slice(candidateStep, promoteStep), /set -euo pipefail[\s\S]*--source-sha "\$SOURCE_SHA"[\s\S]*--target candidate/);
  assert.match(workflow.slice(promoteStep, aliasStep), /vercel@59\.10\.0 promote "\$DEPLOYMENT_URL"[\s\S]*--scope "\$VERCEL_ORG_ID"[\s\S]*--timeout=3m[\s\S]*--token="\$VERCEL_TOKEN"/);
  assert.match(workflow.slice(aliasStep, canonicalStep), /vercel@59\.10\.0 alias set "\$DEPLOYMENT_URL" mcpmaster\.vercel\.app[\s\S]*--scope "\$VERCEL_ORG_ID"[\s\S]*--token="\$VERCEL_TOKEN"/);
  assert.match(workflow.slice(canonicalStep, evidenceStep), /--url https:\/\/mcpmaster\.vercel\.app[\s\S]*--source-sha "\$SOURCE_SHA"[\s\S]*--target canonical/);
  assert.doesNotMatch(workflow.slice(stageStep, evidenceStep), /continue-on-error|always\(\)|\/health|--location|--no-wait|--timeout=0/);
  assert.match(workflow, /test "\$\(git rev-parse HEAD\)" = "\$SOURCE_SHA"/);
  assert.match(workflow, /--prebuilt[\s\S]*--prod/);
  assert.match(workflow, /contents: read/);
});

async function runReleaseSteps(t, failedTarget = '') {
  const f = await fixture(t);
  const workflow = await readFile(join(__dirname, '../.github/workflows/task-146-prebuilt-vercel-deploy.yml'), 'utf8');
  const stepNames = [
    'Stage prebuilt production output without domain assignment',
    'Verify candidate source and served artifact bytes',
    'Promote verified candidate to production',
    'Bind verified deployment to canonical production alias',
    'Verify canonical source and served artifact bytes',
  ];
  const blocks = workflow.split(/^      - name: /m).slice(1);
  const scripts = stepNames.map((name) => {
    const block = blocks.find((value) => value.split('\n')[0] === name);
    assert.ok(block, `missing release step: ${name}`);
    const body = block.split('        run: |\n')[1];
    assert.ok(body);
    return body.split('\n').filter((line) => line.startsWith('          '))
      .map((line) => line.slice(10)).join('\n');
  });
  // Execute the actual workflow shell blocks. Both external commands are
  // replaced locally; this fixture cannot deploy or authenticate to Vercel.
  const harness = `
    set -euo pipefail
    npx() {
      test "$1" = --yes && test "$2" = vercel@59.10.0 || return 71
      case "$3" in
        deploy)
          for required in --prebuilt --prod --skip-domain; do
            case " $* " in *" $required "*) ;;
              *) printf 'premature-domain-assignment\\n' >> "$EVENTS"; return 72;; esac
          done
          printf 'staged-without-domains\\n' >> "$EVENTS"
          printf '%s\\n' "$DEPLOYMENT_URL"
          ;;
        promote)
          test -f "$RUNNER_TEMP/candidate-verified" || return 73
          test "$4" = "$DEPLOYMENT_URL" || return 74
          printf 'promoted\\n' >> "$EVENTS"
          ;;
        alias)
          test -f "$RUNNER_TEMP/candidate-verified" || return 75
          test "$4" = set && test "$5" = "$DEPLOYMENT_URL" && test "$6" = mcpmaster.vercel.app || return 76
          printf 'canonical-bound\\n' >> "$EVENTS"
          ;;
        *) return 77;;
      esac
    }
    node() {
      if test "$2" = --validate-candidate-url; then
        command node "$@"
        return
      fi
      test "$2" = --url && test "$4" = --source-sha && test "$5" = "$SOURCE_SHA" && test "$6" = --target || return 78
      printf 'verify-%s\\n' "$7" >> "$EVENTS"
      test "$7" != "$FAILED_TARGET" || return 79
      if test "$7" = candidate; then : > "$RUNNER_TEMP/candidate-verified"; fi
      printf '{"verified":true}\\n'
    }
  `;
  const eventsPath = join(f.localRoot, 'events');
  const result = spawnSync('bash', ['--noprofile', '--norc', '-c', harness + scripts.join('\n')], {
    cwd: join(__dirname, '..'), encoding: 'utf8', timeout: 10_000,
    env: { PATH: process.env.PATH, SOURCE_SHA: source, DEPLOYMENT_URL: candidate,
      VERCEL_ORG_ID: 'team-test-fixture', VERCEL_TOKEN: 'test-placeholder',
      RUNNER_TEMP: f.localRoot, GITHUB_OUTPUT: join(f.localRoot, 'github-output'),
      EVENTS: eventsPath, FAILED_TARGET: failedTarget },
  });
  assert.equal(result.error, undefined);
  const events = (await readFile(eventsPath, 'utf8')).trim().split('\n');
  return { result, events };
}

test('failed candidate verification leaves the workflow unable to promote or assign an alias', async (t) => {
  const { result, events } = await runReleaseSteps(t, 'candidate');
  assert.notEqual(result.status, 0);
  assert.deepEqual(events, ['staged-without-domains', 'verify-candidate']);
});

test('successful verification promotes only the staged candidate and still fails on a stale canonical readback', async (t) => {
  const passed = await runReleaseSteps(t);
  assert.equal(passed.result.status, 0, passed.result.stderr);
  const expected = ['staged-without-domains', 'verify-candidate', 'promoted', 'canonical-bound', 'verify-canonical'];
  assert.deepEqual(passed.events, expected);
  const stale = await runReleaseSteps(t, 'canonical');
  assert.notEqual(stale.result.status, 0);
  assert.deepEqual(stale.events, expected);
});
