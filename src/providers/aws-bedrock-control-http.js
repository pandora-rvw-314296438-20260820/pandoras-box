"use strict";
const crypto=require("node:crypto");
const {loadOperatorPublicConfig}=require("../operator-public-config.js");
const {resolveVercelWorkloadToken}=require("../runtime/vercel-workload-identity.js");
const {fetchBedrockCatalogTruth,probeBedrockCatalog}=require("./aws-bedrock-control.js");
const MAX_BODY_BYTES=4096;
function sha(value){return crypto.createHash("sha256").update(value,"utf8").digest("hex");}
async function rpc(base,key,name,body){const r=await fetch(`${base}/rest/v1/rpc/${name}`,{method:"POST",headers:{apikey:key,authorization:`Bearer ${key}`,"content-type":"application/json"},body:JSON.stringify(body),redirect:"error"});const raw=await r.text();if(!r.ok)throw new Error(`SUPABASE_RPC_${name}_${r.status}`);return raw?JSON.parse(raw):null;}
async function readBody(req){let bytes=0,raw="";for await(const chunk of req){const b=Buffer.isBuffer(chunk)?chunk:Buffer.from(chunk);bytes+=b.length;if(bytes>MAX_BODY_BYTES)throw new Error("BODY_TOO_LARGE");raw+=b.toString("utf8");}try{return raw?JSON.parse(raw):{};}catch{throw new Error("INVALID_JSON");}}
async function handleBedrockModelControl(req,res){
 if(req.method!=="POST"||req.headers?.origin)return res.status(405).json({ok:false,error:"METHOD_NOT_ALLOWED"});
 try{
  const body=await readBody(req);
  if(!body||typeof body!=="object"||Array.isArray(body)||Object.keys(body).some((key)=>!["operation","ticket"].includes(key)))return res.status(404).json({ok:false,error:"BEDROCK_CONTROL_DENIED"});
  const operation=typeof body.operation==="string"?body.operation:"",ticket=typeof body.ticket==="string"?body.ticket:"";
  if(!["sync","sync_probe"].includes(operation)||ticket.length<32||ticket.length>256)return res.status(404).json({ok:false,error:"BEDROCK_CONTROL_DENIED"});
  const settings=loadOperatorPublicConfig(process.env),service=process.env.SUPABASE_SERVICE_ROLE_KEY||"";if(!service)throw new Error("SUPABASE_SERVICE_ROLE_UNAVAILABLE");
  await rpc(settings.supabaseUrl,service,"pandora_claim_bedrock_control_ticket_v1",{p_token_sha256:sha(ticket),p_operation:operation});
  const resolveWorkloadToken=()=>process.env.VERCEL==="1"?resolveVercelWorkloadToken():Promise.resolve(undefined);
  const snapshot=await fetchBedrockCatalogTruth({resolveWorkloadToken});
  const sync=await rpc(settings.supabaseUrl,service,"pandora_sync_bedrock_catalog_v1",{p_snapshot:snapshot});
  if(operation==="sync")return res.status(200).json({ok:true,operation,observedAt:snapshot.observedAt,modelCount:snapshot.models.length,conversationalCount:snapshot.models.filter((m)=>m.conversational===true).length,sync});
  const probes=await probeBedrockCatalog({snapshot,resolveWorkloadToken});
  const recorded=await rpc(settings.supabaseUrl,service,"pandora_record_bedrock_runtime_probes_v1",{p_results:probes,p_observed_at:snapshot.observedAt});
  return res.status(200).json({ok:true,operation,observedAt:snapshot.observedAt,modelCount:snapshot.models.length,conversationalCount:probes.length,probeSuccesses:probes.filter((p)=>p.success===true).length,probeFailures:probes.filter((p)=>p.success!==true).length,probes,recorded});
 }catch(error){console.error("bedrock-model-control",error instanceof Error?error.message:"unexpected");const code=error instanceof Error?error.message:"";const status=code==="BODY_TOO_LARGE"?413:code==="INVALID_JSON"?400:503;return res.status(status).json({ok:false,error:"BEDROCK_CONTROL_FAILED"});}
}
module.exports={handleBedrockModelControl};
