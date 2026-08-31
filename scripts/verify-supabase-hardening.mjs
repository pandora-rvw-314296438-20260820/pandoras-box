import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
const root='ops/supabase/hardening';
const registry=JSON.parse(await readFile(path.join(root,'edge-function-lifecycle-registry.json'),'utf8'));
const advisor=JSON.parse(await readFile(path.join(root,'security-advisor-dispositions.json'),'utf8'));
const boundary=JSON.parse(await readFile(path.join(root,'plane-boundary-policy.json'),'utf8'));
const allowed=new Set(['CORE','BROKER','WEBHOOK','ADMIN','RECOVERY','TEMPORARY','LEGACY']); const seen=new Set();
for(const fn of registry.functions){const key=fn.plane+'/'+fn.slug;if(seen.has(key))throw new Error('duplicate '+key);seen.add(key);for(const f of ['projectRef','slug','class','decision','purpose','authModel','owner','callerEvidence','observedAt'])if(!fn[f])throw new Error('missing '+f+' for '+key);if(!allowed.has(fn.class))throw new Error('invalid class '+fn.class);if(fn.intentionalActive!==true)throw new Error('active function lacks intentionalActive=true: '+key);if(fn.decision==='KEEP_REVIEWED')throw new Error('unexplained lifecycle decision: '+key);}
if(!advisor.dispositions?.length)throw new Error('advisor dispositions missing');for(const d of advisor.dispositions)if(!d.objects?.length||!d.disposition||!d.compatibilityEvidence||!d.remediation||!d.rollback)throw new Error('incomplete advisor '+d.plane+'/'+d.advisor);
const secondary=registry.projects.secondary;if(!boundary.simpleMode.forbiddenDirectProjectRefs.includes(secondary))throw new Error('secondary plane not forbidden');
async function files(dir){const out=[];for(const e of await readdir(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory())out.push(...await files(p));else if(e.isFile()&&/\.(?:dart|json|ya?ml|js|mjs|ts|html)$/.test(e.name))out.push(p)}return out}
for(const f of await files('apps/pandora-mobile')){const t=await readFile(f,'utf8');if(t.includes(secondary)||t.includes('https://'+secondary+'.supabase.co'))throw new Error('Simple Mode secondary reference: '+f)}
console.log('Supabase hardening registry checks passed: '+registry.functions.length+' intentional active functions, '+advisor.dispositions.length+' advisor groups.');
