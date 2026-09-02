const nativeFetch = window.fetch.bind(window);

const authState = {
  config: null,
  accessToken: '',
  user: null,
  membership: null,
  sessionPromise: null,
  oauthError: '',
};

function html(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character]);
}

async function jsonRequest(url, init = {}) {
  const response = await nativeFetch(url, init);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload?.msg || payload?.message || payload?.error_description || 'Authentication request failed');
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function loadConfig() {
  if (authState.config) return authState.config;
  authState.config = await jsonRequest('/api/operator/auth/config', {
    method: 'GET',
    credentials: 'same-origin',
    headers: { accept: 'application/json' },
  });
  return authState.config;
}

function acceptAuthenticatedSession(session) {
  if (typeof session?.access_token !== 'string' || session.access_token.length < 20) {
    throw new Error('A secure session could not be created');
  }
  authState.accessToken = session.access_token;
  authState.user = session.user || null;
}

const oauthCallbackPromise = (async () => {
  const bridge = window.MCPMasterGitHubAuth;
  if (!bridge?.consumeCallback) return false;
  try {
    const session = await bridge.consumeCallback();
    if (!session) return false;
    acceptAuthenticatedSession(session);
    await verifyOperatorSession();
    authState.oauthError = '';
    window.dispatchEvent(new CustomEvent('mcpmaster-auth-changed', { detail: sessionSnapshot() }));
    return true;
  } catch (error) {
    authState.accessToken = '';
    authState.user = null;
    authState.membership = null;
    authState.oauthError = error?.message || 'Secure sign-in failed';
    return false;
  }
})();

function closeDialog(result) {
  const overlay = document.querySelector('#operator-auth-overlay');
  if (overlay) overlay.remove();
  result?.();
}

function dialog({ eyebrow, title, detail, fields, submitLabel, danger = false, content = '' }) {
  return new Promise((resolve, reject) => {
    document.querySelector('#operator-auth-overlay')?.remove();
    const overlay = document.createElement('div');
    overlay.id = 'operator-auth-overlay';
    overlay.className = 'overlay';
    overlay.innerHTML = `
      <section class="sheet" role="dialog" aria-modal="true" aria-labelledby="operator-auth-title" data-auth-sheet>
        <div class="sheet-header">
          <div><div class="card-title">${html(eyebrow)}</div><h2 id="operator-auth-title" style="margin:3px 0 0">${html(title)}</h2></div>
          <button class="icon-button" type="button" data-auth-cancel aria-label="Cancel">×</button>
        </div>
        <form data-auth-form>
          <div class="sheet-body">
            <div class="alert ${danger ? 'danger' : 'warning'}"><strong>${html(title)}</strong><p>${html(detail)}</p></div>
            ${content}
            ${fields.map((field) => `<div class="field"><label for="operator-${html(field.name)}">${html(field.label)}</label>${field.help ? `<small>${html(field.help)}</small>` : ''}<input id="operator-${html(field.name)}" class="input" name="${html(field.name)}" type="${html(field.type || 'text')}" inputmode="${html(field.inputmode || 'text')}" autocomplete="${html(field.autocomplete || 'off')}" required /></div>`).join('')}
            <div class="alert danger" data-auth-error hidden><strong>Authentication failed</strong><p></p></div>
          </div>
          <div class="sheet-actions"><button class="button ghost" type="button" data-auth-cancel>Cancel</button><button class="button ${danger ? 'danger' : 'primary'}" type="submit">${html(submitLabel)}</button></div>
        </form>
      </section>`;

    const cancel = () => closeDialog(() => reject(new Error('Operator authentication was cancelled')));
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay || event.target.closest('[data-auth-cancel]')) cancel();
    });
    overlay.querySelector('[data-auth-form]').addEventListener('submit', (event) => {
      event.preventDefault();
      const values = Object.fromEntries(new FormData(event.currentTarget).entries());
      resolve({ values, overlay });
    }, { once: true });
    document.body.appendChild(overlay);
    requestAnimationFrame(() => overlay.querySelector('input')?.focus());
  });
}

function showDialogError(overlay, message) {
  const alert = overlay.querySelector('[data-auth-error]');
  alert.hidden = false;
  alert.querySelector('p').textContent = message;
  const form = overlay.querySelector('[data-auth-form]');
  const replacement = form.cloneNode(true);
  form.replaceWith(replacement);
}

async function signIn() {
  const config = await loadConfig();
  while (true) {
    const { values, overlay } = await dialog({
      eyebrow: 'SECURE PANDORA SESSION',
      title: 'Sign in to Pandora',
      detail: 'Sign in to view protected live status and approvals. Your session is kept securely for this visit and is not written to local storage.',
      content: `
        <div style="display:grid;gap:10px;margin-bottom:18px">
          <button class="button primary" type="button" data-github-signin>Continue securely</button>
          <p style="margin:0;color:var(--muted)">Use your authorized Pandora owner account. Approvals remain limited to authenticated owners and admins.</p>
          ${authState.oauthError ? `<div class="alert danger"><strong>Secure sign-in failed</strong><p>${html(authState.oauthError)}</p></div>` : ''}
          <div style="display:flex;align-items:center;gap:10px;color:var(--muted)"><span style="height:1px;flex:1;background:var(--line)"></span><span>or use email and password</span><span style="height:1px;flex:1;background:var(--line)"></span></div>
        </div>`,
      fields: [
        { name: 'email', label: 'Email', type: 'email', autocomplete: 'username' },
        { name: 'password', label: 'Password', type: 'password', autocomplete: 'current-password' },
      ],
      submitLabel: 'Sign in',
    });

    try {
      const session = await jsonRequest(`${config.supabaseUrl}/auth/v1/token?grant_type=password`, {
        method: 'POST',
        redirect: 'error',
        headers: {
          apikey: config.supabasePublishableKey,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify({ email: values.email, password: values.password }),
      });
      if (typeof session.access_token !== 'string' || session.access_token.length < 20) {
        throw new Error('A secure session could not be created');
      }
      authState.accessToken = session.access_token;
      authState.user = session.user || null;
      authState.oauthError = '';
      closeDialog();
      await verifyOperatorSession();
      window.dispatchEvent(new CustomEvent('mcpmaster-auth-changed', { detail: sessionSnapshot() }));
      return;
    } catch (error) {
      authState.accessToken = '';
      authState.user = null;
      showDialogError(overlay, error.message || 'Sign-in failed');
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
  }
}

async function verifyOperatorSession() {
  const payload = await jsonRequest('/api/operator/session', {
    method: 'GET',
    credentials: 'same-origin',
    headers: { authorization: `Bearer ${authState.accessToken}`, accept: 'application/json' },
  });
  authState.membership = payload.user || null;
  return payload;
}

async function ensureSession() {
  await oauthCallbackPromise;
  if (authState.accessToken) return authState.accessToken;
  if (!authState.sessionPromise) {
    authState.sessionPromise = signIn().finally(() => { authState.sessionPromise = null; });
  }
  await authState.sessionPromise;
  return authState.accessToken;
}

function sessionSnapshot() {
  return {
    authenticated: Boolean(authState.accessToken),
    email: authState.membership?.email || authState.user?.email,
    role: authState.membership?.role,
  };
}

function signOut() {
  authState.accessToken = '';
  authState.user = null;
  authState.membership = null;
  authState.oauthError = '';
  window.MCPMasterGitHubAuth?.clearTemporaryState?.();
  window.dispatchEvent(new CustomEvent('mcpmaster-auth-changed', { detail: sessionSnapshot() }));
}

window.fetch = async function authenticatedOperatorFetch(input, init = {}) {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, window.location.href);
  const operatorRequest = url.origin === window.location.origin && url.pathname.startsWith('/api/operator');
  const publicConfig = url.pathname === '/api/operator/auth/config';
  if (!operatorRequest || publicConfig) return nativeFetch(input, init);

  await ensureSession();

  const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
  headers.set('authorization', `Bearer ${authState.accessToken}`);
  headers.delete('x-approval-token');
  headers.delete('x-approver-id');
  headers.delete('x-vercel-oidc-token');
  headers.delete('x-vercel-sc-headers');

  return nativeFetch(input, { ...init, headers, credentials: 'same-origin' });
};

window.MCPMasterAuth = Object.freeze({
  ensureSession,
  signOut,
  session: sessionSnapshot,
});
