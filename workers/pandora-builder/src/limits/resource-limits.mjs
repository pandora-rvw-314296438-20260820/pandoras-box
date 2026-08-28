function providerLimitSupport(providerCapabilities, limits) {
  const requested = {
    cpu: limits.cpuMillis != null,
    memory: limits.memoryBytes != null,
    disk: limits.diskBytes != null,
    processCount: limits.processCount != null,
    wallClock: limits.wallClockMs != null,
    output: limits.outputBytes != null,
  };
  const unsupported = Object.entries(requested)
    .filter(([name, enabled]) => enabled && providerCapabilities?.[name] !== true)
    .map(([name]) => name);
  return { enforceable: unsupported.length === 0, unsupported };
}

function resourceLimitFailure(limit, observed = null) {
  return Object.freeze({
    status: 'failed',
    failureClass: 'resource_limit',
    code: 'RESOURCE_LIMIT_EXCEEDED',
    limit,
    observed,
    retryable: false,
  });
}

export { providerLimitSupport, resourceLimitFailure };
