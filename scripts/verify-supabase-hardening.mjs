import { readFile, readdir } from 'node:fs/promises';
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
  if (
    source.includes(secondary) ||
    source.includes('https://' + secondary + '.supabase.co')
  ) {
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
