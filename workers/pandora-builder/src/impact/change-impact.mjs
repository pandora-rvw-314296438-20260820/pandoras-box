const IMPACT_CLASSES = Object.freeze({
  0: 'visual',
  1: 'component',
  2: 'app_logic',
  3: 'backend',
  4: 'database',
});

const BUILD_SCOPES = new Set(['visual_incremental', 'component_incremental', 'full_candidate']);
const VERIFICATION_SCOPES = new Set([
  'visual_plus_global',
  'component_plus_global',
  'app_plus_global',
  'backend_plus_global',
  'database_plus_global',
]);

function conservativeImpactPlan() {
  return Object.freeze({
    authoritative: false,
    impactTier: 4,
    impactClass: 'database',
    buildScope: 'full_candidate',
    verificationScope: 'database_plus_global',
    changedScopes: Object.freeze({ conservativeFallback: true }),
  });
}

function validateImpactPlan(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return conservativeImpactPlan();
  const impactTier = Number(value.impactTier);
  const impactClass = value.impactClass;
  const buildScope = value.buildScope;
  const verificationScope = value.verificationScope;
  if (!Number.isInteger(impactTier) || impactTier < 0 || impactTier > 4 ||
      impactClass !== IMPACT_CLASSES[impactTier] ||
      !BUILD_SCOPES.has(buildScope) ||
      !VERIFICATION_SCOPES.has(verificationScope) ||
      value.authoritative !== true) {
    return conservativeImpactPlan();
  }
  if ((impactTier >= 2 && buildScope !== 'full_candidate') ||
      (impactTier === 1 && buildScope !== 'component_incremental') ||
      (impactTier === 0 && buildScope !== 'visual_incremental')) {
    return conservativeImpactPlan();
  }
  const expectedVerification = [
    'visual_plus_global',
    'component_plus_global',
    'app_plus_global',
    'backend_plus_global',
    'database_plus_global',
  ][impactTier];
  if (verificationScope !== expectedVerification) return conservativeImpactPlan();
  return Object.freeze({
    authoritative: true,
    assessmentId: typeof value.assessmentId === 'string' ? value.assessmentId : null,
    impactTier,
    impactClass,
    buildScope,
    verificationScope,
    changedScopes: Object.freeze(
      value.changedScopes && typeof value.changedScopes === 'object' && !Array.isArray(value.changedScopes)
        ? { ...value.changedScopes }
        : {},
    ),
  });
}

function selectVerificationDefinitions(testDefinitions, impactPlan) {
  const plan = validateImpactPlan(impactPlan);
  const tests = Array.isArray(testDefinitions) ? testDefinitions : [];
  return Object.freeze(tests.filter((test) => {
    if (!test?.optional) return true;
    if (!plan.authoritative || plan.impactTier >= 2) return true;
    const category = String(test.category ?? '').toLowerCase();
    if (plan.impactTier === 1) return ['unit', 'typecheck', 'lint'].includes(category);
    return ['typecheck', 'lint'].includes(category);
  }));
}

function isIncrementalSourceEligible(impactPlan, priorSource) {
  const plan = validateImpactPlan(impactPlan);
  return Boolean(
    plan.authoritative &&
    plan.impactTier <= 1 &&
    plan.buildScope !== 'full_candidate' &&
    priorSource &&
    Array.isArray(priorSource.files) &&
    priorSource.files.length > 0,
  );
}

export { conservativeImpactPlan, isIncrementalSourceEligible, selectVerificationDefinitions, validateImpactPlan };
