if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const {
  icons, state, esc, deriveProjects, projectInitials,
  projectForPlan, formatTool, formatExpiry, timeAgo
} = window.PandorasOwnerData;
const { button, badge, pendingPlans } = window.PandorasOwnerRuntime;
const { projectRow, sectionHeader } = window.PandorasOwnerScreenCore;

function blockedProjects() {
  return deriveProjects().filter((project) => project.blockedCount > 0);
}

function needsCount() {
  if (!state.live) return 0;
  return pendingPlans().length + blockedProjects().length;
}

function homeHero() {
  if (state.loading || state.refreshing) {
    return `<section class="owner-card owner-decision owner-skeleton-card" aria-label="Checking current work"><div class="owner-skeleton wide"></div><div class="owner-skeleton medium"></div><div class="owner-skeleton button"></div></section>`;
  }
  if (!state.session?.authenticated) {
    return `<section class="owner-card owner-decision owner-decision-muted">
      <div class="owner-decision-icon warning">${icons.shield}</div>
      <div class="owner-decision-copy"><span class="owner-kicker">Your control plane</span><h1>Your work stays here</h1><p>Sign in when you want Pandora to check protected live status, decisions, or connected services.</p></div>
      <div class="owner-decision-actions">${button('Check live status', { kind: 'primary', action: 'refresh' })}</div>
    </section>`;
  }
  if (!state.live) {
    return `<section class="owner-card owner-decision owner-decision-muted">
      <div class="owner-decision-icon warning">${icons.alert}</div>
      <div class="owner-decision-copy"><span class="owner-kicker">Protected status unavailable</span><h1>Your saved project view is still here</h1><p>${esc(state.error?.message || 'Pandora could not verify protected live status.')}</p></div>
      <div class="owner-decision-actions">${button('Try again', { kind: 'primary', action: 'refresh', icon: icons.refresh })}</div>
    </section>`;
  }
  const waiting = pendingPlans();
  const blocked = blockedProjects();
  if (waiting.length || blocked.length) {
    return `<section class="owner-card owner-decision owner-decision-attention">
      <div class="owner-decision-icon warning">${icons.alert}</div>
      <div class="owner-decision-copy"><div class="owner-decision-meta">${badge('Needs You', 'warning')}<span>${needsCount()} waiting</span></div><h1>${needsCount()} thing${needsCount() === 1 ? '' : 's'} need your decision</h1><p>Pandora has stopped at an owner boundary. Nothing consequential will continue just because you open the item.</p></div>
      <div class="owner-decision-actions">${button('Open Needs You', { kind: 'primary', route: 'needs' })}</div>
    </section>`;
  }
  const project = deriveProjects()[0];
  if (!project) {
    return `<section class="owner-card owner-decision owner-decision-clear">
      <div class="owner-decision-icon success">${icons.check}</div>
      <div class="owner-decision-copy"><span class="owner-kicker">Ready for your next intent</span><h1>What should Pandora make real?</h1><p>Start with the outcome. Pandora will keep provider and implementation detail out of the way until it matters.</p></div>
      <div class="owner-decision-actions">${button('Ask Pandora', { kind: 'primary', route: 'ask', icon: icons.ask })}</div>
    </section>`;
  }
  const label = project.progress === 100 ? 'Ready' : 'Working';
  return `<section class="owner-card owner-decision owner-decision-clear">
    <div class="owner-decision-icon success">${project.progress === 100 ? icons.check : icons.projects}</div>
    <div class="owner-decision-copy"><div class="owner-decision-meta">${badge(label, project.progress === 100 ? 'success' : 'neutral')}<span>${project.lastUpdated ? `Updated ${timeAgo(project.lastUpdated)}` : 'Update time unavailable'}</span></div><h1>${esc(project.name)}</h1><p>${esc(project.nextMilestone || 'Pandora is reconciling the next meaningful result.')}</p></div>
    <div class="owner-decision-actions">${button('Open project', { kind: 'primary', action: 'open-project', extra: `data-id="${esc(project.id)}"` })}${button('Ask Pandora', { kind: 'secondary', route: 'ask' })}</div>
  </section>`;
}

function compactAsk() {
  return `<section class="owner-card owner-command-card">
    <div class="owner-command-heading"><span class="owner-command-icon">${icons.ask}</span><div><strong>Ask Pandora</strong><span>Describe the result or change you want.</span></div></div>
    <form class="owner-command-form" data-ask-form>
      <input class="owner-command-input" data-ask-message maxlength="12000" autocomplete="off" placeholder="Tell Pandora what you want to make real…" value="${esc(state.ask.message)}" />
      <button class="owner-command-send" type="submit" aria-label="Send to Pandora" ${state.ask.sending ? 'disabled' : ''}>${icons.arrow}</button>
    </form>
  </section>`;
}

function renderHome() {
  const projects = deriveProjects().slice(0, 3);
  return `<div class="owner-screen owner-home-screen">
    ${homeHero()}
    ${compactAsk()}
    <section class="owner-section">
      ${sectionHeader('Projects', 'View all', 'projects')}
      <div class="owner-card owner-list-card">${projects.length ? projects.map(projectRow).join('') : '<div class="owner-empty compact"><h3>No projects yet</h3><p>Ask Pandora for an outcome to begin.</p></div>'}</div>
    </section>
  </div>`;
}

function askResult() {
  if (state.ask.sending) {
    return `<section class="owner-card owner-ask-result owner-ask-thinking"><span class="owner-command-icon">${icons.ask}</span><div><strong>Pandora is working through your request</strong><p>No production change is executed directly from this conversation.</p></div></section>`;
  }
  if (state.ask.error) {
    return `<section class="owner-card owner-ask-result owner-ask-error"><span class="owner-command-icon">${icons.alert}</span><div><strong>Pandora could not complete that turn</strong><p>${esc(state.ask.error)}</p></div></section>`;
  }
  if (!state.ask.reply) return '';
  return `<section class="owner-card owner-ask-response">
    <div class="owner-ask-response-head"><span class="owner-command-icon">${icons.ask}</span><div><strong>Pandora</strong><span>${state.ask.intent ? esc(state.ask.intent.replaceAll('_', ' ')) : 'Response'}</span></div></div>
    <div class="owner-ask-copy">${esc(state.ask.reply).replaceAll('\n', '<br>')}</div>
    ${state.ask.needsClarification && state.ask.clarifyingQuestion ? `<div class="owner-ask-notice"><strong>One thing is needed</strong><p>${esc(state.ask.clarifyingQuestion)}</p></div>` : ''}
    ${state.ask.handoff?.required ? `<div class="owner-ask-notice"><strong>Governed next step prepared</strong><p>Pandora prepared the next intake request. It has not executed a mutation from model output.</p></div>` : ''}
  </section>`;
}

function renderAsk() {
  return `<div class="owner-screen owner-ask-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Intent first</span><h1>Ask Pandora</h1><p>Describe the outcome. Pandora can reason with project context and prepare governed work without putting provider credentials in the browser.</p></div>
    ${state.ask.projectId ? `<div class="owner-ask-project-context"><span>${icons.projects}</span><div><strong>${esc(state.ask.projectName || 'Selected project')}</strong><small>Pandora is using this exact project context.</small></div><button type="button" data-action="clear-ask-project">Clear</button></div>` : ''}
    ${askResult()}
    <section class="owner-card owner-ask-composer">
      <form data-ask-form>
        <label for="owner-ask-message">What do you want?</label>
        <textarea id="owner-ask-message" data-ask-message maxlength="12000" rows="6" placeholder="Build, fix, change, analyze, publish, or operate something…">${esc(state.ask.message)}</textarea>
        <div class="owner-ask-actions"><span>${state.ask.threadId ? 'Continuing this Pandora thread' : 'New Pandora thread'}</span><button type="submit" class="owner-button primary" ${state.ask.sending ? 'disabled' : ''}>${state.ask.sending ? 'Working…' : 'Send'}</button></div>
      </form>
    </section>
  </div>`;
}

function approvalItem(plan) {
  const project = projectForPlan(plan);
  return `<article class="owner-card owner-need-card">
    <div class="owner-need-mark">${projectInitials(project)}</div>
    <div class="owner-need-copy"><span>${esc(project)}</span><strong>${esc(formatTool(plan.tool))}</strong><p>Review the exact checked change before allowing it to become eligible for separate execution.</p><small>${esc(formatExpiry(plan.expiresAt))}</small></div>
    ${button('Review', { kind: 'primary compact', action: 'review-plan', extra: `data-id="${esc(plan.planId)}"` })}
  </article>`;
}

function blockedItem(project) {
  return `<article class="owner-card owner-need-card">
    <div class="owner-need-mark">${esc(project.initials)}</div>
    <div class="owner-need-copy"><span>${esc(project.name)}</span><strong>Project needs attention</strong><p>${esc(project.nextMilestone || 'A recorded blocker needs review.')}</p><small>${project.blockedCount} blocked recorded task${project.blockedCount === 1 ? '' : 's'}</small></div>
    ${button('Open', { kind: 'secondary compact', action: 'open-project', extra: `data-id="${esc(project.id)}"` })}
  </article>`;
}

function renderNeeds() {
  const plans = state.live ? pendingPlans() : [];
  const blocked = state.live ? blockedProjects() : [];
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Consequential decisions only</span><h1>Needs You</h1><p>Approvals, blocked work, release decisions and other owner boundaries belong here. Routine repair stays out of your way.</p></div>
    ${!state.live ? `<div class="owner-card owner-empty"><span>${icons.alert}</span><h2>Live decisions unavailable</h2><p>${esc(state.error?.message || 'Pandora could not verify protected live decision state.')}</p>${button('Try again', { kind: 'primary', action: 'refresh' })}</div>`
      : (plans.length || blocked.length)
        ? `<div class="owner-needs-list">${plans.map(approvalItem).join('')}${blocked.map(blockedItem).join('')}</div>`
        : `<div class="owner-card owner-empty"><span>${icons.check}</span><h2>Nothing needs you</h2><p>Pandora has no verified consequential owner decision waiting right now.</p></div>`}
  </div>`;
}

function businessMoney(micros, currency) {
  try {
    const value = BigInt(String(micros ?? '0'));
    const cents = (value + 5000n) / 10000n;
    const whole = cents / 100n;
    const fraction = String(cents % 100n).padStart(2, '0');
    return `${String(currency || 'USD').toUpperCase()} ${whole.toLocaleString()}.${fraction}`;
  } catch {
    return '—';
  }
}

function businessCostFact(cost) {
  const charged = BigInt(String(cost?.chargedMicros || '0'));
  const billed = BigInt(String(cost?.billedMicros || '0'));
  const estimated = BigInt(String(cost?.estimatedMicros || '0'));
  if (charged > 0n) return { label: 'Charged', value: businessMoney(cost.chargedMicros, cost.currency) };
  if (billed > 0n) return { label: 'Billed', value: businessMoney(cost.billedMicros, cost.currency) };
  return { label: estimated > 0n ? 'Estimated' : 'Recorded cost', value: businessMoney(cost.estimatedMicros, cost.currency) };
}

function businessProjectRow(project) {
  const objective = project.objective;
  const costFacts = Array.isArray(project.costs) ? project.costs.map(businessCostFact) : [];
  const budgets = Array.isArray(project.budgets) ? project.budgets : [];
  const facts = [
    ...costFacts.map((fact) => `${fact.label}: ${fact.value}`),
    ...budgets.map((budget) => `Budget ${budget.currency}: ${businessMoney(budget.spentMicros, budget.currency)} of ${businessMoney(budget.hardLimitMicros, budget.currency)}`),
  ];
  return `<article class="owner-card owner-need-card">
    <div class="owner-need-mark">${esc(projectInitials(project.name))}</div>
    <div class="owner-need-copy">
      <span>${esc(project.status || 'Recorded')}</span>
      <strong>${esc(project.name)}</strong>
      <p>${esc(objective?.objective || 'No current business objective recorded')}</p>
      <small>${esc(objective?.successMetric ? `Metric: ${objective.successMetric}${objective.baseline || objective.target ? ` · ${objective.baseline || '—'} → ${objective.target || '—'}` : ''}` : 'Success metric not recorded')}</small>
      ${facts.length ? `<small>${esc(facts.join(' · '))}</small>` : '<small>No cost or budget facts recorded for this project.</small>'}
    </div>
  </article>`;
}

function renderBusiness() {
  const item = state.business;
  const data = item?.data;
  if (item?.loading && !data) {
    return `<div class="owner-screen"><div class="owner-page-intro"><span class="owner-kicker">Commercial truth</span><h1>Business</h1><p>Pandora is checking recorded objectives, budgets, and cost facts.</p></div><section class="owner-card owner-skeleton-card"><div class="owner-skeleton wide"></div><div class="owner-skeleton medium"></div></section></div>`;
  }
  if (!data || data.contractVersion !== 'pandora-owner-business-v1') {
    return `<div class="owner-screen">
      <div class="owner-page-intro"><span class="owner-kicker">Commercial truth</span><h1>Business</h1><p>Objectives, budgets, and costs appear only from Pandora’s protected owner contract.</p></div>
      <section class="owner-card owner-business-empty"><span class="owner-business-icon">${icons.business}</span><div><h2>Business facts are unavailable</h2><p>${esc(item?.error || 'Pandora could not read the bounded Business contract right now.')}</p></div></section>
    </div>`;
  }

  const costs = Array.isArray(data.costs) ? data.costs : [];
  const budgets = Array.isArray(data.budgets) ? data.budgets : [];
  const projects = Array.isArray(data.projects) ? data.projects.filter((project) => project.objective || project.costs?.length || project.budgets?.length).slice(0, 12) : [];
  const exhausted = budgets.reduce((total, budget) => total + Number(budget.exhaustedCount || 0), 0);
  const costCards = costs.length
    ? costs.map((cost) => {
        const fact = businessCostFact(cost);
        return `<article class="owner-card professional-metric"><span>${esc(fact.label)} · ${esc(cost.currency)}</span><strong>${esc(fact.value)}</strong><small>${esc(String(cost.entryCount || 0))} recorded cost entr${Number(cost.entryCount) === 1 ? 'y' : 'ies'}</small></article>`;
      }).join('')
    : '<div class="owner-card owner-empty compact"><h3>No cost entries recorded</h3><p>Pandora will not estimate spend when the cost ledger is empty.</p></div>';

  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Commercial truth</span><h1>Business</h1><p>Recorded objectives, budgets, and cost ledger facts. No inferred revenue, ROI, adoption, retention, or customer outcomes.</p></div>
    <section class="professional-metrics-grid" aria-label="Business overview">
      <article class="owner-card professional-metric"><span>Projects</span><strong>${esc(data.counts?.projects ?? '—')}</strong><small>non-archived</small></article>
      <article class="owner-card professional-metric"><span>With objectives</span><strong>${esc(data.counts?.projectsWithObjectives ?? '—')}</strong><small>recorded ProjectSpec truth</small></article>
      <article class="owner-card professional-metric"><span>Cost entries</span><strong>${esc(data.counts?.costEntries ?? '—')}</strong><small>append-only ledger</small></article>
      <article class="owner-card professional-metric"><span>Exhausted budgets</span><strong>${esc(exhausted)}</strong><small>recorded hard-limit state</small></article>
    </section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Cost ledger</span><h2>Recorded spend by currency</h2></div><span>No cross-currency totals</span></div><div class="professional-metrics-grid">${costCards}</div></section>
    <section class="owner-section"><div class="professional-section-head"><div><span class="owner-kicker">Projects</span><h2>Objectives and economics</h2></div><span>${projects.length} shown</span></div><div class="owner-needs-list">${projects.length ? projects.map(businessProjectRow).join('') : '<div class="owner-card owner-empty"><h3>No project business facts to show</h3><p>Objectives, costs, and budgets will appear here when recorded.</p></div>'}</div></section>
    <section class="owner-card professional-boundary-note"><span>${icons.shield}</span><div><strong>Outcome metrics are still unavailable</strong><p>Revenue, ROI, adoption, retention, and customer outcomes remain unavailable until a bounded first-party measurement source is connected. Pandora does not infer them from spend or objectives.</p></div></section>
  </div>`;
}

function nav() {
  const items = [
    ['home', 'Home', icons.home],
    ['projects', 'Projects', icons.projects],
    ['ask', 'Ask Pandora', icons.ask],
    ['needs', 'Needs You', icons.alert],
    ['business', 'Business', icons.business],
  ];
  const count = needsCount();
  return `<nav class="owner-bottom-nav" data-owner-primary-nav aria-label="Primary navigation">${items.map(([route, label, icon]) => `<button type="button" data-route="${route}" class="${state.route === route ? 'active' : ''}" aria-current="${state.route === route ? 'page' : 'false'}"><span class="owner-nav-icon">${icon}${route === 'needs' && count ? `<b>${count > 99 ? '99+' : count}</b>` : ''}</span><span>${label}</span></button>`).join('')}</nav>`;
}

window.PandorasOwnerExperience = Object.freeze({
  renderHome, renderAsk, renderNeeds, renderBusiness, nav, needsCount
});
}
