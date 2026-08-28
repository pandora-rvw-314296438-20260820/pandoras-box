'use strict';

const DEFAULT_ROLE_PERMISSIONS = Object.freeze({
  owner: Object.freeze([
    'project.read','project.manage','users.read','users.manage','settings.read','settings.manage',
    'data.read','data.write','billing.read','billing.manage','booking.read','booking.manage',
    'commerce.read','commerce.manage','admin.read','admin.manage','audit.read',
  ]),
  admin: Object.freeze([
    'project.read','users.read','users.manage','settings.read','settings.manage','data.read','data.write',
    'billing.read','booking.read','booking.manage','commerce.read','commerce.manage','admin.read','admin.manage','audit.read',
  ]),
  manager: Object.freeze([
    'project.read','users.read','settings.read','data.read','data.write','booking.read','booking.manage',
    'commerce.read','commerce.manage','admin.read','audit.read',
  ]),
  staff: Object.freeze(['project.read','settings.read','data.read','booking.read','booking.manage','commerce.read','admin.read']),
  member: Object.freeze(['project.read','settings.read','data.read']),
  customer: Object.freeze(['profile.read_self','profile.write_self','booking.read_self','booking.create_self','commerce.read_self']),
});

class PermissionDeniedError extends Error {
  constructor(permission) {
    super(`permission denied: ${permission}`);
    this.name = 'PermissionDeniedError';
    this.code = 'PERMISSION_DENIED';
    this.permission = permission;
  }
}

class PandoraRbacService {
  constructor({ membershipResolver }) {
    if (!membershipResolver || typeof membershipResolver.resolve !== 'function') {
      throw new TypeError('membershipResolver.resolve is required');
    }
    this.membershipResolver = membershipResolver;
  }

  async permissionsFor({ userId, tenantId }) {
    requireId(userId, 'userId'); requireId(tenantId, 'tenantId');
    const memberships = await this.membershipResolver.resolve({ userId, tenantId });
    if (!Array.isArray(memberships)) throw new TypeError('membership resolver must return an array');
    const permissions = new Set();
    for (const membership of memberships) {
      if (!membership || typeof membership !== 'object') throw new TypeError('membership must be an object');
      if (membership.tenantId !== tenantId) throw new Error('cross-tenant membership rejected');
      const role = requireRole(membership.role);
      const rolePermissions = role === 'custom'
        ? validatePermissionList(membership.permissions, 'membership.permissions')
        : DEFAULT_ROLE_PERMISSIONS[role];
      for (const permission of rolePermissions) permissions.add(permission);
    }
    return Object.freeze([...permissions].sort());
  }

  async can({ userId, tenantId, permission }) {
    requirePermission(permission);
    return (await this.permissionsFor({ userId, tenantId })).includes(permission);
  }

  async assertAllowed(input) {
    if (!(await this.can(input))) throw new PermissionDeniedError(input.permission);
    return Object.freeze({ allowed: true, permission: input.permission });
  }
}

function roleDefinition(role, permissions = null) {
  const normalized = requireRole(role);
  const resolved = normalized === 'custom'
    ? validatePermissionList(permissions, 'permissions')
    : [...DEFAULT_ROLE_PERMISSIONS[normalized]];
  return Object.freeze({ role: normalized, permissions: Object.freeze([...resolved].sort()) });
}

function requireRole(value) {
  if (typeof value !== 'string' || ![...Object.keys(DEFAULT_ROLE_PERMISSIONS), 'custom'].includes(value)) {
    throw new TypeError('role must be owner, admin, manager, staff, member, customer, or custom');
  }
  return value;
}
function validatePermissionList(value, field) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 128) throw new TypeError(`${field} must be a non-empty bounded array`);
  const seen = new Set();
  for (const permission of value) {
    requirePermission(permission);
    if (seen.has(permission)) throw new TypeError(`${field} contains duplicate ${permission}`);
    seen.add(permission);
  }
  return [...seen];
}
function requirePermission(value) {
  if (typeof value !== 'string' || !/^[a-z][a-z0-9_.:-]{1,95}$/.test(value)) throw new TypeError('permission is invalid');
  return value;
}
function requireId(value, field) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value)) throw new TypeError(`${field} is invalid`);
  return value;
}

module.exports = { DEFAULT_ROLE_PERMISSIONS, PandoraRbacService, PermissionDeniedError, roleDefinition, validatePermissionList };
