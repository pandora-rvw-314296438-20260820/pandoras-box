"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CompositeMetaSecretResolver = exports.SupabaseMetaInstallationSecretResolver = void 0;
const resolver_1 = require("./resolver");
const rest_client_1 = require("../supabase/rest-client");
const INSTALLATION_REF = /^installation:\/\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\/(page|marketing)$/i;
class SupabaseMetaInstallationSecretResolver {
    constructor(options) {
        this.organizationId = options.organizationId;
        this.client = new rest_client_1.SupabaseRestClient({
            supabaseUrl: options.supabaseUrl,
            apiKey: options.serviceKey,
            accessToken: options.serviceKey,
            fetchFn: options.fetchFn,
            timeoutMs: options.timeoutMs,
            maxResponseBytes: 64 * 1024,
        });
    }
    canResolve(secretRef) { return INSTALLATION_REF.test(secretRef.trim()); }
    async resolve(secretRef) {
        const match = INSTALLATION_REF.exec(secretRef.trim());
        if (!match) throw new resolver_1.SecretResolutionError("Meta installation secret references must use installation://<uuid>/<page|marketing>");
        const payload = await this.client.requestJson("/rest/v1/rpc/pandora_meta_runtime_secret_v1", {
            method: "POST",
            body: JSON.stringify({ p_organization_id: this.organizationId, p_installation_id: match[1], p_purpose: match[2] }),
        });
        if (!payload || typeof payload !== "object" || typeof payload.token !== "string" || !payload.token.trim()) {
            throw new resolver_1.SecretResolutionError("Supabase did not return a usable Meta runtime credential");
        }
        return { value: payload.token.trim() };
    }
}
exports.SupabaseMetaInstallationSecretResolver = SupabaseMetaInstallationSecretResolver;
class CompositeMetaSecretResolver {
    constructor(primary, installation) { this.primary = primary; this.installation = installation; }
    async resolve(secretRef) {
        if (this.installation.canResolve(secretRef)) return this.installation.resolve(secretRef);
        return this.primary.resolve(secretRef);
    }
}
exports.CompositeMetaSecretResolver = CompositeMetaSecretResolver;
