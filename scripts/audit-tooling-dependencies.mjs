import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const TEMPORARY_AUDIT_EXCEPTION = Object.freeze({
  package: 'braces',
  advisory: 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm',
  expiresOn: '2026-10-17'
});

const BLOCKING_SEVERITIES = new Set(['high','critical']);
const isBlocking = (value) => BLOCKING_SEVERITIES.has(String(value || '').toLowerCase());
const SEVERITIES = ['info', 'low', 'moderate', 'high', 'critical'];
const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function assertAuditReport(report) {
  const invalid = () => {
    throw new Error('npm audit returned an incomplete or unsupported audit report.');
  };
  if (!isRecord(report) || report.error || report.auditReportVersion !== 2
    || !isRecord(report.vulnerabilities)
    || !isRecord(report.metadata) || !isRecord(report.metadata.vulnerabilities)) {
    invalid();
  }
  const vulnerabilities = report.vulnerabilities;
  const counts = Object.fromEntries(SEVERITIES.map((severity) => [severity, 0]));
  for (const [name, vulnerability] of Object.entries(vulnerabilities)) {
    if (!name || !isRecord(vulnerability)
      || !SEVERITIES.includes(vulnerability.severity) || !Array.isArray(vulnerability.via)) {
      invalid();
    }
    counts[vulnerability.severity] += 1;
    for (const via of vulnerability.via) {
      if (typeof via === 'string') {
        if (!via || !Object.hasOwn(vulnerabilities, via)) invalid();
      } else if (!isRecord(via) || !SEVERITIES.includes(via.severity)
        || typeof via.url !== 'string' || !via.url.trim()) {
        invalid();
      }
    }
  }
  for (const vulnerability of Object.values(vulnerabilities)) {
    for (const via of vulnerability.via) {
      const severity = typeof via === 'string' ? vulnerabilities[via].severity : via.severity;
      if (SEVERITIES.indexOf(severity) > SEVERITIES.indexOf(vulnerability.severity)) invalid();
    }
  }
  const summary = report.metadata.vulnerabilities;
  for (const severity of SEVERITIES) {
    if (!Number.isSafeInteger(summary[severity]) || summary[severity] !== counts[severity]) invalid();
  }
  if (!Number.isSafeInteger(summary.total)
    || summary.total !== Object.keys(vulnerabilities).length) invalid();
}

export function parseAuditProcessResult(run) {
  if (!run || run.error || run.signal || (run.status !== 0 && run.status !== 1)) {
    throw new Error('npm audit did not complete successfully.');
  }
  if (typeof run.stdout !== 'string' || !run.stdout.trim()) {
    throw new Error('npm audit returned no report.');
  }
  let report;
  try {
    report = JSON.parse(run.stdout);
  } catch {
    throw new Error('npm audit did not return valid JSON.');
  }
  assertAuditReport(report);
  const hasBlockingFindings = Object.values(report.vulnerabilities)
    .some((vulnerability) => isBlocking(vulnerability.severity));
  // Exit 1 is npm's expected result for findings at the requested audit level.
  // Any disagreement between the process result and report is not audit proof.
  if ((run.status === 1) !== hasBlockingFindings) {
    throw new Error('npm audit exit status does not match its reported findings.');
  }
  return report;
}

export function evaluateAuditReport(report, now = new Date()) {
  assertAuditReport(report);
  const vulnerabilities = report.vulnerabilities;
  const expiry = new Date(TEMPORARY_AUDIT_EXCEPTION.expiresOn + 'T23:59:59.999Z');
  const exceptionActive = Number.isFinite(expiry.getTime()) && now.getTime() <= expiry.getTime();
  const memo = new Map();

  function allowed(name, stack = new Set()) {
    if (memo.has(name)) return memo.get(name);
    const vuln = vulnerabilities[name];
    if (!vuln || !isBlocking(vuln.severity)) return true;
    if (stack.has(name)) return false;
    const nextStack = new Set(stack);
    nextStack.add(name);
    const via = Array.isArray(vuln.via) ? vuln.via : [];
    const direct = via.filter((item) => item && typeof item === 'object' && isBlocking(item.severity));
    const transitive = via.filter((item) => typeof item === 'string' && vulnerabilities[item] && isBlocking(vulnerabilities[item].severity));

    let ok = false;
    if (name === TEMPORARY_AUDIT_EXCEPTION.package) {
      ok = exceptionActive
        && direct.length === 1
        && String(direct[0].url || '') === TEMPORARY_AUDIT_EXCEPTION.advisory
        && transitive.length === 0;
    } else {
      ok = direct.length === 0
        && transitive.length > 0
        && transitive.every((dependency) => allowed(dependency, nextStack));
    }
    memo.set(name, ok);
    return ok;
  }

  const blocking = Object.keys(vulnerabilities)
    .filter((name) => isBlocking(vulnerabilities[name]?.severity));
  const blocked = blocking.filter((name) => !allowed(name));
  const excepted = blocking.filter((name) => allowed(name));
  return { blocked, excepted, exceptionActive };
}

function main() {
  const toolingDir = fileURLToPath(new URL('../tooling/', import.meta.url));
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const run = spawnSync(npm, ['audit', '--json', '--audit-level=high'], {
    cwd: toolingDir,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024
  });
  let report;
  try {
    report = parseAuditProcessResult(run);
  } catch (error) {
    console.error('[tooling-audit]', error.message);
    process.exit(2);
  }
  const verdict = evaluateAuditReport(report);
  if (verdict.blocked.length) {
    console.error('[tooling-audit] blocking high/critical findings:', verdict.blocked.sort().join(', '));
    process.exit(1);
  }
  if (verdict.excepted.length) {
    console.log(
      '[tooling-audit] temporary exception active for '
      + TEMPORARY_AUDIT_EXCEPTION.advisory
      + ' through ' + TEMPORARY_AUDIT_EXCEPTION.expiresOn
      + '; affected dependency nodes: ' + verdict.excepted.sort().join(', ')
    );
  } else {
    console.log('[tooling-audit] no high/critical findings.');
  }
}

const invoked = process.argv[1] ? fileURLToPath(import.meta.url) === fileURLToPath(new URL('file://' + process.argv[1])) : false;
if (invoked) main();
