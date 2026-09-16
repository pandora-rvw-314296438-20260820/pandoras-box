const {
  BRAND_MARK, icons, state, app, esc, normalizeStatus, isComplete, isActive, isBlocked, cleanName, projectName, projectInitials, formatPhase, timeAgo, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage, eventKind, deriveProjects
} = window.PandorasOwnerData;
const { button, badge, statusSummary, pendingPlans, attentionCount } = window.PandorasOwnerRuntime;

function sectionHeader(title, actionLabel, route) {
  return `<div class="owner-section-heading"><h2>${esc(title)}</h2>${actionLabel ? `<button type="button" data-route="${esc(route)}">${esc(actionLabel)}</button>` : ''}</div>`;
}

function decisionCard() {
  if (state.loading) {
    return `<section class="owner-card owner-decision owner-skeleton-card" aria-label="Checking approvals"><div class="owner-skeleton wide"></div><div class="owner-skeleton medium"></div><div class="owner-skeleton button"></div></section>`;
  }
  if (!state.live) {
    return `<section class="owner-card owner-decision owner-decision-muted">
      <div class="owner-decision-icon warning">${icons.alert}</div>
      <div class="owner-decision-copy"><span class="owner-kicker">Live information unavailable</span><h1>Your saved project status is still available</h1><p>${esc(state.error?.message || 'Protected live details could not be confirmed.')}</p></div>
      <div class="owner-decision-actions">${button('Try again', { kind: 'primary', action: 'refresh', icon: icons.refresh })}</div>
    </section>`;
  }
  const pending = pendingPlans();
  if (!pending.length) {
    return `<section class="owner-card owner-decision owner-decision-clear">
      <div class="owner-decision-icon success">${icons.check}</div>
      <div class="owner-decision-copy"><span class="owner-kicker">You are all caught up</span><h1>Nothing needs your approval</h1><p>Routine work can continue through its normal checks and safeguards.</p></div>
    </section>`;
  }
  const plan = pending[0];
  const count = pending.length;
  return `<section class="owner-card owner-decision owner-decision-attention">
    <div class="owner-decision-icon warning">${icons.alert}</div>
    <div class="owner-decision-copy">
      <div class="owner-decision-meta">${badge('Needs your approval', 'warning')}<span>${count} ${count === 1 ? 'item' : 'items'}</span></div>
      <h1>${count === 1 ? '1 thing needs your approval' : `${count} things need your approval`}</h1>
      <p><strong>${esc(projectForPlan(plan))}</strong> has a checked change ready. Nothing will run just because you review or approve it.</p>
    </div>
    <div class="owner-decision-actions">
      ${button('Review', { kind: 'primary', action: 'review-plan', extra: `data-id="${esc(plan.planId)}"` })}
      ${button('Later', { kind: 'secondary', action: 'later' })}
    </div>
  </section>`;
}

function overview() {
  const projects = deriveProjects();
  const values = [
    { label: 'Approvals', value: state.live ? pendingPlans().length : '—', route: 'approvals', icon: icons.approvals },
    { label: 'Active projects', value: state.projection ? projects.filter((project) => project.active).length : '—', route: 'projects', icon: icons.projects },
    { label: 'Needs attention', value: attentionCount() ?? '—', route: state.live ? 'activity' : 'home', icon: icons.alert },
  ];
  return `<section class="owner-overview" aria-label="Quick overview">${values.map((item) => `<button type="button" class="owner-stat" data-route="${item.route}"><span class="owner-stat-icon">${item.icon}</span><span class="owner-stat-copy"><span>${esc(item.label)}</span><strong>${esc(item.value)}</strong></span></button>`).join('')}</section>`;
}

function progressMarkup(project) {
  if (project.progress === null) return `<span class="owner-progress-unavailable">Progress unavailable</span>`;
  return `<div class="owner-progress" aria-label="${project.progress}% evidence-based progress"><span style="width:${Math.max(0, Math.min(100, project.progress))}%"></span></div>`;
}

function projectRow(project) {
  const statusKind = project.needsAttention ? 'warning' : project.progress === 100 ? 'success' : 'neutral';
  return `<button type="button" class="owner-project-row" data-action="open-project" data-id="${esc(project.id)}">
    <span class="owner-project-mark">${esc(project.initials)}</span>
    <span class="owner-project-main">
      <span class="owner-project-title"><strong>${esc(project.name)}</strong><b>${project.progress === null ? '—' : `${project.progress}%`}</b></span>
      <span class="owner-project-phase">${badge(project.phase, statusKind)}<span>${project.lastUpdated ? `Updated ${timeAgo(project.lastUpdated)}` : 'Update time unavailable'}</span></span>
      ${progressMarkup(project)}
      <span class="owner-progress-label">Evidence-based progress · ${project.completed} of ${project.total} recorded tasks complete</span>
    </span>
    <span class="owner-row-arrow">${icons.arrow}</span>
  </button>`;
}

function activityRow(event) {
  const kind = eventKind(event);
  return `<button type="button" class="owner-activity-row" data-action="open-activity" data-sequence="${esc(event.sequence ?? '')}">
    <span class="owner-activity-icon ${kind}">${kind === 'success' ? icons.check : icons.alert}</span>
    <span class="owner-activity-copy"><strong>${esc(eventMessage(event))}</strong><span>${esc(projectForEvent(event))}</span></span>
    <time>${esc(timeAgo(event.occurredAt))}</time>
  </button>`;
}

function renderHome() {
  const projects = deriveProjects().slice(0, 3);
  const events = state.logs.slice(0, 3);
  return `<div class="owner-screen owner-home-screen">
    ${decisionCard()}
    ${overview()}
    <section class="owner-section">
      ${sectionHeader('Top projects', 'View all', 'projects')}
      <div class="owner-card owner-list-card">${projects.length ? projects.map(projectRow).join('') : `<div class="owner-empty"><span>${icons.projects}</span><h3>No project status available</h3><p>Projects will appear when the canonical status includes recorded work.</p></div>`}</div>
    </section>
    <section class="owner-section">
      ${sectionHeader('Recent activity', 'View all', 'activity')}
      <div class="owner-card owner-list-card">${state.live ? (events.length ? events.map(activityRow).join('') : `<div class="owner-empty compact"><h3>No recent activity</h3><p>New verified events will appear here.</p></div>`) : `<div class="owner-empty compact"><h3>Live activity unavailable</h3><p>No activity is shown until the protected audit history is confirmed.</p></div>`}</div>
    </section>
  </div>`;
}

function renderProjects() {
  const projects = deriveProjects();
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Your portfolio</span><h1>Projects</h1><p>Progress is calculated only from tasks recorded in the current Pandora status.</p></div>
    <div class="owner-project-grid">${projects.length ? projects.map((project) => `<article class="owner-card owner-project-card">
      <button type="button" class="owner-project-open" data-action="open-project" data-id="${esc(project.id)}">
        <span class="owner-project-card-top"><span class="owner-project-mark large">${esc(project.initials)}</span><span class="owner-project-card-title"><strong>${esc(project.name)}</strong><span>${esc(project.repository)}</span></span><b>${project.progress === null ? '—' : `${project.progress}%`}</b></span>
        ${progressMarkup(project)}
        <span class="owner-progress-label">Evidence-based progress · ${project.completed} of ${project.total} recorded tasks complete</span>
        <span class="owner-project-details"><span><small>Current phase</small><strong>${esc(project.phase)}</strong></span><span><small>Next milestone</small><strong>${esc(project.nextMilestone)}</strong></span></span>
        <span class="owner-project-card-footer"><span>${project.lastUpdated ? `Updated ${timeAgo(project.lastUpdated)}` : 'Update time unavailable'}</span><span>Open project ${icons.arrow}</span></span>
      </button>
    </article>`).join('') : `<div class="owner-card owner-empty"><span>${icons.projects}</span><h2>No projects found</h2><p>The canonical status does not currently contain project tasks.</p></div>`}</div>
  </div>`;
}

window.PandorasOwnerScreenCore = Object.freeze({
  sectionHeader, decisionCard, overview, progressMarkup, projectRow, activityRow, renderHome, renderProjects
});
