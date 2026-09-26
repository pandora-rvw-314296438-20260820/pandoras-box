"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createMetaRemoteRuntime = createMetaRemoteRuntime;
const supabase_bearer_1 = require("../auth/supabase-bearer");
const membership_1 = require("../auth/membership");
const supabase_store_1 = require("../drafts/supabase-store");
const handler_1 = require("../mcp/handler");
const server_1 = require("../mcp/server");
const api_1 = require("../operator/api");
const resolver_1 = require("../secrets/resolver");
const supabase_installation_resolver_1 = require("../secrets/supabase-installation-resolver");
const supabase_stores_1 = require("../webhooks/supabase-stores");
const official_runtime_1 = require("./official-runtime");
async function createMetaRemoteRuntime(options) {
    const { config, secretResolver, fetchFn } = options;
    const serviceKey = await (0, resolver_1.resolveRequiredSecret)(secretResolver, config.supabaseServiceKeySecretRef);
    const webhookStoreOptions = {
        supabaseUrl: config.supabaseUrl,
        serviceKey: serviceKey.value,
        organizationId: config.organizationId,
        installationId: config.installationId,
        fetchFn,
        timeoutMs: config.supabaseTimeoutMs,
    };
    const webhookHealthStore = new supabase_stores_1.SupabaseMetaWebhookHealthStore(webhookStoreOptions);
    const webhookClaimStore = new supabase_stores_1.SupabaseMetaWebhookClaimStore(webhookStoreOptions);
    const installationResolver = new supabase_installation_resolver_1.SupabaseMetaInstallationSecretResolver({
        supabaseUrl: config.supabaseUrl,
        serviceKey: serviceKey.value,
        organizationId: config.organizationId,
        fetchFn,
        timeoutMs: config.supabaseTimeoutMs,
    });
    const runtimeSecretResolver = new supabase_installation_resolver_1.CompositeMetaSecretResolver(secretResolver, installationResolver);
    const official = (0, official_runtime_1.createOfficialMetaRuntime)({
        config,
        secretResolver: runtimeSecretResolver,
        transport: options.metaTransport,
        webhookHealthStore,
        webhookClaimStore,
    });
    const authenticator = new supabase_bearer_1.SupabaseBearerAuthenticator({
        supabaseUrl: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        fetchFn,
        timeoutMs: config.authTimeoutMs,
        machineCredentials: [],
    });
    const membershipResolver = new membership_1.SupabaseOrganizationMembershipResolver({
        supabaseUrl: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        fetchFn,
        timeoutMs: config.supabaseTimeoutMs,
        machineCredentials: [],
    });
    const handler = new handler_1.MetaRemoteMcpHandler({
        readExecutor: official.readExecutor,
        draftStoreFactory: (accessToken) => new supabase_store_1.SupabaseMetaDraftStore({
            supabaseUrl: config.supabaseUrl,
            publishableKey: config.supabasePublishableKey,
            accessToken,
            fetchFn,
            timeoutMs: config.supabaseTimeoutMs,
        }),
        organizationId: config.organizationId,
        allowedPageIds: config.allowedPageIds,
        killSwitchActive: config.killSwitchActive,
        networkEnabled: config.networkEnabled,
    });
    const operatorApi = (0, api_1.createOperatorApiApp)({
        authenticator,
        membershipResolver,
        organizationId: config.organizationId,
        supabaseUrl: config.supabaseUrl,
        supabasePublishableKey: config.supabasePublishableKey,
        allowedOrigins: config.allowedOrigins,
        requestsPerMinute: config.requestsPerMinute,
    });
    const app = (0, server_1.createMetaRemoteMcpApp)({
        handler,
        authenticator,
        membershipResolver,
        organizationId: config.organizationId,
        allowedOrigins: config.allowedOrigins,
        requireHttps: config.requireHttps,
        requestBodyLimitBytes: config.requestBodyLimitBytes,
        requestsPerMinute: config.requestsPerMinute,
        webhookProcessor: official.webhookProcessor,
        webhookVerifier: official.webhookVerifier,
        webhookBodyLimitBytes: config.webhookMaxBodyBytes,
        operatorApi,
    });
    return { app, official };
}
