const nativeFetch = window.fetch.bind(window);

window.fetch = async function pandoraLiveFetch(input, init = {}) {
  const raw = typeof input === 'string' || input instanceof URL ? String(input) : input instanceof Request ? input.url : String(input);
  let pathname = raw;
  try { pathname = new URL(raw, window.location.origin).pathname; } catch {}
  if (pathname !== '/api/operator/status') return nativeFetch(input, init);
  const token = await window.MCPMasterAuth?.ensureSession?.();
  if (!token) throw new Error('Pandora requires an authenticated operator session');
  const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
  headers.set('authorization', 'Bearer ' + token);
  headers.set('accept', 'application/json');
  headers.delete('x-vercel-oidc-token');
  return nativeFetch(input, { ...init, headers, credentials: 'same-origin', cache: 'no-store' });
};
