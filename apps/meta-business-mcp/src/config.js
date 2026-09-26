"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.loadMetaBusinessConfig = loadMetaBusinessConfig;
function parseBoolean(value, defaultValue) {
    if (value === undefined || value.trim() === '') {
        return defaultValue;
    }
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true') {
        return true;
    }
    if (normalized === 'false') {
        return false;
    }
    throw new Error(`Expected true or false, received: ${value}`);
}
function optional(value) {
    const normalized = value?.trim();
    return normalized || undefined;
}
function parsePageIds(value) {
    const pageIds = (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
    if (pageIds.some((pageId) => pageId.includes('*'))) {
        throw new Error('META_ALLOWED_PAGE_IDS cannot contain wildcards');
    }
    return [...new Set(pageIds)];
}
const FORBIDDEN_RAW_SECRET_ENVIRONMENT_VARIABLES = [
    'META_ACCESS_TOKEN',
    'META_PAGE_ACCESS_TOKEN',
    'META_MARKETING_ACCESS_TOKEN',
    'META_APP_SECRET',
    'META_WEBHOOK_SECRET',
    'META_ENCRYPTION_KEY',
];
function loadMetaBusinessConfig(environment = process.env) {
    for (const variableName of FORBIDDEN_RAW_SECRET_ENVIRONMENT_VARIABLES) {
        if (optional(environment[variableName])) {
            throw new Error(`${variableName} is forbidden. Configure a server-side secret reference instead.`);
        }
    }
    const installationId = optional(environment.META_REMOTE_MCP_INSTALLATION_ID);
    const installationPageSecretRef = installationId ? `installation://${installationId}/page` : undefined;
    const installationMarketingSecretRef = installationId ? `installation://${installationId}/marketing` : undefined;
    const config = {
        allowedPageIds: parsePageIds(environment.META_ALLOWED_PAGE_IDS),
        killSwitchActive: parseBoolean(environment.META_KILL_SWITCH, true),
        networkEnabled: parseBoolean(environment.META_NETWORK_ENABLED, false),
        metaAppId: optional(environment.META_APP_ID),
        tokenSecretRef: optional(environment.META_TOKEN_SECRET_REF) ?? installationPageSecretRef,
        marketingTokenSecretRef: optional(environment.META_MARKETING_TOKEN_SECRET_REF)
            ?? installationMarketingSecretRef
            ?? optional(environment.META_TOKEN_SECRET_REF),
        webhookSecretRef: optional(environment.META_WEBHOOK_SECRET_REF),
        encryptionKeyRef: optional(environment.META_ENCRYPTION_KEY_REF),
    };
    if (config.networkEnabled) {
        const missing = [
            ['META_APP_ID', config.metaAppId],
            ['META_TOKEN_SECRET_REF', config.tokenSecretRef],
            ['META_WEBHOOK_SECRET_REF', config.webhookSecretRef],
            ['META_ENCRYPTION_KEY_REF', config.encryptionKeyRef],
        ]
            .filter(([, value]) => !value)
            .map(([name]) => name);
        if (missing.length > 0) {
            throw new Error(`Meta network mode is missing required configuration: ${missing.join(', ')}`);
        }
        if (config.allowedPageIds.length === 0) {
            throw new Error('Meta network mode requires at least one allowlisted Page ID');
        }
        if (config.killSwitchActive) {
            throw new Error('Meta network mode cannot start while the kill switch is active');
        }
    }
    return config;
}
