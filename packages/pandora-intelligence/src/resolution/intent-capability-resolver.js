'use strict';

/** @typedef {'communication'|'research'|'coding_building'|'files'|'device_operations'|'business'|'travel'|'scheduling'|'future_capability'|'general_assistance'} IntentDomain */
/** @typedef {'no_action'|'read_only'|'state_change'} ActionMode */
/** @typedef {'device'|'pandora_trusted_cloud'|'external_provider'} ExecutionBoundary */
/** @typedef {'device'|'device_first'|'best_available'} ExecutionPlacement */
/** @typedef {{id: string}} SelectedProject */
/** @typedef {{request?: unknown, prompt?: unknown, text?: unknown, selectedProject?: unknown, project?: unknown}} ResolverInput */

const RESOLVER_CONTRACT_VERSION = 'pandora-intent-capability-resolution-v1';
const DOMAINS = Object.freeze([
  'communication', 'research', 'coding_building', 'files', 'device_operations',
  'business', 'travel', 'scheduling', 'future_capability', 'general_assistance',
]);
const ACTION_MODES = Object.freeze(['no_action', 'read_only', 'state_change']);
/** @type {readonly ExecutionBoundary[]} */
const EXECUTION_BOUNDARIES = Object.freeze(['device', 'pandora_trusted_cloud', 'external_provider']);
const MODEL_CAPABILITY_KEYS = Object.freeze([
  'reasoning', 'coding', 'multimodal', 'imageUnderstanding', 'structuredOutput',
  'toolCalling', 'longContext', 'classification', 'summarization', 'copywriting',
]);

const DOMAIN_RULES = Object.freeze({
  communication: [
    [5, /\b(?:email|e-mail|message|reply|respond|text|sms|whatsapp|slack|dm|call)\b/i, 'communication.channel'],
    [3, /\b(?:send|forward|draft|write)\b.{0,40}\b(?:email|message|reply|text|sms|dm)\b/i, 'communication.action'],
  ],
  research: [
    [5, /\b(?:research|investigate|look up|find out|fact[- ]?check|verify|compare|study)\b/i, 'research.explicit'],
    [3, /\b(?:latest|current|recent|evidence|sources?|reviews?|options?)\b/i, 'research.evidence'],
  ],
  coding_building: [
    [6, /\b(?:app|website|web app|software|code|codebase|repository|repo|api|database|schema|function|endpoint|frontend|backend|checkout|bug|pull request|\bpr\b|branch)\b/i, 'software.object'],
    [4, /\b(?:implement|refactor|compile|debug|deploy|merge|commit)\b/i, 'software.action'],
    [3, /\b(?:build|fix|change|update|create|make)\b.{0,50}\b(?:app|website|software|code|repo|repository|api|database|checkout|bug|feature)\b/i, 'software.change_object'],
  ],
  files: [
    [5, /\b(?:file|folder|document|pdf|spreadsheet|worksheet|csv|docx|pptx|attachment)\b/i, 'files.object'],
    [3, /\b(?:open|read|rename|move|copy|delete|organize|extract|upload|download)\b.{0,40}\b(?:file|folder|document|pdf|spreadsheet|attachment)\b/i, 'files.action'],
  ],
  device_operations: [
    [6, /\b(?:phone|android|device|screen|screenshot|wifi|wi-fi|bluetooth|flashlight|volume|brightness|camera|microphone|notification|developer options?|airplane mode)\b/i, 'device.object'],
    [4, /\b(?:battery level|battery status|storage space|device storage|ram usage|cpu usage)\b/i, 'device.status'],
    [3, /\b(?:turn on|turn off|enable|disable|set|change|open)\b.{0,35}\b(?:wifi|wi-fi|bluetooth|flashlight|volume|brightness|camera|microphone|setting|developer options?)\b/i, 'device.action'],
  ],
  business: [
    [5, /\b(?:business|sales|revenue|profit|pricing|marketing|campaign|customers?|restaurant|inventory|operations|conversion|retention|market strategy|business plan)\b/i, 'business.object'],
    [3, /\b(?:forecast|analy[sz]e|optimi[sz]e|strategy|promotion)\b/i, 'business.analysis'],
  ],
  travel: [
    [6, /\b(?:travel|trip|flights?|hotels?|airbnb|airport|visa|itinerary|destination|booking|reservation|tour)\b/i, 'travel.object'],
    [3, /\b(?:book|reserve|plan)\b.{0,35}\b(?:flight|hotel|trip|travel|room|tour)\b/i, 'travel.action'],
  ],
  scheduling: [
    [6, /\b(?:calendar|schedule|appointment|meeting|reminder|remind me|alarm)\b/i, 'scheduling.object'],
    [3, /\b(?:book|set|move|reschedule|cancel)\b.{0,35}\b(?:meeting|appointment|reminder|calendar|alarm)\b/i, 'scheduling.action'],
  ],
  future_capability: [
    [7, /\b(?:future capability|future feature|eventually support|later support|when pandora can|once pandora can|add capability later)\b/i, 'future.explicit'],
  ],
});

const PLANNING = /\b(?:plan|roadmap|strategy|explain|describe|outline|how (?:to|would)|proposal|design|spec(?:ification)?|analy[sz]e)\b/i;
const READ = /\b(?:read|inspect|check|show|list|find|search|research|look up|compare|review|summari[sz]e|analy[sz]e|verify|open)\b/i;
const STATE = /\b(?:send|forward|reply|post|publish|book|reserve|schedule|reschedule|cancel|rename|move|delete|upload|write|edit|turn on|turn off|enable|disable|set|change|update|implement|refactor|deploy|merge|commit|install|uninstall|create|make|build|fix)\b/i;
const SOFTWARE_STATE = /\b(?:build|fix|change|update|implement|refactor|deploy|publish|merge|commit|create|make)\b/i;
const GENERIC_BUILDER = /\b(?:build|create|make|fix|change|update)\b/i;
const PROJECT_REFERENCE = /\b(?:this (?:app|website|project|repo|repository|codebase)|the (?:app|website|project|repo|repository|codebase)|repo|repository|project|codebase|approved plan|it)\b/i;
const PRIVATE = /\b(?:private|confidential|sensitive|local[- ]only|keep (?:it )?local|do not send (?:it )?outside|on[- ]device only)\b/i;

/** @param {ResolverInput} input */
function resolveIntentCapabilities(input) {
  if (!input || typeof input !== 'object') throw new TypeError('resolver input is required');
  const request = normalizeText(input.request ?? input.prompt ?? input.text);
  if (!request) throw new TypeError('request must be a non-empty string');
  const selectedProject = normalizeProject(input.selectedProject ?? input.project ?? null);

  const scored = scoreDomains(request);
  const softwareDirect = scored.scores.coding_building >= 6;
  const projectAction = Boolean(selectedProject && SOFTWARE_STATE.test(request) && PROJECT_REFERENCE.test(request));
  if (projectAction && scored.scores.coding_building < 8) {
    scored.scores.coding_building += 8;
    scored.matched.push('software.selected_project_action');
  }

  let candidates = rank(scored.scores);
  let intent = candidates[0].domain;
  if (candidates[0].score <= 0) intent = 'general_assistance';
  if (intent === 'coding_building' && !softwareDirect && !projectAction) intent = 'general_assistance';

  const planning = PLANNING.test(request) && !/\b(?:according to|execute|do it|go ahead|apply|now)\b/i.test(request);
  const actionMode = resolveActionMode({ request, intent, planning });
  const projectContextUsed = Boolean(selectedProject && intent === 'coding_building' && (softwareDirect || projectAction));
  const contextBinding = projectContextUsed && selectedProject
    ? { kind: 'project', projectId: selectedProject.id, reason: softwareDirect ? 'explicit_software_project_context' : 'selected_project_action_reference' }
    : { kind: 'none', projectId: null, reason: null };

  /** @type {ExecutionBoundary[]} */
  const allowedExecutionBoundaries = PRIVATE.test(request)
    ? ['device', 'pandora_trusted_cloud']
    : [...EXECUTION_BOUNDARIES];
  /** @type {ExecutionPlacement} */
  const preferredExecution = intent === 'device_operations' ? 'device' : intent === 'files' ? 'device_first' : 'best_available';
  const risk = resolveRisk(request, actionMode);
  const requiredCapabilities = capabilitiesFor(intent, actionMode);
  const modelCapabilities = modelCapabilitiesFor(intent, actionMode);

  candidates = rank(scored.scores).slice(0, 5);
  if (intent === 'general_assistance' && !candidates.some((candidate) => candidate.domain === intent)) {
    candidates.unshift({ domain: intent, score: 0 });
    candidates = candidates.slice(0, 5);
  }
  const runnerUp = candidates.find((candidate) => candidate.domain !== intent);
  const winnerScore = candidates.find((candidate) => candidate.domain === intent)?.score ?? 0;
  const ambiguous = winnerScore > 0 && runnerUp && Math.abs(winnerScore - runnerUp.score) <= 1;
  const builderDefaultPrevented = GENERIC_BUILDER.test(request) && intent !== 'coding_building';

  return {
    contractVersion: RESOLVER_CONTRACT_VERSION,
    intent,
    requestedOutcome: request.slice(0, 500),
    requiredCapabilities,
    actionMode,
    riskAuthority: risk,
    privacyExecution: {
      allowedExecutionBoundaries,
      preferredExecution,
      resolverClaimsProviderCompliance: false,
    },
    executionCharacteristics: {
      preferredPlacement: preferredExecution,
      requiresDevicePresence: intent === 'device_operations' && actionMode === 'state_change',
      allowCloudReasoning: preferredExecution !== 'device' || actionMode !== 'state_change',
      allowCloudSideEffects: actionMode === 'state_change' && intent !== 'device_operations',
    },
    contextBinding,
    confidence: confidenceFor(winnerScore, runnerUp?.score ?? 0, intent),
    ambiguity: {
      needsClarification: Boolean(ambiguous && winnerScore < 8),
      reason: ambiguous && winnerScore < 8 ? 'multiple_capability_domains_have_similar_evidence' : null,
      alternatives: ambiguous && winnerScore < 8 ? candidates.slice(0, 3).map((candidate) => candidate.domain) : [],
    },
    capabilityToolConstraints: {
      forbidAutomaticProjectCreation: true,
      requireGovernedMutationBoundary: actionMode === 'state_change',
      requireReadbackAfterStateChange: actionMode === 'state_change',
      reuseIdempotencyOnRetry: actionMode === 'state_change',
      forbidCredentialExposure: true,
      providerNeutral: true,
      allowedEffectClass: actionMode,
    },
    modelRoutingConstraints: {
      requiredModelCapabilities: modelCapabilities,
      allowedExecutionBoundaries: [...allowedExecutionBoundaries],
      providerPreference: null,
      modelPreference: null,
      modelSelectionOwner: 'M3',
    },
    routingEvidence: {
      matchedSignals: unique(scored.matched).slice(0, 24),
      candidateDomains: candidates,
      builderDefaultPrevented,
      projectContextUsed,
      projectContextIgnoredAsIrrelevant: Boolean(selectedProject && !projectContextUsed),
    },
  };
}

/** @param {string} request */
function scoreDomains(request) {
  /** @type {Record<IntentDomain, number>} */
  const scores = { communication: 0, research: 0, coding_building: 0, files: 0, device_operations: 0, business: 0, travel: 0, scheduling: 0, future_capability: 0, general_assistance: 0 };
  /** @type {string[]} */
  const matched = [];
  for (const [domain, rules] of Object.entries(DOMAIN_RULES)) {
    for (const [weight, pattern, label] of /** @type {[number, RegExp, string][]} */ (/** @type {unknown} */ (rules))) {
      if (pattern.test(request)) {
        scores[/** @type {IntentDomain} */ (domain)] += weight;
        matched.push(label);
      }
    }
  }
  return { scores, matched };
}

/** @param {{request: string, intent: IntentDomain, planning: boolean}} input @returns {ActionMode} */
function resolveActionMode({ request, intent, planning }) {
  if (planning) return READ.test(request) && /\b(?:existing|current|repo|repository|file|document|website|app|code)\b/i.test(request) ? 'read_only' : 'no_action';
  if (intent === 'research') return 'read_only';
  if (STATE.test(request)) {
    if (intent === 'coding_building') return SOFTWARE_STATE.test(request) ? 'state_change' : 'read_only';
    if (intent === 'communication' && /\b(?:send|forward|reply|post)\b/i.test(request)) return 'state_change';
    if (intent === 'files' && /\b(?:rename|move|delete|upload|write|edit|create|copy)\b/i.test(request)) return 'state_change';
    if (intent === 'device_operations' && /\b(?:turn on|turn off|enable|disable|set|change|update|install|uninstall)\b/i.test(request)) return 'state_change';
    if (intent === 'travel' && /\b(?:book|reserve|cancel)\b/i.test(request)) return 'state_change';
    if (intent === 'scheduling' && /\b(?:schedule|book|set|move|reschedule|cancel|create)\b/i.test(request)) return 'state_change';
  }
  if (READ.test(request)) return 'read_only';
  return 'no_action';
}

/** @param {string} request @param {ActionMode} actionMode */
function resolveRisk(request, actionMode) {
  /** @type {string[]} */
  const consequenceSignals = [];
  if (/\b(?:publish|production|go live|public release|release publicly|deploy to prod)\b/i.test(request)) consequenceSignals.push('public_release');
  if (/\b(?:send|forward|reply|post|book|reserve|sign|submit)\b/i.test(request)) consequenceSignals.push('external_commitment');
  if (/\b(?:pay|purchase|buy|transfer|withdraw|deposit|cash out|cash in)\b/i.test(request)) consequenceSignals.push('money_movement_or_purchase');
  if (/\b(?:delete|wipe|factory reset|erase|destroy|permanently remove)\b/i.test(request)) consequenceSignals.push('destructive_or_irreversible');
  if (/\b(?:password|credential|api key|secret|security setting|permission|account access|login|2fa|otp|authenticator)\b/i.test(request)) consequenceSignals.push('account_or_security_change');
  return {
    consequential: consequenceSignals.length > 0,
    consequenceSignals: unique(consequenceSignals),
    authorityRequirement: actionMode === 'state_change' ? 'explicit_current_or_matching_standing_policy' : 'none_required',
    authorityDecisionOwner: 'pandora-standing-authority-policy-v1',
    resolverGrantsAuthority: false,
  };
}

/** @param {IntentDomain} intent @param {ActionMode} actionMode @returns {string[]} */
function capabilitiesFor(intent, actionMode) {
  const table = {
    communication: actionMode === 'state_change' ? ['communication.compose', 'communication.send'] : ['communication.compose'],
    research: ['knowledge.research'],
    coding_building: actionMode === 'state_change' ? ['software.reason', 'software.change'] : ['software.reason'],
    files: actionMode === 'state_change' ? ['files.inspect', 'files.mutate'] : ['files.inspect'],
    device_operations: actionMode === 'state_change' ? ['device.inspect', 'device.control'] : ['device.inspect'],
    business: ['business.analyze'],
    travel: actionMode === 'state_change' ? ['travel.research', 'travel.book'] : ['travel.research'],
    scheduling: actionMode === 'state_change' ? ['calendar.inspect', 'calendar.mutate'] : ['calendar.inspect'],
    future_capability: ['capability.plan'],
    general_assistance: ['assistant.reason'],
  };
  return table[intent];
}

/** @param {IntentDomain} intent @param {ActionMode} actionMode @returns {string[]} */
function modelCapabilitiesFor(intent, actionMode) {
  const table = {
    communication: ['reasoning', 'copywriting'],
    research: ['reasoning', 'longContext', 'summarization'],
    coding_building: actionMode === 'state_change' ? ['reasoning', 'coding', 'toolCalling'] : ['reasoning', 'coding'],
    files: actionMode === 'state_change' ? ['reasoning', 'toolCalling'] : ['reasoning', 'summarization'],
    device_operations: ['reasoning', 'toolCalling'],
    business: ['reasoning', 'structuredOutput'],
    travel: ['reasoning', 'toolCalling'],
    scheduling: ['reasoning', 'toolCalling'],
    future_capability: ['reasoning', 'structuredOutput'],
    general_assistance: ['reasoning'],
  };
  return table[intent];
}

/** @param {unknown} project @returns {SelectedProject | null} */
function normalizeProject(project) {
  if (!project) return null;
  if (typeof project === 'string') return { id: project };
  if (typeof project !== 'object') return null;
  const candidate = /** @type {Record<string, unknown>} */ (project);
  const id = candidate.id ?? candidate.projectId ?? candidate.slug ?? candidate.name;
  return id ? { id: String(id) } : null;
}

/** @param {unknown} value @returns {string} */
function normalizeText(value) {
  if (typeof value !== 'string') return '';
  return value.trim().replace(/\s+/g, ' ');
}

/** @param {Record<IntentDomain, number>} scores @returns {{domain: IntentDomain, score: number}[]} */
function rank(scores) {
  return Object.entries(scores)
    .map(([domain, score]) => ({ domain: /** @type {IntentDomain} */ (domain), score }))
    .sort((a, b) => b.score - a.score || DOMAINS.indexOf(a.domain) - DOMAINS.indexOf(b.domain));
}

/** @param {number} winner @param {number} runnerUp @param {IntentDomain} intent */
function confidenceFor(winner, runnerUp, intent) {
  if (intent === 'general_assistance' && winner <= 0) return 0.55;
  const margin = Math.max(0, winner - runnerUp);
  return Math.max(0.55, Math.min(0.99, Number((0.62 + winner * 0.035 + margin * 0.02).toFixed(2))));
}

/** @template T @param {T[]} values @returns {T[]} */
function unique(values) { return [...new Set(values)]; }

module.exports = {
  ACTION_MODES,
  DOMAINS,
  EXECUTION_BOUNDARIES,
  MODEL_CAPABILITY_KEYS,
  RESOLVER_CONTRACT_VERSION,
  resolveIntentCapabilities,
};
