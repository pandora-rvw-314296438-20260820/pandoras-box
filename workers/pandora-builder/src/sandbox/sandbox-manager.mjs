const METHODS = ['create', 'resume', 'execute', 'cancel', 'destroy', 'inspect'];

class SandboxProvider {
  constructor() {
    if (new.target === SandboxProvider) throw new Error('SANDBOX_PROVIDER_ABSTRACT');
  }
}

class SandboxManager {
  constructor({ provider }) {
    if (!provider || METHODS.some((method) => typeof provider[method] !== 'function')) {
      throw new Error('INVALID_SANDBOX_PROVIDER');
    }
    this.provider = provider;
  }

  create(request) { return this.provider.create(request); }
  resume(request) { return this.provider.resume(request); }
  execute(handle, operation) { return this.provider.execute(handle, operation); }
  cancel(handle, reason) { return this.provider.cancel(handle, reason); }
  destroy(handle) { return this.provider.destroy(handle); }
  inspect(handle) { return this.provider.inspect(handle); }
}

export { SandboxManager, SandboxProvider };
