import crypto from 'node:crypto';
import {loadOperatorPublicConfig} from '../src/operator-public-config.js';
import {resolveVercelWorkloadToken} from '../src/runtime/vercel-workload-identity.js';
import control from '../src/providers/aws-bedrock-control.js';
const {fetchBedrockCatalogTruth,probeBedrockCatalog}=control as {fetchBedrockCatalogTruth:(x:any)=>Promise<any>;probeBedrockCatalog:(x:any)=>Promise<any[]>};
export const config={maxDuration:180};
function sha(value:string){return crypto.createHash('sha256').update(value,'utf8').digest('hex')}
async function rpc(base:string,key:string,name:string,body:Record<string,unknown>){const r=await fetch(`${base}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:key,authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(body),redirect:'error'});const raw=await r.text();if(!r.ok)throw new Error(`SUPABASE_RPC_${name}_${r.status}`);return raw?JSON.parse(raw):null}
export default async function bedrockModelControl(req:any,res:any){
 res.setHeader('cache-control','no-store');res.setHeader('x-content-type-options','nosniff');
 try{
  if(req.method!=='POST')return res.status(405).json({ok:false,error:'METHOD_NOT_ALLOWED'});
  const url=new URL(String(req.url||''),'https://mcpmaster.vercel.app');if(url.search||url.hash)return res.status(404).json({ok:false,error:'BEDROCK_CONTROL_DENIED'});
  let body:any=req.body;if(typeof body==='string'){try{body=JSON.parse(body)}catch{return res.status(400).json({ok:false,error:'INVALID_JSON'})}}
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some((key)=>!['operation','ticket'].includes(key)))return res.status(404).json({ok:false,error:'BEDROCK_CONTROL_DENIED'});
  const operation=typeof body.operation==='string'?body.operation:'',ticket=typeof body.ticket==='string'?body.ticket:'';
  if(!['sync','sync_probe'].includes(operation)||ticket.length<32||ticket.length>256)return res.status(404).json({ok:false,error:'BEDROCK_CONTROL_DENIED'});
  const settings=loadOperatorPublicConfig(process.env),service=process.env.SUPABASE_SERVICE_ROLE_KEY||'';if(!service)throw new Error('SUPABASE_SERVICE_ROLE_UNAVAILABLE');
  await rpc(settings.supabaseUrl,service,'pandora_claim_bedrock_control_ticket_v1',{p_token_sha256:sha(ticket),p_operation:operation});
  const snapshot=await fetchBedrockCatalogTruth({resolveWorkloadToken:()=>process.env.VERCEL==='1'?resolveVercelWorkloadToken():Promise.resolve(undefined)});
  const sync=await rpc(settings.supabaseUrl,service,'pandora_sync_bedrock_catalog_v1',{p_snapshot:snapshot});
  if(operation==='sync')return res.status(200).json({ok:true,operation,observedAt:snapshot.observedAt,modelCount:snapshot.models.length,conversationalCount:snapshot.models.filter((m:any)=>m.conversational===true).length,sync});
  const probes=await probeBedrockCatalog({snapshot,resolveWorkloadToken:()=>process.env.VERCEL==='1'?resolveVercelWorkloadToken():Promise.resolve(undefined)});
  const recorded=await rpc(settings.supabaseUrl,service,'pandora_record_bedrock_runtime_probes_v1',{p_results:probes,p_observed_at:snapshot.observedAt});
  return res.status(200).json({ok:true,operation,observedAt:snapshot.observedAt,modelCount:snapshot.models.length,conversationalCount:probes.length,probeSuccesses:probes.filter((p:any)=>p.success===true).length,probeFailures:probes.filter((p:any)=>p.success!==true).length,probes,recorded});
 }catch(error){console.error('bedrock-model-control',error instanceof Error?error.message:'unexpected');return res.status(503).json({ok:false,error:'BEDROCK_CONTROL_FAILED'})}
}
