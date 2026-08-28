'use strict';
const PROJECT_SPEC_VERSION='1.0';
const PROJECT_TYPES=Object.freeze(['website','web_application','mobile_application','system','api','automation','other']);
const PLATFORMS=Object.freeze(['web','ios','android','desktop','server']);
/** @param {unknown} value */ function isRecord(value){return !!value&&typeof value==='object'&&!Array.isArray(value);}
/** @param {unknown} value @param {string} field @param {string[]} errors @param {boolean} required */ function validateString(value,field,errors,required=false){if(value===undefined||value===null||value===''){if(required)errors.push(`${field} is required`);return;}if(typeof value!=='string')errors.push(`${field} must be a string`);}
/** @param {unknown} value @param {string} field @param {string[]} errors */ function validateStringArray(value,field,errors){if(value==null)return;if(!Array.isArray(value)){errors.push(`${field} must be an array`);return;}value.forEach((item,index)=>{if(typeof item!=='string'||item.trim()==='')errors.push(`${field}[${index}] must be a non-empty string`);});}
/** @param {unknown} value @param {string} field @param {string[]} errors */ function requireRecord(value,field,errors){if(!isRecord(value)){errors.push(`${field} must be an object`);return {};}return /** @type {Record<string, unknown>} */(value);}
/** @param {unknown} candidate */
function validateProjectSpecCandidate(candidate){
  /** @type {string[]} */ const errors=[];
  if(!isRecord(candidate))return{ok:false,errors:['ProjectSpec candidate must be an object'],value:null};
  const root=/** @type {Record<string, unknown>} */(candidate);
  if(root.version!==PROJECT_SPEC_VERSION)errors.push(`version must equal ${PROJECT_SPEC_VERSION}`);
  const business=requireRecord(root.business,'business',errors);validateString(business.objective,'business.objective',errors,true);validateString(business.expectedOutcome,'business.expectedOutcome',errors);validateString(business.successMetric,'business.successMetric',errors);validateString(business.baseline,'business.baseline',errors);validateString(business.target,'business.target',errors);validateStringArray(business.constraints,'business.constraints',errors);
  const product=requireRecord(root.product,'product',errors);if(!PROJECT_TYPES.includes(String(product.projectType??'')))errors.push(`product.projectType must be one of: ${PROJECT_TYPES.join(', ')}`);['users','roles','workflows','features','screens','userStories'].forEach(k=>validateStringArray(product[k],`product.${k}`,errors));
  const data=requireRecord(root.data,'data',errors);validateNamedEntityArray(data.entities,'data.entities',errors);validateNamedEntityArray(data.relationships,'data.relationships',errors,true);validateString(data.authentication,'data.authentication',errors);validateString(data.storage,'data.storage',errors);validateString(data.retention,'data.retention',errors);
  const integrations=requireRecord(root.integrations,'integrations',errors);['payment','messaging','analytics','externalApis','providerRequirements'].forEach(k=>validateStringArray(integrations[k],`integrations.${k}`,errors));
  const design=requireRecord(root.design,'design',errors);validateString(design.visualDirection,'design.visualDirection',errors);validateStringArray(design.brandRequirements,'design.brandRequirements',errors);validateStringArray(design.accessibility,'design.accessibility',errors);validateStringArray(design.platforms,'design.platforms',errors);if(Array.isArray(design.platforms))design.platforms.forEach((p,i)=>{if(typeof p==='string'&&!PLATFORMS.includes(p))errors.push(`design.platforms[${i}] is unsupported`);});if(design.responsive!==undefined&&typeof design.responsive!=='boolean')errors.push('design.responsive must be a boolean');
  const deployment=requireRecord(root.deployment,'deployment',errors);['preview','production','domain','runtime','geography'].forEach(k=>validateString(deployment[k],`deployment.${k}`,errors));
  const acceptance=requireRecord(root.acceptance,'acceptance',errors);validateStringArray(acceptance.functional,'acceptance.functional',errors);validateStringArray(acceptance.business,'acceptance.business',errors);if(!Array.isArray(acceptance.functional)||acceptance.functional.length===0)errors.push('acceptance.functional must contain at least one criterion');
  const allowed=new Set(['version','business','product','data','integrations','design','deployment','acceptance','metadata']);for(const key of Object.keys(root))if(!allowed.has(key))errors.push(`unknown top-level ProjectSpec field: ${key}`);
  return errors.length===0?{ok:true,errors:[],value:root}:{ok:false,errors,value:null};
}
/** @param {unknown} value @param {string} field @param {string[]} errors @param {boolean} relationship */
function validateNamedEntityArray(value,field,errors,relationship=false){if(value==null)return;if(!Array.isArray(value)){errors.push(`${field} must be an array`);return;}value.forEach((item,index)=>{if(!isRecord(item)){errors.push(`${field}[${index}] must be an object`);return;}const record=/** @type {Record<string, unknown>} */(item);validateString(record.name,`${field}[${index}].name`,errors,true);if(relationship){validateString(record.from,`${field}[${index}].from`,errors,true);validateString(record.to,`${field}[${index}].to`,errors,true);}});}
module.exports={PLATFORMS,PROJECT_SPEC_VERSION,PROJECT_TYPES,validateProjectSpecCandidate};
