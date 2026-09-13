'use strict';

const CONTINUOUS_EXECUTION_CONTRACT_VERSION='pandora-continuous-execution-v1';
const effects=new Set(['read_only','state_change']);
const actionModes=new Set(['no_action','read_only','state_change']);
const decisions=new Set(['auto_execute','standing_authorized','needs_approval','deny']);
const receiptStatuses=new Set(['succeeded','failed','ambiguous']);
const effectStates=new Set(['observed','applied','not_applied','unknown']);
const terminalStatuses=new Set(['result','needs_you','blocked','cancelled','failed']);
const opaque=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;

/** @typedef {'read_only'|'state_change'} Effect */
/** @typedef {{[key:string]:unknown,actionMode?:string}} Resolution */
/** @typedef {{actionId:string,capability:string,effect:Effect,input?:unknown,authorityScopeRef:string|null,idempotencyKey:string|null}} Action */
/** @typedef {{kind:'act',decisionRef:string,action:Action}|{kind:'verify',decisionRef:string}} Reason */
/** @typedef {{status:'succeeded'|'failed'|'ambiguous',receiptRef:string,retryable:boolean,output?:unknown}} ActionReceipt */
/** @typedef {{observationRef:string,effectState:'observed'|'applied'|'not_applied'|'unknown',progressMade:boolean,retryable:boolean,output?:unknown}} Observation */
/** @typedef {{verified:boolean,verificationRef:string,summary:string|null,progressMade:boolean,retryable:boolean,output?:unknown}} Verification */
/** @typedef {{decision:'auto_execute'|'standing_authorized'|'needs_approval'|'deny',decisionRef:string,policyRef:string|null,summary:string|null}} Authority */
/** @typedef {{phase:string,iteration:number,ref:string,actionId:string|null,status:string|null}} Evidence */
/** @typedef {{jobId:string,iteration:number,resolution:Resolution,observations:readonly Observation[],actions:readonly ActionReceipt[],evidence:readonly Evidence[],lastAction:Action|null,lastObservation:Observation|null}} View */
/** @typedef {{jobId:string,resolution:Resolution,maxIterations?:number,maxNoProgressIterations?:number}} Input */
/** @typedef {{reason:(v:View)=>unknown|Promise<unknown>,act:(a:Action,v:View)=>unknown|Promise<unknown>,observe:(x:{action:Action,receipt:ActionReceipt,view:View})=>unknown|Promise<unknown>,verify:(v:View)=>unknown|Promise<unknown>,authorize?:(a:Action,v:View)=>unknown|Promise<unknown>,control?:(x:{jobId:string,iteration:number,phase:string})=>unknown|Promise<unknown>}} Adapters */
/** @typedef {{authorityScopeRef:string,idempotencyKey:string,applied:boolean,mayRetry:boolean}} Mutation */

/** @param {Input} input @param {Adapters} adapters */
async function runContinuousExecution(input,adapters){
  const jobId=id(input?.jobId,'jobId'), resolution=normalizeResolution(input?.resolution);
  if(!adapters||typeof adapters!=='object')throw new TypeError('adapters are required');
  for(const name of ['reason','act','observe','verify'])fn(adapters[/** @type {keyof Adapters} */(name)],`adapters.${name}`);
  if(adapters.authorize!=null)fn(adapters.authorize,'adapters.authorize');
  if(adapters.control!=null)fn(adapters.control,'adapters.control');
  const maxIterations=bound(input.maxIterations,12,1,100,'maxIterations');
  const maxNoProgress=bound(input.maxNoProgressIterations,3,1,20,'maxNoProgressIterations');
  /** @type {Observation[]} */ const observations=[];
  /** @type {ActionReceipt[]} */ const actions=[];
  /** @type {Evidence[]} */ const evidence=[];
  /** @type {Map<string,Mutation>} */ const mutations=new Map();
  /** @type {Action|null} */ let lastAction=null;
  /** @type {Observation|null} */ let lastObservation=null;
  let noProgress=0;

  for(let iteration=1;iteration<=maxIterations;iteration++){
    if(await cancelled(adapters.control,jobId,iteration,'before_reason',evidence))return end(jobId,'cancelled',false,iteration-1,'Execution cancelled by an accepted user control.',evidence,observations,actions,null,null);
    let view=makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation);
    const reason=normalizeReason(await adapters.reason(view));
    evidence.push(ev('reason',iteration,reason.decisionRef,reason.kind==='act'?reason.action.actionId:null,reason.kind));

    if(reason.kind==='verify'){
      if(await cancelled(adapters.control,jobId,iteration,'before_verify',evidence))return end(jobId,'cancelled',false,iteration,'Execution cancelled by an accepted user control.',evidence,observations,actions,null,null);
      view=makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation);
      const verification=normalizeVerification(await adapters.verify(view));
      evidence.push(ev('verify',iteration,verification.verificationRef,null,verification.verified?'verified':'not_verified'));
      if(verification.verified)return end(jobId,'result',true,iteration,verification.summary||'Requested outcome independently verified.',evidence,observations,actions,null,verification);
      if(!verification.retryable)return end(jobId,'blocked',false,iteration,verification.summary||'Verification failed and cannot safely continue.',evidence,observations,actions,block('verification_failed',verification.summary||'Verification failed and cannot safely continue.',verification.verificationRef,null),verification);
      noProgress=verification.progressMade?0:noProgress+1;
      if(noProgress>=maxNoProgress)return end(jobId,'failed',false,iteration,'Execution stopped after repeated verification cycles without evidence of progress.',evidence,observations,actions,block('no_progress','Repeated verification cycles produced no evidence of progress.',verification.verificationRef,null),verification);
      continue;
    }

    const action=reason.action; lastAction=action;
    const widened=effectViolation(action,resolution);
    if(widened)return end(jobId,'blocked',false,iteration,widened.summary,evidence,observations,actions,block(widened.code,widened.summary,reason.decisionRef,null),null);
    const replay=inspectReplay(action,mutations);
    if(replay)return end(jobId,'blocked',false,iteration,replay.summary,evidence,observations,actions,block(replay.code,replay.summary,reason.decisionRef,null),null);

    if(action.effect==='state_change'){
      if(!adapters.authorize)return end(jobId,'blocked',false,iteration,'State-changing execution has no authoritative policy decision adapter.',evidence,observations,actions,block('authority_unavailable','State-changing execution has no authoritative policy decision adapter.',reason.decisionRef,null),null);
      view=makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation);
      const authority=normalizeAuthority(await adapters.authorize(action,view));
      evidence.push(ev('authorize',iteration,authority.decisionRef,action.actionId,authority.decision));
      if(authority.decision==='needs_approval')return end(jobId,'needs_you',false,iteration,authority.summary||'A real authorization boundary requires user approval.',evidence,observations,actions,block('authorization_required',authority.summary||'A real authorization boundary requires user approval.',authority.decisionRef,authority.policyRef),null);
      if(authority.decision==='deny')return end(jobId,'blocked',false,iteration,authority.summary||'Authoritative policy denied this action.',evidence,observations,actions,block('policy_denied',authority.summary||'Authoritative policy denied this action.',authority.decisionRef,authority.policyRef),null);
    }

    if(await cancelled(adapters.control,jobId,iteration,'before_action',evidence))return end(jobId,'cancelled',false,iteration,'Execution cancelled before the next action.',evidence,observations,actions,null,null);
    view=makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation);
    const receipt=normalizeActionReceipt(await adapters.act(action,view)); actions.push(receipt);
    evidence.push(ev('act',iteration,receipt.receiptRef,action.actionId,receipt.status));
    view=makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation);
    const observation=normalizeObservation(await adapters.observe({action,receipt,view}),action.effect); observations.push(observation); lastObservation=observation;
    evidence.push(ev('observe',iteration,observation.observationRef,action.actionId,observation.effectState));

    if(action.effect==='state_change'){
      rememberMutation(action,receipt,observation,mutations);
      if(observation.effectState==='unknown')return end(jobId,'blocked',false,iteration,'State-changing effect is ambiguous after authoritative readback; retry is unsafe.',evidence,observations,actions,block('ambiguous_effect_unresolved','State-changing effect is ambiguous after authoritative readback; retry is unsafe.',observation.observationRef,null),null);
      if(observation.effectState==='not_applied'&&!receipt.retryable&&!observation.retryable)return end(jobId,'blocked',false,iteration,'State-changing action was not applied and is not safely retryable.',evidence,observations,actions,block('state_change_not_applied','State-changing action was not applied and is not safely retryable.',observation.observationRef,null),null);
    }else if(receipt.status!=='succeeded'&&!receipt.retryable&&!observation.retryable){
      return end(jobId,'blocked',false,iteration,'Read-only action failed and is not retryable.',evidence,observations,actions,block('action_failed','Read-only action failed and is not retryable.',observation.observationRef,null),null);
    }

    noProgress=observation.progressMade?0:noProgress+1;
    if(noProgress>=maxNoProgress)return end(jobId,'failed',false,iteration,'Execution stopped after repeated action/observation cycles without evidence of progress.',evidence,observations,actions,block('no_progress','Repeated action/observation cycles produced no evidence of progress.',observation.observationRef,null),null);
    if(await cancelled(adapters.control,jobId,iteration,'after_observation',evidence))return end(jobId,'cancelled',false,iteration,'Execution cancelled after the latest observed state.',evidence,observations,actions,null,null);
  }
  return end(jobId,'failed',false,maxIterations,'Execution reached the bounded iteration limit without a verified result.',evidence,observations,actions,block('iteration_limit','Execution reached the bounded iteration limit without a verified result.',evidence.at(-1)?.ref||null,null),null);
}

/** @param {Action} action @param {Resolution} resolution */
function effectViolation(action,resolution){
  const mode=String(resolution.actionMode);
  if(action.effect==='state_change'&&mode!=='state_change')return{code:'effect_class_widened',summary:'Reasoning attempted to widen the resolved action effect into a state change.'};
  if(action.effect==='read_only'&&mode==='no_action')return{code:'effect_class_widened',summary:'Reasoning attempted to execute an action for a no-action resolution.'};
  return null;
}
/** @param {Action} action @param {Map<string,Mutation>} mutations */
function inspectReplay(action,mutations){
  if(action.effect!=='state_change')return null;
  const scope=ref(action.authorityScopeRef,'action.authorityScopeRef'),key=id(action.idempotencyKey,'action.idempotencyKey'),prior=mutations.get(action.actionId);
  if(!prior)return null;
  if(prior.applied)return{code:'duplicate_state_change',summary:'A state-changing action already has verified applied effect and will not be executed again.'};
  if(!prior.mayRetry)return{code:'retry_not_authorized',summary:'The prior state-changing attempt is not safely retryable.'};
  if(prior.authorityScopeRef!==scope)return{code:'authority_scope_changed',summary:'A retry attempted to widen or change its authority scope.'};
  if(prior.idempotencyKey!==key)return{code:'idempotency_identity_changed',summary:'A state-changing retry must reuse the original idempotency identity.'};
  return null;
}
/** @param {Action} a @param {ActionReceipt} r @param {Observation} o @param {Map<string,Mutation>} mutations */
function rememberMutation(a,r,o,mutations){mutations.set(a.actionId,Object.freeze({authorityScopeRef:ref(a.authorityScopeRef,'action.authorityScopeRef'),idempotencyKey:id(a.idempotencyKey,'action.idempotencyKey'),applied:o.effectState==='applied',mayRetry:o.effectState==='not_applied'&&(r.retryable||o.retryable)}));}
/** @param {Adapters['control']} control @param {string} jobId @param {number} iteration @param {string} phase @param {Evidence[]} evidence */
async function cancelled(control,jobId,iteration,phase,evidence){if(!control)return false;const x=record(await control({jobId,iteration,phase}),'control receipt');if(typeof x.cancelled!=='boolean')throw new Error('control.cancelled must be boolean');if(!x.cancelled)return false;const r=ref(x.controlRef,'control.controlRef');evidence.push(ev('control',iteration,r,null,'cancelled'));return true;}
/** @param {string} jobId @param {number} iteration @param {Resolution} resolution @param {Observation[]} observations @param {ActionReceipt[]} actions @param {Evidence[]} evidence @param {Action|null} lastAction @param {Observation|null} lastObservation @returns {View} */
function makeView(jobId,iteration,resolution,observations,actions,evidence,lastAction,lastObservation){return Object.freeze({jobId,iteration,resolution,observations:Object.freeze([...observations]),actions:Object.freeze([...actions]),evidence:Object.freeze([...evidence]),lastAction,lastObservation});}
/** @param {string} phase @param {number} iteration @param {string} r @param {string|null} actionId @param {string|null} status @returns {Evidence} */
function ev(phase,iteration,r,actionId,status){return Object.freeze({phase,iteration,ref:ref(r,'evidence.ref'),actionId,status});}
/** @param {string} code @param {string} summary @param {string|null} evidenceRef @param {string|null} policyRef */
function block(code,summary,evidenceRef,policyRef){return Object.freeze({reasonCode:id(code,'blocker.reasonCode'),summary:text(summary,'blocker.summary',1000),evidenceRef:evidenceRef==null?null:ref(evidenceRef,'blocker.evidenceRef'),policyRef:policyRef==null?null:ref(policyRef,'blocker.policyRef')});}
/** @param {string} jobId @param {string} status @param {boolean} verified @param {number} iterations @param {string} summary @param {Evidence[]} evidence @param {Observation[]} observations @param {ActionReceipt[]} actions @param {unknown} blocker @param {Verification|null} verification */
function end(jobId,status,verified,iterations,summary,evidence,observations,actions,blocker,verification){if(!terminalStatuses.has(status))throw new Error('invalid terminal status');return Object.freeze({contractVersion:CONTINUOUS_EXECUTION_CONTRACT_VERSION,jobId,status,verified,iterations,summary:text(summary,'summary',1000),evidence:Object.freeze([...evidence]),observations:Object.freeze([...observations]),actions:Object.freeze([...actions]),blocker,verification});}

/** @param {unknown} x @returns {Resolution} */
function normalizeResolution(x){if(!x||typeof x!=='object'||Array.isArray(x))throw new TypeError('resolution is required');const source=/** @type {Resolution} */(x),mode=String(source.actionMode||'').trim().toLowerCase();if(!actionModes.has(mode))throw new Error('resolution.actionMode must be no_action, read_only, or state_change');return/** @type {Resolution} */(freezeData(x,'resolution',0));}
/** @param {unknown} x @returns {Reason} */
function normalizeReason(x){const v=record(x,'reason decision'),kind=String(v.kind||'').trim().toLowerCase(),decisionRef=ref(v.decisionRef,'reason.decisionRef');if(kind==='verify')return Object.freeze({kind:'verify',decisionRef});if(kind!=='act')throw new Error('reason decision.kind must be act or verify');return Object.freeze({kind:'act',decisionRef,action:normalizeAction(v.action)});}
/** @param {unknown} x @returns {Action} */
function normalizeAction(x){const v=record(x,'action'),effect=String(v.effect||'').trim().toLowerCase();if(!effects.has(effect))throw new Error('action.effect must be read_only or state_change');const a={actionId:id(v.actionId,'action.actionId'),capability:ref(v.capability,'action.capability'),effect:/** @type {Effect} */(effect),input:v.input,authorityScopeRef:v.authorityScopeRef==null?null:ref(v.authorityScopeRef,'action.authorityScopeRef'),idempotencyKey:v.idempotencyKey==null?null:id(v.idempotencyKey,'action.idempotencyKey')};if(a.effect==='state_change'&&(!a.authorityScopeRef||!a.idempotencyKey))throw new Error('state_change action requires authorityScopeRef and idempotencyKey');return Object.freeze(a);}
/** @param {unknown} x @returns {Authority} */
function normalizeAuthority(x){const v=record(x,'authority receipt'),d=String(v.decision||'').trim().toLowerCase();if(!decisions.has(d))throw new Error('unsupported authority decision');const a={decision:/** @type {Authority['decision']} */(d),decisionRef:ref(v.decisionRef,'authority.decisionRef'),policyRef:v.policyRef==null?null:ref(v.policyRef,'authority.policyRef'),summary:v.summary==null?null:text(v.summary,'authority.summary',1000)};if((d==='needs_approval'||d==='deny')&&!a.policyRef)throw new Error(`${d} requires policyRef`);return Object.freeze(a);}
/** @param {unknown} x @returns {ActionReceipt} */
function normalizeActionReceipt(x){const v=record(x,'action receipt'),s=String(v.status||'').trim().toLowerCase();if(!receiptStatuses.has(s))throw new Error('unsupported action receipt status');boolOpt(v.retryable,'action receipt retryable');return Object.freeze({status:/** @type {ActionReceipt['status']} */(s),receiptRef:ref(v.receiptRef,'action receipt.ref'),retryable:v.retryable===true,output:v.output});}
/** @param {unknown} x @param {Effect} effect @returns {Observation} */
function normalizeObservation(x,effect){const v=record(x,'observation receipt'),s=String(v.effectState||'').trim().toLowerCase();if(!effectStates.has(s))throw new Error('unsupported observation effectState');if(typeof v.progressMade!=='boolean')throw new Error('observation progressMade must be boolean');boolOpt(v.retryable,'observation retryable');if(effect==='state_change'&&!['applied','not_applied','unknown'].includes(s))throw new Error('state_change observation must be applied, not_applied, or unknown');if(effect==='read_only'&&s!=='observed')throw new Error('read_only observation must use effectState=observed');return Object.freeze({observationRef:ref(v.observationRef,'observation.ref'),effectState:/** @type {Observation['effectState']} */(s),progressMade:v.progressMade,retryable:v.retryable===true,output:v.output});}
/** @param {unknown} x @returns {Verification} */
function normalizeVerification(x){const v=record(x,'verification receipt');if(typeof v.verified!=='boolean')throw new Error('verification.verified must be boolean');boolOpt(v.progressMade,'verification.progressMade');boolOpt(v.retryable,'verification.retryable');return Object.freeze({verified:v.verified,verificationRef:ref(v.verificationRef,'verification.ref'),summary:v.summary==null?null:text(v.summary,'verification.summary',1000),progressMade:v.progressMade===true,retryable:v.retryable===true,output:v.output});}
/** @param {unknown} x @param {string} field @returns {Record<string,unknown>} */
function record(x,field){if(!x||typeof x!=='object'||Array.isArray(x))throw new TypeError(`${field} must be an object`);return/** @type {Record<string,unknown>} */(x);}
/** @param {unknown} x @param {string} field */
function fn(x,field){if(typeof x!=='function')throw new TypeError(`${field} must be a function`);}
/** @param {unknown} x @param {string} field */
function id(x,field){if(typeof x!=='string'||!opaque.test(x.trim()))throw new Error(`${field} must be a bounded opaque identifier`);return x.trim();}
/** @param {unknown} x @param {string} field */
function ref(x,field){if(typeof x!=='string')throw new Error(`${field} must be a string`);const s=x.trim();if(!s||s.length>500)throw new Error(`${field} is invalid`);if(/authorization\s*:\s*(?:bearer|basic)|github_pat_|\bgh[pousr]_|-----BEGIN .*PRIVATE KEY-----|postgres(?:ql)?:\/\/[^\s:@]+:[^@\s]+@/i.test(s))throw new Error(`${field} contains credential-like material`);return s;}
/** @param {unknown} x @param {string} field @param {number} max */
function text(x,field,max){if(typeof x!=='string')throw new Error(`${field} must be a string`);const s=x.trim();if(!s||s.length>max)throw new Error(`${field} is invalid`);return s;}
/** @param {unknown} x @param {string} field */
function boolOpt(x,field){if(x!=null&&typeof x!=='boolean')throw new Error(`${field} must be boolean`);}
/** @param {unknown} x @param {number} fallback @param {number} min @param {number} max @param {string} field */
function bound(x,fallback,min,max,field){if(x==null)return fallback;if(!Number.isSafeInteger(x)||Number(x)<min||Number(x)>max)throw new Error(`${field} must be an integer from ${min} to ${max}`);return Number(x);}
/** @param {unknown} x @param {string} field @param {number} depth @returns {unknown} */
function freezeData(x,field,depth){if(depth>20)throw new Error(`${field} exceeds maximum nesting depth`);if(x==null||typeof x==='string'||typeof x==='boolean')return x;if(typeof x==='number'){if(!Number.isFinite(x))throw new Error(`${field} contains a non-finite number`);return x;}if(Array.isArray(x))return Object.freeze(x.map((v,i)=>freezeData(v,`${field}[${i}]`,depth+1)));if(typeof x!=='object')throw new Error(`${field} must contain JSON-like data only`);const p=Object.getPrototypeOf(x);if(p!==Object.prototype&&p!==null)throw new Error(`${field} must contain plain objects only`);const out=/** @type {Record<string,unknown>} */({});for(const [k,v] of Object.entries(/** @type {Record<string,unknown>} */(x)))out[k]=freezeData(v,`${field}.${k}`,depth+1);return Object.freeze(out);}

module.exports={CONTINUOUS_EXECUTION_CONTRACT_VERSION,runContinuousExecution};
