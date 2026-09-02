const {
  BRAND_MARK, API_BASE, ROUTES, icons, state, app, rerender, esc, routeFromLocation, normalizeStatus, isComplete, isActive, isBlocked, cleanName, projectName, projectInitials, formatPhase, timeAgo, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage, eventKind, deriveProjects, readiness
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

async function loadProjection() {
  const response = await fetch('/api/operator/status', {
    credentials: 'same-origin', cache: 'no-store', headers: { accept: 'application/json' },
  });
  const projection = await response.json().catch(() => null);
  if (![200, 503].includes(response.status) || projection?.schemaVersion !== '1.0.0' || !Array.isArray(projection?.tasks)) {
    throw new Error('The current project status is unavailable');
  }
  return projection;
}

async function refresh({ announce = false } = {}) {
  if (state.refreshing) return;
  state.refreshing = true;
  state.loading = !state.projection;
  state.error = null;
  rerender();
  try {
    state.projection = await loadProjection();
    rerender();
    const [health, tools, connections, metrics, plans, logs, chain] = await Promise.all([
      request('/health'), request('/tools'), request('/connections'), request('/metrics'),
      request('/plans?limit=100'), request('/logs?limit=100'), request('/logs/verify'),
    ]);
    const candidate = {
      projection: state.projection,
      health,
      tools,
      connections: Array.isArray(connections?.connections) ? connections.connections : [],
      metrics,
      plans: Array.isArray(plans?.plans) ? plans.plans : [],
      logs: Array.isArray(logs?.events) ? logs.events : [],
      chain: chain?.verification || chain,
      error: null,
    };
    state.health = candidate.health;
    state.tools = candidate.tools;
    state.connections = candidate.connections;
    state.metrics = candidate.metrics;
    state.plans = candidate.plans;
    state.logs = candidate.logs;
    state.chain = candidate.chain;
    state.live = readiness(candidate);
    if (!state.live) {
      state.connections = [];
      state.plans = [];
      state.logs = [];
      state.error = { code: 'LIVE_STATUS_INCOMPLETE', message: 'Some protected live checks did not complete. No live approval or connection status is being shown.' };
    }
    state.session = window.MCPMasterAuth?.session?.() || {};
    if (announce) showToast('Status refreshed from connected services.', 'success');
  } catch (error) {
    state.live = false;
    state.connections = [];
    state.plans = [];
    state.logs = [];
    state.error = { code: error.code || 'STATUS_UNAVAILABLE', message: error.message || 'Live status is unavailable.' };
    if (announce) showToast('Live status could not be refreshed. Nothing was changed.', 'error');
  } finally {
    state.loading = false;
    state.refreshing = false;
    rerender();
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

function navigate(route, { replace = false } = {}) {
  const safeRoute = ROUTES.has(route) ? route : 'home';
  state.route = safeRoute;
  closeDialog({ renderAfter: false });
  const nextUrl = `${window.location.pathname}${window.location.search}#${safeRoute}`;
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
  const statusActionLabel = state.session?.authenticated
    ? `${status.label}. Refresh status.`
    : 'Sign in to view protected status.';
  return `<header class="owner-header">
    <div class="owner-brand">
      <img src="${BRAND_MARK}" alt="" class="owner-brand-mark" />
      <div class="owner-brand-copy"><strong>Pandoras-Box</strong><span>Everything in one place</span></div>
    </div>
    <button type="button" class="owner-status ${status.kind}" data-action="refresh" aria-label="${esc(statusActionLabel)}">
      <span class="owner-status-dot" aria-hidden="true"></span><span>${esc(status.label)}</span>
    </button>
  </header>`;
}

window.PandorasOwnerRuntime = Object.freeze({
  request, loadProjection, refresh, statusSummary, pendingPlans, attentionCount, showToast, closeToast, navigate, openDialog, closeDialog, focusableInDialog, button, badge, header
});
