import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
const root='ops/supabase/hardening';
const registry=JSON.parse(await readFile(path.join(root,'edge-function-lifecycle-registry.json'),'utf8'));
const advisor=JSON.parse(await readFile(path.join(root,'security-advisor-dispositions.json'),'utf8'));
const boundary=JSON.parse(await readFile(path.join(root,'plane-boundary-policy.json'),'utf8'));
const allowedClasses=new Set(['CORE','BROKER','WEBHOOK','ADMIN','RECOVERY','TEMPORARY','LEGACY']);
const seen=new Set();
for (const fn of registry.functions) { const key=fn.plane+'/'+fn.slug; if(seen.has(key)) throw new Error('duplicate lifecycle entry '+key); seen.add(key); for(const field of ['projectRef','slug','class','decision','authModel','owner','callerEvidence','observedAt']) if(!fn[field]) throw new Error('missing '+field+' for '+key); if(!allowedClasses.has(fn.class)) throw new Error('invalid class '+fn.class+' for '+key); }
if(!advisor.dispositions?.length) throw new Error('security advisor dispositions missing');
for(const d of advisor.dispositions){ if(!d.objects?.length||!d.disposition||!d.compatibilityEvidence||!d.remediation||!d.rollback) throw new Error('incomplete advisor disposition '+d.plane+'/'+d.advisor); }
const secondary=registry.projects.secondary;
if(!boundary.simpleMode.forbiddenDirectProjectRefs.includes(secondary)) throw new Error('secondary plane not forbidden to Simple Mode');
async function files(dir){ const out=[]; for(const e of await readdir(dir,{withFileTypes:true})){ const p=path.join(dir,e.name); if(e.isDirectory()) out.push(...await files(p)); else if(e.isFile()&&/\.(?:dart|json|ya?ml|js|mjs|ts|html)$/.test(e.name)) out.push(p); } return out; }
for(const file of await files('apps/pandora-mobile')){ const text=await readFile(file,'utf8'); if(text.includes(secondary)||text.includes('https://'+secondary+'.supabase.co')) throw new Error('Simple Mode secondary-plane direct reference: '+file); }
console.log('Supabase hardening registry checks passed: '+registry.functions.length+' functions, '+advisor.dispositions.length+' advisor groups.');
