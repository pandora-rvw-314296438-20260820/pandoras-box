'use strict';

class PandoraAdminService {
  constructor({ rbac, resourceAdapter, audit }) {
    if (!rbac || typeof rbac.assertAllowed !== 'function') throw new TypeError('rbac.assertAllowed is required');
    for (const method of ['list','create','update','changeStatus','remove']) if (!resourceAdapter || typeof resourceAdapter[method] !== 'function') throw new TypeError(`resourceAdapter.${method} is required`);
    if (!audit || typeof audit.recordMutation !== 'function') throw new TypeError('audit.recordMutation is required');
    this.rbac = rbac; this.resourceAdapter = resourceAdapter; this.audit = audit;
  }

  async list({ userId, tenantId, query = {} }) {
    await this.rbac.assertAllowed({ userId, tenantId, permission:'admin.read' });
    return this.resourceAdapter.list(normalizeListQuery(query));
  }

  async create({ userId, tenantId, resourceType, data, mutationId }) {
    await this.rbac.assertAllowed({ userId, tenantId, permission:'admin.manage' });
    const clean = normalizeData(data);
    const result = await this.resourceAdapter.create({ tenantId, resourceType:requireType(resourceType), data:clean, mutationId:requireId(mutationId,'mutationId') });
    await this._audit({ userId, tenantId, eventName:`${requireType(resourceType)}.created`, resourceType, resourceId:result.id, mutationId, change:clean });
    return result;
  }

  async update({ userId, tenantId, resourceType, resourceId, patch, mutationId }) {
    await this.rbac.assertAllowed({ userId, tenantId, permission:'admin.manage' });
    const clean = normalizeData(patch);
    const result = await this.resourceAdapter.update({ tenantId, resourceType:requireType(resourceType), resourceId:requireId(resourceId,'resourceId'), patch:clean, mutationId:requireId(mutationId,'mutationId') });
    await this._audit({ userId, tenantId, eventName:`${requireType(resourceType)}.updated`, resourceType, resourceId, mutationId, change:clean });
    return result;
  }

  async changeStatus({ userId, tenantId, resourceType, resourceId, status, mutationId }) {
    await this.rbac.assertAllowed({ userId, tenantId, permission:'admin.manage' });
    const normalizedStatus = requireToken(status,'status');
    const result = await this.resourceAdapter.changeStatus({ tenantId, resourceType:requireType(resourceType), resourceId:requireId(resourceId,'resourceId'), status:normalizedStatus, mutationId:requireId(mutationId,'mutationId') });
    await this._audit({ userId, tenantId, eventName:`${requireType(resourceType)}.status_changed`, resourceType, resourceId, mutationId, change:{status:normalizedStatus} });
    return result;
  }

  async remove({ userId, tenantId, resourceType, resourceId, mutationId, confirmation }) {
    await this.rbac.assertAllowed({ userId, tenantId, permission:'admin.manage' });
    const id = requireId(resourceId,'resourceId');
    if (confirmation !== `DELETE ${id}`) throw new Error('destructive confirmation mismatch');
    const result = await this.resourceAdapter.remove({ tenantId, resourceType:requireType(resourceType), resourceId:id, mutationId:requireId(mutationId,'mutationId') });
    await this._audit({ userId, tenantId, eventName:`${requireType(resourceType)}.deleted`, resourceType, resourceId:id, mutationId });
    return result;
  }

  async _audit(input) { await this.audit.recordMutation({ actorUserId:input.userId, tenantId:input.tenantId, ...input }); }
}

function normalizeListQuery(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new TypeError('query must be an object');
  const pageSize = input.pageSize == null ? 25 : Number(input.pageSize);
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) throw new TypeError('pageSize must be 1-100');
  const cursor = input.cursor == null ? null : requireId(input.cursor,'cursor');
  const search = input.search == null ? null : String(input.search).trim().slice(0,128) || null;
  const sort = input.sort == null ? null : requireToken(input.sort,'sort');
  const direction = input.direction == null ? 'asc' : String(input.direction).toLowerCase();
  if (!['asc','desc'].includes(direction)) throw new TypeError('direction must be asc or desc');
  const filters = input.filters == null ? {} : normalizeData(input.filters);
  return Object.freeze({ pageSize, cursor, search, sort, direction, filters });
}
function normalizeData(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new TypeError('data must be an object');
  const keys = Object.keys(input); if (keys.length > 64) throw new TypeError('data contains too many fields');
  const out={}; for (const key of keys) { if (!/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/.test(key)) throw new TypeError('data key is invalid'); const v=input[key]; if (v === undefined) continue; if (v !== null && !['string','number','boolean'].includes(typeof v)) throw new TypeError('admin data values must be scalar'); if (typeof v === 'string' && v.length > 4096) throw new TypeError('admin data string exceeds limit'); out[key]=v; }
  return Object.freeze(out);
}
function requireType(v){ if(typeof v!=='string'||!/^[a-z][a-z0-9_-]{1,63}$/.test(v)) throw new TypeError('resourceType is invalid'); return v; }
function requireToken(v,f){ if(typeof v!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/.test(v)) throw new TypeError(`${f} is invalid`); return v; }
function requireId(v,f){ if(typeof v!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(v)) throw new TypeError(`${f} is invalid`); return v; }

module.exports = { PandoraAdminService, normalizeData, normalizeListQuery };
