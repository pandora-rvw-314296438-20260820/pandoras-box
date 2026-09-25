"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.remoteMetaMcpTools = void 0;
exports.getRemoteMetaMcpTool = getRemoteMetaMcpTool;
const catalog_1 = require("../tools/catalog");
const pageId = {
    type: 'string',
    minLength: 1,
    maxLength: 128,
    description: 'Exact allowlisted Facebook Page ID.',
};
const limit = {
    type: 'integer',
    minimum: 1,
    maximum: 100,
    default: 25,
};
const adAccountId = {
    type: 'string',
    minLength: 1,
    maxLength: 64,
    pattern: '^(?:act_)?[0-9]+$',
    description: 'Authorized Meta ad account identifier.',
};
const datePreset = {
    type: 'string',
    enum: ['today', 'yesterday', 'last_7d', 'last_14d', 'last_30d', 'this_month', 'last_month'],
    default: 'last_7d',
};
const message = {
    type: 'string',
    minLength: 1,
    maxLength: 10000,
    description: 'Draft content. This is stored internally and is not sent to Meta.',
};
function objectSchema(properties, required) {
    return {
        type: 'object',
        additionalProperties: false,
        properties,
        required,
    };
}
const INPUT_SCHEMAS = {
    meta_page_get: objectSchema({ pageId }, ['pageId']),
    meta_page_list_posts: objectSchema({ pageId, limit }, ['pageId']),
    meta_post_get: objectSchema({
        pageId,
        postId: { type: 'string', minLength: 1, maxLength: 256 },
    }, ['pageId', 'postId']),
    meta_post_list_comments: objectSchema({
        pageId,
        postId: { type: 'string', minLength: 1, maxLength: 256 },
        limit,
    }, ['pageId', 'postId']),
    meta_inbox_list_threads: objectSchema({ pageId, limit }, ['pageId']),
    meta_inbox_get_thread: objectSchema({
        pageId,
        threadId: { type: 'string', minLength: 1, maxLength: 256 },
    }, ['pageId', 'threadId']),
    meta_page_get_insights: objectSchema({
        pageId,
        metricNames: {
            type: 'array',
            maxItems: 25,
            items: { type: 'string', minLength: 1, maxLength: 128 },
        },
    }, ['pageId']),
    meta_webhook_health: objectSchema({ pageId }, ['pageId']),
    meta_ad_accounts_list: objectSchema({ pageId, limit }, ['pageId']),
    meta_ad_campaigns_list: objectSchema({ pageId, adAccountId, limit }, ['pageId', 'adAccountId']),
    meta_ad_account_insights: objectSchema({ pageId, adAccountId, datePreset }, ['pageId', 'adAccountId']),
    meta_campaign_insights: objectSchema({
        pageId,
        campaignId: { type: 'string', minLength: 1, maxLength: 64, pattern: '^[0-9]+$' },
        datePreset,
    }, ['pageId', 'campaignId']),
    meta_post_create_draft: objectSchema({ pageId, message }, ['pageId', 'message']),
    meta_comment_create_reply_draft: objectSchema({
        pageId,
        postId: { type: 'string', minLength: 1, maxLength: 256 },
        commentId: { type: 'string', minLength: 1, maxLength: 256 },
        message,
    }, ['pageId', 'postId', 'commentId', 'message']),
    meta_message_create_reply_draft: objectSchema({
        pageId,
        threadId: { type: 'string', minLength: 1, maxLength: 256 },
        message,
    }, ['pageId', 'threadId', 'message']),
    meta_content_create_weekly_plan: objectSchema({
        pageId,
        weekOf: { type: 'string', minLength: 1, maxLength: 64 },
        topics: {
            type: 'array',
            minItems: 1,
            maxItems: 14,
            items: { type: 'string', minLength: 1, maxLength: 500 },
        },
    }, ['pageId', 'topics']),
};
function titleFor(name) {
    return name
        .split('_')
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(' ');
}
function expose(definition) {
    const inputSchema = INPUT_SCHEMAS[definition.name];
    if (!inputSchema) {
        throw new Error(`Missing remote MCP schema for ${definition.name}`);
    }
    const readOnly = definition.mode === 'read';
    return {
        name: definition.name,
        title: titleFor(definition.name),
        description: definition.description,
        inputSchema,
        annotations: {
            readOnlyHint: readOnly,
            destructiveHint: false,
            idempotentHint: readOnly,
            openWorldHint: readOnly,
        },
    };
}
exports.remoteMetaMcpTools = catalog_1.metaToolCatalog
    .filter((definition) => definition.mode !== 'write')
    .map(expose);
function getRemoteMetaMcpTool(name) {
    return exports.remoteMetaMcpTools.find((tool) => tool.name === name);
}
