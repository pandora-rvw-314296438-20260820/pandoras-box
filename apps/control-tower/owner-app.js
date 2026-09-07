if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, app, esc, normalizeStatus, deriveProjects, request, routeFromLocation, routeResourceFromLocation } = { ...window.PandorasOwnerData, ...window.PandorasOwnerRuntime };
const { refresh, header, showToast, closeToast, navigate, openDialog, closeDialog, focusableInDialog } = window.PandorasOwnerRuntime;
const { renderHome, renderProjects, renderProjectWorkspace, renderAsk, renderNeeds, renderBusiness, renderApprovals, renderActivity, renderMore, nav } = window.PandorasOwnerScreens;
const { dialogMarkup, toastMarkup } = window.PandorasOwnerDialogs;

const AUTO_REFRESH_INTERVAL_MS = 60_000;

function render() {
  const routeMarkup = {
    home: renderHome,
    projects: renderProjects,
    project: renderProjectWorkspace,
    ask: renderAsk,
    needs: renderNeeds,
    business: renderBusiness,
    approvals: renderApprovals,
    activity: renderActivity,
    more: renderMore,
  }[state.route]?.() || renderHome();
  app.innerHTML = `<div class="owner-app">${header()}<main id="main-content" class="owner-main" tabindex="-1">${routeMarkup}</main>${nav()}${dialogMarkup()}${toastMarkup()}</div>`;
}

function ownerProjectsFromPayload(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.projects)) return payload.projects;
  return [];
}

async function loadProjectWorkspace(sourceId = routeResourceFromLocation()) {
  const item = state.projectWorkspace;
  item.sourceId = sourceId || item.sourceId;
  item.loading = true;
  item.error = null;
  render();
  try {
    const source = deriveProjects().find((project) => project.id === item.sourceId)
      || (item.source?.id === item.sourceId ? item.source : null);
    if (!source) throw new Error('This project is not in the current authoritative project status.');
    const projectItems = ownerProjectsFromPayload(
      await window.MCPMasterAuth?.edgeRequest?.('pandora-owner-api', ['projects'], { method: 'GET' }),
    );
    const ownerSummary = projectItems.find((project) =>
      String(project.repository || '').toLowerCase() === String(source.repository || '').toLowerCase()
    );
    if (!ownerSummary?.id) throw new Error('Pandora could not bind this project to its owner-safe project identity.');
    const [detail, runtime] = await Promise.all([
      window.MCPMasterAuth.edgeRequest('pandora-owner-api', ['projects', ownerSummary.id], { method: 'GET' }),
      window.MCPMasterAuth.edgeRequest('pandora-project-runtime', ['projects', ownerSummary.id, 'runtime'], { method: 'GET' }),
    ]);
    const projectId = runtime?.project?.id;
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(projectId || ''))) {
      throw new Error('Pandora could not verify the exact runtime project identity.');
    }
    const [experience, theatre] = await Promise.all([
      window.MCPMasterAuth.readProjectProjection('pandora_project_experience_projection', projectId),
      window.MCPMasterAuth.readProjectProjection('pandora_build_theatre_projection', projectId),
    ]);
    item.source = source;
    item.ownerSummary = ownerSummary;
    item.detail = detail;
    item.runtime = runtime;
    item.experience = experience;
    item.theatre = theatre;
    item.error = null;
    item.loadedAt = new Date().toISOString();
  } catch (error) {
    item.ownerSummary = null;
    item.detail = null;
    item.runtime = null;
    item.experience = null;
    item.theatre = null;
    item.error = error?.message || 'Pandora could not open this project workspace.';
  } finally {
    item.loading = false;
    item.mutating = false;
    render();
  }
}

function liveRefreshAllowed() {
  return document.visibilityState !== 'hidden'
    && state.session?.authenticated === true
    && !state.refreshing;
}

async function refreshLiveStatus() {
  if (!liveRefreshAllowed()) return;
  await refresh();
  if (state.route === 'project') await loadProjectWorkspace(routeResourceFromLocation());
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

async function askPandora() {
  const message = state.ask.message.trim();
  if (!message || state.ask.sending) return;
  state.ask.sending = true;
  state.ask.error = null;
  render();
  try {
    const payload = await window.MCPMasterAuth?.invokeFunction?.('pandora-intelligence-chat', {
      message,
      ...(state.ask.threadId ? { threadId: state.ask.threadId } : {}),
      ...(state.ask.projectId ? { projectId: state.ask.projectId } : {}),
      mode: 'auto',
    });
    if (!payload?.threadId || typeof payload?.reply !== 'string') {
      throw new Error('Pandora returned an unreadable response');
    }
    state.session = window.MCPMasterAuth?.session?.() || state.session;
    state.ask.threadId = payload.threadId;
    state.ask.reply = payload.reply;
    state.ask.intent = payload.intent || '';
    state.ask.confidence = Number.isFinite(Number(payload.confidence)) ? Number(payload.confidence) : null;
    state.ask.needsClarification = payload.needsClarification === true;
    state.ask.clarifyingQuestion = payload.clarifyingQuestion || '';
    state.ask.handoff = payload.handoff || null;
    state.ask.message = '';
  } catch (error) {
    state.ask.error = error?.message || 'Pandora is temporarily unavailable.';
  } finally {
    state.ask.sending = false;
    render();
  }
}

async function performWorkspaceMutation(kind) {
  const item = state.projectWorkspace;
  const projectKey = item.runtime?.project?.projectKey;
  const candidateVersionId = item.runtime?.candidate?.versionId;
  if (!projectKey || !candidateVersionId || item.mutating) return;
  item.mutating = true;
  item.confirmAction = null;
  render();
  try {
    if (kind === 'publish') {
      await window.MCPMasterAuth.edgeRequest(
        'pandora-project-runtime',
        ['projects', projectKey, 'publish'],
        {
          method: 'POST',
          body: {
            versionId: candidateVersionId,
            expectedProductionVersionId: item.runtime?.production?.versionId ?? null,
          },
        },
      );
      showToast('Publish started from the exact verified candidate. Pandora will keep Live separate until production verification completes.', 'success');
    } else {
      await window.MCPMasterAuth.edgeRequest(
        'pandora-project-runtime',
        ['projects', projectKey, 'undo'],
        {
          method: 'POST',
          body: {
            expectedVersionId: candidateVersionId,
            idempotencyKey: `web-undo-${crypto.randomUUID()}`,
          },
        },
      );
      showToast('Undo completed against the exact current version.', 'success');
    }
    await loadProjectWorkspace(item.sourceId);
  } catch (error) {
    item.mutating = false;
    showToast(`${error?.message || 'Pandora could not complete that project action.'} Nothing was changed implicitly.`, 'error');
    render();
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
    navigate('needs', { replace: true });
  } catch (error) {
    showToast(`${error.message || 'The approval could not be saved.'} Nothing was changed.`, 'error');
    render();
  }
}

app.addEventListener('input', (event) => {
  const input = event.target.closest('[data-ask-message]');
  if (input) state.ask.message = input.value;
  const projectChange = event.target.closest('[data-project-change-message]');
  if (projectChange) {
    state.projectWorkspace.changeMessage = projectChange.value;
    const submit = projectChange.closest('form')?.querySelector('button[type="submit"]');
    if (submit) submit.disabled = !projectChange.value.trim();
  }
});

app.addEventListener('submit', async (event) => {
  const projectForm = event.target.closest('[data-project-change-form]');
  if (projectForm) {
    event.preventDefault();
    const message = state.projectWorkspace.changeMessage.trim();
    const projectId = state.projectWorkspace.runtime?.project?.id;
    const projectName = state.projectWorkspace.runtime?.project?.name || state.projectWorkspace.ownerSummary?.name || '';
    if (!message || !projectId || state.projectWorkspace.experience?.can_change !== true) return;
    if (state.ask.threadId && state.ask.projectId !== projectId) {
      state.ask.threadId = null;
      state.ask.reply = '';
      state.ask.intent = '';
      state.ask.handoff = null;
    }
    state.ask.projectId = projectId;
    state.ask.projectName = projectName;
    state.ask.message = message;
    state.projectWorkspace.changeMessage = '';
    navigate('ask');
    await askPandora();
    return;
  }
  const form = event.target.closest('[data-ask-form]');
  if (!form) return;
  event.preventDefault();
  if (!state.ask.message.trim()) return;
  if (state.route !== 'ask') navigate('ask');
  await askPandora();
});

app.addEventListener('click', async (event) => {
  const target = event.target.closest('[data-route],[data-action]');
  if (!target) return;
  const route = target.dataset.route;
  if (route) {
    navigate(route);
    return;
  }
  const action = target.dataset.action;
  if (action === 'clear-ask-project') {
    state.ask.projectId = null;
    state.ask.projectName = '';
    state.ask.threadId = null;
    state.ask.reply = '';
    state.ask.intent = '';
    state.ask.handoff = null;
    render();
    return;
  }
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
    if (project) {
      state.projectWorkspace.source = project;
      state.projectWorkspace.sourceId = project.id;
      state.projectWorkspace.view = 'current';
      state.projectWorkspace.confirmAction = null;
      navigate('project', { resource: project.id });
      await loadProjectWorkspace(project.id);
    }
    return;
  }
  if (action === 'workspace-view') {
    const view = target.dataset.view;
    if (['current', 'live', 'history'].includes(view)) {
      state.projectWorkspace.view = view;
      render();
    }
    return;
  }
  if (action === 'prepare-workspace-publish') {
    state.projectWorkspace.confirmAction = 'publish';
    render();
    return;
  }
  if (action === 'prepare-workspace-undo') {
    state.projectWorkspace.confirmAction = 'undo';
    render();
    return;
  }
  if (action === 'cancel-workspace-action') {
    state.projectWorkspace.confirmAction = null;
    render();
    return;
  }
  if (action === 'confirm-workspace-publish') {
    await performWorkspaceMutation('publish');
    return;
  }
  if (action === 'confirm-workspace-undo') {
    await performWorkspaceMutation('undo');
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
    state.ask = {
      message: '', threadId: null, projectId: null, projectName: '', reply: '', intent: '', confidence: null,
      needsClarification: false, clarifyingQuestion: '', handoff: null, sending: false, error: null,
    };
    state.projectWorkspace = {
      sourceId: null, source: null, ownerSummary: null, detail: null, runtime: null,
      experience: null, theatre: null, view: 'current', changeMessage: '', loading: false,
      mutating: false, confirmAction: null, error: null, loadedAt: null,
    };
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
  if (state.route === 'project') void loadProjectWorkspace(routeResourceFromLocation());
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
  void refresh().then(() => {
    if (state.route === 'project') void loadProjectWorkspace(routeResourceFromLocation());
  });
} else {
  state.loading = false;
  state.refreshing = false;
  state.live = false;
  state.error = { code: 'SIGNED_OUT', message: 'Sign in to view protected live information.' };
  render();
}
}
