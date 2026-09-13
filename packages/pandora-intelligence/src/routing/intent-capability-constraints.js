'use strict';
const { CAPABILITY_KEYS, EXECUTION_BOUNDARIES } = require('../capabilities/registry.js');
const CONTRACT = 'pandora-intent-capability-resolution-v1';
const AUTHORITY_OWNER = 'pandora-standing-authority-policy-v1';
const ACTIONS = Object.freeze(['no_action', 'read_only', 'state_change']);

/** @param {unknown} v @param {string} n @returns {Record<string, any>} */
function obj(v,n){if(!v||typeof v!=='object'||Array.isArray(v))throw new TypeError(`${n} must be an object`);return /** @type {Record<string, any>} */ (v)}
/** @param {unknown} v @param {string} n @param {readonly string[]} allowed @param {boolean} [nonempty=false] @returns {readonly string[]} */
function arr(v,n,allowed,nonempty=false){if(!Array.isArray(v)||(nonempty&&!v.length))throw new TypeError(`${n} must be an array`);const x=v.map(String);if(new Set(x).size!==x.length||x.some(i=>!allowed.includes(i)))throw new TypeError(`${n} is invalid`);return Object.freeze(x)}
/** @param {readonly string[]} a @param {readonly string[]} b */
function same(a,b){return a.length===b.length&&a.every(x=>b.includes(x))}
/** @param {unknown} v */
function normalizeIntentCapabilityRoutingConstraints(v){
  const r=obj(v,'intentResolution');
  if(r.contractVersion!==CONTRACT)throw new TypeError('unsupported M1 contract');
  if(!ACTIONS.includes(String(r.actionMode)))throw new TypeError('invalid M1 actionMode');
  const risk=obj(r.riskAuthority,'riskAuthority'), privacy=obj(r.privacyExecution,'privacyExecution'), exec=obj(r.executionCharacteristics,'executionCharacteristics'), tools=obj(r.capabilityToolConstraints,'capabilityToolConstraints'), route=obj(r.modelRoutingConstraints,'modelRoutingConstraints');
  if(typeof risk.consequential!=='boolean'||risk.authorityDecisionOwner!==AUTHORITY_OWNER||risk.resolverGrantsAuthority!==false)throw new TypeError('M1 resolver must never grant authority');
  if(!['none_required','explicit_current_or_matching_standing_policy'].includes(String(risk.authorityRequirement)))throw new TypeError('invalid M1 authority requirement');
  if(privacy.resolverClaimsProviderCompliance!==false)throw new TypeError('M1 resolver cannot claim provider compliance');
  const pb=arr(privacy.allowedExecutionBoundaries,'privacy boundaries',EXECUTION_BOUNDARIES,true), rb=arr(route.allowedExecutionBoundaries,'model boundaries',EXECUTION_BOUNDARIES,true);
  if(!same(pb,rb))throw new TypeError('M1 privacy/model boundaries disagree');
  if(route.providerPreference!==null||route.modelPreference!==null||route.modelSelectionOwner!=='M3')throw new TypeError('M1 resolver must not choose provider or model preferences');
  const caps=arr(route.requiredModelCapabilities,'required model capabilities',CAPABILITY_KEYS);
  if(tools.forbidAutomaticProjectCreation!==true||tools.forbidCredentialExposure!==true||tools.providerNeutral!==true||tools.allowedEffectClass!==r.actionMode)throw new TypeError('invalid M1 tool boundary');
  for(const k of ['requireGovernedMutationBoundary','requireReadbackAfterStateChange','reuseIdempotencyOnRetry'])if(typeof tools[k]!=='boolean')throw new TypeError(`invalid ${k}`);
  for(const k of ['requiresDevicePresence','allowCloudReasoning','allowCloudSideEffects'])if(typeof exec[k]!=='boolean')throw new TypeError(`invalid ${k}`);
  if(r.actionMode==='state_change'&&(risk.authorityRequirement!=='explicit_current_or_matching_standing_policy'||!tools.requireGovernedMutationBoundary||!tools.requireReadbackAfterStateChange||!tools.reuseIdempotencyOnRetry))throw new TypeError('state changes require authority, governed mutation, provider readback and idempotency');
  if(exec.allowCloudReasoning===false&&rb.some(x=>x!=='device'))throw new TypeError('cloud reasoning is not allowed');
  return Object.freeze({contractVersion:CONTRACT,requiredModelCapabilities:caps,allowedExecutionBoundaries:rb,actionMode:String(r.actionMode),consequential:risk.consequential,authorityRequirement:String(risk.authorityRequirement),authorityDecisionOwner:AUTHORITY_OWNER,resolverGrantsAuthority:false});
}
/**
 * @param {{get?:(provider:string,model:string)=>Readonly<Record<string,any>>|null,list?:()=>Readonly<Record<string,any>>[]}} registry
 * @param {Record<string,any>} request
 * @param {unknown} resolution
 * @param {Record<string,any>} [options]
 */
function prepareIntentResolvedRouting(registry,request,resolution,options={}){
  const c=normalizeIntentCapabilityRoutingConstraints(resolution), task=String(request.task??'*'), original=Array.isArray(request.requiredCapabilities)?request.requiredCapabilities.map(String):[], required=Object.freeze([...new Set([...original,...c.requiredModelCapabilities])]);
  const base=options.policy&&typeof options.policy==='object'?options.policy:{}, map=base.taskExecutionBoundaries&&typeof base.taskExecutionBoundaries==='object'?base.taskExecutionBoundaries:{}, configured=Array.isArray(map[task])?map[task]:Array.isArray(map['*'])?map['*']:Array.isArray(base.allowedExecutionBoundaries)?base.allowedExecutionBoundaries:[], allowed=configured.length?c.allowedExecutionBoundaries.filter(x=>configured.includes(x)):[...c.allowedExecutionBoundaries];
  if(!allowed.length)throw Object.assign(new Error('no execution boundary satisfies M1 and M3 policy'),{code:'unsupported_capability',retryable:false});
  const policy=Object.freeze({...base,policyVersion:typeof base.policyVersion==='string'&&base.policyVersion?base.policyVersion:'m1-capability-v1',taskExecutionBoundaries:Object.freeze({...map,[task]:Object.freeze(allowed)})});
  let hard=false,s=options.session;
  if(s&&s.stickinessMode!=='unassigned'&&typeof s.provider==='string'&&typeof s.model==='string'){
    let d=typeof registry.get==='function'?registry.get(s.provider,s.model):null;
    if(!d&&typeof registry.list==='function')d=registry.list().find((x)=>x.provider===s.provider&&x.modelId===s.model)||null;
    if(!d)hard=true;else{const b=typeof d.executionBoundary==='string'?d.executionBoundary:'external_provider', mc=d.capabilities&&typeof d.capabilities==='object'?d.capabilities:{};hard=!c.allowedExecutionBoundaries.includes(b)||c.requiredModelCapabilities.some(x=>mc[x]!==true)}
  }
  return Object.freeze({request:Object.freeze({...request,requiredCapabilities:required}),options:Object.freeze({...options,policy,allowRecoveryBoundary:options.allowRecoveryBoundary===true||hard}),constraints:c,hardConstraintRecovery:hard});
}
/** @param {ReturnType<typeof normalizeIntentCapabilityRoutingConstraints>} c @param {boolean} hard */
function intentRoutingAudit(c,hard){return Object.freeze({contractVersion:c.contractVersion,requiredModelCapabilities:c.requiredModelCapabilities,allowedExecutionBoundaries:c.allowedExecutionBoundaries,actionMode:c.actionMode,consequential:c.consequential,authorityRequirement:c.authorityRequirement,authorityDecisionOwner:c.authorityDecisionOwner,resolverGrantsAuthority:false,hardConstraintRecovery:hard===true})}
module.exports={AUTHORITY_DECISION_OWNER:AUTHORITY_OWNER,INTENT_CAPABILITY_CONTRACT_VERSION:CONTRACT,intentRoutingAudit,normalizeIntentCapabilityRoutingConstraints,prepareIntentResolvedRouting};
