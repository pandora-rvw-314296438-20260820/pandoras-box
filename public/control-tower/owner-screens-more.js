if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, esc, cleanName, BRAND_MARK } = window.PandorasOwnerData;
const { badge, statusSummary, pendingPlans } = window.PandorasOwnerRuntime;

function connectionRows() {
  if (!state.live) return `<div class="owner-setting-row static"><span class="owner-setting-icon warning">${icons.link}</span><span><strong>Connected services</strong><small>Status unavailable</small></span>${badge('Unavailable', 'warning')}</div>`;
  if (!state.connections.length) return `<div class="owner-setting-row static"><span class="owner-setting-icon">${icons.link}</span><span><strong>Connected services</strong><small>No live connections returned</small></span>${badge('None', 'neutral')}</div>`;
  return state.connections.map((connection) => `<button type="button" class="owner-setting-row" data-action="open-connection" data-key="${esc(`${connection.provider}:${connection.id}`)}"><span class="owner-setting-icon">${icons.link}</span><span><strong>${esc(connection.label || cleanName(connection.provider))}</strong><small>${esc(cleanName(connection.provider))} · ${connection.mutations ? 'Routine changes enabled' : 'Read only'}</small></span>${badge('Connected', 'success')}${icons.arrow}</button>`).join('');
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
  const isHomeActive = state.route === 'home' && state.wizardStep === 0;
  const isSystemsActive = state.route === 'projects';
  const isNeedsYouActive = state.route === 'approvals';
  const isMoreActive = state.route === 'more';
  
  return `<nav class="owner-bottom-nav" aria-label="Primary navigation">
    <button type="button" data-route="home" data-action="reset-wizard" class="${isHomeActive ? 'active' : ''}">
      <span class="owner-nav-icon">${icons.home}</span>
      <span>Home</span>
    </button>
    <button type="button" data-route="projects" class="${isSystemsActive ? 'active' : ''}">
      <span class="owner-nav-icon">${icons.projects}</span>
      <span>Systems</span>
    </button>
    <button type="button" class="owner-central-ask-btn" data-action="open-ask-pandora" aria-label="Ask Pandora">
      <div class="owner-central-circle">
        <img src="${BRAND_MARK}" alt="Ask Pandora" />
      </div>
      <span>Ask Pandora</span>
    </button>
    <button type="button" data-route="approvals" class="${isNeedsYouActive ? 'active' : ''}">
      <span class="owner-nav-icon">
        ${icons.bell}
        <b class="owner-nav-badge">2</b>
      </span>
      <span>Needs You</span>
    </button>
    <button type="button" data-route="more" class="${isMoreActive ? 'active' : ''}">
      <span class="owner-nav-icon">${icons.more}</span>
      <span>More</span>
    </button>
  </nav>`;
}

window.PandorasOwnerScreenMore = Object.freeze({ connectionRows, renderMore, nav });
}
