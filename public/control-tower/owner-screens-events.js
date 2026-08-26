if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const {
  icons, state, esc, normalizeStatus, cleanName, projectInitials, formatExpiry, formatTool, projectForPlan, timeAgo, eventKind, deriveProjects
} = window.PandorasOwnerData;
const { button, badge, statusSummary, pendingPlans } = window.PandorasOwnerRuntime;
const { activityRow } = window.PandorasOwnerScreenCore;

function planCard(plan) {
  const project = projectForPlan(plan);
  const destructive = normalizeStatus(plan.risk) === 'destructive';
  return `<article class="owner-card owner-approval-card">
    <div class="owner-approval-top"><span class="owner-project-mark">${esc(projectInitials(project))}</span><span><small>${esc(project)}</small><strong>${esc(formatTool(plan.tool))}</strong></span>${badge(destructive ? 'High impact' : 'Approval required', destructive ? 'danger' : 'warning')}</div>
    <p>Review the exact change, its reference, and what approval allows before deciding.</p>
    <div class="owner-approval-footer"><span>${esc(formatExpiry(plan.expiresAt))}</span>${button('Review', { kind: 'primary compact', action: 'review-plan', extra: `data-id="${esc(plan.planId)}"` })}</div>
  </article>`;
}

function renderApprovals() {
  const plans = pendingPlans();
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Owner/admin decisions</span><h1>Approvals</h1><p>Approval records your decision. Execution remains a separate step.</p></div>
    ${!state.live ? `<div class="owner-card owner-empty"><span>${icons.alert}</span><h2>Live approvals unavailable</h2><p>${esc(state.error?.message || 'Protected approval status could not be confirmed.')}</p>${button('Try again', { kind: 'primary', action: 'refresh' })}</div>` : plans.length ? `<div class="owner-approval-list">${plans.map(planCard).join('')}</div>` : `<div class="owner-card owner-empty"><span>${icons.check}</span><h2>All caught up</h2><p>No changes are waiting for your decision.</p></div>`}
  </div>`;
}

function groupLogs() {
  const groups = { Today: [], Yesterday: [], Earlier: [] };
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  for (const event of state.logs) {
    const timestamp = Date.parse(event.occurredAt || '');
    if (!Number.isFinite(timestamp) || timestamp < today - 86400000) groups.Earlier.push(event);
    else if (timestamp < today) groups.Yesterday.push(event);
    else groups.Today.push(event);
  }
  return groups;
}

function renderActivity() {
  const groups = groupLogs();
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Verified history</span><h1>Activity</h1><p>Recent protected events are translated into plain language. Technical details remain available when opened.</p></div>
    ${!state.live ? `<div class="owner-card owner-empty"><span>${icons.activity}</span><h2>Live activity unavailable</h2><p>${esc(state.error?.message || 'The protected audit history could not be confirmed.')}</p>${button('Try again', { kind: 'primary', action: 'refresh' })}</div>` : state.logs.length ? Object.entries(groups).filter(([, events]) => events.length).map(([label, events]) => `<section class="owner-section"><h2 class="owner-group-title">${label}</h2><div class="owner-card owner-list-card">${events.map(activityRow).join('')}</div></section>`).join('') : `<div class="owner-card owner-empty"><span>${icons.activity}</span><h2>No recent activity</h2><p>Verified events will appear here as work moves forward.</p></div>`}
  </div>`;
}

window.PandorasOwnerScreenActivity = Object.freeze({
  planCard, renderApprovals, groupLogs, renderActivity
});
}
