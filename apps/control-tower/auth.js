const nativeFetch = window.fetch.bind(window);
const ALLOWED_EDGE_FUNCTIONS = new Set(['pandora-intelligence-chat', 'pandora-preview-content']);
const EDGE_ROUTE_POLICIES = Object.freeze({
  'pandora-owner-api': Object.freeze({
    GET: Object.freeze([
      /^projects$/,
      /^projects\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/,
    ]),
  }),
  'pandora-project-runtime': Object.freeze({
    GET: Object.freeze([
      /^projects\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/runtime$/,
    ]),
    POST: Object.freeze([
      /^projects\/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\/(?:undo|publish)$/,
    ]),
  }),
});
const PROJECT_PROJECTION_COLUMNS = Object.freeze({
  pandora_project_experience_projection: [
    'project_id','experience_state','current_version_id','current_preview_deployment_id',
    'current_verified','candidate_version_id','candidate_preview_deployment_id',
    'candidate_verification_state','production_version_id','production_deployment_id',
    'active_build_job_id','build_phase','public_message','needs_you','retry_available',
    'can_focus','can_change','can_undo','can_publish','can_rollback',
    'verification_summary','change_summary','safe_failure_code','safe_failure_message',
    'last_transition_at','updated_at',
  ].join(','),
  pandora_build_theatre_projection: [
    'project_id','build_job_id','project_version_id','owner_state','owner_stage',
    'progress_percent','public_message','preview_url','live_url','needs_you',
    'retry_available','last_event_at','updated_at',
  ].join(','),
});

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

async function edgeRequest(functionName, pathSegments = [], options = {}) {
  const method = String(options.method || 'GET').toUpperCase();
  const route = pathSegments.map((segment) => String(segment)).join('/');
  const policy = EDGE_ROUTE_POLICIES[functionName]?.[method];
  if (!Array.isArray(policy) || !policy.some((pattern) => pattern.test(route))) {
    throw new Error('This Pandora route is not available from the owner web surface');
  }
  const config = await loadConfig();
  await ensureSession();
  const suffix = pathSegments.length
    ? `/${pathSegments.map((segment) => encodeURIComponent(String(segment))).join('/')}`
    : '';
  const response = await nativeFetch(
    `${config.supabaseUrl}/functions/v1/${encodeURIComponent(functionName)}${suffix}`,
    {
      method,
      redirect: 'error',
      headers: {
        apikey: config.supabasePublishableKey,
        authorization: `Bearer ${authState.accessToken}`,
        accept: 'application/json',
        ...(options.body === undefined ? {} : { 'content-type': 'application/json' }),
        'x-organization-id': config.organizationId,
      },
      ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.ok === false) {
    throw new Error(payload?.plainMessage || payload?.message || payload?.error?.message || 'Pandora is temporarily unavailable');
  }
  return payload;
}

async function readProjectProjection(tableName, projectId) {
  const select = PROJECT_PROJECTION_COLUMNS[tableName];
  if (!select || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(projectId || ''))) {
    throw new Error('Pandora rejected an invalid project projection request');
  }
  const config = await loadConfig();
  await ensureSession();
  const url = new URL(`${config.supabaseUrl}/rest/v1/${tableName}`);
  url.searchParams.set('select', select);
  url.searchParams.set('project_id', `eq.${projectId}`);
  url.searchParams.set('limit', '1');
  const response = await nativeFetch(url, {
    method: 'GET',
    redirect: 'error',
    headers: {
      apikey: config.supabasePublishableKey,
      authorization: `Bearer ${authState.accessToken}`,
      accept: 'application/json',
    },
  });
  const rows = await response.json().catch(() => []);
  if (!response.ok || !Array.isArray(rows)) {
    throw new Error('Pandora could not read the project experience safely');
  }
  return rows[0] || null;
}

async function invokeFunction(functionName, body = {}) {
  if (!ALLOWED_EDGE_FUNCTIONS.has(functionName)) {
    throw new Error('This Pandora function is not available from the owner web surface');
  }
  const config = await loadConfig();
  await ensureSession();
  const response = await nativeFetch(`${config.supabaseUrl}/functions/v1/${encodeURIComponent(functionName)}`, {
    method: 'POST',
    redirect: 'error',
    headers: {
      apikey: config.supabasePublishableKey,
      authorization: `Bearer ${authState.accessToken}`,
      accept: 'application/json',
      'content-type': 'application/json',
      'x-organization-id': config.organizationId,
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.ok === false) {
    throw new Error(payload?.plainMessage || payload?.message || 'Pandora is temporarily unavailable');
  }
  return payload;
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
  edgeRequest,
  readProjectProjection,
  invokeFunction,
  signOut,
  session: sessionSnapshot,
});
