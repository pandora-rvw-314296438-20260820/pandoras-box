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

function authoritativeData() {
  return state.professionalData || {};
}

function projectRecord(projectId) {
  return (authoritativeData().projects || []).find((project) => project.id === projectId) || null;
}

function authoritativeProjectName(projectId) {
  const project = projectRecord(projectId);
  return project?.name || project?.project_key || (projectId ? `Project ${String(projectId).slice(0, 8)}` : 'Project unavailable');
}

function compactHash(value) {
  const text = String(value || '');
  return text ? (text.length > 16 ? `${text.slice(0, 9)}…${text.slice(-5)}` : text) : 'Unavailable';
}

function safeHttps(value) {
  try {
    const url = new URL(String(value || ''));
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

function sourceError(dataset) {
  return authoritativeData().errors?.[dataset] || null;
}

function dataFreshness() {
  const loadedAt = authoritativeData().loadedAt;
  return loadedAt ? `Updated ${timeAgo(loadedAt)}` : 'Not loaded';
}

function statusKind(value) {
  const normalized = normalizeStatus(value);
  if (['pass','passed','success','succeeded','verified','ready','live','active'].includes(normalized)) return 'success';
  if (['fail','failed','error','blocked','problem','invalid'].includes(normalized)) return 'danger';
  if (['pending','running','working','queued','checking','in_progress'].includes(normalized)) return 'warning';
  return 'neutral';
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
  const data = authoritativeData();
  const deployments = (data.deployments || []).slice(0, 24);
  const production = deployments.filter((item) => normalizeStatus(item.environment) === 'production');
  const verified = deployments.filter((item) => normalizeStatus(item.verification_state) === 'verified');
  const deploymentBody = sourceError('deployments')
    ? unavailable('Deployment inventory is unavailable', sourceError('deployments'), icons.activity)
    : `<section class="owner-card professional-data-list">
        ${deployments.length ? deployments.map((deployment) => {
          const href = safeHttps(deployment.stable_url) || safeHttps(deployment.immutable_url) || safeHttps(deployment.url);
          return `<article class="professional-data-row">
            <span class="professional-provider-icon">${icons.activity}</span>
            <span><strong>${esc(authoritativeProjectName(deployment.project_id))}</strong><small>${esc(cleanName(deployment.provider || 'provider'))} · ${esc(cleanName(deployment.environment || 'environment'))}</small></span>
            <span><strong>${esc(cleanName(deployment.provider_state || deployment.status || 'recorded'))}</strong><small>${esc(deployment.last_provider_check_at ? `Checked ${timeAgo(deployment.last_provider_check_at)}` : `Recorded ${timeAgo(deployment.created_at)}`)}</small></span>
            ${badge(deployment.verification_state ? cleanName(deployment.verification_state) : 'Not verified', statusKind(deployment.verification_state))}
            ${href ? `<a href="${esc(href)}" target="_blank" rel="noopener noreferrer">Open</a>` : '<span></span>'}
          </article>`;
        }).join('') : '<div class="owner-empty compact"><h3>No deployment records</h3><p>The authenticated organization has no member-visible deployment rows.</p></div>'}
      </section>`;
  const body = `
    <section class="professional-two-column">
      <div class="owner-card professional-health-card">
        <div class="professional-card-head"><span class="owner-kicker">Control-plane health</span><h2>${esc(state.health?.status ? cleanName(state.health.status) : 'Status unavailable')}</h2></div>
        <div class="professional-health-list">${healthRows()}</div>
      </div>
      <div class="owner-card professional-runtime-availability">
        <span class="owner-kicker">RLS-backed runtime inventory</span><h2>${deployments.length} recent deployments</h2>
        <p>${production.length} production records · ${verified.length} verification-marked records · ${esc(dataFreshness())}.</p>
        ${badge(sourceError('deployments') ? 'Partial data' : 'Member-scoped', sourceError('deployments') ? 'warning' : 'success')}
      </div>
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Deployments</span><h2>Recent runtime records</h2></div><span>${esc(dataFreshness())}</span></div>
      ${deploymentBody}
    </section>
    <section class="owner-section">
      <div class="professional-section-head"><div><span class="owner-kicker">Protected audit stream</span><h2>Recent operations</h2></div><span>${events.length} shown</span></div>
      <div class="owner-card professional-event-list">${events.length ? events.map((event) => `<button type="button" data-action="open-activity" data-sequence="${esc(event.sequence ?? '')}"><span>${icons.activity}</span><span><strong>${esc(eventMessage(event))}</strong><small>${esc(projectForEvent(event))} · ${esc(timeAgo(event.occurredAt))}</small></span>${icons.arrow}</button>`).join('') : '<div class="owner-empty compact"><h3>No recent protected operations</h3><p>Verified events will appear here.</p></div>'}</div>
    </section>`;
  return professionalShell('Run', 'Operational health, RLS-backed deployments, protected audit activity, failures and recovery signals.', body);
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

function professionalMemory() {
  return professionalShell(
    'Memory',
    'Project context, decisions, learned patterns, evidence candidates, promotion state, health and lineage.',
    unavailable(
      'Dedicated Memory data is not bridged into this web view yet',
      'Pandora will not synthesize project memories or evidence promotion state from unrelated operator logs. This page stays explicit until the dedicated Memory plane has a bounded owner-safe web contract.',
      icons.clock,
    ),
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
  const data = authoritativeData();
  const runs = (data.verificationRuns || []).slice(0, 20);
  const checks = (data.verificationChecks || []).slice(0, 30);
  const evidence = (data.projectosEvidence || []).filter((item) => !item.invalidated_at).slice(0, 20);
  const passedChecks = checks.filter((item) => ['pass','passed','success','verified'].includes(normalizeStatus(item.status))).length;
  const failedChecks = checks.filter((item) => ['fail','failed','error','blocked'].includes(normalizeStatus(item.status))).length;
  const sourceBound = runs.filter((item) => item.source_digest && item.artifact_digest).length;

  const runRows = sourceError('verification_runs')
    ? unavailable('Verification runs are unavailable', sourceError('verification_runs'), icons.shield)
    : `<section class="owner-card professional-data-list">${runs.length ? runs.map((run) => `<article class="professional-data-row professional-verification-data-row">
        <span class="professional-provider-icon">${icons.shield}</span>
        <span><strong>${esc(authoritativeProjectName(run.project_id))}</strong><small>${esc(cleanName(run.target_environment || 'environment'))} · ${esc(run.required_check_profile || 'default profile')}</small></span>
        <span><strong>${esc(compactHash(run.source_commit || run.source_digest))}</strong><small>Artifact ${esc(compactHash(run.artifact_digest))}</small></span>
        ${badge(cleanName(run.status || 'recorded'), statusKind(run.status))}
        <span class="professional-data-time">${esc(timeAgo(run.completed_at || run.created_at))}</span>
      </article>`).join('') : '<div class="owner-empty compact"><h3>No verification runs</h3><p>No member-visible verification run is recorded for this organization.</p></div>'}</section>`;

  const checkRows = sourceError('verification_checks')
    ? unavailable('Verification checks are unavailable', sourceError('verification_checks'), icons.shield)
    : `<section class="owner-card professional-data-list">${checks.length ? checks.map((check) => `<article class="professional-data-row professional-check-row">
        <span class="professional-provider-icon">${icons.check}</span>
        <span><strong>${esc(cleanName(check.check_key || 'verification check'))}</strong><small>${esc(authoritativeProjectName(check.project_id))}</small></span>
        <span><strong>${esc(check.summary || 'No summary recorded')}</strong><small>${esc(check.failure_class ? `Failure class: ${cleanName(check.failure_class)}` : 'No failure class')}</small></span>
        ${badge(cleanName(check.status || 'recorded'), statusKind(check.status))}
        <span class="professional-data-time">${esc(timeAgo(check.completed_at || check.created_at))}</span>
      </article>`).join('') : '<div class="owner-empty compact"><h3>No verification checks</h3><p>No member-visible verification checks are recorded.</p></div>'}</section>`;

  const evidenceRows = sourceError('projectos_evidence')
    ? unavailable('ProjectOS evidence is unavailable', sourceError('projectos_evidence'), icons.shield)
    : `<section class="owner-card professional-data-list">${evidence.length ? evidence.map((item) => {
        const href = safeHttps(item.source_url);
        return `<article class="professional-data-row">
          <span class="professional-provider-icon">${icons.link}</span>
          <span><strong>${esc(cleanName(item.evidence_type || 'evidence'))}</strong><small>${esc(authoritativeProjectName(item.project_id))}</small></span>
          <span><strong>${esc(cleanName(item.provider || 'provider'))}</strong><small>${esc(item.head_sha ? compactHash(item.head_sha) : item.external_id || 'No external identity')}</small></span>
          ${badge(cleanName(item.verdict || item.status || 'recorded'), statusKind(item.verdict || item.status))}
          ${href ? `<a href="${esc(href)}" target="_blank" rel="noopener noreferrer">Evidence</a>` : '<span></span>'}
        </article>`;
      }).join('') : '<div class="owner-empty compact"><h3>No active ProjectOS evidence</h3><p>No non-invalidated member-visible evidence is recorded.</p></div>'}</section>`;

  const body = `
    <section class="professional-metrics-grid" aria-label="Verification evidence overview">
      ${metricCard('Runs', runs.length, 'recent member-visible')}
      ${metricCard('Passed checks', passedChecks, 'recent check window')}
      ${metricCard('Failed checks', failedChecks, 'recent check window', failedChecks ? 'warning' : 'neutral')}
      ${metricCard('Source + artifact bound', sourceBound, 'recent verification runs')}
    </section>
    <section class="professional-two-column professional-verify-grid">
      <div class="owner-card professional-verification-card">
        <div class="professional-card-head"><span class="owner-kicker">Control-plane checks</span><h2>Verification posture</h2></div>
        <div class="professional-verification-list">${verificationRows()}</div>
      </div>
      <div class="owner-card professional-runtime-availability">
        <span class="owner-kicker">Authoritative evidence</span><h2>Exact-source verification is member-readable</h2>
        <p>Source and artifact digests come directly from RLS-protected verification rows. Raw storage paths, credentials and unredacted provider payloads are not exposed.</p>
        ${badge(data.error ? 'Partial data' : 'RLS member-scoped', data.error ? 'warning' : 'success')}
      </div>
    </section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Verification runs</span><h2>Recent exact-source runs</h2></div><span>${esc(dataFreshness())}</span></div>${runRows}</section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Checks</span><h2>Recent verification checks</h2></div><span>${checks.length} shown</span></div>${checkRows}</section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">ProjectOS evidence</span><h2>Source-bound evidence</h2></div><span>${evidence.length} active</span></div>${evidenceRows}</section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>READY is never LIVE</strong><p>Professional Mode inherits the same project runtime rule as Simple Mode: production is Live only after the exact production version and deployment are verified.</p></div>
    </section>`;
  return professionalShell('Verify', 'Canonical status, audit validity, exact-source verification runs, checks and member-scoped evidence.', body);
}

function professionalBusiness() {
  const data = authoritativeData();
  const objectives = (data.businessObjectives || []).slice(0, 40);
  const specs = (data.projectSpecs || []).filter((spec) => !spec.superseded_at).slice(0, 20);

  const objectiveRows = sourceError('business_objectives')
    ? unavailable('Business objectives are unavailable', sourceError('business_objectives'), icons.business)
    : `<section class="owner-card professional-business-objectives">${objectives.length ? objectives.map((item) => `<article>
        <div><span class="owner-kicker">${esc(authoritativeProjectName(item.project_id))}</span><h3>${esc(item.objective || 'Business objective')}</h3><p>${esc(item.desired_outcome || 'No desired outcome recorded')}</p></div>
        <dl>
          <div><dt>Success metric</dt><dd>${esc(item.success_metric || 'Not specified')}</dd></div>
          <div><dt>Baseline</dt><dd>${esc(item.baseline || 'Not recorded')}</dd></div>
          <div><dt>Target</dt><dd>${esc(item.target || 'Not recorded')}</dd></div>
        </dl>
      </article>`).join('') : '<div class="owner-empty compact"><h3>No business objectives recorded</h3><p>No member-visible objective rows exist for this organization.</p></div>'}</section>`;

  const specRows = sourceError('project_specs')
    ? ''
    : specs.map((spec) => `<article class="owner-card professional-business-spec">
        <span class="owner-kicker">${esc(authoritativeProjectName(spec.project_id))} · Spec v${esc(spec.version)}</span>
        <h3>${esc(spec.business_summary || cleanName(spec.project_type || 'Project specification'))}</h3>
        <p>${esc(spec.target_user_summary || 'Target-user summary not recorded')}</p>
        <div>${badge(cleanName(spec.status || 'recorded'), statusKind(spec.status))}<span>SHA ${esc(compactHash(spec.content_sha256))}</span></div>
      </article>`).join('');

  const body = `
    <section class="professional-metrics-grid">
      ${metricCard('Objectives', objectives.length, 'member-visible records')}
      ${metricCard('Active specs', specs.length, 'not superseded')}
      ${metricCard('Measured targets', objectives.filter((item) => item.success_metric && item.target).length, 'defined, not measured')}
      ${metricCard('Revenue data', '—', 'not connected')}
    </section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Defined commercial intent</span><h2>Business objectives</h2></div><span>${esc(dataFreshness())}</span></div>${objectiveRows}</section>
    ${specRows ? `<section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Current specifications</span><h2>Business context</h2></div><span>${specs.length} active</span></div><div class="professional-business-spec-grid">${specRows}</div></section>` : ''}
    <section class="owner-card professional-boundary-note">
      <span>${icons.business}</span><div><strong>Commercial outcomes remain source-bound</strong><p>Pandora is showing recorded objectives and specification context only. Revenue, cost, retention, adoption, ROI and realized customer outcomes remain unavailable until authoritative commercial sources are connected.</p></div>
    </section>`;
  return professionalShell('Business', 'Recorded objectives and business specification context from member-scoped first-party data.', body);
}

function professionalLibrary() {
  const data = authoritativeData();
  const artifacts = (data.artifacts || []).slice(0, 60);
  const versions = data.artifactVersions || [];
  const latestVersion = (artifactId) => versions
    .filter((version) => version.artifact_id === artifactId)
    .sort((a, b) => Number(b.version || 0) - Number(a.version || 0))[0] || null;

  const rows = sourceError('artifacts') || sourceError('artifact_versions')
    ? unavailable('Artifact Library is partially unavailable', sourceError('artifacts') || sourceError('artifact_versions'), icons.projects)
    : `<section class="owner-card professional-data-list professional-library-list">${artifacts.length ? artifacts.map((artifact) => {
        const version = latestVersion(artifact.id);
        const bytes = Number(version?.byte_size);
        const size = Number.isFinite(bytes)
          ? bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : bytes >= 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${bytes} B`
          : 'Size unavailable';
        return `<article class="professional-data-row professional-library-row">
          <span class="professional-provider-icon">${icons.projects}</span>
          <span><strong>${esc(artifact.logical_key || 'Artifact')}</strong><small>${esc(authoritativeProjectName(artifact.project_id))}</small></span>
          <span><strong>${esc(cleanName(artifact.artifact_kind || 'artifact'))}</strong><small>${version ? `v${esc(version.version)} · ${esc(size)} · ${esc(version.media_type || 'media type unavailable')}` : 'No version row loaded'}</small></span>
          ${badge(version ? 'Versioned' : 'Recorded', version ? 'success' : 'neutral')}
          <span class="professional-data-hash">${esc(version?.content_sha256 ? compactHash(version.content_sha256) : 'No digest')}</span>
        </article>`;
      }).join('') : '<div class="owner-empty compact"><h3>No artifacts recorded</h3><p>No member-visible artifact metadata exists for this organization.</p></div>'}</section>`;

  const body = `
    <section class="professional-metrics-grid">
      ${metricCard('Artifacts', artifacts.length, 'recent metadata')}
      ${metricCard('Versions', versions.length, 'recent version metadata')}
      ${metricCard('Verification evidence', (data.verificationEvidence || []).length, 'recent metadata')}
      ${metricCard('Storage secrets', '0', 'never exposed')}
    </section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Artifact metadata</span><h2>Library</h2></div><span>${esc(dataFreshness())}</span></div>${rows}</section>
    <section class="owner-card professional-boundary-note">
      <span>${icons.shield}</span><div><strong>Metadata without storage authority</strong><p>Library shows logical artifact identity, kind, version, byte size, media type and SHA-256 only. Storage buckets, paths, provenance payloads and credentials stay outside this owner surface.</p></div>
    </section>`;
  return professionalShell('Library', 'Member-scoped artifact metadata, versions, digests and verification evidence without storage credentials.', body);
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
