function nonnegativeInt(value, name) {
  if (!Number.isInteger(value) || value < 0) throw new Error(`INVALID_${name}`);
  return value;
}

function createAdmissionController({ maxGlobal = 8, maxPerOrganization = 4, maxPerProject = 2, minFreeMemoryBytes = 256 * 1024 ** 2, minFreeDiskBytes = 1024 ** 3 } = {}) {
  nonnegativeInt(maxGlobal, 'MAX_GLOBAL');
  nonnegativeInt(maxPerOrganization, 'MAX_PER_ORGANIZATION');
  nonnegativeInt(maxPerProject, 'MAX_PER_PROJECT');

  return Object.freeze({
    decide({ job, snapshot }) {
      if (!job?.organizationId || !job?.projectId) throw new Error('ADMISSION_JOB_SCOPE_REQUIRED');
      if (!snapshot || typeof snapshot !== 'object') throw new Error('ADMISSION_SNAPSHOT_REQUIRED');
      if (snapshot.draining) return { admitted: false, reason: 'WORKER_DRAINING' };
      if (snapshot.controlPlaneHealthy === false) return { admitted: false, reason: 'CONTROL_PLANE_UNHEALTHY' };
      if (snapshot.sandboxProviderHealthy === false) return { admitted: false, reason: 'SANDBOX_PROVIDER_UNHEALTHY' };
      if ((snapshot.freeMemoryBytes ?? Infinity) < minFreeMemoryBytes) return { admitted: false, reason: 'MEMORY_PRESSURE' };
      if ((snapshot.freeDiskBytes ?? Infinity) < minFreeDiskBytes) return { admitted: false, reason: 'DISK_PRESSURE' };
      if ((snapshot.activeGlobal ?? 0) >= maxGlobal) return { admitted: false, reason: 'GLOBAL_CONCURRENCY_LIMIT' };
      if ((snapshot.activeByOrganization?.[job.organizationId] ?? 0) >= maxPerOrganization) return { admitted: false, reason: 'ORGANIZATION_CONCURRENCY_LIMIT' };
      if ((snapshot.activeByProject?.[job.projectId] ?? 0) >= maxPerProject) return { admitted: false, reason: 'PROJECT_CONCURRENCY_LIMIT' };
      return { admitted: true, reason: null };
    },
  });
}

export { createAdmissionController };
