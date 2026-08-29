'use strict';
const { digest } = require('./registry');

const OWNERSHIP = Object.freeze(['primitive-core','customer-owned','extension-point']);
const SECRET_FIELD=/(?:secret|token|password|authorization|cookie|private.?key|service.?role|api.?key)/i;

function planPrimitiveMaterialization({manifest,sourceFiles,currentFiles=[],migrationPlan=null}={}){
  if(!manifest||typeof manifest!=='object'||!Array.isArray(manifest.primitives))throw new TypeError('composition manifest required');
  if(!Array.isArray(sourceFiles))throw new TypeError('sourceFiles must be an array');
  if(!Array.isArray(currentFiles))throw new TypeError('currentFiles must be an array');
  const selected=new Map(manifest.primitives.map(p=>[p.name,p])); const existing=new Map();
  for(const f of currentFiles){validateFile(f,'current');if(existing.has(f.path))throw new Error(`duplicate current file ${f.path}`);existing.set(f.path,f);}
  const paths=new Set(); const actions=[]; const collisions=[];
  for(const file of sourceFiles){validateFile(file,'source');if(paths.has(file.path))throw new Error(`duplicate source file ${file.path}`);paths.add(file.path);
    const primitive=selected.get(file.primitive);if(!primitive)throw new Error(`file ${file.path} references primitive outside composition`);
    const ownership=file.ownership||'primitive-core';if(!OWNERSHIP.includes(ownership))throw new TypeError(`invalid ownership for ${file.path}`);
    const prior=existing.get(file.path)||null; const nextDigest=requiredDigest(file.contentDigest,'contentDigest');
    if(!prior){actions.push(action('CREATE',file,primitive,{nextDigest,ownership}));continue;}
    const priorDigest=requiredDigest(prior.contentDigest,'current contentDigest');
    if(ownership==='customer-owned'){actions.push(action('PRESERVE',file,primitive,{nextDigest:priorDigest,ownership,reason:'customer-owned'}));continue;}
    if(ownership==='extension-point'){
      if(prior.basePrimitiveDigest&&file.basePrimitiveDigest&&prior.basePrimitiveDigest===file.basePrimitiveDigest){actions.push(action('PRESERVE',file,primitive,{nextDigest:priorDigest,ownership,reason:'custom-extension'}));}
      else {collisions.push(collision(file,prior,'extension-base-changed'));}
      continue;
    }
    if(prior.basePrimitiveDigest&&prior.basePrimitiveDigest!==priorDigest&&priorDigest!==nextDigest){collisions.push(collision(file,prior,'primitive-core-modified-by-customer'));continue;}
    actions.push(action(priorDigest===nextDigest?'NOOP':'REPLACE',file,primitive,{nextDigest,ownership}));
  }
  for(const prior of currentFiles)if(!paths.has(prior.path)){
    const ownership=prior.ownership||'customer-owned';
    if(ownership==='customer-owned'||ownership==='extension-point')actions.push(Object.freeze({type:'PRESERVE',path:prior.path,primitive:prior.primitive||null,ownership,contentDigest:requiredDigest(prior.contentDigest,'current contentDigest'),reason:'not-owned-by-new-primitive'}));
    else collisions.push(Object.freeze({path:prior.path,primitive:prior.primitive||null,reason:'primitive-core-removed',currentDigest:requiredDigest(prior.contentDigest,'current contentDigest'),nextDigest:null}));
  }
  const sortedActions=actions.sort((a,b)=>a.path.localeCompare(b.path)); const sortedCollisions=collisions.sort((a,b)=>a.path.localeCompare(b.path));
  const planBase={schemaVersion:'1.0',projectId:required(manifest.projectId,'manifest.projectId'),projectVersionId:required(manifest.projectVersionId,'manifest.projectVersionId'),manifestDigest:requiredDigest(manifest.manifestDigest,'manifest.manifestDigest'),actions:sortedActions,collisions:sortedCollisions,migrations:migrationPlan&&Array.isArray(migrationPlan.steps)?migrationPlan.steps.map(s=>({name:s.name,fromVersion:s.fromVersion,toVersion:s.toVersion,decision:s.decision,stepDigest:s.stepDigest})):[]};
  const decision=sortedCollisions.length?'MANUAL_REVIEW':migrationPlan&&migrationPlan.decision==='BLOCKED'?'BLOCKED':migrationPlan&&migrationPlan.decision==='MANUAL_REVIEW'?'MANUAL_REVIEW':'READY';
  return Object.freeze({...planBase,decision,planDigest:digest({...planBase,decision})});
}

function validateEventCompatibility(definitions){
  if(!Array.isArray(definitions))throw new TypeError('definitions must be an array');const seen=new Map(),errors=[];
  for(const d of definitions)for(const e of d.events||[]){if(!e||typeof e.name!=='string'||typeof e.version!=='string'||!/^\d+\.\d+$/.test(e.version)){errors.push(`${d.name||'primitive'} has invalid event contract`);continue;}const major=Number(e.version.split('.')[0]);const existing=seen.get(e.name);if(existing&&existing.major!==major)errors.push(`event ${e.name} has incompatible majors ${existing.major} and ${major}`);else if(!existing)seen.set(e.name,{major,producer:d.name||null});}
  return Object.freeze({ok:errors.length===0,errors:Object.freeze(errors)});
}

function planExecutionBoundaries(steps){
  if(!Array.isArray(steps)||steps.length===0)throw new TypeError('steps are required');const groups=[];let current=null;
  for(const raw of steps){if(!raw||typeof raw!=='object')throw new TypeError('execution step must be object');const step={id:required(raw.id,'step.id'),provider:required(raw.provider,'step.provider'),transactional:raw.transactional===true,compensation:raw.compensation||null};if(step.compensation&&typeof step.compensation!=='string')throw new TypeError(`compensation for ${step.id} must be an action id`);
    if(!current||!step.transactional||!current.transactional||current.provider!==step.provider){current={provider:step.provider,transactional:step.transactional,steps:[]};groups.push(current);}current.steps.push(step);
  }
  const crossProvider=groups.length>1;const errors=[];if(crossProvider)for(const g of groups)for(const s of g.steps)if(!s.transactional&&!s.compensation)errors.push(`non-transactional cross-boundary step ${s.id} requires compensation`);
  const normalized=groups.map(g=>Object.freeze({provider:g.provider,transactional:g.transactional,steps:Object.freeze(g.steps.map(Object.freeze))}));
  return Object.freeze({ok:errors.length===0,errors:Object.freeze(errors),groups:Object.freeze(normalized),requiresSaga:crossProvider,planDigest:digest({groups:normalized})});
}

function buildWorkerDMaterializationRequest({manifest,materializationPlan,runtimeBindings={}}={}){
  if(!manifest||!materializationPlan)throw new TypeError('manifest and materializationPlan are required');
  if(materializationPlan.decision==='BLOCKED'||materializationPlan.collisions&&materializationPlan.collisions.length)throw new Error('materialization is not executable');
  rejectSecrets(runtimeBindings);
  const request={schemaVersion:'1.0',projectId:required(manifest.projectId,'manifest.projectId'),projectVersionId:required(manifest.projectVersionId,'manifest.projectVersionId'),compositionManifestDigest:requiredDigest(manifest.manifestDigest,'manifest.manifestDigest'),materializationPlanDigest:requiredDigest(materializationPlan.planDigest,'materializationPlan.planDigest'),runtimeBindings:sortObject(runtimeBindings),actions:materializationPlan.actions.map(a=>({type:a.type,path:a.path,primitive:a.primitive,contentDigest:a.contentDigest,ownership:a.ownership})),migrations:materializationPlan.migrations||[]};
  return Object.freeze({...request,requestDigest:digest(request)});
}
function action(type,file,primitive,{nextDigest,ownership,reason=null}){return Object.freeze({type,path:file.path,primitive:file.primitive,primitiveVersion:primitive.version,primitiveSourceDigest:primitive.sourceDigest||null,contentDigest:nextDigest,ownership,basePrimitiveDigest:file.basePrimitiveDigest||null,customizationDigest:file.customizationDigest||null,reason});}
function collision(file,prior,reason){return Object.freeze({path:file.path,primitive:file.primitive,reason,currentDigest:requiredDigest(prior.contentDigest,'current contentDigest'),nextDigest:requiredDigest(file.contentDigest,'contentDigest')});}
function validateFile(f,label){if(!f||typeof f!=='object')throw new TypeError(`${label} file must be object`);required(f.path,`${label} file path`);if(f.path.startsWith('/')||f.path.includes('..'))throw new Error(`unsafe file path ${f.path}`);}
function requiredDigest(v,f){if(typeof v!=='string'||!/^sha256:[0-9a-f]{64}$/.test(v))throw new TypeError(`${f} must be immutable sha256 digest`);return v;}
function required(v,f){if(typeof v!=='string'||!v.trim())throw new TypeError(`${f} is required`);return v.trim();}
function rejectSecrets(value,path='runtimeBindings'){if(!value||typeof value!=='object')return;for(const [k,v] of Object.entries(value)){if(SECRET_FIELD.test(k))throw new Error(`${path}.${k} may not contain raw secret material`);if(v&&typeof v==='object')rejectSecrets(v,`${path}.${k}`);}}
function sortObject(v){if(Array.isArray(v))return v.map(sortObject);if(!v||typeof v!=='object')return v;return Object.fromEntries(Object.keys(v).sort().map(k=>[k,sortObject(v[k])]));}
module.exports={OWNERSHIP,buildWorkerDMaterializationRequest,planExecutionBoundaries,planPrimitiveMaterialization,validateEventCompatibility};
