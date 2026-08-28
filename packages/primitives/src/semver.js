'use strict';

const SEMVER_RE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?$/;

function parseVersion(input) {
  if (typeof input !== 'string' || input === 'latest') {
    throw new TypeError('primitive version must be an exact semantic version');
  }
  const match = SEMVER_RE.exec(input.trim());
  if (!match) throw new TypeError(`invalid semantic version: ${input}`);
  return Object.freeze({ raw: input.trim(), major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]), prerelease: match[4] || null });
}

function compareVersions(a, b) {
  const left = typeof a === 'string' ? parseVersion(a) : a;
  const right = typeof b === 'string' ? parseVersion(b) : b;
  for (const key of ['major', 'minor', 'patch']) {
    if (left[key] !== right[key]) return left[key] < right[key] ? -1 : 1;
  }
  if (left.prerelease === right.prerelease) return 0;
  if (left.prerelease === null) return 1;
  if (right.prerelease === null) return -1;
  return left.prerelease.localeCompare(right.prerelease);
}

function satisfies(version, range) {
  const parsed = parseVersion(version);
  if (typeof range !== 'string' || !range.trim()) return false;
  return range.split('||').some((alternative) => alternative.trim().split(/\s+/).filter(Boolean).every((term) => satisfiesTerm(parsed, term)));
}

function satisfiesTerm(version, term) {
  if (term === '*' || term.toLowerCase() === 'x') return true;
  if (term.startsWith('^')) {
    const floor = parseVersion(normalizePartial(term.slice(1)));
    const ceiling = floor.major > 0 ? { ...floor, major: floor.major + 1, minor: 0, patch: 0, prerelease: null } : floor.minor > 0 ? { ...floor, minor: floor.minor + 1, patch: 0, prerelease: null } : { ...floor, patch: floor.patch + 1, prerelease: null };
    return compareVersions(version, floor) >= 0 && compareVersions(version, ceiling) < 0;
  }
  if (term.startsWith('~')) {
    const floor = parseVersion(normalizePartial(term.slice(1)));
    const ceiling = { ...floor, minor: floor.minor + 1, patch: 0, prerelease: null };
    return compareVersions(version, floor) >= 0 && compareVersions(version, ceiling) < 0;
  }
  const match = /^(>=|<=|>|<|=)?(.+)$/.exec(term);
  const operator = match[1] || '=';
  const target = parseVersion(normalizePartial(match[2]));
  const cmp = compareVersions(version, target);
  return operator === '>=' ? cmp >= 0 : operator === '<=' ? cmp <= 0 : operator === '>' ? cmp > 0 : operator === '<' ? cmp < 0 : cmp === 0;
}

function normalizePartial(value) {
  const parts = value.trim().split('.');
  if (parts.length === 1) return `${parts[0]}.0.0`;
  if (parts.length === 2) return `${parts[0]}.${parts[1]}.0`;
  return value.trim();
}

module.exports = { compareVersions, parseVersion, satisfies };
