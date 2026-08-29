'use strict';
const { compareVersions, parseVersion } = require('./semver');
const { digest } = require('./registry');

const UPGRADE_DECISIONS = Object.freeze(['AUTO','MANUAL_REVIEW','BLOCKED']);
const ACTIVE_TRUST = new Set(['TRUSTED','EXPERIMENTAL','DEPRECATED','BLOCKED']);

function planPrimitiveUpgrades(registry,{currentManifest,targets,migrations=[],now=new Date().toISOString(),requireTrustedForAuto=true}={}){
  if(!registry||typeof registry.getExact!=='function')throw new TypeError('registry.getExact is required');
  if(!currentManifest||typeof currentManifest!=='object'||!Array.isArray(currentManifest.primitives))throw new TypeError('currentManifest.primitives is required');
  if(!Array.isArray(targets)||targets.length===0)throw new TypeError('targets must contain exact primitive versions');
  const current=new Map(currentManifest.primitives.map(p=>[required(p.name,'current primitive name'),p]));
  const targetNames=new Set(); const steps=[]; const errors=[];
  for(const target of targets){
    if(!target||typeof target!=='object'){errors.push('upgrade target must be an object');continue;}
    const name=required(target.name,'target.name'); const toVersion=exactVersion(target.version,'target.version');
    if(targetNames.has(name)){errors.push(`duplicate upgrade target for ${name}`);continue;} targetNames.add(name);
    const from=current.get(name); if(!from){errors.push(`${name} is not present in current manifest`);continue;}
    const fromVersion=exactVersion(from.version,'current version'); const cmp=compareVersions(toVersion,fromVersion);
    if(cmp===0){errors.push(`${name} target must differ from current version`);continue;}
    if(cmp<0){errors.push(`${name} downgrade ${fromVersion} -> ${toVersion} is not allowed`);continue;}
    const definition=registry.getExact(name,toVersion); if(!definition){errors.push(`unknown primitive ${name}@${toVersion}`);continue;}
    if(!ACTIVE_TRUST.has(definition.trustState))errors.push(`${name}@${toVersion} has invalid trust state`);
    const applicable=validateMigrationChain(name,fromVersion,toVersion,migrations.filter(m=>m&&m.name===name),errors);
    const fromParsed=parseVersion(fromVersion),toParsed=parseVersion(toVersion);
    const securityDeadline=definition.securityDeadline||target.securityDeadline||null;
    const deadlineExpired=securityDeadline?new Date(securityDeadline).getTime()<=new Date(now).getTime():false;
    let decision='AUTO'; const reasons=[];
    if(definition.trustState==='BLOCKED'){decision='BLOCKED';reasons.push('target-blocked');}
    else {
      if(requireTrustedForAuto&&definition.trustState!=='TRUSTED'){decision='MANUAL_REVIEW';reasons.push(`target-${String(definition.trustState).toLowerCase()}`);}
      if(fromParsed.major!==toParsed.major){decision='MANUAL_REVIEW';reasons.push('major-version-change');}
      if(applicable.some(m=>m.reversible!==true&&typeof m.forwardFix!=='string')){decision='MANUAL_REVIEW';reasons.push('irreversible-migration');}
      if(definition.trustState==='DEPRECATED'){decision='MANUAL_REVIEW';reasons.push('target-deprecated');}
      if(deadlineExpired)reasons.push('security-deadline-reached');
    }
    const stepBase={name,fromVersion,toVersion,decision,reasons:[...new Set(reasons)].sort(),targetTrustState:definition.trustState,targetSourceDigest:definition.sourceDigest||null,targetDefinitionDigest:definition.definitionDigest||null,deprecation:definition.deprecation||null,replacement:definition.replacement||null,securityDeadline,migrations:applicable.map(m=>({id:m.id,fromVersion:m.fromVersion,toVersion:m.toVersion,digest:m.digest,reversible:m.reversible===true,rollback:m.rollback||null,forwardFix:m.forwardFix||null}))};
    steps.push(Object.freeze({...stepBase,stepDigest:digest(stepBase)}));
  }
  if(errors.length)return Object.freeze({ok:false,errors:Object.freeze(errors),plan:null});
  const planBase={schemaVersion:'1.0',projectId:required(currentManifest.projectId,'currentManifest.projectId'),projectVersionId:required(currentManifest.projectVersionId,'currentManifest.projectVersionId'),fromManifestDigest:required(currentManifest.manifestDigest,'currentManifest.manifestDigest'),createdAt:now,steps:steps.sort((a,b)=>a.name.localeCompare(b.name))};
  const overall=steps.some(s=>s.decision==='BLOCKED')?'BLOCKED':steps.some(s=>s.decision==='MANUAL_REVIEW')?'MANUAL_REVIEW':'AUTO';
  return Object.freeze({ok:true,errors:Object.freeze([]),plan:Object.freeze({...planBase,decision:overall,planDigest:digest({...planBase,decision:overall})})});
}

function validateMigrationChain(name,fromVersion,toVersion,migrations,errors){
  const sorted=[...migrations].sort((a,b)=>compareVersions(a.fromVersion,b.fromVersion)||compareVersions(a.toVersion,b.toVersion));
  let cursor=fromVersion; const used=[];
  while(compareVersions(cursor,toVersion)<0){
    const candidates=sorted.filter(m=>m.fromVersion===cursor&&compareVersions(m.toVersion,toVersion)<=0);
    if(candidates.length===0){errors.push(`${name} migration chain has a gap after ${cursor}`);return used;}
    if(candidates.length>1){errors.push(`${name} migration chain is ambiguous after ${cursor}`);return used;}
    const m=candidates[0];
    if(typeof m.id!=='string'||!m.id.trim())errors.push(`${name} migration id is required`);
    if(typeof m.digest!=='string'||!/^sha256:[0-9a-f]{64}$/.test(m.digest))errors.push(`${name} migration ${m.id||'?'} requires immutable sha256 digest`);
    exactVersion(m.fromVersion,'migration.fromVersion'); exactVersion(m.toVersion,'migration.toVersion');
    if(compareVersions(m.toVersion,m.fromVersion)<=0)errors.push(`${name} migration ${m.id||'?'} must move forward`);
    used.push(m); cursor=m.toVersion;
  }
  if(cursor!==toVersion)errors.push(`${name} migration chain did not terminate at ${toVersion}`);
  return used;
}

function exactVersion(value,field){if(value==='latest')throw new TypeError(`${field} may not use latest`);return parseVersion(value).raw;}
function required(value,field){if(typeof value!=='string'||!value.trim())throw new TypeError(`${field} is required`);return value.trim();}
module.exports={UPGRADE_DECISIONS,planPrimitiveUpgrades,validateMigrationChain};
