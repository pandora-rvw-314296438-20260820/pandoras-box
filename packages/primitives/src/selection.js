'use strict';
const { compareVersions, satisfies } = require('./semver');
const { digest } = require('./registry');

const PRIMITIVE_NAME_RE = /^pandora-[a-z0-9-]+$/;

function inferPrimitiveRequirements(projectSpec = {}) {
  if (!projectSpec || typeof projectSpec !== 'object' || Array.isArray(projectSpec)) throw new TypeError('projectSpec must be an object');
  const product = objectValue(projectSpec.product || projectSpec.product_scope);
  const integrations = objectValue(projectSpec.integrations || projectSpec.integration_scope);
  const required = new Set();
  for (const value of arrayValue(projectSpec.requiredPrimitives || projectSpec.required_primitives)) addName(required, value);
  if (arrayValue(product.roles).length) {
    required.add('pandora-auth');
    required.add('pandora-rbac');
  }
  if (hasEntries(integrations.payment)) {
    required.add('pandora-commerce');
    required.add('pandora-billing');
  }
  if (hasEntries(integrations.messaging)) required.add('pandora-notifications');
  if (hasEntries(integrations.analytics)) required.add('pandora-analytics');

  const corpus = flattenStrings(projectSpec).join(' ').toLowerCase();
  const rules = [
    ['pandora-auth', /\b(?:auth(?:entication)?|sign[ -]?in|log[ -]?in|password reset|magic link|account access)\b/],
    ['pandora-rbac', /\b(?:role|permission|access control|rbac)\b/],
    ['pandora-admin', /\b(?:admin|back office|operations console)\b/],
    ['pandora-audit', /\b(?:audit|activity log|change log)\b/],
    ['pandora-notifications', /\b(?:notification|push message|in-app message|email notification|sms notification)\b/],
    ['pandora-analytics', /\b(?:analytics|product metric|business metric|event tracking)\b/],
    ['pandora-booking', /\b(?:booking|reservation|availability|capacity)\b/],
    ['pandora-commerce', /\b(?:commerce|cart|checkout|catalog|inventory|order|storefront|shop)\b/],
    ['pandora-billing', /\b(?:payment|billing|refund|invoice|subscription charge)\b/],
    ['pandora-crm', /\b(?:crm|lead pipeline|sales pipeline|customer interaction)\b/],
    ['pandora-forms', /\b(?:form submission|intake form|survey form|application form)\b/],
    ['pandora-files', /\b(?:file upload|attachment|object storage|signed file|image upload)\b/],
    ['pandora-search', /\b(?:search|filterable search)\b/],
    ['pandora-content', /\b(?:cms|content management|article|faq|page editor)\b/],
    ['pandora-scheduling', /\b(?:schedule|calendar|recurrence|time slot)\b/],
    ['pandora-customer-profile', /\b(?:customer profile|user profile|preferences|consent)\b/],
    ['pandora-settings', /\b(?:settings|timezone|currency|locale|branding settings)\b/],
    ['pandora-feature-flags', /\b(?:feature flag|feature toggle|runtime flag)\b/],
  ];
  for (const [name, pattern] of rules) if (pattern.test(corpus)) required.add(name);
  return Object.freeze([...required].sort());
}

function resolvePrimitiveRequirements(registry, { requiredPrimitives = [], projectType = null, requireTrusted = true } = {}) {
  if (!registry || typeof registry.list !== 'function' || typeof registry.verificationHistory !== 'function') throw new TypeError('primitive registry is required');
  if (!Array.isArray(requiredPrimitives)) throw new TypeError('requiredPrimitives must be an array');
  const requested = [...new Set(requiredPrimitives.map((value) => normalizeName(value)))].sort();
  if (!requested.length) return readyResult([], projectType, requireTrusted);
  const definitions = registry.list({ includeBlocked: false });
  const selected = new Map();
  const errors = [];
  const queue = requested.map((name) => ({ name, range: '*', optional: false, parent: null }));

  while (queue.length) {
    const requirement = queue.shift();
    const prior = selected.get(requirement.name);
    if (prior) {
      if (!satisfies(prior.definition.version, requirement.range)) errors.push(`primitive dependency conflict for ${requirement.name}: selected ${prior.version} does not satisfy ${requirement.range}`);
      continue;
    }
    const candidates = definitions
      .filter((item) => item.name === requirement.name)
      .filter((item) => !projectType || item.supportedProjectTypes.includes(projectType))
      .filter((item) => satisfies(item.version, requirement.range))
      .filter((item) => item.trustState !== 'BLOCKED')
      .filter((item) => !requireTrusted || item.trustState === 'TRUSTED')
      .sort((a, b) => compareVersions(b.version, a.version));
    const chosen = candidates[0] || null;
    if (!chosen) {
      if (!requirement.optional) errors.push(`no ${requireTrusted ? 'TRUSTED ' : ''}primitive satisfies ${requirement.name}@${requirement.range}${projectType ? ` for ${projectType}` : ''}`);
      continue;
    }
    const evidence = latestPass(registry.verificationHistory(chosen.name, chosen.version), chosen.sourceDigest);
    if (requireTrusted && !evidence) {
      errors.push(`TRUSTED primitive ${chosen.name}@${chosen.version} lacks exact Worker E evidence`);
      continue;
    }
    selected.set(chosen.name, { definition: chosen, evidence });
    for (const dependency of chosen.dependencies || []) {
      if (dependency.optional === true) continue;
      queue.push({ name: normalizeName(dependency.name), range: dependency.range || '*', optional: false, parent: chosen.name });
    }
  }

  if (errors.length) return blockedResult(errors, requested, projectType, requireTrusted);
  const selections = [...selected.values()]
    .map(({ definition, evidence }) => Object.freeze({
      id: definition.name,
      name: definition.name,
      version: definition.version,
      trustState: definition.trustState,
      sourceDigest: definition.sourceDigest,
      definitionDigest: definition.definitionDigest,
      source: definition.source,
      verificationEvidenceId: evidence ? evidence.evidenceId : null,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return readyResult(selections, projectType, requireTrusted);
}

function resolveProjectSpecPrimitives(registry, { projectSpec, projectType = null, requireTrusted = true } = {}) {
  const spec = projectSpec || {};
  const product = objectValue(spec.product || spec.product_scope);
  const type = projectType || product.projectType || spec.project_type || null;
  const requiredPrimitives = inferPrimitiveRequirements(spec);
  const resolved = resolvePrimitiveRequirements(registry, { requiredPrimitives, projectType: type, requireTrusted });
  return Object.freeze({ ...resolved, requiredPrimitives });
}

function readyResult(selections, projectType, requireTrusted) {
  const identity = selections.map((item) => ({ name: item.name, version: item.version, sourceDigest: item.sourceDigest, definitionDigest: item.definitionDigest, trustState: item.trustState, verificationEvidenceId: item.verificationEvidenceId }));
  return Object.freeze({ ok: true, state: 'READY', requireTrusted: requireTrusted === true, projectType: projectType || null, selections: Object.freeze(selections), errors: Object.freeze([]), selectionDigest: digest({ projectType: projectType || null, requireTrusted: requireTrusted === true, selections: identity }) });
}
function blockedResult(errors, requested, projectType, requireTrusted) {
  return Object.freeze({ ok: false, state: 'BLOCKED', requireTrusted: requireTrusted === true, projectType: projectType || null, selections: Object.freeze([]), errors: Object.freeze([...errors].sort()), selectionDigest: digest({ projectType: projectType || null, requireTrusted: requireTrusted === true, requested, errors: [...errors].sort() }) });
}
function latestPass(history, sourceDigest) {
  for (let i = history.length - 1; i >= 0; i--) {
    const item = history[i];
    if (item && item.authority === 'worker-e' && item.status === 'PASS' && item.sourceDigest === sourceDigest && typeof item.evidenceId === 'string' && item.evidenceId) return item;
  }
  return null;
}
function normalizeName(value) {
  const name = typeof value === 'string' ? value.trim() : '';
  if (!PRIMITIVE_NAME_RE.test(name)) throw new TypeError(`invalid primitive name: ${value}`);
  return name;
}
function addName(set, value) { set.add(normalizeName(value)); }
function objectValue(value) { return value && typeof value === 'object' && !Array.isArray(value) ? value : {}; }
function arrayValue(value) { return Array.isArray(value) ? value : []; }
function hasEntries(value) { return Array.isArray(value) ? value.length > 0 : typeof value === 'string' ? value.trim().length > 0 : value && typeof value === 'object' ? Object.keys(value).length > 0 : false; }
function flattenStrings(value, output = []) {
  if (typeof value === 'string') output.push(value);
  else if (Array.isArray(value)) for (const item of value) flattenStrings(item, output);
  else if (value && typeof value === 'object') for (const item of Object.values(value)) flattenStrings(item, output);
  return output;
}

module.exports = { inferPrimitiveRequirements, resolvePrimitiveRequirements, resolveProjectSpecPrimitives };
