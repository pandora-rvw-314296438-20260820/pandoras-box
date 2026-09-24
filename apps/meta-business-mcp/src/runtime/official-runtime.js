"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createOfficialMetaRuntime = createOfficialMetaRuntime;
const official_read_provider_1 = require("../meta/official-read-provider");
const network_read_executor_1 = require("../tools/network-read-executor");
const health_store_1 = require("../webhooks/health-store");
const processor_1 = require("../webhooks/processor");
const signature_1 = require("../webhooks/signature");
function required(value, name) {
    if (!value) {
        throw new Error(`${name} is required for the official Meta runtime`);
    }
    return value;
}
function createOfficialMetaRuntime(options) {
    const { config, secretResolver } = options;
    if (!config.networkEnabled) {
        throw new Error('Official Meta runtime requires META_NETWORK_ENABLED=true');
    }
    const webhookHealthStore = options.webhookHealthStore ?? new health_store_1.InMemoryMetaWebhookHealthStore();
    const provider = new official_read_provider_1.OfficialMetaReadProvider({
        apiVersion: config.graphApiVersion,
        pageAccessTokenSecretRef: required(config.tokenSecretRef, 'META_TOKEN_SECRET_REF or META_REMOTE_MCP_INSTALLATION_ID'),
        marketingAccessTokenSecretRef: config.marketingTokenSecretRef ?? config.tokenSecretRef,
        secretResolver,
        transport: options.transport,
        requestTimeoutMs: config.requestTimeoutMs,
        webhookHealthReader: webhookHealthStore,
    });
    const readExecutor = new network_read_executor_1.MetaNetworkReadExecutor(provider);
    if (!config.webhooksEnabled) {
        return { readExecutor, webhookHealthStore };
    }
    const webhookVerifier = new signature_1.MetaWebhookSignatureVerifier({
        appSecretRef: required(config.webhookSecretRef, 'META_WEBHOOK_SECRET_REF'),
        verifyTokenSecretRef: required(config.webhookVerifyTokenSecretRef, 'META_WEBHOOK_VERIFY_TOKEN_SECRET_REF'),
        secretResolver,
    });
    const webhookProcessor = new processor_1.MetaWebhookProcessor({
        signatureVerifier: webhookVerifier,
        claimStore: options.webhookClaimStore ?? new processor_1.InMemoryMetaWebhookClaimStore(),
        healthStore: webhookHealthStore,
        allowedPageIds: config.allowedPageIds,
        maxBodyBytes: config.webhookMaxBodyBytes,
    });
    return {
        readExecutor,
        webhookProcessor,
        webhookVerifier,
        webhookHealthStore,
    };
}
