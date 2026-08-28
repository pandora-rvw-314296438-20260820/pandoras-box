class AdmissionController {
  constructor({ maxConcurrentJobs = 2, maxPerProject = 1, minFreeDiskBytes = 1024 ** 3, maxMemoryPressure = 0.9 } = {}) {
    this.policy = { maxConcurrentJobs, maxPerProject, minFreeDiskBytes, maxMemoryPressure }; this.active = new Map();
  }
  admit({ jobId, projectId }, pressure = {}) {
    if (this.active.has(jobId)) return { admitted: true, replay: true };
    if (this.active.size >= this.policy.maxConcurrentJobs) return { admitted: false, reason: 'worker_capacity' };
    if ([...this.active.values()].filter((x) => x.projectId === projectId).length >= this.policy.maxPerProject) return { admitted: false, reason: 'project_capacity' };
    if ((pressure.freeDiskBytes ?? Infinity) < this.policy.minFreeDiskBytes) return { admitted: false, reason: 'disk_pressure' };
    if ((pressure.memoryPressure ?? 0) >= this.policy.maxMemoryPressure) return { admitted: false, reason: 'memory_pressure' };
    this.active.set(jobId, { projectId, admittedAt: new Date().toISOString() }); return { admitted: true, replay: false };
  }
  release(jobId) { return this.active.delete(jobId); }
  snapshot() { return Object.freeze({ activeJobs: this.active.size, availableCapacity: Math.max(0, this.policy.maxConcurrentJobs - this.active.size) }); }
}
export { AdmissionController };
