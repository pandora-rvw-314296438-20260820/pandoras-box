if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, esc, timeAgo } = window.PandorasOwnerData;
const { button, badge } = window.PandorasOwnerRuntime;

const INITIAL_THEATRE_STAGES = Object.freeze([
  { label: 'Understanding', stages: ['understanding'] },
  { label: 'Planning', stages: ['designing', 'planning'] },
  { label: 'Building', stages: ['building', 'connecting'] },
  { label: 'Testing', stages: ['checking', 'testing', 'fixing', 'verifying'] },
  { label: 'Preview Ready', stages: ['preparing_preview', 'preview_ready'] },
]);

const EDIT_THEATRE_STAGES = Object.freeze([
  { label: 'Edit Requested', stages: ['edit_requested'] },
  { label: 'Rebuilding', stages: ['rebuilding', 'building', 'connecting'] },
  { label: 'Verifying', stages: ['verifying', 'checking', 'testing', 'fixing'] },
  { label: 'Updated Preview', stages: ['updated_preview', 'preparing_preview', 'preview_ready'] },
]);

const PUBLISH_THEATRE_STAGES = Object.freeze([
  { label: 'Preparing', stages: ['preparing'] },
  { label: 'Deploying', stages: ['publishing', 'deploying'] },
  { label: 'Verifying Live', stages: ['verifying_live'] },
  { label: 'Live', stages: ['live'] },
]);

const STAGE_LABEL_BY_KEY = Object.freeze({
  understanding: 'Understanding',
  designing: 'Planning',
  planning: 'Planning',
  building: 'Building',
  connecting: 'Building',
  checking: 'Testing',
  testing: 'Testing',
  fixing: 'Testing',
  verifying: 'Verifying',
  preparing_preview: 'Preview Ready',
  preview_ready: 'Preview Ready',
  edit_requested: 'Edit Requested',
  rebuilding: 'Rebuilding',
  updated_preview: 'Updated Preview',
  preparing: 'Preparing',
  publishing: 'Deploying',
  deploying: 'Deploying',
  verifying_live: 'Verifying Live',
  live: 'Live',
});

const EDIT_STAGE_KEYS = new Set(['edit_requested', 'rebuilding', 'updated_preview']);
const PUBLISH_STAGE_KEYS = new Set(['preparing', 'publishing', 'deploying', 'verifying_live', 'live']);

function theatreStageKey(item) {
  const theatre = item?.theatre || {};
  return String(theatre.owner_stage || item?.changePhase || '').toLowerCase();
}

function theatreStagesFor(item) {
  const kind = String(item?.mutationKind || '').toLowerCase();
  const stage = theatreStageKey(item);
  if (kind === 'publish' || PUBLISH_STAGE_KEYS.has(stage)) return PUBLISH_THEATRE_STAGES;
  if (kind === 'edit' || EDIT_STAGE_KEYS.has(stage)) return EDIT_THEATRE_STAGES;
  return INITIAL_THEATRE_STAGES;
}

function theatreStageLabel(stage, item) {
  const key = String(stage || '').toLowerCase();
  if (!key) return 'unavailable';
  if (item && key === 'verifying' && theatreStagesFor(item) === INITIAL_THEATRE_STAGES) return 'Testing';
  if (item && (key === 'checking' || key === 'testing' || key === 'fixing') && theatreStagesFor(item) === EDIT_THEATRE_STAGES) return 'Verifying';
  if (STAGE_LABEL_BY_KEY[key]) return STAGE_LABEL_BY_KEY[key];
  return key.replaceAll('_', ' ');
}

window.PandorasOwnerTheatre = Object.freeze({
  INITIAL_THEATRE_STAGES,
  EDIT_THEATRE_STAGES,
  PUBLISH_THEATRE_STAGES,
  STAGE_LABEL_BY_KEY,
  theatreStagesFor,
  theatreStageKey,
  theatreStageLabel,
});

function workspace() {
  return state.projectWorkspace;
}

function safeHttps(value) {
  try {
    const url = new URL(String(value || ''));
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

function compactId(value) {
  const text = String(value || '');
  return text.length > 14 ? `${text.slice(0, 8)}…${text.slice(-4)}` : text || 'Unavailable';
}

function ownerState() {
  const item = workspace();
  const experience = item.experience || {};
  const theatre = item.theatre || {};
  if (experience.safe_failure_code || experience.safe_failure_message || item.mutationPhase === 'problem') {
    return { label: 'Problem', kind: 'danger' };
  }
  if (experience.needs_you === true || theatre.needs_you === true || item.mutationPhase === 'needs-you') {
    return { label: 'Needs You', kind: 'warning' };
  }
  if (String(experience.experience_state || '').toUpperCase() === 'LIVE') {
    return { label: 'Live', kind: 'success' };
  }
  if (item.mutationKind === 'publish' && (item.mutationPhase === 'checking' || item.mutationPhase === 'publishing')) {
    return { label: 'Working', kind: 'neutral' };
  }
  if (experience.can_publish === true && item.runtime?.verification?.publishEligible === true) {
    return { label: 'Ready', kind: 'success' };
  }
  return { label: 'Working', kind: 'neutral' };
}

function exactPreviewUrl() {
  const { runtime, experience } = workspace();
  if (!runtime?.preview || !experience) return null;
  const allowedIds = new Set([
    experience.current_preview_deployment_id,
    experience.candidate_preview_deployment_id,
  ].filter(Boolean));
  if (!allowedIds.has(runtime.preview.id)) return null;
  return safeHttps(runtime.preview.url);
}

function previewIdentity() {
  const item = workspace();
  const preview = exactPreviewUrl();
  const runtimePreview = item.runtime?.preview;
  const projectId = String(item.runtime?.project?.id || '').toLowerCase();
  const versionId = String(runtimePreview?.version_id || item.experience?.candidate_version_id || item.experience?.current_version_id || '').toLowerCase();
  const artifactDigest = String(runtimePreview?.artifact_digest || item.runtime?.candidate?.artifactDigest || '').toLowerCase();
  const visibleVersions = new Set([
    item.experience?.current_version_id,
    item.experience?.candidate_version_id,
  ].filter(Boolean).map((value) => String(value).toLowerCase()));
  if (!preview || !projectId || !versionId || !visibleVersions.has(versionId) || !/^[0-9a-f]{64}$/.test(artifactDigest)) return null;
  return { projectId, versionId, artifactDigest, url: preview };
}

function focusCapablePreviewUrl() {
  const preview = exactPreviewUrl();
  if (!preview) return null;
  const url = new URL(preview);
  const proxyPath = /^\/preview\/[0-9a-f]{64}\/index\.html$/i.test(url.pathname);
  const trustedOrigins = new Set([window.location.origin, 'https://mcpmaster.vercel.app']);
  if (!trustedOrigins.has(url.origin) || !proxyPath) return null;
  url.searchParams.set('focus', '1');
  return url.toString();
}

function embeddedPreviewUrl() {
  return focusCapablePreviewUrl() || exactPreviewUrl();
}

function selectedTargetLabel() {
  const selected = workspace().selectedTarget;
  if (!selected) return '';
  return selected.accessibleName || selected.componentId || selected.semanticId || selected.selector || 'Selected object';
}

function verifiedLiveUrl() {
  const { runtime, experience } = workspace();
  if (!runtime?.production || !experience) return null;
  if (String(experience.experience_state || '').toUpperCase() !== 'LIVE') return null;
  if (!experience.production_deployment_id || runtime.production.id !== experience.production_deployment_id) return null;
  if (!experience.production_version_id || runtime.production.version_id !== experience.production_version_id) return null;
  const domain = runtime.domain;
  if (domain?.verified === true && domain?.domain) return safeHttps(`https://${domain.domain}`);
  return safeHttps(runtime.project?.liveUrl) || safeHttps(runtime.production.url);
}

function buildTheatre() {
  const item = workspace();
  const theatre = item.theatre || {};
  const hasTheatre = Boolean(item.theatre);
  const stage = theatreStageKey(item);
  const stages = theatreStagesFor(item);
  const message = theatre.public_message
    || (item.changing ? 'Pandora is preparing this change.' : 'No active build projection');
  return `<section class="owner-card owner-workspace-theatre ${hasTheatre ? '' : 'owner-workspace-unavailable'}">
    <div class="owner-workspace-theatre-head">
      <div><span class="owner-kicker">Build Theatre</span><h2 data-workspace-theatre-message>${esc(message)}</h2></div>
      <strong data-workspace-theatre-progress hidden></strong>
    </div>
    <div class="owner-theatre-stages" aria-label="Current build stage">
      ${stages.map((entry) => {
        const active = entry.stages.includes(stage);
        return `<div class="owner-theatre-stage ${active ? 'active' : ''}" data-workspace-theatre-stages="${esc(entry.stages.join(','))}"><span></span><small>${entry.label}</small></div>`;
      }).join('')}
    </div>
    <div class="owner-workspace-meta">
      <span>Stage: <strong data-workspace-theatre-current>${esc(theatreStageLabel(stage, item))}</strong></span>
      <span data-workspace-theatre-updated>${theatre.updated_at ? `Updated ${esc(timeAgo(theatre.updated_at))}` : (hasTheatre ? 'Update time unavailable' : 'Waiting for build activity')}</span>
    </div>
    ${!hasTheatre && !item.changing ? '<p>Pandora has not published a member-safe build activity projection for this project yet.</p>' : ''}
  </section>`;
}

function currentView() {
  const item = workspace();
  const { runtime, experience } = item;
  const preview = exactPreviewUrl();
  const embedded = embeddedPreviewUrl();
  const identity = previewIdentity();
  const proxyFocus = Boolean(focusCapablePreviewUrl());
  const focusAvailable = Boolean(identity && experience?.can_focus === true);
  const preparedFocus = Boolean(
    item.selectionMode
      && item.focusPreviewHtml
      && identity
      && item.focusPreviewVersionId === identity.versionId
      && item.focusPreviewArtifactDigest === identity.artifactDigest
  );
  const frameSource = preparedFocus ? 'about:blank' : embedded;
  const versionId = experience?.candidate_version_id || experience?.current_version_id || runtime?.candidate?.versionId;
  const verification = String(experience?.candidate_verification_state || runtime?.verification?.state || 'not checked').replaceAll('_', ' ');
  if (!preview || !embedded) {
    return `<div class="owner-workspace-result">
      <div class="owner-workspace-result-copy">
        <span class="owner-kicker">Current</span>
        <h3>Current result is not previewable yet</h3>
        <p>${esc(experience?.change_summary || experience?.public_message || 'Pandora will show the current result when an exact preview is available.')}</p>
        <dl class="owner-workspace-facts">
          <div><dt>Version</dt><dd>${esc(compactId(versionId))}</dd></div>
          <div><dt>Verification</dt><dd>${esc(verification)}</dd></div>
        </dl>
      </div>
    </div>`;
  }
  const selected = selectedTargetLabel();
  return `<div class="owner-workspace-preview">
    <div class="owner-workspace-preview-toolbar">
      <div>
        <span class="owner-kicker">Current exact preview</span>
        <strong>${esc(compactId(versionId))}</strong>
        <small>${esc(verification)}</small>
      </div>
      <div class="owner-workspace-preview-actions">
        <button type="button" class="owner-button secondary" data-action="toggle-preview-focus"${focusAvailable && !item.changing && !item.focusPreviewLoading ? '' : ' disabled'}>${item.focusPreviewLoading ? 'Preparing focus…' : item.selectionMode ? 'Cancel focus' : item.selectedTarget ? 'Select another' : 'Focus object'}</button>
        <a class="owner-button primary" href="${esc(preview)}" target="_blank" rel="noopener noreferrer">Open full preview</a>
      </div>
    </div>
    <div class="owner-workspace-preview-frame-wrap ${item.selectionMode ? 'is-focusing' : ''}">
      <iframe data-project-preview-frame data-focus-proxy="${proxyFocus ? 'true' : 'false'}" title="Exact project preview" src="${esc(frameSource)}" sandbox="allow-scripts allow-popups allow-modals allow-downloads" referrerpolicy="no-referrer"></iframe>
      ${item.selectionMode ? '<div class="owner-workspace-focus-hint">Choose the exact object you want Pandora to change.</div>' : ''}
    </div>
    ${selected ? `<div class="owner-workspace-selected-target"><span>Focused</span><strong>${esc(selected)}</strong><button type="button" data-action="clear-preview-focus">Clear</button></div>` : ''}
    ${item.focusPreviewError ? `<div class="owner-workspace-focus-unavailable">${esc(item.focusPreviewError)}</div>` : ''}
  </div>`;
}

function liveView() {
  const item = workspace();
  const live = verifiedLiveUrl();
  return `<div class="owner-workspace-result">
    <div class="owner-workspace-result-copy">
      <span class="owner-kicker">Live</span>
      <h3>${live ? 'Verified production result' : 'No verified live version yet'}</h3>
      <p>${live ? 'This destination is shown only because the production deployment matches Pandora’s canonical Live projection.' : 'Pandora will not label a build or production candidate as Live before production verification is complete.'}</p>
      ${live ? `<dl class="owner-workspace-facts"><div><dt>Version</dt><dd>${esc(compactId(item.experience?.production_version_id))}</dd></div><div><dt>Deployment</dt><dd>${esc(compactId(item.experience?.production_deployment_id))}</dd></div></dl>` : ''}
    </div>
    <div class="owner-workspace-result-actions">
      ${live ? `<a class="owner-button primary" href="${esc(live)}" target="_blank" rel="noopener noreferrer">Open live site</a>` : ''}
    </div>
  </div>`;
}

function historyView() {
  const releases = Array.isArray(workspace().detail?.recentReleases) ? workspace().detail.recentReleases : [];
  if (!releases.length) {
    return `<div class="owner-empty compact"><h3>No verified release history available</h3><p>Release evidence will appear here when Pandora records it.</p></div>`;
  }
  return `<div class="owner-workspace-history">${releases.map((release) => {
    const href = safeHttps(release.sourceUrl);
    return `<article>
      <div><strong>${esc(release.title || 'Release')}</strong><span>${esc(release.plainStatus || 'Not checked')}</span></div>
      <div>${badge(release.verified ? 'Verified' : 'Recorded', release.verified ? 'success' : 'neutral')}${href ? `<a href="${esc(href)}" target="_blank" rel="noopener noreferrer">Evidence</a>` : ''}</div>
    </article>`;
  }).join('')}</div>`;
}

function resultPanel() {
  const item = workspace();
  const renderView = item.view === 'live' ? liveView : item.view === 'history' ? historyView : currentView;
  return `<section class="owner-card owner-workspace-panel">
    <div class="owner-workspace-tabs" role="tablist" aria-label="Project versions">
      ${[['current','Current'],['live','Live'],['history','History']].map(([key,label]) => `<button type="button" role="tab" data-action="workspace-view" data-view="${key}" aria-selected="${item.view === key}" class="${item.view === key ? 'active' : ''}">${label}</button>`).join('')}
    </div>
    <div class="owner-workspace-tab-body">${renderView()}</div>
  </section>`;
}

function changePanel() {
  const item = workspace();
  const canChange = item.experience?.can_change === true;
  const selected = selectedTargetLabel();
  const busy = item.changing === true;
  const phase = String(item.changePhase || '').replaceAll('_', ' ');
  const actionLabel = busy ? (phase ? `Pandora is ${phase}…` : 'Pandora is working…') : (selected ? 'Change selected object' : 'Tell Pandora');
  return `<section class="owner-card owner-workspace-change">
    <div><span class="owner-kicker">Tell Pandora</span><h2>${selected ? 'Change this exact object' : 'What should change?'}</h2><p>${canChange ? (selected ? `Focused on ${esc(selected)}. Pandora will bind the request to this exact preview version and artifact.` : 'Describe the result. Pandora will save the change, prepare the exact spec, build it, verify it and replace the preview only when the new version is safe to show.') : 'Pandora has not marked this project safe for a new change yet. You can still inspect the current result.'}</p></div>
    <form data-project-change-form>
      <textarea data-project-change-message rows="3" maxlength="8000" placeholder="Make the checkout simpler, move this button higher, rewrite this heading…"${canChange && !busy ? '' : ' disabled'}>${esc(item.changeMessage)}</textarea>
      <button class="owner-button primary" type="submit" data-workspace-change-submit${canChange && !busy && item.changeMessage.trim() ? '' : ' disabled'}>${esc(actionLabel)}</button>
    </form>
  </section>`;
}

function actionConfirmation() {
  const item = workspace();
  if (!item.confirmAction) return '';
  const publish = item.confirmAction === 'publish';
  return `<section class="owner-card owner-workspace-confirm">
    <div class="owner-decision-icon warning">${publish ? icons.link : icons.refresh}</div>
    <div>
      <span class="owner-kicker">${publish ? 'Publish' : 'Undo'}</span>
      <h3>${publish ? 'Make this verified version live?' : 'Undo the latest current change?'}</h3>
      <p>${publish ? 'Pandora will re-check exact version, preview, verification and production preconditions before moving production.' : 'Pandora will restore only the exact verified parent version. If this would require a production rollback, the runtime will refuse the implicit undo.'}</p>
    </div>
    <div class="owner-workspace-confirm-actions">
      ${button('Cancel', { kind: 'secondary', action: 'cancel-workspace-action' })}
      ${button(publish ? 'Publish verified version' : 'Undo current change', { kind: 'primary', action: publish ? 'confirm-workspace-publish' : 'confirm-workspace-undo', disabled: item.mutating })}
    </div>
  </section>`;
}

function controls() {
  const item = workspace();
  const experience = item.experience || {};
  const candidateId = item.runtime?.candidate?.versionId;
  const canPublish = experience.can_publish === true && item.runtime?.verification?.publishEligible === true && Boolean(candidateId);
  const canUndo = experience.can_undo === true && Boolean(candidateId);
  if (!canPublish && !canUndo) return '';
  return `<section class="owner-workspace-controls" aria-label="Project actions">
    ${canUndo ? button('Undo', { kind: 'secondary', action: 'prepare-workspace-undo', disabled: item.mutating }) : ''}
    ${canPublish ? button('Publish', { kind: 'primary', action: 'prepare-workspace-publish', disabled: item.mutating }) : ''}
  </section>`;
}

function renderProjectWorkspace() {
  const item = workspace();
  if (item.loading) {
    return `<div class="owner-screen"><div class="owner-page-intro"><span class="owner-kicker">Project</span><h1>Opening exact project state…</h1><p>Pandora is reconciling owner, runtime and experience projections.</p></div><section class="owner-card owner-workspace-loading"><div class="owner-skeleton wide"></div><div class="owner-skeleton medium"></div><div class="owner-skeleton button"></div></section></div>`;
  }
  if (item.error || !item.runtime || !item.detail) {
    return `<div class="owner-screen"><div class="owner-page-intro"><span class="owner-kicker">Project</span><h1>Project workspace unavailable</h1><p>${esc(item.error || 'Choose a project from Projects to open its workspace.')}</p></div><section class="owner-card owner-empty"><span>${icons.alert}</span><h2>No project result was changed</h2><p>Pandora could not establish the exact project workspace state.</p>${button('Back to Projects', { kind: 'primary', route: 'projects' })}</section></div>`;
  }
  const stateLabel = ownerState();
  const name = item.runtime.project?.name || item.ownerSummary?.name || item.source?.name || 'Project';
  return `<div class="owner-screen owner-project-workspace">
    <div class="owner-workspace-header">
      <button type="button" class="owner-workspace-back" data-route="${state.mode === 'professional' ? 'build' : 'projects'}">${icons.arrow}<span>${state.mode === 'professional' ? 'Build' : 'Projects'}</span></button>
      <div><span class="owner-kicker">Project workspace</span><h1>${esc(name)}</h1><p>${esc(item.runtime.project?.objective || item.detail.objective || item.ownerSummary?.plainPurpose || 'Project objective unavailable')}</p></div>
      <div class="owner-workspace-state">${badge(stateLabel.label, stateLabel.kind)}${verifiedLiveUrl() ? '<span>Production verified</span>' : ''}</div>
    </div>
    ${actionConfirmation()}
    ${buildTheatre()}
    ${resultPanel()}
    ${controls()}
    ${changePanel()}
  </div>`;
}

window.PandorasOwnerProjectWorkspace = Object.freeze({
  renderProjectWorkspace,
  exactPreviewUrl,
  previewIdentity,
  focusCapablePreviewUrl,
  verifiedLiveUrl,
});
}
