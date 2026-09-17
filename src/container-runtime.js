"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveContainerRuntimeMode = resolveContainerRuntimeMode;
function normalized(value) {
    const result = value?.trim().toLowerCase();
    return result || undefined;
}
function resolveContainerRuntimeMode(environment = process.env) {
    const explicit = normalized(environment.MCPMASTER_CONTAINER_MODE);
    if (explicit === 'pandora' || explicit === 'meta-remote') {
        return explicit;
    }
    if (explicit) {
        throw new Error('MCPMASTER_CONTAINER_MODE must be either projectos or meta-remote');
    }
    // ProjectOS is the safe public-container default. The legacy Meta enable
    // variable may still be present in transferred Vercel projects, so it must
    // never select the Meta runtime implicitly. Meta remote mode now requires
    // the explicit MCPMASTER_CONTAINER_MODE=meta-remote selector in addition to
    // its existing startup configuration and enable guard.
    return 'pandora';
}
//# sourceMappingURL=container-runtime.js.map