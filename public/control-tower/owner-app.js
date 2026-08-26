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
  const action = target.dataset.action;

  if (action === 'open-ask-pandora') {
    state.wizardStep = 1;
    state.route = 'home';
    render();
    requestAnimationFrame(() => document.querySelector('#pandora-intent-input')?.focus());
    return;
  }
  if (action === 'reset-wizard') {
    state.wizardStep = 0;
    render();
    return;
  }
  if (action === 'quick-prompt') {
    const prompt = target.dataset.prompt || '';
    state.wizardData.prompt = prompt;
    state.wizardData.goal = `Build an online booking system: ${prompt}`;
    state.wizardStep = 2;
    render();
    return;
  }
  if (action === 'submit-intent') {
    const inputEl = document.querySelector('#pandora-intent-input');
    const val = (inputEl ? inputEl.value : state.wizardData.prompt).trim();
    if (val) {
      state.wizardData.prompt = val;
      state.wizardData.goal = val;
    }
    state.wizardStep = 2;
    render();
    return;
  }
  if (action === 'wizard-back') {
    state.wizardStep = Math.max(0, state.wizardStep - 1);
    render();
    return;
  }
  if (action === 'set-wizard-step') {
    const stepNum = parseInt(target.dataset.step, 10);
    if (!isNaN(stepNum)) {
      state.wizardStep = stepNum;
      render();
    }
    return;
  }
  if (action === 'edit-goal') {
    state.wizardStep = 0;
    render();
    requestAnimationFrame(() => document.querySelector('#pandora-intent-input')?.focus());
    return;
  }
  if (action === 'proceed-to-build') {
    state.wizardStep = 3;
    showToast('Pandora started building your system...', 'info');
    render();
    return;
  }
  if (action === 'open-full-preview' || action === 'start-review') {
    state.wizardStep = 5;
    render();
    return;
  }
  if (action === 'set-preview-mode') {
    state.wizardData.previewMode = target.dataset.mode || 'mobile';
    render();
    return;
  }
  if (action === 'set-preview-tab') {
    state.wizardData.previewTab = target.dataset.tab || 'home';
    render();
    return;
  }
  if (action === 'select-preview-service') {
    state.wizardData.selectedService = target.value;
    return;
  }
  if (action === 'select-preview-time') {
    state.wizardData.selectedTime = target.value;
    return;
  }
  if (action === 'submit-preview-booking') {
    showToast('Booking submitted successfully! Notification sent.', 'success');
    state.wizardData.previewTab = 'bookings';
    render();
    return;
  }
  if (action === 'voice-input' || action === 'voice-feedback') {
    state.wizardData.voiceFeedbackActive = !state.wizardData.voiceFeedbackActive;
    showToast(state.wizardData.voiceFeedbackActive ? 'Listening for voice input...' : 'Voice input captured.', 'info');
    render();
    return;
  }
  if (action === 'approve-and-publish') {
    showToast('Booking system approved & published live! Your system is healthy.', 'success');
    state.wizardStep = 0;
    render();
    return;
  }

  if (route) {
    if (action !== 'reset-wizard') {
      navigate(route);
    }
    return;
  }

  if (action === 'refresh') {
    if (target.closest('[data-owner-dialog]')) closeDialog({ renderAfter: false });
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
refresh();
}
