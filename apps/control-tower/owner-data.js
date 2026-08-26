const BRAND_MARK = 'https://raw.githubusercontent.com/mbanatao/Battle/c3594e4721097714118a3e1a6854e9836410b00a/public/brand/banatao/red-apple-mark-96.png';
const USER_AVATAR = 'https://raw.githubusercontent.com/mbanatao/Battle/c3594e4721097714118a3e1a6854e9836410b00a/public/brand/banatao/owner-mark-avatar.png';
const API_BASE = '/api/operator';
const ROUTES = new Set(['home', 'projects', 'approvals', 'activity', 'more']);
const COMPLETE_STATES = new Set(['complete', 'completed', 'merged', 'released', 'production_verified']);
const ACTIVE_STATES = new Set(['active', 'in-progress', 'in_progress', 'building', 'reviewing', 'testing', 'queued-qualification', 'partial']);

const icons = {
  home: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/></svg>',
  projects: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/><path d="M3 9h18"/></svg>',
  approvals: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="4"/><path d="m8 12 3 3 5-6"/></svg>',
  activity: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l2-6 4 12 2-6h6"/></svg>',
  more: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></svg>',
  check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>',
  alert: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 2.8 19a1.4 1.4 0 0 0 1.2 2h16a1.4 1.4 0 0 0 1.2-2Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>',
  arrow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>',
  clock: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  refresh: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg>',
  link: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.1.1l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1"/><path d="M14 11a5 5 0 0 0-7.1-.1l-2 2A5 5 0 0 0 12 20l1.1-1.1"/></svg>',
  shield: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 4 6v5c0 5 3.3 8.4 8 10 4.7-1.6 8-5 8-10V6Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/></svg>',
  user: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
  palette: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><circle cx="8" cy="10" r="1"/><circle cx="12" cy="7" r="1"/><circle cx="16" cy="10" r="1"/><path d="M14 17c0-1.1.9-2 2-2h1a2 2 0 0 0 0-4"/></svg>',
  close: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg>',
  sparkles: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3Z"/></svg>',
  mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" x2="12" y1="19" y2="22"/></svg>',
  paperclip: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>',
  bell: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>',
  phone: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect width="14" height="20" x="5" y="2" rx="2" ry="2"/><line x1="12" x2="12.01" y1="18" y2="18"/></svg>',
  tablet: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect width="16" height="20" x="4" y="2" rx="2" ry="2"/><line x1="12" x2="12.01" y1="18" y2="18"/></svg>',
  desktop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/></svg>',
  calendar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect width="18" height="18" x="3" y="4" rx="2" ry="2"/><line x1="16" x2="16" y1="2" y2="6"/><line x1="8" x2="8" y1="2" y2="6"/><line x1="3" x2="21" y1="10" y2="10"/></svg>',
  shoppingBag: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><line x1="3" x2="21" y1="6" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>',
  facebook: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg>',
  code: '<svg viewBox="0 0 24 24" aria-hidden="true"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>',
  users: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
  externalLink: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" x2="21" y1="14" y2="3"/></svg>',
  back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 12H5"/><path d="m12 19-7-7 7-7"/></svg>',
};

const state = {
  route: routeFromLocation(),
  projection: null,
  health: null,
  tools: null,
  connections: [],
  plans: [],
  logs: [],
  chain: null,
  metrics: null,
  session: window.MCPMasterAuth?.session?.() || {},
  loading: true,
  refreshing: false,
  live: false,
  error: null,
  dialog: null,
  toast: null,
  theme: localStorage.getItem('pandoras-owner-theme') || 'light',
  wizardStep: 0, // 0: Home, 1: Ask, 2: Understand, 3: Build, 4: Review, 5: Preview
  wizardData: {
    goal: 'Build an online booking system for your aircon technician business.',
    prompt: '',
    previewMode: 'mobile', // 'mobile', 'tablet', 'desktop'
    previewTab: 'home', // 'home', 'bookings', 'services', 'help'
    selectedService: 'Cleaning Service',
    selectedDate: 'May 20, 2025 (Tue)',
    selectedTime: '09:00 AM – 11:00 AM',
    location: '123 Rizal St., Makati City',
    feedbackText: '',
    voiceFeedbackActive: false,
    buildStepIndex: 2, // 0 to 5
  },
};

const app = document.querySelector('#app');
function rerender() { window.PandorasOwnerRender?.(); }
document.body.classList.add('owner-first-mode');
document.documentElement.dataset.ownerTheme = state.theme;

function esc(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[char]);
}

function routeFromLocation() {
  const route = window.location.hash.replace(/^#\/?/, '').split('/')[0];
  return ROUTES.has(route) ? route : 'home';
}

function normalizeStatus(value) {
  return String(value || '').trim().toLowerCase().replaceAll(' ', '_');
}

function isComplete(task) {
  return COMPLETE_STATES.has(normalizeStatus(task?.status));
}

function isActive(task) {
  const value = normalizeStatus(task?.status);
  return ACTIVE_STATES.has(value) && !isComplete(task);
}

function isBlocked(task) {
  const value = normalizeStatus(task?.status);
  return value === 'blocked' || (Array.isArray(task?.blockerIds) && task.blockerIds.length > 0);
}

function cleanName(value) {
  return String(value || '')
    .replace(/^mbanatao\//i, '')
    .replace(/-platform$/i, '')
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function projectName(repository) {
  const value = String(repository || 'Project');
  if (/mcpmaster/i.test(value)) return 'MCPMaster';
  if (/callgate/i.test(value)) return 'CallGate';
  if (/\bbattle\b|batalla/i.test(value)) return 'Battle';
  if (/porknyeta/i.test(value)) return 'Porknyeta';
  if (/realmatch/i.test(value)) return 'RealMatch';
  if (/banatao systems portfolio/i.test(value)) return 'Banatao Systems';
  return cleanName(value);
}

function projectInitials(name) {
  return String(name || 'P').split(/\s+/).map((part) => part[0]).join('').slice(0, 2).toUpperCase();
}

function formatPhase(value) {
  const normalized = normalizeStatus(value);
  const labels = {
    complete: 'Completed', completed: 'Completed', active: 'In progress', in_progress: 'In progress',
    'in-progress': 'In progress', partial: 'In progress', planned: 'Planning', 'not-started': 'Planning',
    not_started: 'Planning', blocked: 'Blocked', testing: 'Testing', reviewing: 'Reviewing',
    queued_qualification: 'Preparing', 'queued-qualification': 'Preparing', released: 'Released',
  };
  return labels[normalized] || cleanName(normalized || 'Status unavailable');
}

function timeAgo(value) {
  const timestamp = Date.parse(value || '');
  if (!Number.isFinite(timestamp)) return 'Time unavailable';
  const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
  if (seconds < 60) return 'Just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 172800) return 'Yesterday';
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(timestamp));
}

function formatExpiry(value) {
  const timestamp = Date.parse(value || '');
  if (!Number.isFinite(timestamp)) return 'Expiry unavailable';
  if (timestamp <= Date.now()) return 'Expired';
  const minutes = Math.max(1, Math.floor((timestamp - Date.now()) / 60000));
  if (minutes < 60) return `Expires in ${minutes} min`;
  return `Expires ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp))}`;
}

function formatTool(tool) {
  const value = String(tool || 'change').split('.').pop().replaceAll('-', ' ').replaceAll('_', ' ');
  const labels = {
    'create issue': 'Create a project task',
    'update issue': 'Update a project task',
    'create pull request': 'Open a proposed change',
    'merge pull request': 'Merge an approved change',
    'write repository api': 'Update a connected repository',
    'enable leaked password protection': 'Turn on stronger password protection',
    'restore project': 'Restore a paused project',
    'pause project': 'Pause a connected project',
  };
  return labels[value] || value.replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function projectForPlan(plan) {
  const args = plan?.args && typeof plan.args === 'object' ? plan.args : {};
  const repository = args.owner && args.repo ? `${args.owner}/${args.repo}` : args.repository || args.target || '';
  if (repository) return projectName(repository);
  const provider = String(plan?.tool || '').split('.')[0];
  return provider ? cleanName(provider) : 'Pandoras-Box';
}

function projectForEvent(event) {
  const serialized = JSON.stringify(event || {}).toLowerCase();
  for (const project of deriveProjects()) {
    if (serialized.includes(project.repository.toLowerCase()) || serialized.includes(project.name.toLowerCase())) return project.name;
  }
  const tool = String(event?.tool || '').split('.')[0];
  return tool ? cleanName(tool) : 'Pandoras-Box';
}

function eventMessage(event) {
  const type = normalizeStatus(event?.eventType || event?.event || 'activity');
  const messages = {
    plan_created: 'A new change was prepared',
    plan_approved: 'An approval was recorded',
    plan_expired: 'A pending approval expired',
    plan_failed: 'A planned change could not continue',
    execution_started: 'Approved work started',
    execution_completed: 'A change finished successfully',
    execution_failed: 'A change could not finish',
    execution_denied: 'A change was safely blocked',
    approval_denied: 'An approval was not accepted',
    reconciliation_completed: 'Project status was refreshed',
    runtime_event: 'A system event was recorded',
  };
  return messages[type] || type.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function eventKind(event) {
  const status = normalizeStatus(event?.status);
  const type = normalizeStatus(event?.eventType || event?.event);
  if (['failed', 'denied', 'blocked'].includes(status) || /failed|denied|blocked/.test(type)) return 'danger';
  if (['pending', 'planned', 'approved', 'executing'].includes(status) || /created|approved|started/.test(type)) return 'warning';
  return 'success';
}

function deriveProjects() {
  const tasks = Array.isArray(state.projection?.tasks) ? state.projection.tasks : [];
  const groups = new Map();
  for (const task of tasks) {
    const repository = String(task.repository || 'Unassigned project');
    if (!groups.has(repository)) groups.set(repository, []);
    groups.get(repository).push(task);
  }
  const observedThrough = state.projection?.observedThrough;
  const pending = state.plans.filter((plan) => normalizeStatus(plan.status) === 'pending_approval');
  return [...groups.entries()].map(([repository, projectTasks]) => {
    const completed = projectTasks.filter(isComplete).length;
    const total = projectTasks.length;
    const blocked = projectTasks.filter(isBlocked);
    const current = projectTasks.find((task) => isBlocked(task))
      || projectTasks.find((task) => task.dependencyReady && !isComplete(task))
      || projectTasks.find((task) => !isComplete(task))
      || projectTasks[projectTasks.length - 1];
    const matchingLogs = state.logs.filter((event) => JSON.stringify(event).toLowerCase().includes(repository.toLowerCase()));
    const latestLog = matchingLogs.sort((a, b) => Date.parse(b.occurredAt || '') - Date.parse(a.occurredAt || ''))[0];
    const name = projectName(repository);
    const pendingApprovals = pending.filter((plan) => projectForPlan(plan) === name).length;
    const progress = total ? Math.round((completed / total) * 100) : null;
    return {
      id: repository.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
      repository,
      name,
      initials: projectInitials(name),
      progress,
      progressType: 'evidence-based',
      phase: current ? formatPhase(current.status) : 'Status unavailable',
      nextMilestone: current?.title || 'No next milestone available',
      lastUpdated: latestLog?.occurredAt || observedThrough || null,
      completed,
      total,
      blockedCount: blocked.length,
      pendingApprovals,
      active: projectTasks.some(isActive),
      needsAttention: blocked.length > 0 || pendingApprovals > 0,
      tasks: projectTasks,
    };
  }).sort((a, b) => {
    if (a.needsAttention !== b.needsAttention) return Number(b.needsAttention) - Number(a.needsAttention);
    if (a.pendingApprovals !== b.pendingApprovals) return b.pendingApprovals - a.pendingApprovals;
    if (a.active !== b.active) return Number(b.active) - Number(a.active);
    return String(b.lastUpdated || '').localeCompare(String(a.lastUpdated || ''));
  });
}

function readiness(candidate) {
  return Boolean(
    candidate.projection
    && candidate.projection.authoritative === true
    && candidate.projection.status === 'current'
    && Number.isFinite(Date.parse(candidate.projection.expiresAt || ''))
    && Date.parse(candidate.projection.expiresAt) > Date.now()
    && candidate.health?.status === 'healthy'
    && candidate.health.protectedRoutesConfigured === true
    && candidate.health.durableLedgerConfigured === true
    && candidate.health.distributedRateLimitConfigured === true
    && Array.isArray(candidate.tools?.tools)
    && Array.isArray(candidate.connections)
    && Array.isArray(candidate.plans)
    && Array.isArray(candidate.logs)
    && candidate.metrics && typeof candidate.metrics === 'object'
    && candidate.chain?.valid === true
    && !candidate.error
  );
}


window.PandorasOwnerData = Object.freeze({
  BRAND_MARK, USER_AVATAR, API_BASE, ROUTES, icons, state, app, rerender, esc, routeFromLocation, normalizeStatus, isComplete, isActive, isBlocked, cleanName, projectName, projectInitials, formatPhase, timeAgo, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage, eventKind, deriveProjects, readiness
});
