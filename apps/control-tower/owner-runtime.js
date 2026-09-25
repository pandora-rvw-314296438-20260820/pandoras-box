const {
  BRAND_MARK, API_BASE, ROUTES, PROFESSIONAL_ROUTES, icons, state, app, rerender, esc, routeFromLocation, normalizeStatus, isComplete, isActive, isBlocked, cleanName, projectName, projectInitials, formatPhase, timeAgo, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage, eventKind, deriveProjects, readiness
} = window.PandorasOwnerData;

let toastTimer = null;
let dialogReturnFocus = null;

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    credentials: 'same-origin',
    cache: 'no-store',
    headers: { accept: 'application/json', ...(options.body ? { 'content-type': 'application/json' } : {}) },
    ...options,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload?.error?.message || payload?.message || `Request failed (${response.status})`;
    throw Object.assign(new Error(message), { status: response.status, code: payload?.error?.code || `HTTP_${response.status}` });
  }
  return payload;
}

// Bound refresh reads only. Mutations using request() retain their existing contract.
const REFRESH_READ_TIMEOUT_MS = 12_000;
let refreshGeneration = 0;

function readForRefresh(operation) {
  const controller = new AbortController();
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(Object.assign(new Error('Status read timed out. Try refreshing again.'), { code: 'STATUS_TIMEOUT' }));
      controller.abort();
    }, REFRESH_READ_TIMEOUT_MS);
  });
  // Race the entire read, including JSON decoding. Some auth transports do not
  // forward AbortSignal; their late results must not hold the refresh lock.
  return Promise.race([
    Promise.resolve().then(() => operation(controller.signal)),
    deadline,
  ]).finally(() => clearTimeout(timer));
}

async function loadProjection({ signal } = {}) {
  const response = await fetch('/api/operator/status', {
    credentials: 'same-origin', cache: 'no-store', headers: { accept: 'application/json' }, signal,
  });
  const projection = await response.json().catch(() => null);
  if (![200, 503].includes(response.status) || projection?.schemaVersion !== '1.0.0' || !Array.isArray(projection?.tasks)) {
    throw new Error('The current project status is unavailable');
  }
  return projection;
}

async function refresh({ announce = false } = {}) {
  if (state.refreshing) return;
  const generation = ++refreshGeneration;
  // owner-app replaces this object on auth changes. Never restore a previous
  // session's results, or let an older refresh release a newer refresh's lock.
  const businessState = state.business;
  const isCurrent = () => generation === refreshGeneration && state.business === businessState;
  state.refreshing = true;
  state.loading = !state.projection;
  state.live = false;
  state.error = null;
  state.connections = [];
  state.plans = [];
  state.logs = [];
  state.business.loading = true;
  state.business.error = null;
  try {
    rerender();
    // Independent reads start together: neither the projection nor a protected
    // status failure may prevent a successful Business response from rendering.
    const projectionPromise = readForRefresh((signal) => loadProjection({ signal }))
      .then((projection) => {
        if (isCurrent()) {
          state.projection = projection;
          state.loading = false;
          rerender();
        }
        return projection;
      });
    const businessPromise = (window.MCPMasterAuth?.edgeRequest
      ? readForRefresh(() => window.MCPMasterAuth.edgeRequest('pandora-owner-api', ['business'], { method: 'GET' }))
          .then((data) => ({ data, error: null }))
          .catch((error) => ({ data: null, error }))
      : Promise.resolve({ data: null, error: new Error('Business owner contract is unavailable') }))
      .then((result) => {
        if (!isCurrent()) return result;
        const businessData = result.data;
        if (businessData?.contractVersion === 'pandora-owner-business-v1') {
          state.business.data = businessData;
          state.business.error = null;
          state.business.loadedAt = businessData.observedAt || new Date().toISOString();
        } else {
          state.business.data = null;
          state.business.error = result.error?.code === 'STATUS_TIMEOUT'
            ? 'Business data timed out. Try refreshing again.'
            : 'Business data could not be refreshed. Try again.';
          state.business.loadedAt = null;
        }
        state.business.loading = false;
        rerender();
        return result;
      });
    const results = await Promise.allSettled([
      projectionPromise,
      ...['/health', '/tools', '/connections', '/metrics', '/plans?limit=100', '/logs?limit=100', '/logs/verify']
        .map((path) => readForRefresh((signal) => request(path, { signal }))),
      businessPromise,
    ]);
    if (!isCurrent()) return;
    const protectedResults = results.slice(0, 8);
    const [projection, health, tools, connections, metrics, plans, logs, chain] = protectedResults
      .map((result) => result.status === 'fulfilled' ? result.value : null);
    const failure = protectedResults.find((result) => result.status === 'rejected')?.reason;
    const candidate = {
      projection,
      health,
      tools,
      // Missing/malformed responses are unknown, not a valid empty result.
      connections: Array.isArray(connections?.connections) ? connections.connections : null,
      metrics,
      plans: Array.isArray(plans?.plans) ? plans.plans : null,
      logs: Array.isArray(logs?.events) ? logs.events : null,
      chain: chain?.verification || chain,
      error: failure || null,
    };
    state.projection = candidate.projection;
    state.health = candidate.health;
    state.tools = candidate.tools;
    state.connections = candidate.connections || [];
    state.metrics = candidate.metrics;
    state.plans = candidate.plans || [];
    state.logs = candidate.logs || [];
    state.chain = candidate.chain;
    state.live = readiness(candidate);
    if (!state.live) {
      state.connections = [];
      state.plans = [];
      state.logs = [];
      state.error = {
        code: failure?.code || 'LIVE_STATUS_INCOMPLETE',
        message: failure?.code === 'STATUS_TIMEOUT'
          ? 'Live status checks timed out. Try refreshing again. Protected actions remain unavailable.'
          : 'Some protected live checks did not complete. Try refreshing again. No live approval or connection status is being shown.',
      };
    }
    state.session = window.MCPMasterAuth?.session?.() || {};
    if (announce) {
      if (state.live && !state.business.error) showToast('Status refreshed from connected services.', 'success');
      else if (state.live) showToast('Live status refreshed, but Business data is unavailable. Try refreshing again.', 'error');
      else showToast('Live status could not be refreshed. Try again. Protected actions remain unavailable.', 'error');
    }
  } catch (error) {
    if (!isCurrent()) return;
    state.live = false;
    state.connections = [];
    state.plans = [];
    state.logs = [];
    state.error = { code: error?.code || 'STATUS_UNAVAILABLE', message: 'Live status could not be refreshed. Try again.' };
    if (announce) showToast('Live status could not be refreshed. Try again.', 'error');
  } finally {
    if (generation === refreshGeneration) {
      state.loading = false;
      state.refreshing = false;
      if (isCurrent()) state.business.loading = false;
      rerender();
    }
  }
}

function statusSummary() {
  if (state.loading || state.refreshing) return { label: 'Checking status', kind: 'checking' };
  if (!state.session?.authenticated) return { label: 'Sign in to view status', kind: 'warning' };
  if (!state.live) return { label: 'Live status unavailable', kind: 'warning' };
  const blockedProjects = deriveProjects().filter((project) => project.blockedCount > 0).length;
  if (blockedProjects) return { label: `${blockedProjects} project${blockedProjects === 1 ? '' : 's'} need attention`, kind: 'warning' };
  if (pendingPlans().length) return { label: `${pendingPlans().length} approval${pendingPlans().length === 1 ? '' : 's'} waiting`, kind: 'warning' };
  return { label: 'No urgent problems', kind: 'success' };
}

function pendingPlans() {
  return state.plans.filter((plan) => normalizeStatus(plan.status) === 'pending_approval');
}

function attentionCount() {
  if (!state.live) return null;
  return deriveProjects().filter((project) => project.blockedCount > 0).length;
}

function showToast(message, kind = 'success') {
  state.toast = { message, kind };
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    state.toast = null;
    rerender();
  }, 4200);
  rerender();
}

function closeToast() {
  clearTimeout(toastTimer);
  state.toast = null;
  rerender();
}

function navigate(route, { replace = false, resource = '' } = {}) {
  const safeRoute = ROUTES.has(route) ? route : 'home';
  state.route = safeRoute;
  closeDialog({ renderAfter: false });
  const suffix = resource ? `/${encodeURIComponent(String(resource))}` : '';
  const nextUrl = `${window.location.pathname}${window.location.search}#${safeRoute}${suffix}`;
  if (replace) history.replaceState({ route: safeRoute }, '', nextUrl);
  else history.pushState({ route: safeRoute }, '', nextUrl);
  window.scrollTo({ top: 0, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  rerender();
  requestAnimationFrame(() => document.querySelector('#main-content')?.focus());
}

function openDialog(dialog, trigger) {
  dialogReturnFocus = trigger || document.activeElement;
  state.dialog = dialog;
  document.body.classList.add('owner-dialog-open');
  rerender();
  requestAnimationFrame(() => {
    const modal = document.querySelector('[data-owner-dialog]');
    const first = modal?.querySelector('[data-initial-focus], button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    first?.focus();
  });
}

function closeDialog({ renderAfter = true } = {}) {
  if (!state.dialog) return;
  state.dialog = null;
  document.body.classList.remove('owner-dialog-open');
  if (renderAfter) rerender();
  requestAnimationFrame(() => dialogReturnFocus?.focus?.());
}

function focusableInDialog() {
  return [...document.querySelectorAll('[data-owner-dialog] button:not([disabled]), [data-owner-dialog] [href], [data-owner-dialog] input:not([disabled]), [data-owner-dialog] select:not([disabled]), [data-owner-dialog] textarea:not([disabled]), [data-owner-dialog] [tabindex]:not([tabindex="-1"])')];
}

function button(label, options = {}) {
  const { kind = 'secondary', action = '', route = '', extra = '', icon = '', disabled = false, initial = false } = options;
  return `<button type="button" class="owner-button ${kind}" ${action ? `data-action="${esc(action)}"` : ''} ${route ? `data-route="${esc(route)}"` : ''} ${extra} ${disabled ? 'disabled' : ''} ${initial ? 'data-initial-focus' : ''}>${icon ? `<span class="owner-button-icon">${icon}</span>` : ''}<span>${esc(label)}</span></button>`;
}

function badge(label, kind = 'neutral') {
  return `<span class="owner-badge ${kind}">${esc(label)}</span>`;
}

function header() {
  const status = statusSummary();
  const professional = state.mode === 'professional';
  const statusActionLabel = state.session?.authenticated
    ? `${status.label}. Refresh status.`
    : 'Sign in to view protected status.';
  return `<header class="owner-header">
    <div class="owner-brand">
      <img src="${BRAND_MARK}" alt="" class="owner-brand-mark" />
      <div class="owner-brand-copy"><strong>Pandoras-Box</strong><span>${professional ? 'Professional workspace' : 'Everything in one place'}</span></div>
    </div>
    <div class="owner-header-actions">
      <button type="button" class="owner-mode-button" data-action="switch-mode" data-mode="${professional ? 'simple' : 'professional'}" aria-label="Switch to ${professional ? 'Simple' : 'Professional'} Mode">
        <span>${professional ? 'Professional' : 'Simple'}</span><b>Mode</b>
      </button>
      <button type="button" class="owner-account-button" data-route="${professional ? 'settings' : 'more'}" aria-label="Account, settings, and advanced controls">${icons.user}</button>
      <button type="button" class="owner-status ${status.kind}" data-action="refresh" aria-label="${esc(statusActionLabel)}">
        <span class="owner-status-dot" aria-hidden="true"></span><span>${esc(status.label)}</span>
      </button>
    </div>
  </header>`;
}

window.PandorasOwnerRuntime = Object.freeze({
  request, loadProjection, refresh, statusSummary, pendingPlans, attentionCount, showToast, closeToast, navigate, openDialog, closeDialog, focusableInDialog, button, badge, header
});
