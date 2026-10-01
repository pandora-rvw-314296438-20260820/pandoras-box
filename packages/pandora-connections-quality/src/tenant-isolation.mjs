const actions = new Set(['read', 'use', 'refresh', 'revoke']);
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,199}$/;
const sensitiveCredentialKeys = /(?:access|refresh|api|client|private|secret|token|password|authorization)/i;

export class TenantIsolationError extends Error {
  constructor(code) {
    super(code);
    this.name = 'TenantIsolationError';
    this.code = code;
  }
}

function identifier(value, code) {
  if (typeof value !== 'string' || !identifierPattern.test(value)) {
    throw new TenantIsolationError(code);
  }
  return value;
}

function record(value, code) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TenantIsolationError(code);
  }
  return value;
}

function assertNoCredentialMaterial(value) {
  for (const [key, item] of Object.entries(value)) {
    if (sensitiveCredentialKeys.test(key) && key !== 'credentialReferenceId') {
      throw new TenantIsolationError('CREDENTIAL_MATERIAL_FORBIDDEN');
    }
    if (typeof item === 'string' && /^(?:bearer\s+|sk[-_]|eyJ[A-Za-z0-9_-]+[.])/i.test(item)) {
      throw new TenantIsolationError('CREDENTIAL_MATERIAL_FORBIDDEN');
    }
  }
}

function actorBinding(value) {
  const actor = record(value, 'ACTOR_BINDING_REQUIRED');
  return {
    organizationId: identifier(actor.organizationId, 'ACTOR_ORGANIZATION_REQUIRED'),
    tenantId: identifier(actor.tenantId, 'ACTOR_TENANT_REQUIRED'),
    accountId: identifier(actor.accountId, 'ACTOR_ACCOUNT_REQUIRED'),
  };
}

function connectionBinding(value) {
  const connection = record(value, 'CONNECTION_NOT_FOUND');
  assertNoCredentialMaterial(connection);
  return {
    id: identifier(connection.id, 'CONNECTION_NOT_FOUND'),
    organizationId: identifier(connection.organizationId, 'CONNECTION_TENANT_INVALID'),
    tenantId: identifier(connection.tenantId, 'CONNECTION_TENANT_INVALID'),
    accountId: identifier(connection.accountId, 'CONNECTION_ACCOUNT_INVALID'),
    provider: identifier(connection.provider, 'CONNECTION_PROVIDER_INVALID'),
    state: identifier(connection.state, 'CONNECTION_STATE_INVALID'),
  };
}

function credentialBinding(value) {
  const credential = record(value, 'CREDENTIAL_BINDING_REQUIRED');
  assertNoCredentialMaterial(credential);
  return {
    credentialReferenceId: identifier(
      credential.credentialReferenceId,
      'CREDENTIAL_BINDING_REQUIRED',
    ),
    organizationId: identifier(credential.organizationId, 'CREDENTIAL_TENANT_INVALID'),
    tenantId: identifier(credential.tenantId, 'CREDENTIAL_TENANT_INVALID'),
    accountId: identifier(credential.accountId, 'CREDENTIAL_ACCOUNT_INVALID'),
    connectionId: identifier(credential.connectionId, 'CREDENTIAL_CONNECTION_INVALID'),
  };
}

export function assertTenantActionBinding({ action, actor, connection, credential }) {
  if (!actions.has(action)) {
    throw new TenantIsolationError('CONNECTION_ACTION_NOT_ALLOWED');
  }
  const selected = actorBinding(actor);
  const boundConnection = connectionBinding(connection);
  if (boundConnection.organizationId !== selected.organizationId) {
    throw new TenantIsolationError('ORGANIZATION_MISMATCH');
  }
  if (boundConnection.tenantId !== selected.tenantId) {
    throw new TenantIsolationError('TENANT_MISMATCH');
  }
  if (boundConnection.accountId !== selected.accountId) {
    throw new TenantIsolationError('ACCOUNT_MISMATCH');
  }

  let boundCredential = null;
  if (action !== 'read') {
    boundCredential = credentialBinding(credential);
    if (
      boundCredential.organizationId !== selected.organizationId ||
      boundCredential.organizationId !== boundConnection.organizationId
    ) {
      throw new TenantIsolationError('CREDENTIAL_ORGANIZATION_MISMATCH');
    }
    if (
      boundCredential.tenantId !== selected.tenantId ||
      boundCredential.tenantId !== boundConnection.tenantId
    ) {
      throw new TenantIsolationError('CREDENTIAL_TENANT_MISMATCH');
    }
    if (
      boundCredential.accountId !== selected.accountId ||
      boundCredential.accountId !== boundConnection.accountId
    ) {
      throw new TenantIsolationError('CREDENTIAL_ACCOUNT_MISMATCH');
    }
    if (boundCredential.connectionId !== boundConnection.id) {
      throw new TenantIsolationError('CREDENTIAL_CONNECTION_MISMATCH');
    }
  }

  return Object.freeze({
    action,
    actor: Object.freeze(selected),
    connection: Object.freeze(boundConnection),
    credential: boundCredential ? Object.freeze(boundCredential) : null,
  });
}

function publicConnection(connection) {
  const bound = connectionBinding(connection);
  return Object.freeze({
    id: bound.id,
    provider: bound.provider,
    state: bound.state,
    accountId: bound.accountId,
    tenantId: bound.tenantId,
  });
}

export function createTenantScopedConnectionApi(dependencies) {
  const deps = record(dependencies, 'TENANT_API_DEPENDENCIES_REQUIRED');
  for (const name of ['listConnections', 'getConnection', 'getCredentialReference', 'executeAction']) {
    if (typeof deps[name] !== 'function') {
      throw new TenantIsolationError('TENANT_API_DEPENDENCIES_REQUIRED');
    }
  }

  async function load(actor, connectionId, action) {
    const selected = actorBinding(actor);
    const connection = await deps.getConnection(connectionId);
    let credential = null;
    if (action !== 'read') {
      // Connection ownership is checked before a credential reference is read.
      assertTenantActionBinding({ action: 'read', actor: selected, connection });
      credential = await deps.getCredentialReference(connectionId);
    }
    const binding = assertTenantActionBinding({ action, actor: selected, connection, credential });
    return { binding, connection };
  }

  return Object.freeze({
    async list(actor) {
      const selected = actorBinding(actor);
      const rows = await deps.listConnections(selected.organizationId);
      if (!Array.isArray(rows) || rows.length > 500) {
        throw new TenantIsolationError('CONNECTION_LIST_INVALID');
      }
      return rows.map((connection) => {
        assertTenantActionBinding({ action: 'read', actor: selected, connection });
        return publicConnection(connection);
      });
    },

    async read(actor, connectionId) {
      const { connection } = await load(actor, connectionId, 'read');
      return publicConnection(connection);
    },

    async use(actor, connectionId) {
      const { binding } = await load(actor, connectionId, 'use');
      await deps.executeAction(binding);
      return Object.freeze({ ok: true, action: 'use', connectionId: binding.connection.id });
    },

    async refresh(actor, connectionId) {
      const { binding } = await load(actor, connectionId, 'refresh');
      await deps.executeAction(binding);
      return Object.freeze({ ok: true, action: 'refresh', connectionId: binding.connection.id });
    },

    async revoke(actor, connectionId) {
      const { binding } = await load(actor, connectionId, 'revoke');
      await deps.executeAction(binding);
      return Object.freeze({ ok: true, action: 'revoke', connectionId: binding.connection.id });
    },
  });
}
