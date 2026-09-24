"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MetaRemoteMcpHandler = exports.SUPPORTED_MCP_PROTOCOL_VERSIONS = void 0;
const membership_1 = require("../auth/membership");
const catalog_1 = require("../tools/catalog");
const draft_executor_1 = require("../tools/draft-executor");
const executor_1 = require("../tools/executor");
const tools_1 = require("./tools");
exports.SUPPORTED_MCP_PROTOCOL_VERSIONS = [
    '2025-11-25',
    '2025-06-18',
    '2025-03-26',
];
function record(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value)
        ? value
        : {};
}
function validId(value) {
    return value === null || typeof value === 'string' || typeof value === 'number';
}
function errorResponse(id, code, message, data) {
    return {
        jsonrpc: '2.0',
        id,
        error: {
            code,
            message,
            ...(data === undefined ? {} : { data }),
        },
    };
}
function resultResponse(id, result) {
    return { jsonrpc: '2.0', id, result };
}
function negotiatedVersion(requested) {
    if (typeof requested === 'string' && exports.SUPPORTED_MCP_PROTOCOL_VERSIONS.includes(requested)) {
        return requested;
    }
    return exports.SUPPORTED_MCP_PROTOCOL_VERSIONS[0];
}
function toolErrorMessage(error) {
    if (error instanceof executor_1.MetaPolicyDeniedError) {
        return `Request denied: ${error.reasons.join(', ')}`;
    }
    if (error instanceof executor_1.MetaWriteExecutionDisabledError) {
        return 'External write execution is disabled.';
    }
    if (error instanceof Error && /(?:required|must|cannot|unsupported|between|contain)/i.test(error.message)) {
        return error.message.slice(0, 300);
    }
    return 'Tool execution failed.';
}
class MetaRemoteMcpHandler {
    constructor(options) {
        this.options = options;
        this.maxToolResponseBytes = options.maxToolResponseBytes ?? 512 * 1024;
    }
    async handle(message, actor) {
        if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
            return {
                notification: false,
                response: errorResponse(null, -32600, 'Invalid Request'),
            };
        }
        const isNotification = message.id === undefined;
        if (!isNotification && !validId(message.id)) {
            return {
                notification: false,
                response: errorResponse(null, -32600, 'Invalid Request'),
            };
        }
        if (isNotification) {
            return { notification: true };
        }
        const id = message.id;
        switch (message.method) {
            case 'initialize': {
                const params = record(message.params);
                return {
                    notification: false,
                    response: resultResponse(id, {
                        protocolVersion: negotiatedVersion(params.protocolVersion),
                        capabilities: { tools: { listChanged: false } },
                        serverInfo: {
                            name: 'mcpmaster-meta-business',
                            title: 'MCPMaster Meta Business MCP',
                            version: '1.0.0',
                            description: 'Authenticated Page, Marketing API read, and internal-draft tools for an allowlisted Meta Business connection.',
                        },
                        instructions: [
                            'This server exposes Meta Page and Marketing API read tools plus internal draft creation only.',
                            'It does not publish, schedule, reply, send, or delete external content.',
                            'Drafts involving legal advice, deadlines, fees, conflicts, case facts, strategy, or outcomes require human legal review.',
                        ].join(' '),
                    }),
                };
            }
            case 'ping':
                return { notification: false, response: resultResponse(id, {}) };
            case 'tools/list':
                return {
                    notification: false,
                    response: resultResponse(id, { tools: tools_1.remoteMetaMcpTools }),
                };
            case 'tools/call':
                return {
                    notification: false,
                    response: resultResponse(id, await this.callTool(message.params, actor)),
                };
            default:
                return {
                    notification: false,
                    response: errorResponse(id, -32601, 'Method not found'),
                };
        }
    }
    async callTool(paramsValue, actor) {
        const params = record(paramsValue);
        const name = typeof params.name === 'string' ? params.name : '';
        const argumentsValue = record(params.arguments);
        const exposedTool = (0, tools_1.getRemoteMetaMcpTool)(name);
        const catalogTool = (0, catalog_1.getMetaToolDefinition)(name);
        if (!exposedTool) {
            return {
                content: [{
                        type: 'text',
                        text: catalogTool?.mode === 'write'
                            ? 'External write tools are not exposed by this server.'
                            : 'Unknown tool.',
                    }],
                isError: true,
            };
        }
        try {
            const context = {
                organizationId: this.options.organizationId,
                staffId: actor.identity.userId,
                requesterId: actor.identity.userId,
                allowedPageIds: this.options.allowedPageIds,
                killSwitchActive: this.options.killSwitchActive,
                networkEnabled: this.options.networkEnabled,
            };
            let data;
            if (catalogTool?.mode === 'read') {
                data = (await this.options.readExecutor.execute(name, argumentsValue, context)).data;
            }
            else if (catalogTool?.mode === 'draft') {
                if (!(0, membership_1.roleCanCreateDraft)(actor.membership.role)) {
                    throw new executor_1.MetaPolicyDeniedError(name, ['draft_role_required']);
                }
                const drafts = this.options.draftStoreFactory(actor.identity.accessToken);
                data = (await new draft_executor_1.PersistentMetaDraftExecutor(drafts).execute(name, argumentsValue, context)).data;
            }
            else {
                throw new executor_1.MetaWriteExecutionDisabledError(name);
            }
            const text = JSON.stringify(data);
            if (Buffer.byteLength(text, 'utf8') > this.maxToolResponseBytes) {
                throw new Error('Tool response exceeds the configured size limit');
            }
            return {
                content: [{ type: 'text', text }],
                structuredContent: data,
                isError: false,
            };
        }
        catch (error) {
            return {
                content: [{ type: 'text', text: toolErrorMessage(error) }],
                isError: true,
            };
        }
    }
}
exports.MetaRemoteMcpHandler = MetaRemoteMcpHandler;
