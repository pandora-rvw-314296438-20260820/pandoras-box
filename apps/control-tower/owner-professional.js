if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const {
  icons, state, esc, deriveProjects, cleanName, timeAgo, normalizeStatus,
  formatTool, projectForPlan, projectForEvent, eventMessage
} = window.PandorasOwnerData;
const { button, badge, pendingPlans, statusSummary } = window.PandorasOwnerRuntime;

const PROFESSIONAL_NAV = Object.freeze([
  ['professional-home', 'Home', icons.home],
  ['build', 'Build', icons.projects],
  ['run', 'Run', icons.activity],
  ['connect', 'Connect', icons.link],
  ['memory', 'Memory', icons.clock],
  ['verify', 'Verify', icons.shield],
  ['professional-business', 'Business', icons.business],
  ['library', 'Library', icons.projects],
  ['settings', 'Settings', icons.palette],
]);

function professionalShell(title, subtitle, body, kicker = 'Professional Mode') {
  return `<div class="owner-screen professional-screen">
    <div class="professional-page-intro">
      <div><span class="owner-kicker">${esc(kicker)}</span><h1>${esc(title)}</h1><p>${esc(subtitle)}</p></div>
      <div class="professional-page-state">${badge(state.live ? 'Protected live' : 'Protected status unavailable', state.live ? 'success' : 'warning')}</div>
    </div>
    ${body}
  </div>`;
}

function unavailable(title, message, icon = icons.alert) {
  return `<section class="owner-card professional-unavailable">
    <span class="professional-unavailable-icon">${icon}</span>
    <div><h2>${esc(title)}</h2><p>${esc(message)}</p></div>
  </section>`;
}

function metricCard(label, value, detail = '', kind = 'neutral') {
  return `<article class="owner-card professional-metric">
    <span>${esc(label)}</span>
    <strong>${esc(value)}</strong>
    ${detail ? `<small>${esc(detail)}</small>` : ''}
    <i class="${esc(kind)}" aria-hidden="true"></i>
  </article>`;
}

function projectBuildRow(project) {
  const progress = project.progress === null ? '—' : `${project.progress}%`;
  return `<button type="button" class="professional-build-row" data-action="open-project" data-id="${esc(project.id)}">
    <span class="owner-project-mark">${esc(project.initials)}</span>
    <span class="professional-build-copy">
      <span><strong>${esc(project.name)}</strong><small>${esc(project.repository)}</small></span>
      <span><b>${esc(project.phase)}</b><small>${esc(project.nextMilestone || 'No next milestone available')}</small></span>
    </span>
    <span class="professional-build-progress"><strong>${progress}</strong><small>evidence-based</small></span>
    <span class="owner-row-arrow">${icons.arrow}</span>
  </button>`;
}

function professionalHome() {
  const projects = deriveProjects();
  const blocked = projects.filter((project) => project.blockedCount > 0).length;
  const active = projects.filter((project) => project.active).length;
  const approvals = state.live ? pendingPlans().length : null;
  const recent = state.live ? state.logs.slice(0, 5) : [];

  const body = `
    <section class="professional-metrics-grid" aria-label="Operational overview">
      ${metricCard('Projects', state.projection ? projects.length : '—', 'canonical status')}
      ${metricCard('Active', state.projection ? active : '—', 'recorded active work')}
      ${metricCard('Needs attention', state.projection ? blocked : '—', 'recorded blockers', blocked ? 'warning' : 'neutral')}
      ${metricCard('Approvals', approvals === null ? '—' : approvals, 'durable plans', approvals ? 'warning' : 'neutral')}
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Cross-project operations</span><h2>Current work</h2></div><button type="button" data-route="build">Open Build</button></div>
      <div class="owner-card professional-build-list">${projects.length ? projects.slice(0, 6).map(projectBuildRow).join('') : '<div class="owner-empty compact"><h3>No project status available</h3><p>The canonical status contains no project tasks.</p></div>'}</div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Verification and operations</span><h2>Recent protected events</h2></div><button type="button" data-route="run">Open Run</button></div>
      <div class="owner-card professional-event-list">${state.live ? (recent.length ? recent.map((event) => `<button type="button" data-action="open-activity" data-sequence="${esc(event.sequence ?? '')}"><span>${icons.activity}</span><span><strong>${esc(eventMessage(event))}</strong><small>${esc(projectForEvent(event))} · ${esc(timeAgo(event.occurredAt))}</small></span>${icons.arrow}</button>`).join('') : '<div class="owner-empty compact"><h3>No recent protected events</h3><p>New verified events will appear here.</p></div>') : '<div class="owner-empty compact"><h3>Protected events unavailable</h3><p>No audit activity is shown until the protected live checks are verified.</p></div>'}</div>
    </section>`;
  return professionalShell('Home', 'Cross-project operations, blockers, connections and verification signals from Pandora’s protected sources.', body);
}

function professionalBuild() {
  const projects = deriveProjects();
  const body = `
    <section class="owner-card professional-callout">
      <div><span class="owner-kicker">Intent → artifact → preview → publish</span><h2>Build stays bound to exact project runtime</h2><p>Open a project to see its Build Theatre, current candidate, verified preview, Current / Live / History, Undo and Publish controls.</p></div>
      <div>${button('Ask Pandora', { kind: 'primary', route: 'ask', icon: icons.ask })}</div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Portfolio</span><h2>Projects</h2></div><span>${projects.length} recorded</span></div>
      <div class="owner-card professional-build-list">${projects.length ? projects.map(projectBuildRow).join('') : '<div class="owner-empty"><h3>No projects available</h3><p>Project Build controls appear only when canonical status records project work.</p></div>'}</div>
    </section>`;
  return professionalShell('Build', 'Intent, Build Theatre, lineage, preview, candidate verification and publish readiness.', body);
}

function healthRows() {
  if (!state.live || !state.health) return '';
  const rows = [
    ['Protected routes', state.health.protectedRoutesConfigured === true],
    ['Durable plan ledger', state.health.durableLedgerConfigured === true],
    ['Distributed rate limit', state.health.distributedRateLimitConfigured === true],
    ['Audit chain', state.chain?.valid === true],
  ];
  return rows.map(([label, ok]) => `<div class="professional-health-row"><span>${esc(label)}</span>${badge(ok ? 'Verified' : 'Unavailable', ok ? 'success' : 'warning')}</div>`).join('');
}

function professionalRun() {
  if (!state.live) {
    return professionalShell('Run', 'Deployments, workers, jobs, retries, failures and recovery state.', unavailable('Protected runtime state is unavailable', state.error?.message || 'Pandora could not complete the protected live checks.', icons.activity));
  }
  const events = state.logs.slice(0, 40);
  const body = `
    <section class="professional-two-column">
      <div class="owner-card professional-health-card">
        <div class="professional-card-head"><span class="owner-kicker">Control-plane health</span><h2>${esc(state.health?.status ? cleanName(state.health.status) : 'Status unavailable')}</h2></div>
        <div class="professional-health-list">${healthRows()}</div>
      </div>
      <div class="owner-card professional-runtime-availability">
        <span class="owner-kicker">Runtime inventory</span><h2>Deployment and worker inventory</h2><p>The owner operator feed currently exposes protected health and audit events, but not a complete normalized deployment/worker inventory for this web surface.</p>
        ${badge('Explicitly unavailable', 'neutral')}
      </div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Protected audit stream</span><h2>Recent operations</h2></div><span>${events.length} shown</span></div>
      <div class="owner-card professional-event-list">${events.length ? events.map((event) => `<button type="button" data-action="open-activity" data-sequence="${esc(event.sequence ?? '')}"><span>${icons.activity}</span><span><strong>${esc(eventMessage(event))}</strong><small>${esc(projectForEvent(event))} · ${esc(timeAgo(event.occurredAt))}</small></span>${icons.arrow}</button>`).join('') : '<div class="owner-empty compact"><h3>No recent protected operations</h3><p>Verified events will appear here.</p></div>'}</div>
    </section>`;
  return professionalShell('Run', 'Operational health, protected audit activity, failures and recovery signals.', body);
}

function connectionRow(connection) {
  const key = `${connection.provider}:${connection.id}`;
  const scopeText = Array.isArray(connection.scopes) && connection.scopes.length
    ? connection.scopes.map(cleanName).join(', ')
    : 'Scope detail unavailable';
  return `<button type="button" class="professional-connection-row" data-action="open-connection" data-key="${esc(key)}">
    <span class="professional-provider-icon">${icons.link}</span>
    <span><strong>${esc(connection.label || cleanName(connection.provider))}</strong><small>${esc(cleanName(connection.provider))}</small></span>
    <span><small>${esc(scopeText)}</small><b>${connection.mutations ? 'Governed changes enabled' : 'Read only'}</b></span>
    ${badge('Connected', 'success')}
    ${icons.arrow}
  </button>`;
}

function professionalConnect() {
  const body = !state.live
    ? unavailable('Connection status is unavailable', state.error?.message || 'Pandora could not verify protected connection state.', icons.link)
    : `<section class="owner-card professional-connections">
        ${state.connections.length ? state.connections.map(connectionRow).join('') : '<div class="owner-empty"><h3>No connected services returned</h3><p>This protected session has no verified connection inventory to show.</p></div>'}
      </section>
      <section class="owner-card professional-boundary-note">
        <span>${icons.shield}</span><div><strong>Credentials stay outside the browser</strong><p>This view exposes identities, provider labels, scopes and governance posture only. Tokens, private keys and Vault values are never rendered here.</p></div>
      </section>`;
  return professionalShell('Connect', 'GitHub, Supabase, Vercel, PostHog, model providers and installed connectors without credential exposure.', body);
}

function compactMemoryId(value) {
  const id = String(value || '');
  return id.length > 16 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id || 'Unavailable';
}

function professionalMemory() {
  const memory = state.projection?.evidence?.memory;
  if (!state.live || !memory || memory.ok !== true) {
    return professionalShell(
      'Memory',
      'Canonical Memory health, freshness, approved lineage and conflicts from Pandora’s protected status authority.',
      unavailable(
        'Protected Memory status is unavailable',
        state.error?.message || 'Pandora could not verify the bounded Memory status envelope for this protected session.',
        icons.clock,
      ),
    );
  }

  const approved = Array.isArray(memory.approvedRecordIds) ? memory.approvedRecordIds : [];
  const conflicts = Array.isArray(memory.conflicts) ? memory.conflicts : [];
  const connected = memory.healthStatus === 'projectos-connected';
  const fresh = memory.fresh === true && memory.contextState === 'healthy';
  const body = `
    <section class="professional-metrics-grid" aria-label="Memory authority overview">
      ${metricCard('Connection', connected ? 'Connected' : cleanName(memory.healthStatus || 'Unavailable'), 'Pandora Memory health', connected ? 'success' : 'warning')}
      ${metricCard('Context', cleanName(memory.contextState || 'Unavailable'), fresh ? 'approved canon is current' : 'degraded or stale', fresh ? 'success' : 'warning')}
      ${metricCard('Approved canon', approved.length, 'record IDs in current context')}
      ${metricCard('Conflicts', conflicts.length, conflicts.length ? 'requires resolution' : 'none reported', conflicts.length ? 'warning' : 'success')}
    </section>
    <section class="professional-two-column">
      <div class="owner-card professional-health-card">
        <div class="professional-card-head"><span class="owner-kicker">Memory plane</span><h2>Protected status</h2></div>
        <div class="professional-health-list">
          <div class="professional-health-row"><span>Health</span>${badge(connected ? 'Connected' : cleanName(memory.healthStatus || 'Unavailable'), connected ? 'success' : 'warning')}</div>
          <div class="professional-health-row"><span>Authentication</span>${badge(memory.authentication ? cleanName(memory.authentication) : 'Unavailable', memory.authentication ? 'success' : 'warning')}</div>
          <div class="professional-health-row"><span>Canonical context</span>${badge(fresh ? 'Current' : cleanName(memory.contextState || 'Unavailable'), fresh ? 'success' : 'warning')}</div>
          <div class="professional-health-row"><span>Freshest approved record</span><strong>${esc(memory.freshestRecordAt ? timeAgo(memory.freshestRecordAt) : 'Unavailable')}</strong></div>
        </div>
      </div>
      <div class="owner-card professional-runtime-availability">
        <span class="owner-kicker">Scope</span><h2>Canonical control-plane context</h2>
        <p>This protected status envelope is scoped to <strong>mcpmaster-pandoras-box</strong>. It proves Memory health and approved lineage for the control plane; it is not a fabricated portfolio-wide memory index.</p>
        ${badge(fresh ? 'Fresh approved context' : 'Degraded context', fresh ? 'success' : 'warning')}
      </div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Approved lineage</span><h2>Canonical record IDs</h2></div><span>${approved.length} approved</span></div>
      <div class="owner-card professional-verification-list">
        ${approved.length
          ? approved.slice(0, 25).map((id) => `<div class="professional-verification-row"><span><strong>${esc(compactMemoryId(id))}</strong><small>Approved canonical Memory record</small></span>${badge('Approved', 'success')}</div>`).join('')
          : '<div class="owner-empty compact"><h3>No approved canonical record IDs returned</h3><p>Pandora will not infer Memory contents when the protected status pack does not return approved lineage.</p></div>'}
      </div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Contradictions</span><h2>Memory conflicts</h2></div><span>${conflicts.length} reported</span></div>
      <div class="owner-card professional-verification-list">
        ${conflicts.length
          ? conflicts.map((conflict) => `<div class="professional-verification-row"><span><strong>${esc(conflict.subject || 'Memory conflict')}</strong><small>${esc(conflict.reason || 'Reason unavailable')}</small></span>${badge('Resolve', 'warning')}</div>`).join('')
          : '<div class="owner-empty compact"><h3>No conflicts reported</h3><p>The current bounded canonical context has no unresolved Memory conflicts.</p></div>'}
      </div>
    </section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>Memory contents remain bounded</strong><p>This page does not render raw memory contents, proposed evidence bodies, candidate payloads or promotion internals. Those are not exposed by the canonical owner-safe status contract.</p></div>
    </section>`;
  return professionalShell(
    'Memory',
    'Canonical Memory health, freshness, approved lineage and conflicts from Pandora’s protected status authority.',
    body,
  );
}

function verificationRows() {
  const projection = state.projection;
  const checks = [
    ['Canonical status', projection?.authoritative === true && projection?.status === 'current', projection?.observedThrough || projection?.generatedAt || null],
    ['Protected control plane', state.live === true, null],
    ['Audit chain', state.chain?.valid === true, null],
    ['Protected routes', state.health?.protectedRoutesConfigured === true, null],
    ['Durable ledger', state.health?.durableLedgerConfigured === true, null],
    ['Distributed limiter', state.health?.distributedRateLimitConfigured === true, null],
  ];
  return checks.map(([label, ok, observed]) => `<div class="professional-verification-row">
    <span><strong>${esc(label)}</strong>${observed ? `<small>Observed ${esc(timeAgo(observed))}</small>` : ''}</span>
    ${badge(ok ? 'Verified' : 'Unavailable', ok ? 'success' : 'warning')}
  </div>`).join('');
}

function professionalVerify() {
  const body = `
    <section class="professional-two-column professional-verify-grid">
      <div class="owner-card professional-verification-card">
        <div class="professional-card-head"><span class="owner-kicker">Current protected checks</span><h2>Verification</h2></div>
        <div class="professional-verification-list">${verificationRows()}</div>
      </div>
      <div class="owner-card professional-runtime-availability">
        <span class="owner-kicker">Exact-source evidence</span><h2>Artifact and deployment binding</h2>
        <p>Exact source SHA, artifact SHA-256, independent review and deployment receipts are not exposed as a normalized owner-safe aggregate by the current operator feed.</p>
        ${badge('Source-specific evidence on demand', 'neutral')}
      </div>
    </section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>READY is never LIVE</strong><p>Professional Mode inherits the same project runtime rule as Simple Mode: production is Live only after the exact production version and deployment are verified.</p></div>
    </section>`;
  return professionalShell('Verify', 'Canonical status, audit validity, protected controls and exact-source verification posture.', body);
}

function formatMoneyMicros(value, currency = 'USD') {
  const micros = Number(value);
  if (!Number.isSafeInteger(micros) || micros < 0 || !/^[A-Z]{3}$/.test(String(currency))) return 'Unknown';
  const amount = micros / 1_000_000;
  const precision = amount > 0 && amount < 1 ? 6 : 2;
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency,
      minimumFractionDigits: Math.min(2, precision),
      maximumFractionDigits: precision,
    }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(precision)}`;
  }
}

function businessObjectiveRows(project) {
  const objectives = Array.isArray(project.objectives) ? project.objectives : [];
  if (!objectives.length) return '<div class="owner-empty compact"><h3>No business objective configured</h3><p>Pandora has no durable ProjectSpec business objective for this project.</p></div>';
  return objectives.slice(0, 4).map((objective) => `<div class="professional-verification-row">
    <span>
      <strong>${esc(objective.objective || 'Business objective')}</strong>
      <small>${esc(objective.desiredOutcome || 'Desired outcome not specified')} · metric: ${esc(objective.successMetric || 'not configured')} · baseline: ${esc(objective.baseline || 'unknown')} · target: ${esc(objective.target || 'unknown')}</small>
    </span>
    ${badge(objective.measurementState === 'configured_not_measured' ? 'Not measured' : 'Metric not configured', 'warning')}
  </div>`).join('');
}

function businessEconomicsRows(project) {
  const economics = Array.isArray(project.economics) ? project.economics : [];
  const budgets = Array.isArray(project.budgets) ? project.budgets : [];
  const rows = [];
  for (const item of economics) {
    const internal = item.totalInternalCostMicros != null
      ? `internal cost ${formatMoneyMicros(item.totalInternalCostMicros, item.currency)}`
      : `known internal cost ${formatMoneyMicros(item.knownInternalCostMicros, item.currency)} · ${Number(item.unknownCostCount || 0)} unknown entr${Number(item.unknownCostCount || 0) === 1 ? 'y' : 'ies'}`;
    const charge = item.netCustomerChargeMicros != null
      ? `recorded customer charge ${formatMoneyMicros(item.netCustomerChargeMicros, item.currency)} after ${formatMoneyMicros(item.creditMicros, item.currency)} credits`
      : 'recorded customer charge unknown';
    rows.push(`<div class="professional-verification-row"><span><strong>${esc(item.currency)} economics ledger</strong><small>${esc(internal)} · ${esc(charge)} · ${esc(item.entryCount || 0)} cost entries</small></span>${badge(cleanName(item.confidence || 'unknown'), item.confidence === 'actual' ? 'success' : 'neutral')}</div>`);
  }
  for (const item of budgets) {
    const remaining = item.remainingMicros == null ? 'remaining unknown' : `${formatMoneyMicros(item.remainingMicros, item.currency)} remaining`;
    const committed = item.spentMicros == null || item.reservedMicros == null
      ? 'committed amount unknown'
      : `${formatMoneyMicros(item.spentMicros, item.currency)} spent · ${formatMoneyMicros(item.reservedMicros, item.currency)} reserved`;
    const warning = Number(item.exhaustedCount || 0) > 0 ? 'Exhausted' : Number(item.nearLimitCount || 0) > 0 ? 'Near limit' : 'Within limit';
    rows.push(`<div class="professional-verification-row"><span><strong>${esc(item.currency)} budget</strong><small>${esc(committed)} · hard limit ${esc(formatMoneyMicros(item.hardLimitMicros, item.currency))} · ${esc(remaining)}</small></span>${badge(warning, warning === 'Within limit' ? 'success' : 'warning')}</div>`);
  }
  return rows.length ? rows.join('') : '<div class="owner-empty compact"><h3>No economics ledger data</h3><p>No bounded cost or budget records were returned for this project.</p></div>';
}

function professionalBusiness() {
  const session = window.MCPMasterAuth?.session?.() || state.session || {};
  if (!session.authenticated) {
    return professionalShell(
      'Business',
      'Durable business objectives, measurement readiness, economics and budgets from Pandora’s member-RLS control plane.',
      unavailable('Sign in to view Business truth', 'Business control-plane records are protected and are purged from this owner surface after sign-out.', icons.business),
    );
  }
  const business = state.businessTruth || {};
  if (business.loading && !business.loadedAt) {
    return professionalShell(
      'Business',
      'Durable business objectives, measurement readiness, economics and budgets from Pandora’s member-RLS control plane.',
      '<div class="owner-card owner-workspace-loading"><span class="owner-spinner"></span><h2>Loading bounded Business truth</h2><p>Pandora is reading ProjectSpec objectives, economics entries and budget limits.</p></div>',
    );
  }
  if (business.error) {
    return professionalShell(
      'Business',
      'Durable business objectives, measurement readiness, economics and budgets from Pandora’s member-RLS control plane.',
      unavailable('Business truth is unavailable', business.error.message || 'Pandora could not load the bounded Business projection.', icons.business),
    );
  }
  const projects = Array.isArray(business.projects) ? business.projects : [];
  const objectiveCount = projects.reduce((sum, project) => sum + (Array.isArray(project.objectives) ? project.objectives.length : 0), 0);
  const costTracked = projects.filter((project) => Array.isArray(project.economics) && project.economics.some((item) => Number(item.entryCount || 0) > 0)).length;
  const budgetAlerts = projects.reduce((sum, project) => sum + (Array.isArray(project.budgets)
    ? project.budgets.reduce((inner, item) => inner + Number(item.exhaustedCount || 0) + Number(item.nearLimitCount || 0), 0)
    : 0), 0);
  const body = `
    <section class="professional-metrics-grid" aria-label="Business truth overview">
      ${metricCard('Projects', projects.length, 'with durable business/economics records')}
      ${metricCard('Objectives', objectiveCount, 'ProjectSpec business objectives')}
      ${metricCard('Cost-tracked', costTracked, 'projects with economics ledger entries')}
      ${metricCard('Budget alerts', budgetAlerts, budgetAlerts ? 'near/exhausted limits' : 'none in bounded data', budgetAlerts ? 'warning' : 'success')}
    </section>
    <section class="professional-metrics-grid" aria-label="Commercial outcome measurement">
      ${metricCard('Revenue', 'Not measured', 'no provider outcome evidence in this contract')}
      ${metricCard('Retention', 'Not measured', 'no provider outcome evidence in this contract')}
      ${metricCard('Paid pilots', 'Not measured', 'no live pilot evidence in this contract')}
      ${metricCard('ROI', 'Unknown', 'benefit/outcome evidence is incomplete')}
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Project truth</span><h2>Objectives, economics and budgets</h2></div><span>${projects.length} projects</span></div>
      <div class="professional-project-list">
        ${projects.length ? projects.map((project) => `<article class="owner-card professional-project-card">
          <div class="professional-project-head"><div><span class="owner-kicker">${esc(project.repository || 'Pandora project')}</span><h3>${esc(project.projectName || 'Project')}</h3></div>${badge(project.measurementState === 'configured_not_measured' ? 'Configured · not measured' : 'Measurement not configured', 'warning')}</div>
          <div class="professional-verification-list">${businessObjectiveRows(project)}</div>
          <div class="professional-verification-list">${businessEconomicsRows(project)}</div>
        </article>`).join('') : '<div class="owner-card owner-empty"><h3>No bounded Business records returned</h3><p>Pandora will not convert missing objectives, economics or provider measurements into zero or success.</p></div>'}
      </div>
    </section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>Operational economics are not commercial proof</strong><p>Recorded customer charge, credits, internal cost and budgets come from the durable control-plane ledger. They are not silently relabeled as revenue, margin, ROI, retention, pilot success or customer outcomes. Those remain not measured until their own authoritative evidence is exposed.</p></div>
    </section>`;
  return professionalShell(
    'Business',
    'Durable business objectives, measurement readiness, economics and budgets from Pandora’s member-RLS control plane.',
    body,
  );
}

function formatBytes(value) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes < 0) return 'Size unavailable';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(bytes < 10240 ? 1 : 0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB`;
}

function compactDigest(value) {
  const digest = String(value || '');
  return /^[0-9a-f]{64}$/i.test(digest) ? `${digest.slice(0, 10)}…${digest.slice(-6)}` : 'Digest unavailable';
}

function professionalLibrary() {
  const session = window.MCPMasterAuth?.session?.() || state.session || {};
  if (!session.authenticated) {
    return professionalShell(
      'Library',
      'Immutable artifact metadata and project-version lineage from Pandora’s member-RLS control plane.',
      unavailable('Sign in to view Library', 'Library metadata is protected and is not retained in the owner surface after sign-out.', icons.projects),
    );
  }
  const library = state.library || {};
  if (library.loading && !library.loadedAt) {
    return professionalShell(
      'Library',
      'Immutable artifact metadata and project-version lineage from Pandora’s member-RLS control plane.',
      '<div class="owner-card owner-workspace-loading"><span class="owner-spinner"></span><h2>Loading bounded Library index</h2><p>Pandora is reading member-safe artifact and release metadata.</p></div>',
    );
  }
  if (library.error) {
    return professionalShell(
      'Library',
      'Immutable artifact metadata and project-version lineage from Pandora’s member-RLS control plane.',
      unavailable('Library index is unavailable', library.error.message || 'Pandora could not load the bounded Library index.', icons.projects),
    );
  }
  const artifacts = Array.isArray(library.artifacts) ? library.artifacts : [];
  const releases = Array.isArray(library.releases) ? library.releases : [];
  const body = `
    <section class="professional-metrics-grid" aria-label="Library overview">
      ${metricCard('Artifacts', artifacts.length, 'latest immutable artifact versions')}
      ${metricCard('Project versions', releases.length, 'latest release/version lineage')}
      ${metricCard('Updated', library.generatedAt ? timeAgo(library.generatedAt) : 'Unavailable', 'bounded index refresh')}
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Artifacts</span><h2>Immutable artifact versions</h2></div><span>${artifacts.length} shown</span></div>
      <div class="owner-card professional-verification-list">
        ${artifacts.length ? artifacts.map((artifact) => `<div class="professional-verification-row">
          <span>
            <strong>${esc(artifact.projectName || 'Project')} · ${esc(artifact.logicalKey || 'artifact')}</strong>
            <small>${esc(cleanName(artifact.artifactKind || 'other'))} · v${esc(artifact.version ?? '—')} · ${esc(formatBytes(artifact.byteSize))} · ${esc(artifact.mediaType || 'media type unavailable')} · ${esc(compactDigest(artifact.sha256))} · ${esc(artifact.createdAt ? timeAgo(artifact.createdAt) : 'time unavailable')}</small>
          </span>
          ${badge('Immutable', 'success')}
        </div>`).join('') : '<div class="owner-empty compact"><h3>No artifact versions returned</h3><p>The bounded member-safe index currently contains no artifact versions.</p></div>'}
      </div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Versions & releases</span><h2>Project version lineage</h2></div><span>${releases.length} shown</span></div>
      <div class="owner-card professional-verification-list">
        ${releases.length ? releases.map((release) => `<div class="professional-verification-row">
          <span>
            <strong>${esc(release.projectName || 'Project')} · version ${esc(release.sequenceNo ?? '—')}</strong>
            <small>${esc(cleanName(release.lifecycleStatus || 'unknown'))} · ${esc(cleanName(release.kind || 'preview'))} · artifact ${esc(compactDigest(release.artifactDigest))} · source ${esc(release.sourceCommit ? release.sourceCommit.slice(0, 10) : compactDigest(release.sourceSha256))} · ${esc(release.createdAt ? timeAgo(release.createdAt) : 'time unavailable')}</small>
          </span>
          ${badge(cleanName(release.lifecycleStatus || 'unknown'), ['live','preview_ready','verified'].includes(String(release.lifecycleStatus || '').toLowerCase()) ? 'success' : 'neutral')}
        </div>`).join('') : '<div class="owner-empty compact"><h3>No project versions returned</h3><p>The bounded member-safe index currently contains no project-version lineage.</p></div>'}
      </div>
    </section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>Metadata only</strong><p>Library v1 does not expose storage paths, raw provenance, source payloads, deployment URLs, provider deployment IDs or artifact bytes. Artifact download remains outside this bounded contract.</p></div>
    </section>`;
  return professionalShell(
    'Library',
    'Immutable artifact metadata and project-version lineage from Pandora’s member-RLS control plane.',
    body,
  );
}

function professionalSettings() {
  const session = window.MCPMasterAuth?.session?.() || state.session || {};
  const body = `
    <section class="owner-section">
      <h2 class="owner-group-title">Mode</h2>
      <div class="owner-card professional-mode-settings">
        <button type="button" data-action="switch-mode" data-mode="simple"><span><strong>Simple</strong><small>Outcome-first owner view</small></span>${state.mode === 'simple' ? badge('Current', 'success') : icons.arrow}</button>
        <button type="button" data-action="switch-mode" data-mode="professional"><span><strong>Professional</strong><small>Cross-project operating workspace</small></span>${state.mode === 'professional' ? badge('Current', 'success') : icons.arrow}</button>
        <a href="?advanced=1"><span><strong>Admin</strong><small>Protected technical controls, plans, approvals, audit and operations</small></span>${icons.arrow}</a>
      </div>
    </section>
    <section class="owner-section">
      <h2 class="owner-group-title">Session and appearance</h2>
      <div class="owner-card owner-settings-card">
        <div class="owner-setting-row static"><span class="owner-setting-icon">${icons.user}</span><span><strong>${esc(session.email || 'Signed-in operator')}</strong><small>${esc(session.role ? cleanName(session.role) : 'Session details unavailable')}</small></span></div>
        <button type="button" class="owner-setting-row" data-action="toggle-theme"><span class="owner-setting-icon">${icons.palette}</span><span><strong>Appearance</strong><small>${state.theme === 'dark' ? 'Dark' : 'Light'} mode</small></span>${icons.arrow}</button>
        <button type="button" class="owner-setting-row" data-action="refresh"><span class="owner-setting-icon">${icons.refresh}</span><span><strong>Refresh protected status</strong><small>${esc(statusSummary().label)}</small></span>${icons.arrow}</button>
        <button type="button" class="owner-setting-row owner-signout" data-action="sign-out"><span class="owner-setting-icon">${icons.user}</span><span><strong>Sign out</strong><small>End this operator session</small></span>${icons.arrow}</button>
      </div>
    </section>`;
  return professionalShell('Settings', 'Organization mode, session, appearance, notifications and integration entry points.', body);
}

function professionalNav() {
  return `<nav class="professional-nav" data-professional-nav aria-label="Professional navigation">
    <div class="professional-nav-heading"><span>Professional</span><small>Operator workspace</small></div>
    <div class="professional-nav-items">
      ${PROFESSIONAL_NAV.map(([route,label,icon]) => `<button type="button" data-route="${route}" class="${state.route === route ? 'active' : ''}" aria-current="${state.route === route ? 'page' : 'false'}"><span>${icon}</span><strong>${label}</strong></button>`).join('')}
    </div>
  </nav>`;
}

window.PandorasOwnerProfessional = Object.freeze({
  professionalHome,
  professionalBuild,
  professionalRun,
  professionalConnect,
  professionalMemory,
  professionalVerify,
  professionalBusiness,
  professionalLibrary,
  professionalSettings,
  professionalNav,
});
}
