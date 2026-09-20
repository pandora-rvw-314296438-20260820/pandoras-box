"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupabaseBearerAuthenticator = exports.BearerAuthenticationError = void 0;
exports.resolvePandoraMachineCredential = resolvePandoraMachineCredential;
const node_crypto_1 = require("node:crypto");
class BearerAuthenticationError extends Error {
    constructor(message, status = 401) {
        super(message);
        this.name = 'BearerAuthenticationError';
        this.status = status;
    }
}
exports.BearerAuthenticationError = BearerAuthenticationError;
// No source-controlled machine credentials are active. Machine credentials must
// be issued through the owner-authenticated enrollment flow and stored only as
// hashes in the credential registry. This empty default also immediately revokes
// any previously embedded credential.
const DEFAULT_MACHINE_CREDENTIALS = Object.freeze([]);
function normalizeSupabaseUrl(value) {
    const url = new URL(value.trim());
    const isLocal = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
    if (url.protocol !== 'https:' && !(isLocal && url.protocol === 'http:')) {
        throw new Error('Supabase URL must use HTTPS except for localhost tests');
    }
    url.pathname = '/auth/v1/user';
    url.search = '';
    url.hash = '';
    return url;
}
function required(value, name) {
    const normalized = value.trim();
    if (!normalized) {
        throw new Error(`${name} is required`);
    }
    return normalized;
}
function bearerToken(header) {
    const match = /^Bearer\s+([^\s]+)$/i.exec(header?.trim() ?? '');
    if (!match || match[1].length < 20 || match[1].length > 8192) {
        throw new BearerAuthenticationError('A valid bearer access token is required');
    }
    return match[1];
}
function isUuid(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function validMachineCredentialShape(credential) {
    return (/^pmt_v1_[a-z0-9_-]+_$/.test(credential.tokenPrefix)
        && /^[0-9a-f]{64}$/.test(credential.tokenHash)
        && isUuid(credential.userId)
        && isUuid(credential.organizationId)
        && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(credential.repositoryFullName)
        && credential.role === 'operator'
        && Number.isFinite(Date.parse(credential.expiresAt)));
}
function machineCredentialMatches(token, credential, now) {
    if (!validMachineCredentialShape(credential))
        return false;
    if (!token.startsWith(credential.tokenPrefix))
        return false;
    if (!/^[A-Za-z0-9_-]{43,128}$/.test(token.slice(credential.tokenPrefix.length)))
        return false;
    if (Date.parse(credential.expiresAt) <= now)
        return false;
    const expected = Buffer.from(credential.tokenHash, 'hex');
    const actual = (0, node_crypto_1.createHash)('sha256').update(token, 'utf8').digest();
    return expected.length === actual.length && (0, node_crypto_1.timingSafeEqual)(expected, actual);
}
function resolvePandoraMachineCredential(accessToken, userId, credentials = DEFAULT_MACHINE_CREDENTIALS, now = Date.now()) {
    for (const credential of credentials) {
        if (userId && credential.userId !== userId)
            continue;
        if (machineCredentialMatches(accessToken, credential, now))
            return credential;
    }
    return undefined;
}
function verifiedTokenClaims(accessToken, userId) {
    const segments = accessToken.split('.');
    if (segments.length !== 3 || segments[1].length > 16 * 1024)
        return {};
    try {
        const payload = JSON.parse(Buffer.from(segments[1], 'base64url').toString('utf8'));
        if (payload.sub !== userId)
            return {};
        const scopeClaimsPresent = ['scope', 'scp', 'scopes']
            .some((claim) => Object.prototype.hasOwnProperty.call(payload, claim));
        const scopeValues = [
            ...(typeof payload.scope === 'string' ? payload.scope.split(/\s+/) : []),
            ...(typeof payload.scp === 'string' ? payload.scp.split(/\s+/) : []),
            ...(Array.isArray(payload.scp) ? payload.scp : []),
            ...(Array.isArray(payload.scopes) ? payload.scopes : []),
        ].filter((scope) => typeof scope === 'string' && /^[a-z0-9:*._-]{1,128}$/i.test(scope));
        return {
            aal: payload.aal === 'aal1' || payload.aal === 'aal2' ? payload.aal : undefined,
            scopes: [...new Set(scopeValues)],
            scopeClaimsPresent,
        };
    }
    catch {
        return {};
    }
}
class SupabaseBearerAuthenticator {
    constructor(options) {
        this.userUrl = normalizeSupabaseUrl(options.supabaseUrl);
        this.publishableKey = required(options.publishableKey, 'Supabase publishable key');
        this.fetchFn = options.fetchFn ?? fetch;
        this.timeoutMs = options.timeoutMs ?? 8000;
        this.machineCredentials = options.machineCredentials ?? DEFAULT_MACHINE_CREDENTIALS;
        if (!Number.isInteger(this.timeoutMs) || this.timeoutMs < 500 || this.timeoutMs > 20000) {
            throw new Error('Supabase authentication timeout must be between 500 and 20000 milliseconds');
        }
    }
    async authenticate(authorizationHeader) {
        const accessToken = bearerToken(authorizationHeader);
        const machine = resolvePandoraMachineCredential(accessToken, undefined, this.machineCredentials);
        if (machine) {
            return {
                userId: machine.userId,
                accessToken,
                email: `${machine.subject}@pandora.machine`,
            };
        }
        if (accessToken.startsWith('pmt_v1_')) {
            throw new BearerAuthenticationError('The Pandora machine credential is invalid, expired, or revoked');
        }
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
        try {
            const response = await this.fetchFn(this.userUrl, {
                method: 'GET',
                headers: {
                    accept: 'application/json',
                    apikey: this.publishableKey,
                    authorization: `Bearer ${accessToken}`,
                },
                redirect: 'error',
                signal: controller.signal,
            });
            if (response.status === 401 || response.status === 403) {
                throw new BearerAuthenticationError('The bearer access token is invalid or expired');
            }
            if (!response.ok) {
                throw new BearerAuthenticationError('The authentication service is unavailable', 503);
            }
            const bytes = new Uint8Array(await response.arrayBuffer());
            if (bytes.byteLength > 64 * 1024) {
                throw new BearerAuthenticationError('The authentication service returned an invalid response', 503);
            }
            let payload;
            try {
                payload = JSON.parse(Buffer.from(bytes).toString('utf8'));
            }
            catch {
                throw new BearerAuthenticationError('The authentication service returned invalid JSON', 503);
            }
            const record = typeof payload === 'object' && payload !== null
                ? payload
                : {};
            const userId = typeof record.id === 'string' ? record.id : '';
            if (!isUuid(userId)) {
                throw new BearerAuthenticationError('The authentication response did not contain a valid user', 503);
            }
            const identity = {
                userId,
                accessToken,
                email: typeof record.email === 'string' ? record.email : undefined,
            };
            const claims = verifiedTokenClaims(accessToken, userId);
            if (claims.aal)
                identity.aal = claims.aal;
            if (claims.scopes)
                identity.scopes = claims.scopes;
            identity.scopeClaimsPresent = claims.scopeClaimsPresent === true;
            return identity;
        }
        catch (error) {
            if (error instanceof BearerAuthenticationError) {
                throw error;
            }
            if (error instanceof Error && error.name === 'AbortError') {
                throw new BearerAuthenticationError('The authentication service timed out', 503);
            }
            throw new BearerAuthenticationError('The authentication service is unavailable', 503);
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
exports.SupabaseBearerAuthenticator = SupabaseBearerAuthenticator;
