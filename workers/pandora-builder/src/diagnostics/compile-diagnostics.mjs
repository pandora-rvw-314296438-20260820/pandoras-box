import { createHash } from 'node:crypto';
import path from 'node:path';
import { redactText } from '../logs/log-records.mjs';

const MAX_DIAGNOSTICS = 100;

function safeRelativePath(candidate, workspaceRoot = null) {
  if (typeof candidate !== 'string' || !candidate.trim()) return null;
  let value = candidate.trim().replaceAll('\\', '/');
  if (workspaceRoot) {
    const normalizedRoot = path.resolve(workspaceRoot).replaceAll('\\', '/').replace(/\/+$/, '');
    const normalizedCandidate = path.resolve(candidate).replaceAll('\\', '/');
    if (normalizedCandidate === normalizedRoot) return null;
    if (normalizedCandidate.startsWith(`${normalizedRoot}/`)) value = normalizedCandidate.slice(normalizedRoot.length + 1);
  }
  value = value.replace(/^file:\/+/, '').replace(/^\.\/+/, '');
  const absoluteLike = value.startsWith('/') || /^[A-Za-z]:\//.test(value);
  if (absoluteLike || value.includes('../') || value === '..') return null;
  return value.slice(0, 512);
}

function messageClass(message) {
  return String(message ?? '')
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/g, '<uuid>')
    .replace(/\b[0-9a-f]{32,64}\b/g, '<digest>')
    .replace(/`[^`]*`|'[^']*'|"[^"]*"/g, '<value>')
    .replace(/\b\d+\b/g, '<n>')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 240);
}

function diagnosticFingerprint(diagnostic) {
  const basis = [
    diagnostic.tool ?? 'unknown',
    diagnostic.severity ?? 'error',
    diagnostic.errorCode ?? '',
    path.extname(diagnostic.filePath ?? '').toLowerCase(),
    messageClass(diagnostic.message),
  ].join('|');
  return createHash('sha256').update(basis).digest('hex');
}

function parseLine(line, { tool, workspaceRoot, secrets }) {
  const text = redactText(line, secrets).trim();
  if (!text) return null;

  let match = text.match(/^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s*([A-Za-z]+\d+)?\s*:?\s*(.+)$/i);
  if (match) {
    const [, file, lineNo, columnNo, severity, code, message] = match;
    return { tool, severity: severity.toLowerCase(), errorCode: code || null, filePath: safeRelativePath(file, workspaceRoot), line: Number(lineNo), column: Number(columnNo), message };
  }

  match = text.match(/^(.+?):(\d+):(\d+)\s*-\s*(error|warning)\s*([A-Za-z]+\d+)?\s*:?\s*(.+)$/i);
  if (match) {
    const [, file, lineNo, columnNo, severity, code, message] = match;
    return { tool, severity: severity.toLowerCase(), errorCode: code || null, filePath: safeRelativePath(file, workspaceRoot), line: Number(lineNo), column: Number(columnNo), message };
  }

  match = text.match(/^(error|warning|info)\s*[•-]\s*(.+?)\s*[•-]\s*(.+?):(\d+):(\d+)\s*[•-]\s*([a-z0-9_]+)\s*$/i);
  if (match) {
    const [, severity, message, file, lineNo, columnNo, code] = match;
    return { tool, severity: severity.toLowerCase(), errorCode: code || null, filePath: safeRelativePath(file, workspaceRoot), line: Number(lineNo), column: Number(columnNo), message };
  }

  match = text.match(/^(.+?):(\d+):(\d+):\s*(error|warning)(?:\s+([A-Za-z0-9_-]+))?:\s*(.+)$/i);
  if (match) {
    const [, file, lineNo, columnNo, severity, code, message] = match;
    return { tool, severity: severity.toLowerCase(), errorCode: code || null, filePath: safeRelativePath(file, workspaceRoot), line: Number(lineNo), column: Number(columnNo), message };
  }

  return null;
}

function parseCompileDiagnostics({
  stdout = '',
  stderr = '',
  tool = 'compiler',
  workspaceRoot = null,
  secrets = [],
  maxDiagnostics = MAX_DIAGNOSTICS,
} = {}) {
  if (!Number.isInteger(maxDiagnostics) || maxDiagnostics < 1 || maxDiagnostics > MAX_DIAGNOSTICS) {
    throw new Error('INVALID_DIAGNOSTIC_LIMIT');
  }
  const deduped = new Map();
  for (const line of `${stderr}\n${stdout}`.split(/\r?\n/)) {
    const parsed = parseLine(line, { tool, workspaceRoot, secrets });
    if (!parsed || !parsed.filePath) continue;
    const diagnostic = {
      ...parsed,
      message: redactText(parsed.message, secrets).slice(0, 1000),
    };
    diagnostic.fingerprint = diagnosticFingerprint(diagnostic);
    const dedupeKey = [
      diagnostic.fingerprint,
      diagnostic.filePath,
      diagnostic.line ?? '',
      diagnostic.column ?? '',
    ].join('|');
    if (!deduped.has(dedupeKey)) deduped.set(dedupeKey, Object.freeze(diagnostic));
    if (deduped.size >= maxDiagnostics) break;
  }
  return Object.freeze([...deduped.values()]);
}

function diagnosticSetFingerprint(diagnostics = []) {
  const fingerprints = diagnostics
    .map((diagnostic) => diagnostic?.fingerprint ?? diagnosticFingerprint(diagnostic ?? {}))
    .filter(Boolean)
    .sort();
  if (!fingerprints.length) return null;
  return createHash('sha256').update(fingerprints.join('|')).digest('hex');
}

export {
  MAX_DIAGNOSTICS,
  diagnosticFingerprint,
  diagnosticSetFingerprint,
  messageClass,
  parseCompileDiagnostics,
  safeRelativePath,
};
