if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { icons, state, esc, timeAgo } = window.PandorasOwnerData;
const { button, badge } = window.PandorasOwnerRuntime;

const THEATRE_STAGES = Object.freeze([
  { label: 'Understanding', stages: ['understanding'] },
  { label: 'Designing', stages: ['designing'] },
  { label: 'Building', stages: ['building', 'connecting'] },
  { label: 'Checking', stages: ['checking', 'fixing'] },
  { label: 'Preview', stages: ['preparing_preview', 'preview_ready'] },
  { label: 'Publishing', stages: ['publishing'] },
  { label: 'Live', stages: ['live'] },
]);

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
  if (item.mutationKind === 'publish' && item.mutationPhase === 'checking') {
    return { label: 'Checking', kind: 'neutral' };
  }
  if (item.mutationKind === 'publish' && item.mutationPhase === 'publishing') {
    return { label: 'Publishing', kind: 'neutral' };
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
  const theatre = item.theatre;
  if (!theatre) {
    return `<section class="owner-card owner-workspace-theatre owner-workspace-unavailable">
      <div><span class="owner-kicker">Build Theatre</span><h2>No active build projection</h2><p>Pandora has not published a member-safe build activity projection for this project yet.</p></div>
    </section>`;
  }
  const stage = String(theatre.owner_stage || '').toLowerCase();
  const progress = Number(theatre.progress_percent);
  return `<section class="owner-card owner-workspace-theatre">
    <div class="owner-workspace-theatre-head">
      <div><span class="owner-kicker">Build Theatre</span><h2>${esc(theatre.public_message || 'Pandora is working on this project.')}</h2></div>
      ${Number.isFinite(progress) ? `<strong aria-label="${progress}% projected build activity">${Math.max(0, Math.min(100, progress))}%</strong>` : ''}
    </div>
    <div class="owner-theatre-stages" aria-label="Current build stage">
      ${THEATRE_STAGES.map((entry) => {
        const active = entry.stages.includes(stage);
        return `<div class="owner-theatre-stage ${active ? 'active' : ''}"><span></span><small>${entry.label}</small></div>`;
      }).join('')}
    </div>
    <div class="owner-workspace-meta">
      <span>Stage: <strong>${esc(stage ? stage.replaceAll('_', ' ') : 'unavailable')}</strong></span>
      <span>${theatre.updated_at ? `Updated ${esc(timeAgo(theatre.updated_at))}` : 'Update time unavailable'}</span>
    </div>
  </section>`;
}

function currentView() {
  const item = workspace();
  const { runtime, experience } = item;
  const preview = exactPreviewUrl();
  const versionId = item.previewVersionId || experience?.current_version_id || experience?.candidate_version_id || runtime?.candidate?.versionId;
  const verification = String(experience?.candidate_verification_state || runtime?.verification?.state || 'not checked').replaceAll('_', ' ');
  const exactEmbedded = Boolean(item.previewBundle && item.previewVersionId === versionId);
  const canFocus = exactEmbedded && experience?.can_focus === true && experience?.can_change === true && !item.mutating;
  const selected = item.focusToken && item.previewSelection;
  return `<div class="owner-workspace-current">
    <div class="owner-workspace-result">
      <div class="owner-workspace-result-copy">
        <span class="owner-kicker">Current</span>
        <h3>${exactEmbedded ? 'Your exact current result' : preview ? 'Your latest exact preview is ready' : 'Current result is not previewable yet'}</h3>
        <p>${esc(experience?.change_summary || experience?.public_message || 'Pandora will show the current result when an exact preview is available.')}</p>
        <dl class="owner-workspace-facts">
          <div><dt>Version</dt><dd>${esc(compactId(versionId))}</dd></div>
          <div><dt>Verification</dt><dd>${esc(verification)}</dd></div>
        </dl>
      </div>
      <div class="owner-workspace-result-actions">
        ${exactEmbedded ? `<button class="owner-button ${item.selectionMode ? 'primary' : 'secondary'}" type="button" data-action="toggle-preview-focus"${canFocus ? '' : ' disabled'}>${item.selectionMode ? 'Select an object' : 'Focus object'}</button>` : ''}
        ${preview ? `<a class="owner-button secondary" href="${esc(preview)}" target="_blank" rel="noopener noreferrer">Open preview</a>` : ''}
      </div>
    </div>
    ${selected ? `<div class="owner-focus-chip"><div><span class="owner-kicker">Focused object</span><strong>${esc(item.previewSelection.accessibleName || item.previewSelection.text || item.previewSelection.componentId || 'Selected object')}</strong><small>${esc(item.previewSelection.tag || 'element')} · exact version ${esc(compactId(item.previewVersionId))}</small></div><button type="button" data-action="clear-preview-focus" aria-label="Clear focused object">×</button></div>` : ''}
    ${exactEmbedded ? '<div class="owner-preview-shell"><div class="owner-preview-stage" data-owner-preview-host></div></div>' : ''}
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
  return `<section class="owner-card owner-workspace-change">
    <div><span class="owner-kicker">Tell Pandora</span><h2>What should change?</h2><p>${canChange ? (item.focusToken ? 'Describe what should change on the focused object. Pandora will bind the request to this exact version and rebuild safely.' : 'Describe the result, or focus an object in the exact preview first. Pandora will prepare governed work without replacing the current version until verification passes.') : 'Pandora has not marked this project safe for a new change yet. You can still inspect the current result.'}</p></div>
    ${item.changeReply ? `<div class="owner-workspace-change-reply">${esc(item.changeReply)}</div>` : ''}
    <form data-project-change-form>
      <textarea data-project-change-message rows="3" maxlength="8000" placeholder="Make the checkout simpler, change the hero, fix the publish flow…"${canChange ? '' : ' disabled'}>${esc(item.changeMessage)}</textarea>
      <button class="owner-button primary" type="submit"${canChange && item.changeMessage.trim() ? '' : ' disabled'}>Tell Pandora</button>
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
  verifiedLiveUrl,
});
}
