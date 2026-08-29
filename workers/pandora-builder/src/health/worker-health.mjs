function createWorkerHealthSnapshot({ workerIdentity, activeJobs = 0, queuedJobs = 0, capacity = 0, freeMemoryBytes = null, freeDiskBytes = null, sandboxProviderHealthy = true, controlPlaneHealthy = true, draining = false, observedAt = new Date().toISOString() }) {
  if (typeof workerIdentity !== 'string' || workerIdentity.length < 3) throw new Error('WORKER_IDENTITY_REQUIRED');
  for (const [name, value] of Object.entries({ activeJobs, queuedJobs, capacity })) if (!Number.isInteger(value) || value < 0) throw new Error(`INVALID_${name.toUpperCase()}`);
  const ready = !draining && sandboxProviderHealthy && controlPlaneHealthy && activeJobs < capacity;
  return Object.freeze({ workerIdentity, activeJobs, queuedJobs, capacity, availableCapacity: Math.max(0, capacity - activeJobs), freeMemoryBytes, freeDiskBytes, sandboxProviderHealthy: Boolean(sandboxProviderHealthy), controlPlaneHealthy: Boolean(controlPlaneHealthy), draining: Boolean(draining), ready, observedAt });
}

export { createWorkerHealthSnapshot };
