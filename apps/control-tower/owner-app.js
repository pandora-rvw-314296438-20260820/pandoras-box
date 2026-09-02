if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, app, esc, normalizeStatus, deriveProjects, request, routeFromLocation } = { ...window.PandorasOwnerData, ...window.PandorasOwnerRuntime };
const { refresh, header, showToast, closeToast, navigate, openDialog, closeDialog, focusableInDialog } = window.PandorasOwnerRuntime;
const { renderHome, renderProjects, renderApprovals, renderActivity, renderMore, nav } = window.PandorasOwnerScreens;
const { dialogMarkup, toastMarkup } = window.PandorasOwnerDialogs;

const AUTO_REFRESH_INTERVAL_MS = 60_000;

function render() {
  const routeMarkup = {
    home: renderHome, projects: renderProjects, approvals: renderApprovals,
    activity: renderActivity, more: renderMore,
  }[state.route]?.() || renderHome();
  app.innerHTML = `<div class="owner-app">${header()}<main id="main-content" class="owner-main" tabindex="-1">${routeMarkup}</main>${nav()}${dialogMarkup()}${toastMarkup()}</div>`;
}

function liveRefreshAllowed() {
  return document.visibilityState !== 'hidden'
    && state.session?.authenticated === true
    && !state.refreshing;
}

async function refreshLiveStatus() {
  if (!liveRefreshAllowed()) return;
  await refresh();
}

async function beginOwnerSession({ announce = true } = {}) {
  try {
    await window.MCPMasterAuth?.ensureSession?.();
    state.session = window.MCPMasterAuth?.session?.() || {};
    if (!state.session.authenticated) throw new Error('Sign-in did not complete');
    await refresh({ announce });
  } catch (error) {
    state.loading = false;
    state.refreshing = false;
    if (!/cancel/i.test(error?.message || '')) {
      showToast('Sign-in could not be completed. Nothing was changed.', 'error');
    } else {
      render();
    }
  }
}

async function approve(planId, trigger) {
  const plan = state.plans.find((item) => item.planId === planId);
  if (!plan || !state.live) return;
  trigger?.setAttribute('disabled', '');
  trigger?.setAttribute('aria-busy', 'true');
  try {
    await request('/tools/approve', { method: 'POST', body: JSON.stringify({ planId }) });
    closeDialog({ renderAfter: false });
    showToast('Approval recorded. The update can now continue.', 'success');
    await refresh();
    navigate('approvals', { replace: true });
  } catch (error) {
    showToast(`${error.message || 'The approval could not be saved.'} Nothing was changed.`, 'error');
    render();
  }
}

app.addEventListener('click', async (event) => {
  const target = event.target.closest('[data-route],[data-action]');
  if (!target) return;
  const route = target.dataset.route;
  if (route) {
    navigate(route);
    return;
  }
  const action = target.dataset.action;
  if (action === 'refresh') {
    if (target.closest('[data-owner-dialog]')) closeDialog({ renderAfter: false });
    if (!state.session?.authenticated) {
      await beginOwnerSession();
      return;
    }
    await refresh({ announce: true });
    return;
  }
  if (action === 'later') {
    showToast('Saved for later. The approval is still waiting.', 'info');
    return;
  }
  if (action === 'review-plan') {
    const plan = state.plans.find((item) => item.planId === target.dataset.id);
    if (plan) openDialog({ kind: 'approval', plan }, target);
    return;
  }
  if (action === 'confirm-approve') {
    await approve(target.dataset.id, target);
    return;
  }
  if (action === 'open-project') {
    const project = deriveProjects().find((item) => item.id === target.dataset.id);
    if (project) openDialog({ kind: 'project', project }, target);
    return;
  }
  if (action === 'open-activity') {
    const eventItem = state.logs.find((item) => String(item.sequence ?? '') === target.dataset.sequence);
    if (eventItem) openDialog({ kind: 'activity', event: eventItem }, target);
    return;
  }
  if (action === 'open-connection') {
    const connection = state.connections.find((item) => `${item.provider}:${item.id}` === target.dataset.key);
    if (connection) openDialog({ kind: 'connection', connection }, target);
    return;
  }
  if (action === 'open-system-status') {
    openDialog({ kind: 'system' }, target);
    return;
  }
  if (action === 'toggle-theme') {
    state.theme = state.theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem('pandoras-owner-theme', state.theme);
    document.documentElement.dataset.ownerTheme = state.theme;
    showToast(`${state.theme === 'dark' ? 'Dark' : 'Light'} appearance selected.`, 'info');
    return;
  }
  if (action === 'sign-out') {
    window.MCPMasterAuth?.signOut?.();
    state.session = {};
    state.loading = false;
    state.live = false;
    state.connections = [];
    state.plans = [];
    state.logs = [];
    state.error = { code: 'SIGNED_OUT', message: 'Sign in again to view protected live information.' };
    showToast('Signed out. Protected live information is hidden.', 'info');
    return;
  }
  if (action === 'close-dialog') {
    if (event.target.matches('.owner-dialog-backdrop') || target.closest('.owner-dialog') || target.dataset.action === 'close-dialog') closeDialog();
    return;
  }
  if (action === 'close-toast') closeToast();
});

window.addEventListener('popstate', () => {
  state.route = routeFromLocation();
  closeDialog({ renderAfter: false });
  render();
});

window.addEventListener('focus', refreshLiveStatus);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshLiveStatus();
});
setInterval(refreshLiveStatus, AUTO_REFRESH_INTERVAL_MS);

window.addEventListener('keydown', (event) => {
  if (!state.dialog) return;
  if (event.key === 'Escape') {
    event.preventDefault();
    closeDialog();
    return;
  }
  if (event.key !== 'Tab') return;
  const focusable = focusableInDialog();
  if (!focusable.length) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
});

window.addEventListener('mcpmaster-auth-changed', (event) => {
  state.session = event.detail || window.MCPMasterAuth?.session?.() || {};
  if (!state.session.authenticated) {
    state.loading = false;
    state.live = false;
    state.connections = [];
    state.plans = [];
    state.logs = [];
  } else {
    refreshLiveStatus();
  }
  render();
});

window.PandorasOwnerRender = render;
navigate(state.route, { replace: true });
if (state.session?.authenticated) {
  refresh();
} else {
  state.loading = false;
  state.refreshing = false;
  state.live = false;
  state.error = { code: 'SIGNED_OUT', message: 'Sign in to view protected live information.' };
  render();
}
}
