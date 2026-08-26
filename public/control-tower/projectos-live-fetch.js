const nativeFetch = typeof window !== 'undefined' && typeof window.fetch === 'function'
  ? window.fetch.bind(window)
  : globalThis.fetch?.bind(globalThis);

async function projectOSLiveFetch(input, init = {}) {
  const raw = typeof input === 'string' || input instanceof URL
    ? String(input)
    : input instanceof Request
      ? input.url
      : String(input);
  let pathname = raw;
  try {
    pathname = new URL(raw, window.location.origin).pathname;
  } catch {
    // Preserve the original input when URL parsing is not possible.
  }

  const legacyStatusRequest = pathname === '/control-tower/projectos-status.json';
  const projectOSRequest = legacyStatusRequest
    || pathname === '/api/operator/status'
    || pathname === '/api/projectos'
    || pathname === '/api/projectos-status';

  if (!projectOSRequest) return nativeFetch(input, init);

  const token = await window.MCPMasterAuth?.ensureSession?.();
  if (!token) throw new Error('ProjectOS requires an authenticated operator session');

  const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
  headers.set('authorization', `Bearer ${token}`);
  headers.set('accept', 'application/json');
  headers.delete('x-vercel-oidc-token');

  const target = legacyStatusRequest ? '/api/operator/status' : input;
  return nativeFetch(target, {
    ...init,
    headers,
    credentials: 'same-origin',
    cache: 'no-store',
  });
}

try {
  Object.defineProperty(window, 'fetch', {
    value: projectOSLiveFetch,
    writable: true,
    configurable: true,
  });
} catch {
  // Ignore in sandboxed or getter-only environments
}

