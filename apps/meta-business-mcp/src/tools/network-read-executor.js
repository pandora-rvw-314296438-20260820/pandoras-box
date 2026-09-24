"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MetaNetworkReadExecutor = void 0;
const index_1 = require("../../../../packages/shared-security/dist/index");
const policy_1 = require("../security/policy");
const catalog_1 = require("./catalog");
const executor_1 = require("./executor");
function requiredString(argumentsValue, key) {
    const value = argumentsValue[key];
    if (typeof value !== 'string' || !value.trim()) {
        throw new Error(`${key} is required`);
    }
    return value.trim();
}
function optionalLimit(argumentsValue) {
    const value = argumentsValue.limit;
    if (value === undefined) {
        return 25;
    }
    if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 100) {
        throw new Error('limit must be an integer between 1 and 100');
    }
    return value;
}
function optionalDatePreset(argumentsValue) {
    const value = argumentsValue.datePreset;
    if (value === undefined) return 'last_7d';
    if (typeof value !== 'string' || !value.trim()) throw new Error('datePreset must be a string');
    return value.trim();
}
function optionalStringArray(argumentsValue, key) {
    const value = argumentsValue[key];
    if (value === undefined) {
        return [];
    }
    if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
        throw new Error(`${key} must be an array of strings`);
    }
    return value.map((item) => item.trim()).filter(Boolean);
}
class MetaNetworkReadExecutor {
    constructor(provider) {
        this.provider = provider;
        if (!provider.networkCapable || provider.providerKind !== 'official-meta') {
            throw new Error('MetaNetworkReadExecutor requires the official network-capable Meta provider');
        }
    }
    async execute(toolName, argumentsValue, context) {
        const definition = (0, catalog_1.getMetaToolDefinition)(toolName);
        if (definition?.mode === 'write') {
            throw new executor_1.MetaWriteExecutionDisabledError(toolName);
        }
        if (!definition || definition.mode !== 'read') {
            throw new executor_1.MetaPolicyDeniedError(toolName, ['network_executor_read_only']);
        }
        const pageId = requiredString(argumentsValue, 'pageId');
        const policy = (0, policy_1.evaluateMetaInvocation)(toolName, {
            staffId: context.staffId,
            requesterId: context.requesterId,
            pageId,
            allowedPageIds: context.allowedPageIds,
            arguments: argumentsValue,
            killSwitchActive: context.killSwitchActive,
            networkEnabled: context.networkEnabled,
        });
        const reasons = [...policy.reasons];
        if (!context.networkEnabled) {
            reasons.push('meta_network_disabled');
        }
        if (!policy.allowed || reasons.length > 0) {
            throw new executor_1.MetaPolicyDeniedError(toolName, [...new Set(reasons)]);
        }
        let data;
        switch (toolName) {
            case 'meta_page_get':
                data = await this.provider.getPage(pageId);
                break;
            case 'meta_page_list_posts':
                data = await this.provider.listPosts(pageId, optionalLimit(argumentsValue));
                break;
            case 'meta_post_get':
                data = await this.provider.getPost(pageId, requiredString(argumentsValue, 'postId'));
                break;
            case 'meta_post_list_comments':
                data = await this.provider.listComments(pageId, requiredString(argumentsValue, 'postId'), optionalLimit(argumentsValue));
                break;
            case 'meta_inbox_list_threads':
                data = await this.provider.listInboxThreads(pageId, optionalLimit(argumentsValue));
                break;
            case 'meta_inbox_get_thread':
                data = await this.provider.getInboxThread(pageId, requiredString(argumentsValue, 'threadId'));
                break;
            case 'meta_page_get_insights':
                data = await this.provider.getPageInsights(pageId, optionalStringArray(argumentsValue, 'metricNames'));
                break;
            case 'meta_webhook_health':
                data = await this.provider.getWebhookHealth(pageId);
                break;
            case 'meta_ad_accounts_list':
                data = await this.provider.listAdAccounts(pageId, optionalLimit(argumentsValue));
                break;
            case 'meta_ad_campaigns_list':
                data = await this.provider.listCampaigns(pageId, requiredString(argumentsValue, 'adAccountId'), optionalLimit(argumentsValue));
                break;
            case 'meta_ad_account_insights':
                data = await this.provider.getAdAccountInsights(pageId, requiredString(argumentsValue, 'adAccountId'), optionalDatePreset(argumentsValue));
                break;
            case 'meta_campaign_insights':
                data = await this.provider.getCampaignInsights(pageId, requiredString(argumentsValue, 'campaignId'), optionalDatePreset(argumentsValue));
                break;
            default:
                throw new executor_1.MetaPolicyDeniedError(toolName, ['unsupported_network_read_tool']);
        }
        return {
            toolName,
            mode: 'read',
            data,
            policy: {
                actionHash: policy.actionHash,
                requiresLegalReview: policy.requiresLegalReview,
            },
            audit: {
                argumentsRedacted: (0, index_1.redactForAudit)(argumentsValue),
            },
        };
    }
}
exports.MetaNetworkReadExecutor = MetaNetworkReadExecutor;
