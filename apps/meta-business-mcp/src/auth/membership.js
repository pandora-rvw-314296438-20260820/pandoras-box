"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupabaseOrganizationMembershipResolver = void 0;
exports.roleCanCreateDraft = roleCanCreateDraft;
const supabase_bearer_1 = require("./supabase-bearer");
const rest_client_1 = require("../supabase/rest-client");
const ROLES = new Set(['owner', 'admin', 'operator', 'member', 'viewer']);
function roleCanCreateDraft(role) {
    return role !== 'viewer';
}
class SupabaseOrganizationMembershipResolver {
    constructor(options) {
        this.supabaseUrl = options.supabaseUrl;
        this.publishableKey = options.publishableKey;
        this.fetchFn = options.fetchFn;
        this.timeoutMs = options.timeoutMs ?? 8000;
        this.machineCredentials = options.machineCredentials;
    }
    async resolve(organizationId, userId, accessToken) {
        const machine = (0, supabase_bearer_1.resolvePandoraMachineCredential)(accessToken, userId, this.machineCredentials);
        if (machine) {
            if (machine.organizationId !== organizationId)
                return null;
            return {
                organizationId,
                userId,
                role: machine.role,
            };
        }
        if (accessToken.startsWith('pmt_v1_'))
            return null;
        const query = new URLSearchParams({
            select: 'organization_id,user_id,role,status',
            organization_id: `eq.${organizationId}`,
            user_id: `eq.${userId}`,
            status: 'eq.active',
            limit: '1',
        });
        const client = new rest_client_1.SupabaseRestClient({
            supabaseUrl: this.supabaseUrl,
            apiKey: this.publishableKey,
            accessToken,
            fetchFn: this.fetchFn,
            timeoutMs: this.timeoutMs,
        });
        const payload = await client.requestJson(`/rest/v1/memberships?${query.toString()}`);
        if (!Array.isArray(payload) || payload.length === 0) {
            return null;
        }
        const row = typeof payload[0] === 'object' && payload[0] !== null
            ? payload[0]
            : {};
        const role = row.role;
        if (row.organization_id !== organizationId
            || row.user_id !== userId
            || row.status !== 'active'
            || typeof role !== 'string'
            || !ROLES.has(role)) {
            return null;
        }
        return {
            organizationId,
            userId,
            role: role,
        };
    }
}
exports.SupabaseOrganizationMembershipResolver = SupabaseOrganizationMembershipResolver;
