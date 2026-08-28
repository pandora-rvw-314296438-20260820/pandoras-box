function workerHealth({ admission, providerHealth = 'unknown', queueDepth = null, lastHeartbeat = new Date().toISOString(), pressure = {} }) {
  const capacity = admission.snapshot();
  const diskPressure = pressure.freeDiskBytes != null && pressure.minFreeDiskBytes != null ? pressure.freeDiskBytes < pressure.minFreeDiskBytes : false;
  const memoryPressure = (pressure.memoryPressure ?? 0) >= (pressure.maxMemoryPressure ?? 0.9);
  return Object.freeze({ schemaVersion: 1, status: providerHealth === 'healthy' && !diskPressure && !memoryPressure ? 'healthy' : 'degraded', ...capacity, queueDepth, lastHeartbeat, sandboxProviderHealth: providerHealth, diskPressure, memoryPressure });
}
export { workerHealth };
