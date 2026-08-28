'use strict';
const { isRecord } = require('./contracts');
function validateConfiguration(schema, configuration) {
  const errors = []; const config = configuration == null ? {} : configuration;
  if (!isRecord(config)) return { ok: false, errors: ['configuration must be an object'] };
  if (!isRecord(schema)) return { ok: false, errors: ['configuration schema is invalid'] };
  const properties = isRecord(schema.properties) ? schema.properties : {}; const required = new Set(Array.isArray(schema.required) ? schema.required : []);
  for (const field of required) if (!(field in config)) errors.push(`configuration.${field} is required`);
  for (const [key, value] of Object.entries(config)) { const rule = properties[key]; if (!rule) { if (schema.additionalProperties === false) errors.push(`configuration.${key} is not allowed`); continue; } if (!isRecord(rule)) { errors.push(`configuration schema for ${key} is invalid`); continue; } if (!matchesType(value, rule.type)) errors.push(`configuration.${key} must be ${rule.type}`); if (Array.isArray(rule.enum) && !rule.enum.includes(value)) errors.push(`configuration.${key} must be one of: ${rule.enum.join(', ')}`); if (typeof value === 'string' && typeof rule.maxLength === 'number' && value.length > rule.maxLength) errors.push(`configuration.${key} exceeds maxLength`); if (typeof value === 'number' && Number.isFinite(rule.minimum) && value < rule.minimum) errors.push(`configuration.${key} is below minimum`); }
  return { ok: errors.length === 0, errors };
}
function matchesType(value, type) { if (!type) return true; if (type === 'array') return Array.isArray(value); if (type === 'object') return isRecord(value); if (type === 'integer') return Number.isInteger(value); if (type === 'number') return typeof value === 'number' && Number.isFinite(value); return typeof value === type; }
module.exports = { validateConfiguration };
