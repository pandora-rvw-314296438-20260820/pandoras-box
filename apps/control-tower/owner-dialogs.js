import { ownerScreenCore } from './owner-screens-core.js?v=control-tower-esm-v1-20261015-1';
const { icons, state, esc, normalizeStatus, isComplete, isBlocked, cleanName, timeAgo, formatPhase, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage } = window.PandorasOwnerData;
const { button, badge } = window.PandorasOwnerRuntime;
const { progressMarkup } = ownerScreenCore;

function approvalDialog(plan) {
  const project = projectForPlan(plan);
  const risk = normalizeStatus(plan.risk);
  const impactLabel = risk === 'destructive' ? 'High impact' : 'Approval required';
  const args = plan.args && typeof plan.args === 'object' ? plan.args : {};
  const reference = plan.planId || plan.requestId || 'Unavailable';
  const payloadHash = plan.payloadHash || 'Unavailable';
  return `<div class="owner-dialog-backdrop" data-action="close-dialog">
    <section class="owner-dialog" role="dialog" aria-modal="true" aria-labelledby="owner-dialog-title" data-owner-dialog>
      <header class="owner-dialog-header"><div><span class="owner-kicker">${esc(project)}</span><h2 id="owner-dialog-title">${esc(formatTool(plan.tool))}</h2></div><button type="button" class="owner-icon-button" data-action="close-dialog" aria-label="Close">${icons.close}</button></header>
      <div class="owner-dialog-body">
        <div class="owner-dialog-summary ${risk === 'destructive' ? 'danger' : 'warning'}"><span>${icons.alert}</span><div><strong>${impactLabel}</strong><p>Approval allows this checked plan to become eligible for separate execution. It does not run or guarantee a release.</p></div></div>
        <dl class="owner-detail-list">
          <div><dt>What is changing</dt><dd>${esc(formatTool(plan.tool))}${args.title ? `: ${esc(args.title)}` : ''}</dd></div>
          <div><dt>Risk</dt><dd>${risk === 'destructive' ? 'This plan is marked destructive.' : 'This plan requires owner or admin approval and is not marked destructive.'}</dd></div>
          <div><dt>Can it be reversed?</dt><dd>${typeof plan.reversible === 'boolean' ? (plan.reversible ? 'Marked reversible by the plan.' : 'Marked not reversible by the plan.') : 'The plan did not provide a reversibility statement.'}</dd></div>
          <div><dt>Checks</dt><dd>${state.live && state.chain?.valid ? 'Identity, live control, and activity-history checks are available.' : 'Verification status unavailable. Approval is blocked.'}</dd></div>
          <div><dt>Reference</dt><dd><code>${esc(reference)}</code></dd></div>
          <div><dt>Exact version</dt><dd><code>${esc(payloadHash)}</code></dd></div>
          <div><dt>Expiry</dt><dd>${esc(formatExpiry(plan.expiresAt))}</dd></div>
          <div><dt>After approval</dt><dd>The plan becomes eligible for a separate one-time execution from Advanced controls.</dd></div>
        </dl>
      </div>
      <footer class="owner-dialog-actions">
        ${button('Later', { kind: 'secondary', action: 'close-dialog', initial: true })}
        ${button('Approve', { kind: risk === 'destructive' ? 'danger' : 'primary', action: 'confirm-approve', extra: `data-id="${esc(plan.planId)}"`, disabled: !state.live || state.refreshing })}
      </footer>
    </section>
  </div>`;
}

function projectDialog(project) {
  const tasks = project.tasks || [];
  return `<div class="owner-dialog-backdrop" data-action="close-dialog">
    <section class="owner-dialog owner-dialog-wide" role="dialog" aria-modal="true" aria-labelledby="owner-dialog-title" data-owner-dialog>
      <header class="owner-dialog-header"><div><span class="owner-kicker">${esc(project.repository)}</span><h2 id="owner-dialog-title">${esc(project.name)}</h2></div><button type="button" class="owner-icon-button" data-action="close-dialog" aria-label="Close">${icons.close}</button></header>
      <div class="owner-dialog-body">
        <div class="owner-project-dialog-progress"><div><strong>${project.progress === null ? '—' : `${project.progress}%`}</strong><span>Evidence-based progress</span></div>${progressMarkup(project)}</div>
        <dl class="owner-detail-list">
          <div><dt>Current phase</dt><dd>${esc(project.phase)}</dd></div>
          <div><dt>Next milestone</dt><dd>${esc(project.nextMilestone)}</dd></div>
          <div><dt>Recorded tasks</dt><dd>${project.completed} complete out of ${project.total}</dd></div>
          <div><dt>Needs attention</dt><dd>${project.needsAttention ? `${project.blockedCount} blocked and ${project.pendingApprovals} awaiting approval` : 'No current attention flag in the available status.'}</dd></div>
          <div><dt>Last updated</dt><dd>${project.lastUpdated ? timeAgo(project.lastUpdated) : 'Unavailable'}</dd></div>
        </dl>
        <div class="owner-task-list"><h3>Recorded work</h3>${tasks.map((task) => `<div><span class="owner-task-dot ${isComplete(task) ? 'success' : isBlocked(task) ? 'danger' : 'warning'}"></span><span><strong>${esc(task.title)}</strong><small>${esc(formatPhase(task.status))} · ${esc(task.id)}</small></span></div>`).join('')}</div>
      </div>
      <footer class="owner-dialog-actions">${button('Close', { kind: 'primary', action: 'close-dialog', initial: true })}</footer>
    </section>
  </div>`;
}

function activityDialog(event) {
  const details = event?.details && typeof event.details === 'object' ? event.details : {};
  return `<div class="owner-dialog-backdrop" data-action="close-dialog">
    <section class="owner-dialog" role="dialog" aria-modal="true" aria-labelledby="owner-dialog-title" data-owner-dialog>
      <header class="owner-dialog-header"><div><span class="owner-kicker">${esc(projectForEvent(event))}</span><h2 id="owner-dialog-title">${esc(eventMessage(event))}</h2></div><button type="button" class="owner-icon-button" data-action="close-dialog" aria-label="Close">${icons.close}</button></header>
      <div class="owner-dialog-body"><dl class="owner-detail-list">
        <div><dt>Result</dt><dd>${esc(cleanName(event.status || 'Recorded'))}</dd></div>
        <div><dt>When</dt><dd>${esc(event.occurredAt ? new Date(event.occurredAt).toLocaleString() : 'Unavailable')}</dd></div>
        <div><dt>Action</dt><dd>${esc(formatTool(event.tool || 'System event'))}</dd></div>
        <div><dt>Reference</dt><dd><code>${esc(event.planId || event.requestId || event.sequence || 'Unavailable')}</code></dd></div>
        <div><dt>Details</dt><dd>${esc(details.reason || details.error || details.message || 'No additional plain-language details were provided.')}</dd></div>
      </dl></div>
      <footer class="owner-dialog-actions">${button('Close', { kind: 'primary', action: 'close-dialog', initial: true })}</footer>
    </section>
  </div>`;
}

function connectionDialog(connection) {
  const targets = [...new Set(Object.values(connection.targets || {}).flat())];
  return `<div class="owner-dialog-backdrop" data-action="close-dialog"><section class="owner-dialog" role="dialog" aria-modal="true" aria-labelledby="owner-dialog-title" data-owner-dialog>
    <header class="owner-dialog-header"><div><span class="owner-kicker">Connected service</span><h2 id="owner-dialog-title">${esc(connection.label || cleanName(connection.provider))}</h2></div><button type="button" class="owner-icon-button" data-action="close-dialog" aria-label="Close">${icons.close}</button></header>
    <div class="owner-dialog-body"><dl class="owner-detail-list"><div><dt>Service</dt><dd>${esc(cleanName(connection.provider))}</dd></div><div><dt>Access</dt><dd>${connection.mutations ? 'Routine changes enabled within approved targets.' : 'Read only.'}</dd></div><div><dt>Available targets</dt><dd>${targets.length ? targets.map(esc).join(', ') : 'No targets returned.'}</dd></div><div><dt>Credentials</dt><dd>Credential values are not shown in this interface.</dd></div></dl></div>
    <footer class="owner-dialog-actions">${button('Close', { kind: 'primary', action: 'close-dialog', initial: true })}</footer>
  </section></div>`;
}

function systemDialog() {
  const checks = [
    ['Live service', state.health?.status === 'healthy'],
    ['Protected pages', state.health?.protectedRoutesConfigured === true],
    ['Saved decision history', state.health?.durableLedgerConfigured === true],
    ['Shared safety limits', state.health?.distributedRateLimitConfigured === true],
    ['Activity history', state.chain?.valid === true],
  ];
  return `<div class="owner-dialog-backdrop" data-action="close-dialog"><section class="owner-dialog" role="dialog" aria-modal="true" aria-labelledby="owner-dialog-title" data-owner-dialog>
    <header class="owner-dialog-header"><div><span class="owner-kicker">Current checks</span><h2 id="owner-dialog-title">System status</h2></div><button type="button" class="owner-icon-button" data-action="close-dialog" aria-label="Close">${icons.close}</button></header>
    <div class="owner-dialog-body"><div class="owner-check-list">${checks.map(([label, ok]) => `<div><span class="owner-task-dot ${ok ? 'success' : 'danger'}"></span><strong>${esc(label)}</strong>${badge(ok ? 'Available' : 'Unavailable', ok ? 'success' : 'warning')}</div>`).join('')}</div>${state.error ? `<div class="owner-dialog-summary warning"><span>${icons.alert}</span><div><strong>${esc(state.error.code)}</strong><p>${esc(state.error.message)}</p></div></div>` : ''}</div>
    <footer class="owner-dialog-actions">${button('Refresh', { kind: 'secondary', action: 'refresh' })}${button('Close', { kind: 'primary', action: 'close-dialog', initial: true })}</footer>
  </section></div>`;
}

function dialogMarkup() {
  if (!state.dialog) return '';
  if (state.dialog.kind === 'approval') return approvalDialog(state.dialog.plan);
  if (state.dialog.kind === 'project') return projectDialog(state.dialog.project);
  if (state.dialog.kind === 'activity') return activityDialog(state.dialog.event);
  if (state.dialog.kind === 'connection') return connectionDialog(state.dialog.connection);
  if (state.dialog.kind === 'system') return systemDialog();
  return '';
}

function toastMarkup() {
  if (!state.toast) return '';
  const icon = state.toast.kind === 'error' ? icons.alert : icons.check;
  return `<div class="owner-toast ${state.toast.kind}" role="status" aria-live="polite"><span>${icon}</span><p>${esc(state.toast.message)}</p><button type="button" data-action="close-toast" aria-label="Close notification">${icons.close}</button></div>`;
}

export const ownerDialogs = Object.freeze({
  approvalDialog, projectDialog, activityDialog, connectionDialog, systemDialog, dialogMarkup, toastMarkup
});
