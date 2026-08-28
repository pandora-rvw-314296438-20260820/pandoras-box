'use strict';

const { normalizeIdentity } = require('../../core/src/identity');

class PandoraAuthService {
  constructor({ adapter, environment }) {
    if (!adapter || typeof adapter !== 'object') throw new TypeError('auth adapter is required');
    for (const method of ['signUp', 'signIn', 'requestPasswordReset', 'signOut', 'getSession']) {
      if (typeof adapter[method] !== 'function') throw new TypeError(`auth adapter.${method} is required`);
    }
    if (adapter.privileged === true) throw new Error('privileged auth adapters cannot cross the customer client boundary');
    this.adapter = adapter;
    this.environment = requireText(environment, 'environment');
  }

  async signUp({ email, password, redirectUrl }) {
    validateEmail(email); validatePassword(password);
    const result = await this.adapter.signUp({ email: email.trim().toLowerCase(), password, redirectUrl: optionalHttpsUrl(redirectUrl) });
    return normalizeAuthResult(result, this.environment);
  }

  async signIn({ email, password }) {
    validateEmail(email); validatePassword(password);
    const result = await this.adapter.signIn({ email: email.trim().toLowerCase(), password });
    return normalizeAuthResult(result, this.environment);
  }

  async requestPasswordReset({ email, redirectUrl }) {
    validateEmail(email);
    await this.adapter.requestPasswordReset({ email: email.trim().toLowerCase(), redirectUrl: optionalHttpsUrl(redirectUrl) });
    return Object.freeze({ accepted: true });
  }

  async getSession() {
    const result = await this.adapter.getSession();
    if (!result) return null;
    return normalizeAuthResult(result, this.environment);
  }

  async requireUser() {
    const session = await this.getSession();
    if (!session || !session.identity) throw new AuthRequiredError();
    return session.identity;
  }

  async signOut() {
    await this.adapter.signOut();
    const after = await this.adapter.getSession();
    if (after) throw new Error('auth adapter did not invalidate the local session after sign-out');
    return Object.freeze({ signedOut: true });
  }
}

class AuthRequiredError extends Error {
  constructor() { super('authentication required'); this.name = 'AuthRequiredError'; this.code = 'AUTH_REQUIRED'; }
}

function normalizeAuthResult(result, environment) {
  if (!result || typeof result !== 'object') throw new TypeError('auth provider returned an invalid session');
  const rawIdentity = result.identity || result.user;
  const identity = normalizeIdentity({ ...rawIdentity, provider: rawIdentity && rawIdentity.provider || result.provider || 'unknown', environment });
  return Object.freeze({ identity, expiresAt: result.expiresAt || null, requiresEmailVerification: result.requiresEmailVerification === true });
}
function validateEmail(value) { if (typeof value !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())) throw new TypeError('valid email is required'); }
function validatePassword(value) { if (typeof value !== 'string' || value.length < 8 || value.length > 256) throw new TypeError('password must be 8-256 characters'); }
function optionalHttpsUrl(value) { if (value == null || value === '') return null; const parsed = new URL(value); if (parsed.protocol !== 'https:') throw new TypeError('redirectUrl must use https'); return parsed.toString(); }
function requireText(value, field) { if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${field} is required`); return value.trim(); }

module.exports = { AuthRequiredError, PandoraAuthService };
