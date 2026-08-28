'use strict';

const { parseVersion } = require('./semver');
const TRUST_STATES = Object.freeze(['EXPERIMENTAL', 'TRUSTED', 'DEPRECATED', 'BLOCKED']);
const SOURCE_KINDS = Object.freeze(['package', 'source-template', 'generated-module', 'migration-package', 'runtime-service', 'combination']);
const PROJECT_TYPES = Object.freeze(['website', 'web_application', 'mobile_application', 'system', 'api', 'automation', 'other']);
const PRIMITIVE_CATEGORIES = Object.freeze(['identity','authorization','operations','observability','communications','analytics','booking','commerce','payments','crm','forms','files','search','content','scheduling','profile','settings','configuration']);
function isRecord(value) { return Boolean(value) && typeof value === 'object' && !Array.isArray(value); }
function deepFreeze(value) { if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value; Object.freeze(value); for (const child of Object.values(value)) deepFreeze(child); return value; }
function clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }
function validatePrimitiveDefinition(input) {
  const errors = [];
  if (!isRecord(input)) return { ok: false, errors: ['primitive definition must be an object'], value: null };
  const value = clone(input);
  if (!/^pandora-[a-z0-9][a-z0-9-]*$/.test(String(value.name || ''))) errors.push('name must use canonical pandora-* form');
  try { parseVersion(value.version); } catch (error) { errors.push(error.message); }
  if (!PRIMITIVE_CATEGORIES.includes(value.category)) errors.push(`category must be one of: ${PRIMITIVE_CATEGORIES.join(', ')}`);
  if (!TRUST_STATES.includes(value.trustState)) errors.push(`trustState must be one of: ${TRUST_STATES.join(', ')}`);
  validateStringArray(value.capabilities, 'capabilities', errors, true);
  validateStringArray(value.supportedProjectTypes, 'supportedProjectTypes', errors, true);
  if (Array.isArray(value.supportedProjectTypes)) for (const type of value.supportedProjectTypes) if (!PROJECT_TYPES.includes(type)) errors.push(`unsupported project type: ${type}`);
  if (!isRecord(value.configurationSchema)) errors.push('configurationSchema must be an object');
  validateObjectArray(value.dependencies, 'dependencies', errors, validateDependency);
  validateObjectArray(value.runtimeRequirements, 'runtimeRequirements', errors, validateRuntimeRequirement);
  validateStringArray(value.secretRequirements, 'secretRequirements', errors, false);
  validateStringArray(value.extensionPoints, 'extensionPoints', errors, false);
  validateStringArray(value.permissions, 'permissions', errors, false);
  validateObjectArray(value.events, 'events', errors, validateEvent);
  if (!isRecord(value.verificationProfile)) errors.push('verificationProfile must be an object'); else validateStringArray(value.verificationProfile.requiredChecks, 'verificationProfile.requiredChecks', errors, true);
  if (!isRecord(value.source) || !SOURCE_KINDS.includes(value.source.kind) || typeof value.source.path !== 'string') errors.push(`source must declare kind (${SOURCE_KINDS.join(', ')}) and path`);
  if (value.sourceDigest != null && !/^sha256:[a-f0-9]{64}$/.test(value.sourceDigest)) errors.push('sourceDigest must be null or sha256:<64 hex>');
  if (value.trustState === 'TRUSTED' && !value.sourceDigest) errors.push('TRUSTED primitive requires sourceDigest');
  if (value.deprecation != null && !isRecord(value.deprecation)) errors.push('deprecation must be null or an object');
  scanForEmbeddedSecretValues(value, errors);
  return errors.length ? { ok: false, errors, value: null } : { ok: true, errors: [], value: deepFreeze(value) };
}
function validateDependency(item, field, errors) { if (typeof item.name !== 'string' || !item.name.startsWith('pandora-')) errors.push(`${field}.name must reference a canonical primitive`); if (typeof item.range !== 'string' || !item.range.trim()) errors.push(`${field}.range is required`); if (item.optional != null && typeof item.optional !== 'boolean') errors.push(`${field}.optional must be boolean`); }
function validateRuntimeRequirement(item, field, errors) { if (typeof item.capability !== 'string' || !item.capability.trim()) errors.push(`${field}.capability is required`); if (item.required != null && typeof item.required !== 'boolean') errors.push(`${field}.required must be boolean`); }
function validateEvent(item, field, errors) { if (typeof item.name !== 'string' || !/^[a-z][a-z0-9_.-]+$/.test(item.name)) errors.push(`${field}.name is invalid`); if (typeof item.version !== 'string' || !/^\d+\.\d+$/.test(item.version)) errors.push(`${field}.version must be major.minor`); }
function validateObjectArray(value, field, errors, itemValidator) { if (value == null) return; if (!Array.isArray(value)) { errors.push(`${field} must be an array`); return; } value.forEach((item, index) => { if (!isRecord(item)) errors.push(`${field}[${index}] must be an object`); else itemValidator(item, `${field}[${index}]`, errors); }); }
function validateStringArray(value, field, errors, required) { if (!Array.isArray(value)) { if (required || value != null) errors.push(`${field} must be an array`); return; } if (required && value.length === 0) errors.push(`${field} must not be empty`); const seen = new Set(); value.forEach((item, index) => { if (typeof item !== 'string' || !item.trim()) errors.push(`${field}[${index}] must be a non-empty string`); else if (seen.has(item)) errors.push(`${field} contains duplicate ${item}`); else seen.add(item); }); }
function scanForEmbeddedSecretValues(value, errors, path = '') { if (Array.isArray(value)) return value.forEach((child, index) => scanForEmbeddedSecretValues(child, errors, `${path}[${index}]`)); if (!isRecord(value)) return; for (const [key, child] of Object.entries(value)) { const childPath = path ? `${path}.${key}` : key; if (/^(secretValue|tokenValue|apiKeyValue|serviceRoleKey|privateKey)$/i.test(key) && child != null && String(child).length) errors.push(`${childPath} must never embed a credential value`); scanForEmbeddedSecretValues(child, errors, childPath); } }
module.exports = { PRIMITIVE_CATEGORIES, PROJECT_TYPES, SOURCE_KINDS, TRUST_STATES, clone, deepFreeze, isRecord, validatePrimitiveDefinition };
