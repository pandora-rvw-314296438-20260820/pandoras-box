if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, esc, cleanName } = window.PandorasOwnerData;
const { badge, statusSummary, pendingPlans } = window.PandorasOwnerRuntime;

function connectionRows() {
  if (!state.live) return `<div class="owner-setting-row static"><span class="owner-setting-icon warning">${icons.link}</span><span><strong>Connected services</strong><small>Status unavailable</small></span>${badge('Unavailable', 'warning')}</div>`;
  if (!state.connections.length) return `<div class="owner-setting-row static"><span class="owner-setting-icon">${icons.link}</span><span><strong>Connected services</strong><small>No live connections returned</small></span>${badge('None', 'neutral')}</div>`;
  return state.connections.map((connection) => {
    const connected = connection.state === 'ready' && connection.plainStatus === 'Connected';
    const status = connected ? 'Connected' : (connection.plainStatus || 'Needs attention');
    const tone = connected ? 'success' : status === 'Needs permission' ? 'neutral' : 'warning';
    const access = connection.canChange === true ? 'Changes require approval' : 'Read only';
    return `<button type="button" class="owner-setting-row" data-action="open-connection" data-key="${esc(`${connection.provider}:${connection.id}`)}"><span class="owner-setting-icon">${icons.link}</span><span><strong>${esc(connection.label || cleanName(connection.provider))}</strong><small>${esc(cleanName(connection.provider))} · ${esc(status)} · ${access}</small></span>${badge(status, tone)}${icons.arrow}</button>`;
  }).join('');
}

function renderMore() {
  const session = window.MCPMasterAuth?.session?.() || state.session || {};
  const themeLabel = state.theme === 'dark' ? 'Dark' : 'Light';
  const chainLabel = state.chain?.valid === true ? 'Verified' : 'Unavailable';
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Account and controls</span><h1>More</h1><p>Connected services, safety status, appearance, and advanced operator tools.</p></div>
    <section class="owner-section">
      <h2 class="owner-group-title">Account</h2>
      <div class="owner-card owner-settings-card">
        <div class="owner-setting-row static"><span class="owner-setting-icon">${icons.user}</span><span><strong>${esc(session.email || 'Signed-in operator')}</strong><small>${esc(session.role ? cleanName(session.role) : 'Session details unavailable')}</small></span></div>
        <button type="button" class="owner-setting-row owner-signout" data-action="sign-out"><span class="owner-setting-icon">${icons.user}</span><span><strong>Sign out</strong><small>End this operator session</small></span>${icons.arrow}</button>
      </div>
    </section>
    <section class="owner-section">
      <h2 class="owner-group-title">Connected services</h2>
      <div class="owner-card owner-settings-card">${connectionRows()}</div>
    </section>
    <section class="owner-section">
      <h2 class="owner-group-title">System</h2>
      <div class="owner-card owner-settings-card">
        <button type="button" class="owner-setting-row" data-action="open-system-status"><span class="owner-setting-icon">${icons.shield}</span><span><strong>System status</strong><small>${esc(statusSummary().label)} · Activity history ${chainLabel.toLowerCase()}</small></span>${badge(state.live ? 'Live' : 'Unavailable', state.live ? 'success' : 'warning')}${icons.arrow}</button>
        <button type="button" class="owner-setting-row" data-action="toggle-theme"><span class="owner-setting-icon">${icons.palette}</span><span><strong>Appearance</strong><small>${themeLabel} mode</small></span>${icons.arrow}</button>
        <a class="owner-setting-row" href="?advanced=1"><span class="owner-setting-icon">${icons.more}</span><span><strong>Advanced controls</strong><small>Open technical tools and one-time execution controls</small></span>${icons.arrow}</a>
        <button type="button" class="owner-setting-row" data-action="refresh"><span class="owner-setting-icon">${icons.refresh}</span><span><strong>Refresh status</strong><small>Check connected services again</small></span>${icons.arrow}</button>
      </div>
    </section>
  </div>`;
}

function nav() {
  const items = [
    ['home', 'Home', icons.home], ['projects', 'Projects', icons.projects],
    ['approvals', 'Approvals', icons.approvals], ['activity', 'Activity', icons.activity], ['more', 'More', icons.more],
  ];
  const approvalCount = state.live ? pendingPlans().length : 0;
  return `<nav class="owner-bottom-nav" aria-label="Primary navigation">${items.map(([route, label, icon]) => `<button type="button" data-route="${route}" class="${state.route === route ? 'active' : ''}" aria-current="${state.route === route ? 'page' : 'false'}"><span class="owner-nav-icon">${icon}${route === 'approvals' && approvalCount ? `<b>${approvalCount > 99 ? '99+' : approvalCount}</b>` : ''}</span><span>${label}</span></button>`).join('')}</nav>`;
}

window.PandorasOwnerScreenMore = Object.freeze({ connectionRows, renderMore, nav });
}
