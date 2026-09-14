
'use strict';

const CONTINUOUS_EXECUTION_CONTRACT_VERSION = 'pandora-continuous-execution-v2';
const EFFECTS = new Set(['read_only', 'state_change']);
const ACTION_MODES = new Set(['no_action', 'read_only', 'state_change']);
const GOVERNED_STATES = new Set(['completed', 'needs_approval', 'denied', 'verification_required', 'failed', 'cancelled']);
const READ_RECEIPT_STATUSES = new Set(['succeeded', 'failed']);
const READ_EFFECT_STATES = new Set(['observed', 'not_applied']);
const TERMINAL_STATUSES = new Set(['result', 'needs_you', 'blocked', 'cancelled', 'failed']);
const OPAQUE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;

/** @typedef {'read_only'|'state_change'} Effect */
/** @typedef {{[key:string]:unknown, actionMode?:string}} Resolution */
/** @typedef {{actionId:string, capability:string, effect:Effect, input?:unknown, idempotencyKey:string|null}} Action */
/** @typedef {{kind:'act', decisionRef:string, action:Action}|{kind:'verify', decisionRef:string}} Reason */
/** @typedef {{status:'succeeded'|'failed', receiptRef:string, retryable:boolean, output?:unknown}} ReadReceipt */
/** @typedef {{observationRef:string, effectState:'observed'|'not_applied', progressMade:boolean, retryable:boolean, output?:unknown}} ReadObservation */
/** @typedef {{state:'completed'|'needs_approval'|'denied'|'verification_required'|'failed'|'cancelled', receiptRef:string|null, readbackRef:string|null, effectState:'applied'|'not_applied'|'unknown'|null, progressMade:boolean, retryable:boolean, summary:string|null, policyRef:string|null, output?:unknown}} GovernedOutcome */
/** @typedef {{verified:boolean, verificationReceiptRef:string|null, summary:string|null, progressMade:boolean, retryable:boolean, output?:unknown}} Verification */
/** @typedef {{phase:string, iteration:number, ref:string, actionId:string|null, status:string|null}} Evidence */
/** @typedef {{jobId:string, iteration:number, resolution:Resolution, observations:readonly unknown[], actions:readonly unknown[], evidence:readonly Evidence[], lastAction:Action|null, lastObservation:unknown|null}} View */
/** @typedef {{jobId:string, resolution:Resolution, maxIterations?:number, maxNoProgressIterations?:number}} Input */
/** @typedef {{reason:(v:View)=>unknown|Promise<unknown>, actRead?:(a:Action,v:View)=>unknown|Promise<unknown>, observeRead?:(x:{action:Action,receipt:ReadReceipt,view:View})=>unknown|Promise<unknown>, executeGoverned?:(a:Action,v:View)=>unknown|Promise<unknown>, verify:(v:View)=>unknown|Promise<unknown>, projectResult?:(x:{jobId:string,resolution:Resolution,verification:Verification,evidence:readonly Evidence[]})=>unknown|Promise<unknown>, control?:(x:{jobId:string,iteration:number,phase:string})=>unknown|Promise<unknown>, authorize?:unknown, act?:unknown, observe?:unknown}} Adapters */
/** @typedef {{idempotencyKey:string, applied:boolean, mayRetry:boolean}} LocalMutationInvariant */

/** @param {Input} input @param {Adapters} adapters */
async function runContinuousExecution(input, adapters) {
  const jobId = id(input?.jobId, 'jobId');
  const resolution = normalizeResolution(input?.resolution);
  if (!adapters || typeof adapters !== 'object') throw new TypeError('adapters are required');
  fn(adapters.reason, 'adapters.reason');
  fn(adapters.verify, 'adapters.verify');
  if (adapters.control != null) fn(adapters.control, 'adapters.control');
  if (adapters.projectResult != null) fn(adapters.projectResult, 'adapters.projectResult');
  if (adapters.executeGoverned != null) fn(adapters.executeGoverned, 'adapters.executeGoverned');
  if (adapters.actRead != null) fn(adapters.actRead, 'adapters.actRead');
  if (adapters.observeRead != null) fn(adapters.observeRead, 'adapters.observeRead');
  if (adapters.authorize != null || adapters.act != null || adapters.observe != null) {
    throw new Error('legacy authorize/act/observe adapters are forbidden; state changes must use executeGoverned and reads must use actRead/observeRead');
  }

  const maxIterations = bound(input.maxIterations, 12, 1, 100, 'maxIterations');
  const maxNoProgress = bound(input.maxNoProgressIterations, 3, 1, 20, 'maxNoProgressIterations');
  /** @type {unknown[]} */ const observations = [];
  /** @type {unknown[]} */ const actions = [];
  /** @type {Evidence[]} */ const evidence = [];
  /** @type {Map<string,LocalMutationInvariant>} */ const localMutations = new Map();
  /** @type {Action|null} */ let lastAction = null;
  /** @type {unknown|null} */ let lastObservation = null;
  let noProgress = 0;

  for (let iteration = 1; iteration <= maxIterations; iteration += 1) {
    if (await cancelled(adapters.control, jobId, iteration, 'before_reason', evidence)) {
      return end(jobId, 'cancelled', false, iteration - 1, 'Execution cancelled by an accepted user control.', evidence, observations, actions, null, null, null);
    }
    let view = makeView(jobId, iteration, resolution, observations, actions, evidence, lastAction, lastObservation);
    const reason = normalizeReason(await adapters.reason(view));
    evidence.push(ev('reason', iteration, reason.decisionRef, reason.kind === 'act' ? reason.action.actionId : null, reason.kind));

    if (reason.kind === 'verify') {
      if (await cancelled(adapters.control, jobId, iteration, 'before_verify', evidence)) {
        return end(jobId, 'cancelled', false, iteration, 'Execution cancelled before verification.', evidence, observations, actions, null, null, null);
      }
      view = makeView(jobId, iteration, resolution, observations, actions, evidence, lastAction, lastObservation);
      const verification = normalizeVerification(await adapters.verify(view));
      const verifyRef = verification.verificationReceiptRef || reason.decisionRef;
      evidence.push(ev('verify', iteration, verifyRef, null, verification.verified ? 'verified' : 'not_verified'));
      if (verification.verified) {
        if (!verification.verificationReceiptRef) {
          return end(jobId, 'blocked', false, iteration, 'Verified completion is missing a canonical verification receipt.', evidence, observations, actions, block('verification_receipt_missing', 'Verified completion requires a canonical verification receipt.', reason.decisionRef, null), verification, null);
        }
        if (!adapters.projectResult) {
          return end(jobId, 'blocked', false, iteration, 'Verified completion cannot become Result without the canonical Activity Theatre projector.', evidence, observations, actions, block('activity_projection_unavailable', 'Canonical Activity Theatre result projection is unavailable.', verification.verificationReceiptRef, null), verification, null);
        }
        const projection = normalizeResultProjection(await adapters.projectResult(Object.freeze({ jobId, resolution, verification, evidence: Object.freeze([...evidence]) })), jobId, verification.verificationReceiptRef);
        return end(jobId, 'result', true, iteration, verification.summary || 'Requested outcome independently verified.', evidence, observations, actions, null, verification, projection);
      }
      if (!verification.retryable) {
        return end(jobId, 'blocked', false, iteration, verification.summary || 'Verification failed and cannot safely continue.', evidence, observations, actions, block('verification_failed', verification.summary || 'Verification failed and cannot safely continue.', verifyRef, null), verification, null);
      }
      noProgress = verification.progressMade ? 0 : noProgress + 1;
      if (noProgress >= maxNoProgress) {
        return end(jobId, 'failed', false, iteration, 'Execution stopped after repeated verification cycles without evidence of progress.', evidence, observations, actions, block('no_progress', 'Repeated verification cycles produced no evidence of progress.', verifyRef, null), verification, null);
      }
      continue;
    }

    const action = reason.action;
    lastAction = action;
    const widened = effectViolation(action, resolution);
    if (widened) return end(jobId, 'blocked', false, iteration, widened.summary, evidence, observations, actions, block(widened.code, widened.summary, reason.decisionRef, null), null, null);
    const replay = inspectLocalReplay(action, localMutations);
    if (replay) return end(jobId, 'blocked', false, iteration, replay.summary, evidence, observations, actions, block(replay.code, replay.summary, reason.decisionRef, null), null, null);
    if (await cancelled(adapters.control, jobId, iteration, 'before_action', evidence)) {
      return end(jobId, 'cancelled', false, iteration, 'Execution cancelled before the next action.', evidence, observations, actions, null, null, null);
    }
    view = makeView(jobId, iteration, resolution, observations, actions, evidence, lastAction, lastObservation);
    let progressMade = false;

    if (action.effect === 'state_change') {
      if (!adapters.executeGoverned) {
        return end(jobId, 'blocked', false, iteration, 'State-changing execution is unavailable because the governed M3 tool executor is not connected.', evidence, observations, actions, block('governed_executor_unavailable', 'State-changing execution requires the governed M3 ToolGateway/authority executor.', reason.decisionRef, null), null, null);
      }
      const outcome = normalizeGovernedOutcome(await adapters.executeGoverned(action, view));
      actions.push(outcome); lastObservation = outcome; observations.push(outcome);
      evidence.push(ev('governed_execute', iteration, outcome.receiptRef || outcome.readbackRef || reason.decisionRef, action.actionId, outcome.state));
      if (outcome.readbackRef) evidence.push(ev('readback', iteration, outcome.readbackRef, action.actionId, outcome.effectState));
      rememberLocalMutation(action, outcome, localMutations);
      if (outcome.state === 'needs_approval') return end(jobId, 'needs_you', false, iteration, outcome.summary || 'A real authorization boundary requires user approval.', evidence, observations, actions, block('authorization_required', outcome.summary || 'A real authorization boundary requires user approval.', outcome.receiptRef || reason.decisionRef, outcome.policyRef), null, null);
      if (outcome.state === 'denied') return end(jobId, 'blocked', false, iteration, outcome.summary || 'Authoritative policy denied this action.', evidence, observations, actions, block('policy_denied', outcome.summary || 'Authoritative policy denied this action.', outcome.receiptRef || reason.decisionRef, outcome.policyRef), null, null);
      if (outcome.state === 'verification_required') return end(jobId, 'blocked', false, iteration, outcome.summary || 'The governed mutation has an ambiguous effect and requires authoritative reconciliation before retry.', evidence, observations, actions, block('ambiguous_effect_verification_required', outcome.summary || 'The governed mutation requires authoritative readback before retry.', outcome.readbackRef || outcome.receiptRef || reason.decisionRef, outcome.policyRef), null, null);
      if (outcome.state === 'cancelled') return end(jobId, 'cancelled', false, iteration, outcome.summary || 'Governed execution was cancelled.', evidence, observations, actions, null, null, null);
      if (outcome.state === 'failed' && !outcome.retryable) return end(jobId, 'blocked', false, iteration, outcome.summary || 'Governed execution failed and is not safely retryable.', evidence, observations, actions, block('governed_action_failed', outcome.summary || 'Governed execution failed and is not safely retryable.', outcome.receiptRef || reason.decisionRef, outcome.policyRef), null, null);
      progressMade = outcome.progressMade;
    } else {
      if (!adapters.actRead || !adapters.observeRead) {
        return end(jobId, 'blocked', false, iteration, 'Read execution adapters are unavailable.', evidence, observations, actions, block('read_executor_unavailable', 'Read-only execution requires actRead and observeRead adapters.', reason.decisionRef, null), null, null);
      }
      const receipt = normalizeReadReceipt(await adapters.actRead(action, view)); actions.push(receipt);
      evidence.push(ev('act', iteration, receipt.receiptRef, action.actionId, receipt.status));
      view = makeView(jobId, iteration, resolution, observations, actions, evidence, lastAction, lastObservation);
      const observation = normalizeReadObservation(await adapters.observeRead({ action, receipt, view }));
      observations.push(observation); lastObservation = observation;
      evidence.push(ev('observe', iteration, observation.observationRef, action.actionId, observation.effectState));
      if (receipt.status !== 'succeeded' && !receipt.retryable && !observation.retryable) return end(jobId, 'blocked', false, iteration, 'Read-only action failed and is not retryable.', evidence, observations, actions, block('action_failed', 'Read-only action failed and is not retryable.', observation.observationRef, null), null, null);
      progressMade = observation.progressMade;
    }

    noProgress = progressMade ? 0 : noProgress + 1;
    if (noProgress >= maxNoProgress) return end(jobId, 'failed', false, iteration, 'Execution stopped after repeated action/observation cycles without evidence of progress.', evidence, observations, actions, block('no_progress', 'Repeated action/observation cycles produced no evidence of progress.', evidence.at(-1)?.ref || reason.decisionRef, null), null, null);
    if (await cancelled(adapters.control, jobId, iteration, 'after_observation', evidence)) return end(jobId, 'cancelled', false, iteration, 'Execution cancelled after the latest observed state.', evidence, observations, actions, null, null, null);
  }
  return end(jobId, 'failed', false, maxIterations, 'Execution reached the bounded iteration limit without a verified result.', evidence, observations, actions, block('iteration_limit', 'Execution reached the bounded iteration limit without a verified result.', evidence.at(-1)?.ref || null, null), null, null);
}

/** @param {Action} action @param {Resolution} resolution */
function effectViolation(action, resolution) { const mode = String(resolution.actionMode); if (action.effect === 'state_change' && mode !== 'state_change') return { code:'effect_class_widened', summary:'Reasoning attempted to widen the resolved action effect into a state change.' }; if (action.effect === 'read_only' && mode === 'no_action') return { code:'effect_class_widened', summary:'Reasoning attempted to execute an action for a no-action resolution.' }; return null; }
/** @param {Action} action @param {Map<string,LocalMutationInvariant>} localMutations */
function inspectLocalReplay(action, localMutations) { if (action.effect !== 'state_change') return null; const key=id(action.idempotencyKey,'action.idempotencyKey'), prior=localMutations.get(action.actionId); if(!prior)return null; if(prior.applied)return{code:'duplicate_state_change',summary:'A state-changing action already has a governed applied/readback result and will not be executed again.'}; if(!prior.mayRetry)return{code:'retry_not_authorized',summary:'The governed state-changing attempt is not safely retryable.'}; if(prior.idempotencyKey!==key)return{code:'idempotency_identity_changed',summary:'A state-changing retry must reuse the original idempotency identity.'}; return null; }
/** @param {Action} action @param {GovernedOutcome} outcome @param {Map<string,LocalMutationInvariant>} localMutations */
function rememberLocalMutation(action,outcome,localMutations){const key=id(action.idempotencyKey,'action.idempotencyKey');localMutations.set(action.actionId,Object.freeze({idempotencyKey:key,applied:outcome.state==='completed'&&outcome.effectState==='applied',mayRetry:outcome.state==='failed'&&outcome.effectState==='not_applied'&&outcome.retryable}));}
/** @param {Adapters['control']} control @param {string} jobId @param {number} iteration @param {string} phase @param {Evidence[]} evidence */
async function cancelled(control,jobId,iteration,phase,evidence){if(!control)return false;const value=record(await control({jobId,iteration,phase}),'control receipt');if(typeof value.cancelled!=='boolean')throw new Error('control.cancelled must be boolean');if(!value.cancelled)return false;const controlRef=ref(value.controlRef,'control.controlRef');evidence.push(ev('control',iteration,controlRef,null,'cancelled'));return true;}
/** @param {string} jobId @param {number} iteration @param {Resolution} resolution @param {unknown[]} observations @param {unknown[]} actions @param {Evidence[]} evidence @param {Action|null} lastAction @param {unknown|null} lastObservation @returns {View} */
function makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation){return Object.freeze({jobId,iteration,resolution,observations:Object.freeze([...observations]),actions:Object.freeze([...actions]),evidence:Object.freeze([...evidence]),lastAction,lastObservation});}
/** @param {string} phase @param {number} iteration @param {string} evidenceRef @param {string|null} actionId @param {string|null} status @returns {Evidence} */
function ev(phase,iteration,evidenceRef,actionId,status){return Object.freeze({phase,iteration,ref:ref(evidenceRef,'evidence.ref'),actionId,status});}
/** @param {string} code @param {string} summary @param {string|null} evidenceRef @param {string|null} policyRef */
function block(code,summary,evidenceRef,policyRef){return Object.freeze({reasonCode:id(code,'blocker.reasonCode'),summary:text(summary,'blocker.summary',1000),evidenceRef:evidenceRef==null?null:ref(evidenceRef,'blocker.evidenceRef'),policyRef:policyRef==null?null:ref(policyRef,'blocker.policyRef')});}
/** @param {string} jobId @param {string} status @param {boolean} verified @param {number} iterations @param {string} summary @param {Evidence[]} evidence @param {unknown[]} observations @param {unknown[]} actions @param {unknown} blocker @param {Verification|null} verification @param {unknown} activityProjection */
function end(jobId,status,verified,iterations,summary,evidence,observations,actions,blocker,verification,activityProjection){if(!TERMINAL_STATUSES.has(status))throw new Error('invalid terminal status');return Object.freeze({contractVersion:CONTINUOUS_EXECUTION_CONTRACT_VERSION,jobId,status,verified,iterations,summary:text(summary,'summary',1000),evidence:Object.freeze([...evidence]),observations:Object.freeze([...observations]),actions:Object.freeze([...actions]),blocker,verification,activityProjection});}
/** @param {unknown} value @returns {Resolution} */
function normalizeResolution(value){if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError('resolution is required');const source=/** @type {Resolution} */(value),mode=String(source.actionMode||'').trim().toLowerCase();if(!ACTION_MODES.has(mode))throw new Error('resolution.actionMode must be no_action, read_only, or state_change');return/** @type {Resolution} */(freezeData(value,'resolution',0));}
/** @param {unknown} value @returns {Reason} */
function normalizeReason(value){const decision=record(value,'reason decision'),kind=String(decision.kind||'').trim().toLowerCase(),decisionRef=ref(decision.decisionRef,'reason.decisionRef');if(kind==='verify')return Object.freeze({kind:'verify',decisionRef});if(kind!=='act')throw new Error('reason decision.kind must be act or verify');return Object.freeze({kind:'act',decisionRef,action:normalizeAction(decision.action)});}
/** @param {unknown} value @returns {Action} */
function normalizeAction(value){const input=record(value,'action'),effect=String(input.effect||'').trim().toLowerCase();if(!EFFECTS.has(effect))throw new Error('action.effect must be read_only or state_change');const action={actionId:id(input.actionId,'action.actionId'),capability:ref(input.capability,'action.capability'),effect:/** @type {Effect} */(effect),input:input.input,idempotencyKey:input.idempotencyKey==null?null:id(input.idempotencyKey,'action.idempotencyKey')};if(action.effect==='state_change'&&!action.idempotencyKey)throw new Error('state_change action requires an idempotencyKey for M1 replay defense; M3 remains the durable idempotency authority');return Object.freeze(action);}
/** @param {unknown} value @returns {ReadReceipt} */
function normalizeReadReceipt(value){const receipt=record(value,'read receipt'),status=String(receipt.status||'').trim().toLowerCase();if(!READ_RECEIPT_STATUSES.has(status))throw new Error('read receipt.status must be succeeded or failed');if(receipt.retryable!=null&&typeof receipt.retryable!=='boolean')throw new Error('read receipt.retryable must be boolean');return Object.freeze({status:/** @type {'succeeded'|'failed'} */(status),receiptRef:ref(receipt.receiptRef,'read receipt.receiptRef'),retryable:receipt.retryable===true,output:freezeData(receipt.output,'read receipt.output',0)});}
/** @param {unknown} value @returns {ReadObservation} */
function normalizeReadObservation(value){const observation=record(value,'read observation'),effectState=String(observation.effectState||'').trim().toLowerCase();if(!READ_EFFECT_STATES.has(effectState))throw new Error('read observation.effectState must be observed or not_applied');if(typeof observation.progressMade!=='boolean')throw new Error('read observation.progressMade must be boolean');if(observation.retryable!=null&&typeof observation.retryable!=='boolean')throw new Error('read observation.retryable must be boolean');return Object.freeze({observationRef:ref(observation.observationRef,'read observation.observationRef'),effectState:/** @type {'observed'|'not_applied'} */(effectState),progressMade:observation.progressMade,retryable:observation.retryable===true,output:freezeData(observation.output,'read observation.output',0)});}
/** @param {unknown} value @returns {GovernedOutcome} */
function normalizeGovernedOutcome(value){const outcome=record(value,'governed execution outcome'),state=String(outcome.state||'').trim().toLowerCase(),effectState=outcome.effectState==null?null:String(outcome.effectState).trim().toLowerCase();if(!GOVERNED_STATES.has(state))throw new Error('governed execution state is unsupported');if(effectState!=null&&!['applied','not_applied','unknown'].includes(effectState))throw new Error('governed outcome.effectState is invalid');if(typeof outcome.progressMade!=='boolean')throw new Error('governed outcome.progressMade must be boolean');if(outcome.retryable!=null&&typeof outcome.retryable!=='boolean')throw new Error('governed outcome.retryable must be boolean');const receiptRef=outcome.receiptRef==null?null:ref(outcome.receiptRef,'governed outcome.receiptRef'),readbackRef=outcome.readbackRef==null?null:ref(outcome.readbackRef,'governed outcome.readbackRef');if(state==='completed'&&(!receiptRef||!readbackRef||!['applied','not_applied'].includes(effectState||'')))throw new Error('completed governed state change requires provider receipt, authoritative readback, and applied/not_applied effect state');if(state==='verification_required'&&!receiptRef)throw new Error('verification_required governed outcome requires a provider/runtime receipt');return Object.freeze({state:/** @type {GovernedOutcome['state']} */(state),receiptRef,readbackRef,effectState:/** @type {GovernedOutcome['effectState']} */(effectState),progressMade:outcome.progressMade,retryable:outcome.retryable===true,summary:outcome.summary==null?null:text(outcome.summary,'governed outcome.summary',1000),policyRef:outcome.policyRef==null?null:ref(outcome.policyRef,'governed outcome.policyRef'),output:freezeData(outcome.output,'governed outcome.output',0)});}
/** @param {unknown} value @returns {Verification} */
function normalizeVerification(value){const verification=record(value,'verification');if(typeof verification.verified!=='boolean')throw new Error('verification.verified must be boolean');if(typeof verification.progressMade!=='boolean')throw new Error('verification.progressMade must be boolean');if(verification.retryable!=null&&typeof verification.retryable!=='boolean')throw new Error('verification.retryable must be boolean');const verificationReceiptRef=verification.verificationReceiptRef==null?null:ref(verification.verificationReceiptRef,'verification.verificationReceiptRef');return Object.freeze({verified:verification.verified,verificationReceiptRef,summary:verification.summary==null?null:text(verification.summary,'verification.summary',1000),progressMade:verification.progressMade,retryable:verification.retryable===true,output:freezeData(verification.output,'verification.output',0)});}
/** @param {unknown} value @param {string} jobId @param {string} verificationReceiptRef */
function normalizeResultProjection(value,jobId,verificationReceiptRef){const projection=record(value,'activity result projection');if(projection.state!=='result')throw new Error('activity result projection must have state=result');if(projection.jobId!==jobId)throw new Error('activity result projection jobId must match the continuous execution job');if(!Array.isArray(projection.evidenceRefs))throw new Error('activity result projection requires evidenceRefs');const verified=projection.evidenceRefs.some((item)=>{if(!item||typeof item!=='object'||Array.isArray(item))return false;const evidenceItem=/** @type {Record<string,unknown>} */(item);return evidenceItem.type==='verification_receipt'&&evidenceItem.relation==='verification'&&evidenceItem.ref===verificationReceiptRef;});if(!verified)throw new Error('activity result projection must carry the exact overall-job verification receipt');return freezeData(projection,'activity result projection',0);}
/** @param {unknown} value @param {string} field @returns {Record<string,unknown>} */
function record(value,field){if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError(`${field} must be an object`);return/** @type {Record<string,unknown>} */(value);}
/** @param {unknown} value @param {string} field */
function fn(value,field){if(typeof value!=='function')throw new TypeError(`${field} must be a function`);}
/** @param {unknown} value @param {string} field */
function id(value,field){const result=text(value,field,200);if(!OPAQUE.test(result))throw new Error(`${field} must be an opaque identifier`);return result;}
/** @param {unknown} value @param {string} field */
function ref(value,field){return text(value,field,500);}
/** @param {unknown} value @param {string} field @param {number} max */
function text(value,field,max){if(typeof value!=='string'||!value.trim())throw new TypeError(`${field} is required`);const result=value.trim();if(result.length>max)throw new Error(`${field} is too long`);assertNoCredentialLike(result,field);return result;}
/** @param {unknown} value @param {number|undefined} fallback @param {number} min @param {number} max @param {string} field */
function bound(value,fallback,min,max,field){const result=value==null?fallback:value;if(!Number.isInteger(result)||Number(result)<min||Number(result)>max)throw new Error(`${field} must be an integer from ${min} to ${max}`);return Number(result);}
const CREDENTIAL_PATTERNS=[/Authorization\s*:\s*(?:Bearer|Basic)\s+\S+/i,/\bgithub_pat_[A-Za-z0-9_]{20,}\b/,/\bgh[pousr]_[A-Za-z0-9_]{20,}\b/,/\bsk-[A-Za-z0-9_-]{20,}\b/,/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,/(?:postgres(?:ql)?):\/\/[^\s:@]+:[^@\s]+@/i];
/** @param {string} value @param {string} field */
function assertNoCredentialLike(value,field){if(CREDENTIAL_PATTERNS.some((pattern)=>pattern.test(value)))throw new Error(`${field} contains credential-like material`);}
/** @param {unknown} value @param {string} field @param {number} depth @returns {unknown} */
function freezeData(value,field,depth){if(value==null||typeof value==='number'||typeof value==='boolean')return value;if(typeof value==='string'){assertNoCredentialLike(value,field);return value;}if(depth>10)throw new Error(`${field} exceeds maximum nesting depth`);if(Array.isArray(value))return Object.freeze(value.map((item,index)=>freezeData(item,`${field}[${index}]`,depth+1)));if(typeof value!=='object')throw new TypeError(`${field} contains an unsupported value`);const source=/** @type {Record<string,unknown>} */(value),copy=/** @type {Record<string,unknown>} */({});for(const [key,item] of Object.entries(source))copy[key]=freezeData(item,`${field}.${key}`,depth+1);return Object.freeze(copy);}

module.exports={CONTINUOUS_EXECUTION_CONTRACT_VERSION,runContinuousExecution};
