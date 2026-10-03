'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const policy = import('../scripts/audit-tooling-dependencies.mjs');
const advisory = 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm';
const currentDate = new Date('2026-10-03T00:00:00Z');

function auditReport(vulnerabilities = {}) {
  const counts = { info: 0, low: 0, moderate: 0, high: 0, critical: 0, total: 0 };
  for (const vulnerability of Object.values(vulnerabilities)) {
    counts[vulnerability.severity] += 1;
    counts.total += 1;
  }
  return { auditReportVersion: 2, vulnerabilities, metadata: { vulnerabilities: counts } };
}

function exceptedReport() {
  return auditReport({
    braces: { severity: 'high', via: [{ severity: 'high', url: advisory }] },
    micromatch: { severity: 'high', via: ['braces'] },
    'fast-glob': { severity: 'high', via: ['micromatch'] },
  });
}

test('tooling policy preserves the exact advisory and expiry and permits its complete transitive chain', async () => {
  const { evaluateAuditReport, TEMPORARY_AUDIT_EXCEPTION } = await policy;
  assert.deepEqual(TEMPORARY_AUDIT_EXCEPTION, {
    package: 'braces',
    advisory,
    expiresOn: '2026-10-17',
  });
  const verdict = evaluateAuditReport(exceptedReport(), currentDate);
  assert.deepEqual(verdict.blocked, []);
  assert.deepEqual(verdict.excepted.sort(), ['braces', 'fast-glob', 'micromatch']);
});

test('tooling policy blocks unrelated high and critical findings alongside the exception', async () => {
  const { evaluateAuditReport } = await policy;
  for (const severity of ['high', 'critical']) {
    const report = auditReport({
      ...exceptedReport().vulnerabilities,
      other: { severity, via: [{ severity, url: 'https://github.com/advisories/GHSA-unrelated' }] },
    });
    assert.deepEqual(evaluateAuditReport(report, currentDate).blocked, ['other']);
  }
});

test('tooling policy rejects an added blocking advisory on the excepted package', async () => {
  const { evaluateAuditReport } = await policy;
  const report = exceptedReport();
  report.vulnerabilities.braces.via.push({
    severity: 'high', url: 'https://github.com/advisories/GHSA-unrelated',
  });
  assert.deepEqual(evaluateAuditReport(report, currentDate).blocked.sort(),
    ['braces', 'fast-glob', 'micromatch']);
});

test('tooling exception retains its exact inclusive expiry and then blocks its chain', async () => {
  const { evaluateAuditReport } = await policy;
  assert.deepEqual(evaluateAuditReport(exceptedReport(),
    new Date('2026-10-17T23:59:59.999Z')).blocked, []);
  assert.deepEqual(evaluateAuditReport(exceptedReport(),
    new Date('2026-10-18T00:00:00Z')).blocked.sort(), ['braces', 'fast-glob', 'micromatch']);
});

test('complete empty and below-threshold audit reports remain valid', async () => {
  const { evaluateAuditReport, parseAuditProcessResult } = await policy;
  for (const report of [auditReport(), auditReport({
    moderate: { severity: 'moderate', via: [{ severity: 'moderate', url: advisory }] },
  })]) {
    assert.deepEqual(parseAuditProcessResult({ status: 0, signal: null, stdout: JSON.stringify(report) }), report);
    assert.deepEqual(evaluateAuditReport(report, currentDate).blocked, []);
  }
});

test('npm exit one is accepted only as a complete report of findings at the requested threshold', async () => {
  const { parseAuditProcessResult, evaluateAuditReport } = await policy;
  const report = exceptedReport();
  const parsed = parseAuditProcessResult({ status: 1, signal: null, stdout: JSON.stringify(report) });
  assert.deepEqual(evaluateAuditReport(parsed, currentDate).blocked, []);
  assert.throws(() => parseAuditProcessResult({ status: 1, stdout: JSON.stringify(auditReport()) }), /exit status/);
  assert.throws(() => parseAuditProcessResult({ status: 0, stdout: JSON.stringify(report) }), /exit status/);
});

for (const [label, report] of [
  ['null report', null],
  ['array report', []],
  ['empty object', {}],
  ['missing vulnerability map', { auditReportVersion: 2, metadata: auditReport().metadata }],
  ['null vulnerability map', { ...auditReport(), vulnerabilities: null }],
  ['array vulnerability map', { ...auditReport(), vulnerabilities: [] }],
  ['missing audit version', { vulnerabilities: {}, metadata: auditReport().metadata }],
  ['unsupported audit version', { ...auditReport(), auditReportVersion: 3 }],
  ['missing summary', { auditReportVersion: 2, vulnerabilities: {} }],
  ['inconsistent summary', { ...auditReport(), metadata: { vulnerabilities: { ...auditReport().metadata.vulnerabilities, total: 1 } } }],
  ['provider error object', { ...auditReport(), error: { summary: 'private child output' } }],
]) {
  test('tooling policy fails closed for ' + label, async () => {
    const { evaluateAuditReport, parseAuditProcessResult } = await policy;
    assert.throws(() => evaluateAuditReport(report, currentDate), /incomplete or unsupported/);
    assert.throws(() => parseAuditProcessResult({ status: 0, stdout: JSON.stringify(report) }), /incomplete or unsupported/);
  });
}

test('incomplete or contradictory vulnerability entries cannot hide an advisory', async () => {
  const { evaluateAuditReport } = await policy;
  for (const mutate of [
    (report) => { report.vulnerabilities.braces = null; },
    (report) => { report.vulnerabilities.braces.severity = 'unknown'; },
    (report) => { report.vulnerabilities.braces.via = null; },
    (report) => { report.vulnerabilities.braces.via = [null]; },
    (report) => { report.vulnerabilities.braces.via = [{ severity: 'high' }]; },
    (report) => { report.vulnerabilities.micromatch.via.push('missing-advisory-node'); },
    (report) => { report.vulnerabilities.braces.via[0].severity = 'critical'; },
    (report) => { report.metadata.vulnerabilities.high = 0; },
  ]) {
    const report = exceptedReport();
    mutate(report);
    assert.throws(() => evaluateAuditReport(report, currentDate), /incomplete or unsupported/);
  }
});

test('signals, execution failures and unexpected statuses fail before audit interpretation', async () => {
  const { parseAuditProcessResult } = await policy;
  for (const result of [
    null,
    { status: null, signal: 'SIGTERM' },
    { status: 0, signal: 'SIGTERM' },
    { status: null },
    { status: 2 },
    { status: 127 },
    { status: 0, error: new Error('private child failure') },
  ]) {
    assert.throws(() => parseAuditProcessResult(result
      ? { stdout: JSON.stringify(auditReport()), ...result } : result),
    (error) => error.message === 'npm audit did not complete successfully.');
  }
});

test('empty, whitespace, non-text and malformed audit output never becomes a clean report', async () => {
  const { parseAuditProcessResult } = await policy;
  for (const stdout of ['', ' \n\t', undefined, null, Buffer.from('{}'), '{broken-json']) {
    assert.throws(() => parseAuditProcessResult({ status: 0, stdout }), /no report|valid JSON/);
  }
});

test('actual CLI rejects interrupted and incomplete npm processes and reports valid audit outcomes', {
  skip: process.platform === 'win32' ? 'POSIX executable fixture; process-result policy is covered on every platform' : false,
}, () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'pandora-audit-process-'));
  const executable = path.join(dir, 'npm');
  const script = path.resolve(__dirname, '../scripts/audit-tooling-dependencies.mjs');
  writeFileSync(executable, '#!' + process.execPath + '\n'
    + "if(process.env.PANDORA_AUDIT_FIXTURE_SIGNAL){process.kill(process.pid,'SIGTERM');}"
    + "else{process.stdout.write(process.env.PANDORA_AUDIT_FIXTURE_STDOUT||'');process.exit(Number(process.env.PANDORA_AUDIT_FIXTURE_STATUS));}\n",
  { mode: 0o755 });
  try {
    for (const fixture of [
      { stdout: '', status: 0, expected: 2 },
      { stdout: '{}', status: 0, expected: 2 },
      { stdout: '{private malformed audit output', status: 0, expected: 2 },
      { stdout: JSON.stringify(auditReport()), status: 2, expected: 2 },
      { stdout: JSON.stringify(auditReport()), status: 1, expected: 2 },
      { signal: 'SIGTERM', status: 0, expected: 2 },
      { stdout: JSON.stringify(auditReport()), status: 0, expected: 0 },
      { stdout: JSON.stringify(auditReport({
        other: { severity: 'high', via: [{ severity: 'high', url: 'https://github.com/advisories/GHSA-unrelated' }] },
      })), status: 1, expected: 1 },
    ]) {
      const result = spawnSync(process.execPath, [script], {
        encoding: 'utf8',
        env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH,
          PANDORA_AUDIT_FIXTURE_STDOUT: fixture.stdout || '',
          PANDORA_AUDIT_FIXTURE_STATUS: String(fixture.status),
          PANDORA_AUDIT_FIXTURE_SIGNAL: fixture.signal || '' },
      });
      assert.equal(result.status, fixture.expected, result.stderr);
      assert.doesNotMatch(result.stderr, /private malformed audit output/);
      if (fixture.expected === 0) assert.match(result.stdout, /no high\/critical findings/);
      if (fixture.expected === 1) assert.match(result.stderr, /blocking high\/critical findings: other/);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
