"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const environment_resolver_1 = require("./secrets/environment-resolver");
const remote_config_1 = require("./remote-config");
const remote_runtime_1 = require("./runtime/remote-runtime");
function resolveEntrypointMode() {
    const runtime = require('../../../dist/container-runtime.js');
    return runtime.resolveContainerRuntimeMode(process.env);
}
function startPandoraFallback() {
    const runtime = require('../../../dist/pandora-container-server.js');
    console.warn('Legacy Meta container entrypoint invoked; starting Pandora safe default');
    runtime.startPandoraContainerServer();
}
async function main() {
    const mode = resolveEntrypointMode();
    if (mode === 'pandora') {
        startPandoraFallback();
        return;
    }
    const config = (0, remote_config_1.loadMetaRemoteMcpConfig)();
    if (!config.requireHttps && !['127.0.0.1', 'localhost', '::1'].includes(config.host)) {
        throw new Error('HTTPS may only be disabled for a loopback development server');
    }
    const secretResolver = new environment_resolver_1.EnvironmentSecretResolver();
    const runtime = await (0, remote_runtime_1.createMetaRemoteRuntime)({ config, secretResolver });
    const server = runtime.app.listen(config.port, config.host, () => {
        console.log(`Meta Business MCP listening on ${config.host}:${config.port}`);
        console.log('Remote endpoint: /mcp; external writes: disabled');
    });
    const shutdown = (signal) => {
        console.log(`Received ${signal}; closing Meta Business MCP`);
        server.close((error) => {
            if (error) {
                console.error('Meta Business MCP shutdown failed');
                process.exitCode = 1;
            }
            process.exit();
        });
    };
    process.once('SIGINT', () => shutdown('SIGINT'));
    process.once('SIGTERM', () => shutdown('SIGTERM'));
}
main().catch((error) => {
    console.error(error instanceof Error ? error.message : 'Meta Business MCP startup failed');
    process.exitCode = 1;
});
