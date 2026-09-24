"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OfficialMetaReadProvider = exports.MetaGraphApiError = exports.FetchMetaHttpTransport = void 0;
const resolver_1 = require("../secrets/resolver");
const GRAPH_API_ORIGIN = 'https://graph.facebook.com';
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
class FetchMetaHttpTransport {
    async send(request) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), request.timeoutMs);
        try {
            const response = await fetch(request.url, {
                method: request.method,
                headers: request.headers,
                redirect: 'error',
                signal: controller.signal,
            });
            const contentLength = Number(response.headers.get('content-length') ?? '0');
            if (Number.isFinite(contentLength) && contentLength > MAX_RESPONSE_BYTES) {
                throw new MetaGraphApiError('Meta response exceeded the maximum allowed size', {
                    httpStatus: response.status,
                });
            }
            const bodyText = await response.text();
            if (Buffer.byteLength(bodyText, 'utf8') > MAX_RESPONSE_BYTES) {
                throw new MetaGraphApiError('Meta response exceeded the maximum allowed size', {
                    httpStatus: response.status,
                });
            }
            return {
                status: response.status,
                bodyText,
                contentType: response.headers.get('content-type') ?? undefined,
            };
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
exports.FetchMetaHttpTransport = FetchMetaHttpTransport;
class MetaGraphApiError extends Error {
    constructor(message, details = {}) {
        super(message);
        this.name = 'MetaGraphApiError';
        this.details = details;
    }
}
exports.MetaGraphApiError = MetaGraphApiError;
function record(value) {
    return typeof value === 'object' && value !== null ? value : {};
}
function stringValue(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}
function numberValue(value) {
    return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}
function dateFromSeconds(value) {
    const seconds = numberValue(value);
    return seconds === undefined ? undefined : new Date(seconds * 1000).toISOString();
}
function requireApiVersion(value) {
    const normalized = value.trim();
    if (!/^v\d+\.\d+$/.test(normalized)) {
        throw new Error('Meta Graph API version must match v<major>.<minor>');
    }
    return normalized;
}
function requireTimeout(value) {
    const timeout = value ?? 10000;
    if (!Number.isInteger(timeout) || timeout < 1000 || timeout > 30000) {
        throw new Error('Meta request timeout must be an integer between 1000 and 30000 milliseconds');
    }
    return timeout;
}
function pathSegment(value, fieldName) {
    const normalized = value.trim();
    if (!normalized || normalized.includes('/') || normalized.includes('..')) {
        throw new Error(`${fieldName} is invalid`);
    }
    return encodeURIComponent(normalized);
}
function pageAddress(locationValue) {
    const location = record(locationValue);
    const pieces = [
        stringValue(location.street),
        stringValue(location.city),
        stringValue(location.state),
        stringValue(location.zip),
        stringValue(location.country),
    ].filter((value) => Boolean(value));
    return pieces.length > 0 ? pieces.join(', ') : undefined;
}
function graphArray(value) {
    if (Array.isArray(value)) {
        return value.map(record);
    }
    const nested = record(value).data;
    return Array.isArray(nested) ? nested.map(record) : [];
}
function participantName(value, pageId) {
    const participants = graphArray(value);
    const external = participants.find((participant) => stringValue(participant.id) !== pageId);
    return stringValue(external?.name) ?? 'Facebook user';
}
function insightPeriod(value) {
    return value === 'week' || value === 'month' || value === 'lifetime' ? value : 'day';
}
function numericMetaId(value, fieldName) {
    const normalized = value.trim().replace(/^act_/, '');
    if (!/^\d+$/.test(normalized)) {
        throw new Error(`${fieldName} must be a numeric Meta identifier`);
    }
    return normalized;
}
function marketingDatePreset(value) {
    const preset = value ?? 'last_7d';
    const allowed = new Set(['today', 'yesterday', 'last_7d', 'last_14d', 'last_30d', 'this_month', 'last_month']);
    if (!allowed.has(preset)) {
        throw new Error('datePreset is unsupported');
    }
    return preset;
}
function metricArray(value) {
    return graphArray(value).map((row) => ({
        actionType: stringValue(row.action_type) ?? 'unknown',
        value: stringValue(row.value) ?? String(numberValue(row.value) ?? 0),
    }));
}
class OfficialMetaReadProvider {
    constructor(options) {
        this.providerKind = 'official-meta';
        this.networkCapable = true;
        this.apiVersion = requireApiVersion(options.apiVersion);
        this.pageAccessTokenSecretRef = options.pageAccessTokenSecretRef.trim();
        if (!this.pageAccessTokenSecretRef) {
            throw new Error('A Page access token secret reference is required');
        }
        this.marketingAccessTokenSecretRef = (options.marketingAccessTokenSecretRef ?? options.pageAccessTokenSecretRef).trim();
        if (!this.marketingAccessTokenSecretRef) {
            throw new Error('A Marketing API access token secret reference is required');
        }
        this.secretResolver = options.secretResolver;
        this.transport = options.transport ?? new FetchMetaHttpTransport();
        this.requestTimeoutMs = requireTimeout(options.requestTimeoutMs);
        this.webhookHealthReader = options.webhookHealthReader;
    }
    async getPage(pageId) {
        const value = record(await this.graphGet(pathSegment(pageId, 'pageId'), {
            fields: 'id,name,category,website,phone,location',
        }));
        return {
            id: stringValue(value.id) ?? pageId,
            name: stringValue(value.name) ?? 'Facebook Page',
            category: stringValue(value.category),
            website: stringValue(value.website),
            phone: stringValue(value.phone),
            address: pageAddress(value.location),
        };
    }
    async listPosts(pageId, limit) {
        const value = await this.graphGet(`${pathSegment(pageId, 'pageId')}/posts`, {
            fields: 'id,message,created_time,is_published,scheduled_publish_time',
            limit: String(limit),
        });
        return graphArray(value).map((post) => this.mapPost(pageId, post));
    }
    async getPost(pageId, postId) {
        try {
            const value = record(await this.graphGet(pathSegment(postId, 'postId'), {
                fields: 'id,message,created_time,is_published,scheduled_publish_time',
            }));
            return this.mapPost(pageId, value);
        }
        catch (error) {
            if (error instanceof MetaGraphApiError && error.details.code === 100) {
                return null;
            }
            throw error;
        }
    }
    async listComments(pageId, postId, limit) {
        const value = await this.graphGet(`${pathSegment(postId, 'postId')}/comments`, {
            fields: 'id,message,created_time,from{id,name}',
            limit: String(limit),
        });
        return graphArray(value).map((comment) => {
            const author = record(comment.from);
            return {
                id: stringValue(comment.id) ?? 'unknown-comment',
                postId,
                authorDisplayName: stringValue(author.name) ?? 'Facebook user',
                message: stringValue(comment.message) ?? '',
                createdAt: stringValue(comment.created_time) ?? new Date(0).toISOString(),
                needsStaffAttention: true,
            };
        });
    }
    async listInboxThreads(pageId, limit) {
        const value = await this.graphGet(`${pathSegment(pageId, 'pageId')}/conversations`, {
            fields: 'id,updated_time,unread_count,participants.limit(10){id,name}',
            limit: String(limit),
        });
        return graphArray(value).map((thread) => ({
            id: stringValue(thread.id) ?? 'unknown-thread',
            pageId,
            participantDisplayName: participantName(thread.participants, pageId),
            updatedAt: stringValue(thread.updated_time) ?? new Date(0).toISOString(),
            unreadCount: numberValue(thread.unread_count) ?? 0,
        }));
    }
    async getInboxThread(pageId, threadId) {
        try {
            const value = record(await this.graphGet(pathSegment(threadId, 'threadId'), {
                fields: 'id,updated_time,unread_count,participants.limit(10){id,name},messages.limit(100){id,message,created_time,from,to}',
            }));
            const messages = graphArray(value.messages).map((message) => {
                const from = record(message.from);
                return {
                    id: stringValue(message.id) ?? 'unknown-message',
                    threadId,
                    direction: stringValue(from.id) === pageId ? 'outbound' : 'inbound',
                    message: stringValue(message.message) ?? '',
                    createdAt: stringValue(message.created_time) ?? new Date(0).toISOString(),
                };
            });
            return {
                id: stringValue(value.id) ?? threadId,
                pageId,
                participantDisplayName: participantName(value.participants, pageId),
                updatedAt: stringValue(value.updated_time) ?? new Date(0).toISOString(),
                unreadCount: numberValue(value.unread_count) ?? 0,
                messages,
            };
        }
        catch (error) {
            if (error instanceof MetaGraphApiError && error.details.code === 100) {
                return null;
            }
            throw error;
        }
    }
    async getPageInsights(pageId, metricNames) {
        if (metricNames.length === 0) {
            return [];
        }
        const value = await this.graphGet(`${pathSegment(pageId, 'pageId')}/insights`, {
            metric: metricNames.join(','),
            period: 'day',
        });
        return graphArray(value).map((insight) => {
            const values = graphArray(insight.values);
            const latest = values.length > 0 ? values[values.length - 1] : {};
            return {
                name: stringValue(insight.name) ?? 'unknown_metric',
                period: insightPeriod(insight.period),
                value: numberValue(latest.value) ?? 0,
                asOf: stringValue(latest.end_time) ?? new Date(0).toISOString(),
            };
        });
    }
    async listAdAccounts(_pageId, limit) {
        const value = await this.marketingGraphGet('me/adaccounts', {
            fields: 'id,account_id,name,account_status,currency,business{id,name}',
            limit: String(limit),
        });
        return graphArray(value).map((account) => {
            const business = record(account.business);
            return {
                id: stringValue(account.id) ?? 'unknown-account',
                accountId: stringValue(account.account_id),
                name: stringValue(account.name) ?? 'Meta ad account',
                accountStatus: numberValue(account.account_status),
                currency: stringValue(account.currency),
                business: stringValue(business.id) ? {
                    id: stringValue(business.id),
                    name: stringValue(business.name),
                } : undefined,
            };
        });
    }
    async listCampaigns(_pageId, adAccountId, limit) {
        const accountId = numericMetaId(adAccountId, 'adAccountId');
        const value = await this.marketingGraphGet(`act_${accountId}/campaigns`, {
            fields: 'id,name,status,effective_status,objective,buying_type,daily_budget,lifetime_budget,start_time,stop_time,updated_time',
            limit: String(limit),
        });
        return graphArray(value).map((campaign) => ({
            id: stringValue(campaign.id) ?? 'unknown-campaign',
            name: stringValue(campaign.name) ?? 'Meta campaign',
            status: stringValue(campaign.status),
            effectiveStatus: stringValue(campaign.effective_status),
            objective: stringValue(campaign.objective),
            buyingType: stringValue(campaign.buying_type),
            dailyBudget: stringValue(campaign.daily_budget),
            lifetimeBudget: stringValue(campaign.lifetime_budget),
            startTime: stringValue(campaign.start_time),
            stopTime: stringValue(campaign.stop_time),
            updatedTime: stringValue(campaign.updated_time),
        }));
    }
    async getAdAccountInsights(_pageId, adAccountId, datePreset) {
        const accountId = numericMetaId(adAccountId, 'adAccountId');
        const value = await this.marketingGraphGet(`act_${accountId}/insights`, {
            fields: 'account_id,account_name,account_currency,impressions,reach,clicks,spend,cpc,cpm,ctr,frequency,actions,action_values,date_start,date_stop',
            date_preset: marketingDatePreset(datePreset),
            limit: '100',
        });
        return graphArray(value).map((row) => this.mapMarketingInsight(row));
    }
    async getCampaignInsights(_pageId, campaignId, datePreset) {
        const id = numericMetaId(campaignId, 'campaignId');
        const value = await this.marketingGraphGet(`${id}/insights`, {
            fields: 'campaign_id,campaign_name,account_currency,impressions,reach,clicks,spend,cpc,cpm,ctr,frequency,actions,action_values,date_start,date_stop',
            date_preset: marketingDatePreset(datePreset),
            limit: '100',
        });
        return graphArray(value).map((row) => this.mapMarketingInsight(row));
    }
    mapMarketingInsight(row) {
        return {
            accountId: stringValue(row.account_id),
            accountName: stringValue(row.account_name),
            campaignId: stringValue(row.campaign_id),
            campaignName: stringValue(row.campaign_name),
            currency: stringValue(row.account_currency),
            impressions: stringValue(row.impressions) ?? '0',
            reach: stringValue(row.reach) ?? '0',
            clicks: stringValue(row.clicks) ?? '0',
            spend: stringValue(row.spend) ?? '0',
            cpc: stringValue(row.cpc),
            cpm: stringValue(row.cpm),
            ctr: stringValue(row.ctr),
            frequency: stringValue(row.frequency),
            actions: metricArray(row.actions),
            actionValues: metricArray(row.action_values),
            dateStart: stringValue(row.date_start),
            dateStop: stringValue(row.date_stop),
        };
    }
    async getWebhookHealth(pageId) {
        if (this.webhookHealthReader) {
            return this.webhookHealthReader.getWebhookHealth(pageId);
        }
        return {
            pageId,
            status: 'unconfigured',
            signatureVerificationEnabled: false,
            pendingDeliveries: 0,
            failedDeliveries: 0,
        };
    }
    mapPost(pageId, value) {
        const scheduledFor = dateFromSeconds(value.scheduled_publish_time);
        return {
            id: stringValue(value.id) ?? 'unknown-post',
            pageId,
            message: stringValue(value.message) ?? '',
            createdAt: stringValue(value.created_time) ?? new Date(0).toISOString(),
            status: scheduledFor || value.is_published === false ? 'scheduled' : 'published',
            scheduledFor,
        };
    }
    async graphGet(path, query) {
        return this.graphGetWithSecret(path, query, this.pageAccessTokenSecretRef);
    }
    async marketingGraphGet(path, query) {
        return this.graphGetWithSecret(path, query, this.marketingAccessTokenSecretRef);
    }
    async graphGetWithSecret(path, query, secretRef) {
        const token = await (0, resolver_1.resolveRequiredSecret)(this.secretResolver, secretRef);
        const url = new URL(`${GRAPH_API_ORIGIN}/${this.apiVersion}/${path}`);
        for (const [name, value] of Object.entries(query)) {
            url.searchParams.set(name, value);
        }
        const response = await this.transport.send({
            method: 'GET',
            url: url.toString(),
            headers: {
                accept: 'application/json',
                authorization: `Bearer ${token.value}`,
                'user-agent': 'MCPMaster-Meta-Business-MCP/1.0',
            },
            timeoutMs: this.requestTimeoutMs,
        });
        let parsed;
        try {
            parsed = JSON.parse(response.bodyText);
        }
        catch {
            throw new MetaGraphApiError('Meta returned a non-JSON response', {
                httpStatus: response.status,
            });
        }
        if (response.status < 200 || response.status >= 300 || parsed.error) {
            const graphError = parsed.error ?? {};
            throw new MetaGraphApiError(stringValue(graphError.message) ?? `Meta Graph API request failed with HTTP ${response.status}`, {
                httpStatus: response.status,
                type: stringValue(graphError.type),
                code: numberValue(graphError.code),
                subcode: numberValue(graphError.error_subcode),
                traceId: stringValue(graphError.fbtrace_id),
            });
        }
        return parsed.data ?? parsed;
    }
}
exports.OfficialMetaReadProvider = OfficialMetaReadProvider;
