import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

const root = 'ops/supabase/hardening';
const registry = JSON.parse(
  await readFile(path.join(root, 'edge-function-lifecycle-registry.json'), 'utf8'),
);
const advisor = JSON.parse(
  await readFile(path.join(root, 'security-advisor-dispositions.json'), 'utf8'),
);
const boundary = JSON.parse(
  await readFile(path.join(root, 'plane-boundary-policy.json'), 'utf8'),
);

const allowedClasses = new Set([
  'CORE',
  'BROKER',
  'WEBHOOK',
  'ADMIN',
  'RECOVERY',
  'TEMPORARY',
  'LEGACY',
  'UNRECONCILED',
]);
const seen = new Set();
const counts = new Map();
const unreconciled = [];
const reconciliationCounts = new Map();
const allowedReconciliationDecisions = new Set([
  'REVIEW_REQUIRED_CAPACITY_RECONCILIATION',
  'RETIRE_CANDIDATE_SELF_RETIRED',
  'RETAIN_EVIDENCE_PENDING_OWNER_RECONCILIATION',
  'REVIEW_REQUIRED_CALLER_PROOF',
  'RETIRE_CANDIDATE_NO_LIVE_CALLER',
]);

const limit = registry.providerLimits?.edgeFunctionsPerProject;
if (!Number.isInteger(limit) || limit < 1) {
  throw new Error('edge function provider limit missing or invalid');
}

for (const fn of registry.functions) {
  const key = fn.projectRef + '/' + fn.slug;
  if (seen.has(key)) throw new Error('duplicate ' + key);
  seen.add(key);

  for (const field of [
    'projectRef',
    'slug',
    'class',
    'decision',
    'purpose',
    'authModel',
    'owner',
    'callerEvidence',
    'observedAt',
  ]) {
    if (!fn[field]) throw new Error('missing ' + field + ' for ' + key);
  }

  if (!allowedClasses.has(fn.class)) {
    throw new Error('invalid class ' + fn.class + ' for ' + key);
  }
  if (fn.status !== 'ACTIVE') {
    throw new Error('registry entry is not an ACTIVE live inventory record: ' + key);
  }
  if (fn.decision === 'KEEP_REVIEWED') {
    throw new Error('unexplained lifecycle decision: ' + key);
  }

  if (fn.intentionalActive === true) {
    if (fn.class === 'UNRECONCILED') {
      throw new Error('unreconciled function cannot be marked intentional: ' + key);
    }
  } else if (fn.intentionalActive === false) {
    if (
      fn.class !== 'UNRECONCILED' ||
      !allowedReconciliationDecisions.has(fn.decision)
    ) {
      throw new Error('non-intentional live function lacks reconciliation state: ' + key);
    }
    if (
      fn.decision === 'RETIRE_CANDIDATE_SELF_RETIRED' &&
      !/retired|410/i.test(fn.callerEvidence)
    ) {
      throw new Error('retirement candidate lacks provider-retired evidence: ' + key);
    }
    if (
      fn.decision === 'REVIEW_REQUIRED_CALLER_PROOF' &&
      !/caller proof/i.test(fn.callerEvidence)
    ) {
      throw new Error('caller-proof review lacks explicit evidence gap: ' + key);
    }
    if (
      fn.decision === 'RETIRE_CANDIDATE_NO_LIVE_CALLER' &&
      !/no repository references|no live caller/i.test(fn.callerEvidence)
    ) {
      throw new Error('no-live-caller retirement candidate lacks caller evidence: ' + key);
    }
    if (
      fn.decision === 'RETAIN_EVIDENCE_PENDING_OWNER_RECONCILIATION' &&
      !/retention evidence/i.test(fn.callerEvidence)
    ) {
      throw new Error('retain candidate lacks retention evidence: ' + key);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(fn.reviewBy || '')) {
      throw new Error('unreconciled function lacks review deadline: ' + key);
    }
    const observed = Date.parse(fn.observedAt);
    const review = Date.parse(fn.reviewBy + 'T23:59:59Z');
    if (!Number.isFinite(observed) || !Number.isFinite(review) || review < observed) {
      throw new Error('invalid reconciliation deadline: ' + key);
    }
    if (review - observed > 7 * 24 * 60 * 60 * 1000) {
      throw new Error('reconciliation deadline exceeds seven days: ' + key);
    }
    unreconciled.push(key);
    reconciliationCounts.set(
      fn.decision,
      (reconciliationCounts.get(fn.decision) || 0) + 1,
    );
  } else {
    throw new Error('intentionalActive must be boolean: ' + key);
  }

  counts.set(fn.projectRef, (counts.get(fn.projectRef) || 0) + 1);
}

for (const [plane, projectRef] of Object.entries(registry.projects)) {
  const count = counts.get(projectRef) || 0;
  if (count > limit) {
    throw new Error(
      plane + ' Supabase Edge inventory exceeds provider limit: ' + count + '/' + limit,
    );
  }
}

const retiredFunctions = Array.isArray(registry.retiredFunctions)
  ? registry.retiredFunctions
  : [];
for (const fn of retiredFunctions) {
  const key = fn.projectRef + '/' + fn.slug;
  if (seen.has(key)) throw new Error('live/retired duplicate ' + key);
  seen.add(key);

  if (
    fn.status !== 'RETIRED' ||
    fn.decision !== 'RETIRED_VERIFIED' ||
    fn.intentionalActive !== false
  ) {
    throw new Error('invalid verified-retirement state: ' + key);
  }

  const receipt = fn.retirement;
  if (
    !receipt ||
    receipt.classificationDecision !== 'RETIRE_CANDIDATE_SELF_RETIRED' ||
    !/^[0-9a-f]{40}$/.test(receipt.classificationSourceSha || '') ||
    receipt.expectedVersion !== fn.version ||
    receipt.deleteStatus !== 200 ||
    receipt.verificationStatus !== 404 ||
    !Number.isFinite(Date.parse(receipt.deletedAt || ''))
  ) {
    throw new Error('invalid retirement receipt evidence: ' + key);
  }
}

const primaryCount = counts.get(registry.projects.primary) || 0;
const secondaryCount = counts.get(registry.projects.secondary) || 0;
if (
  registry.liveInventoryCounts?.primary !== primaryCount ||
  registry.liveInventoryCounts?.secondary !== secondaryCount ||
  registry.liveInventoryCounts?.total !== registry.functions.length
) {
  throw new Error('declared live Supabase inventory counts do not match registry entries');
}

if (!advisor.dispositions?.length) throw new Error('advisor dispositions missing');
for (const disposition of advisor.dispositions) {
  if (
    !disposition.objects?.length ||
    !disposition.disposition ||
    !disposition.compatibilityEvidence ||
    !disposition.remediation ||
    !disposition.rollback
  ) {
    throw new Error(
      'incomplete advisor ' + disposition.plane + '/' + disposition.advisor,
    );
  }
}

const secondary = registry.projects.secondary;
if (!boundary.simpleMode.forbiddenDirectProjectRefs.includes(secondary)) {
  throw new Error('secondary plane not forbidden');
}

// A forbidden target must be named by its executable rejection and its negative
// test. Recognize only those reviewed constructs; a path never exempts its other
// references. Comments, strings, nested/unreachable copies and changed behavior
// cannot supply the code tokens needed by this narrow classifier.
function dartTokens(source) {
  function commentEnd(start) {
    if (source.startsWith('//', start)) {
      const end = source.indexOf('\n', start + 2);
      return end < 0 ? source.length : end;
    }
    let depth = 1;
    for (let i = start + 2; i < source.length;) {
      if (source.startsWith('/*', i)) { depth++; i += 2; }
      else if (source.startsWith('*/', i)) {
        i += 2;
        if (--depth === 0) return i;
      } else i++;
    }
    return -1;
  }
  const stringStart = i => /['"]/.test(source[i] || '') ||
    (/[rR]/.test(source[i] || '') && /['"]/.test(source[i + 1] || ''));
  function stringEnd(start, nesting = 0) {
    if (nesting > 64) return -1;
    const raw = /[rR]/.test(source[start]);
    const quoteAt = start + Number(raw), quote = source[quoteAt];
    const delimiter = source.startsWith(quote.repeat(3), quoteAt) ? quote.repeat(3) : quote;
    for (let i = quoteAt + delimiter.length; i < source.length;) {
      if (source.startsWith(delimiter, i)) return i + delimiter.length;
      if (!raw && source[i] === '\\') { i += 2; continue; }
      if (!raw && source.startsWith('${', i)) {
        let depth = 1;
        i += 2;
        while (i < source.length && depth) {
          if (source.startsWith('//', i) || source.startsWith('/*', i)) i = commentEnd(i);
          else if (stringStart(i)) i = stringEnd(i, nesting + 1);
          else if (source[i] === '{') { depth++; i++; }
          else if (source[i] === '}') { depth--; i++; }
          else i++;
          if (i < 0) return -1;
        }
        if (depth) return -1;
      } else i++;
    }
    return -1;
  }
  const tokens = [], brackets = [], braces = [], pairs = new Map();
  for (let i = 0; i < source.length;) {
    if (/\s/.test(source[i])) { i++; continue; }
    if (source.startsWith('//', i) || source.startsWith('/*', i)) {
      i = commentEnd(i);
      if (i < 0) return null;
      continue;
    }
    const start = i;
    let kind = 'code';
    if (stringStart(i)) { i = stringEnd(i); kind = 'string'; }
    else if (/[A-Za-z_$]/.test(source[i])) {
      i++;
      while (i < source.length && /[A-Za-z0-9_$]/.test(source[i])) i++;
    } else i++;
    if (i < 0) return null;
    const text = source.slice(start, i), index = tokens.length;
    tokens.push({ text, kind, start, end: i, parent: braces.at(-1) ?? null });
    if (kind === 'string') continue;
    if ('([{'.includes(text)) {
      brackets.push({ text, index });
      if (text === '{') braces.push(index);
    } else if (')]}'.includes(text)) {
      const opening = brackets.pop();
      if (!opening || '([{'.indexOf(opening.text) !== ')]}'.indexOf(text)) return null;
      pairs.set(opening.index, index);
      if (text === '}') braces.pop();
    }
  }
  return brackets.length ? null : { tokens, pairs };
}

function reviewedDenialReferences(file, source, primary, forbidden) {
  const runtimePath = 'apps/pandora-mobile/lib/core/config/pandora_runtime_binding.dart';
  const testPath = 'apps/pandora-mobile/test/core/config/pandora_runtime_binding_test.dart';
  const normalizedPath = file.split(path.sep).join('/');
  if (![runtimePath, testPath].includes(normalizedPath)) return [];
  if (![primary, forbidden].every(ref => /^[a-z0-9]{20}$/.test(ref))) return [];
  const parsed = dartTokens(source);
  if (!parsed) return [];
  const { tokens, pairs } = parsed;
  const sequence = text => dartTokens(text)?.tokens.map(token => token.text) ?? [];
  const at = (index, expected) => expected.length > 0 &&
    expected.every((text, offset) => tokens[index + offset]?.text === text);
  const find = (expected, parent) => tokens.flatMap((token, index) =>
    token.parent === parent && at(index, expected) ? [index] : []);
  const exactRef = token => token.kind === 'string' && token.text === `'${forbidden}'`;
  if (normalizedPath === runtimePath) {
    const classes = find(['class', 'PandoraRuntimeBinding', '{'], null);
    if (classes.length !== 1) return [];
    const factories = find(['factory', 'PandoraRuntimeBinding', '.', 'fromConfiguration', '('], classes[0] + 2);
    if (factories.length !== 1) return [];
    const body = (pairs.get(factories[0] + 4) ?? -2) + 1;
    if (tokens[body]?.text !== '{') return [];
    // The guard must be in the factory's leading validation sequence, before
    // target construction. A copied guard under `if (false)` is not sufficient.
    const validation = sequence(`
      final acceptanceFields = [acceptanceProjectRef, acceptanceOrganizationId,
        acceptanceSourceSha, acceptancePublishableKeySha256, acceptanceConfigSha256,];
      if (runtimeProfile == 'production') {
        if (acceptanceFields.any((field) => field != null)) {
          throw const PandoraRuntimeBindingException('ACCEPTANCE_ORPHAN_CONFIG');
        }
        return production;
      }
      if (runtimeProfile != acceptanceProfile) {
        throw const PandoraRuntimeBindingException('ACCEPTANCE_PROFILE_INVALID');
      }
      if (acceptanceFields.any((field) => field == null || field.isEmpty)) {
        throw const PandoraRuntimeBindingException('ACCEPTANCE_CONFIG_INCOMPLETE');
      }
      final ref = acceptanceProjectRef!;
      if (!_matches(_ref, ref) || const {'${primary}', '${forbidden}'}.contains(ref)) {
        throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');
      }
    `);
    if (!at(body + 1, validation)) return [];
    return tokens.slice(body + 1, body + 1 + validation.length).filter(exactRef);
  }
  const mains = find(['void', 'main', '(', ')', '{'], null);
  if (mains.length !== 1) return [];
  const mainBody = mains[0] + 4;
  if (pairs.get(mainBody) !== tokens.length - 1) return [];
  const matcher = sequence(`Matcher code(String value) => throwsA(isA<PandoraRuntimeBindingException>()
    .having((error) => error.code, 'fixed code', value)
    .having((error) => error.toString(), 'private error text', value));`);
  if (find(matcher, mainBody).length !== 1) return [];
  // The tail closes the loop's condition, so tokenize it with its opening
  // condition and retain only the tokens after that synthetic list.
  const completeTail = sequence(`for (final ref in []) {
    test('rejects forbidden or malformed project $ref', () {
      expect(() => acceptanceProfileBinding(overrides: {'acceptanceProjectRef': ref}),
        code('ACCEPTANCE_PROJECT_INVALID'));
    });
  }`).slice(7);
  const reviewedValues = sequence(`['${primary}', '${forbidden}', 'not-a-project',
    'ABCDEFGHIJKLMNOPQRST', '${primary}\\n', 'abcdefghijklmnopqrst\\n',]`).slice(1, -1);
  const permitted = [];
  for (const loop of find(['for', '(', 'final', 'ref', 'in', '['], mainBody)) {
    // Bind the reviewed imports and registration prefix, not merely a copied
    // loop. This is the token prefix in the independently reviewed ed4b7236
    // test, before the forbidden-reference list. It contains no secondary ref.
    // An earlier return/exit, library @Skip or shadowed assertion invalidates
    // the exception. Whitespace/comments may change; their raw refs still fail.
    const prefix = JSON.stringify(tokens.slice(0, loop).map(token => token.text));
    if (createHash('sha256').update(prefix).digest('hex') !== 'd5daa3a6fabc6a4c8108b1cf0eb89d725e01f028f606f7b4262be095f4bbf3c8') continue;
    const end = pairs.get(loop + 5);
    if (end === undefined || !at(end + 1, completeTail)) continue;
    const values = tokens.slice(loop + 6, end);
    // An interpolated string can execute while the iterable is constructed and
    // abort registration. Only the actual reviewed constant cases are eligible.
    if (values.length !== reviewedValues.length || !at(loop + 6, reviewedValues)) continue;
    permitted.push(...values.filter(exactRef));
  }
  return permitted.length === 1 ? permitted : [];
}

function hasUnexpectedSecondaryReference(file, source) {
  if (!source.includes(secondary)) return false;
  const allowed = reviewedDenialReferences(file, source, registry.projects.primary, secondary);
  for (let offset = source.indexOf(secondary); offset >= 0; offset = source.indexOf(secondary, offset + secondary.length)) {
    if (!allowed.some(token => offset === token.start + 1 && token.end === offset + secondary.length + 1)) return true;
  }
  return false;
}

async function files(directory) {
  const output = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      output.push(...(await files(target)));
    } else if (
      entry.isFile() &&
      /\.(?:dart|json|ya?ml|js|mjs|ts|html)$/.test(entry.name)
    ) {
      output.push(target);
    }
  }
  return output;
}

for (const file of await files('apps/pandora-mobile')) {
  const source = await readFile(file, 'utf8');
  if (hasUnexpectedSecondaryReference(file, source)) {
    throw new Error('Simple Mode secondary reference: ' + file);
  }
}

console.log(
  'Supabase hardening registry checks passed: ' +
    registry.functions.length +
    ' live functions (' +
    primaryCount +
    '/' +
    limit +
    ' primary, ' +
    secondaryCount +
    '/' +
    limit +
    ' secondary), ' +
    retiredFunctions.length +
    ' retired-verified, ' +
    unreconciled.length +
    ' live unreconciled (' +
    (reconciliationCounts.get('RETIRE_CANDIDATE_SELF_RETIRED') || 0) +
    ' pending-retirement, ' +
    (reconciliationCounts.get('RETAIN_EVIDENCE_PENDING_OWNER_RECONCILIATION') || 0) +
    ' retain-evidence, ' +
    (reconciliationCounts.get('REVIEW_REQUIRED_CALLER_PROOF') || 0) +
    ' caller-proof-required, ' +
    (reconciliationCounts.get('RETIRE_CANDIDATE_NO_LIVE_CALLER') || 0) +
    ' no-live-caller-retirement), ' +
    advisor.dispositions.length +
    ' advisor groups.',
);
