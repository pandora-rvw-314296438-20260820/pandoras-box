"use strict";
const crypto=require("node:crypto");
const {resolveVercelWorkloadToken}=require("../runtime/vercel-workload-identity.js");
const {converseWithBedrockTarget}=require("./aws-bedrock-runtime.js");
const MAX_BODY_BYTES=4096;
const CONTROL_URL="https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/mcpmaster-supabase-control";
function sha(value){return crypto.createHash("sha256").update(value,"utf8").digest("hex")}
async function claimTicket(tokenSha256,{fetchFn=globalThis.fetch,resolveWorkloadToken=resolveVercelWorkloadToken}={}){
  const oidc=await resolveWorkloadToken();if(!oidc)throw Error("BEDROCK_CHAT_WORKLOAD_IDENTITY_UNAVAILABLE");
  const r=await fetchFn(CONTROL_URL,{method:"POST",headers:{authorization:"Bearer "+oidc,"content-type":"application/json","accept":"application/json"},body:JSON.stringify({action:"bedrock_chat_ticket_claim",tokenSha256}),redirect:"error"});
  const raw=await r.text();if(!r.ok)throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED");
  let payload;try{payload=raw?JSON.parse(raw):{}}catch{throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED")}
  if(payload?.ok!==true||!payload.operations||typeof payload.operations!=="object"||Array.isArray(payload.operations))throw Error("BEDROCK_CHAT_TICKET_CLAIM_FAILED");
  return{claim:payload.operations,oidc};
}
async function readBody(req){
  let bytes=0,raw="";for await(const chunk of req){const b=Buffer.isBuffer(chunk)?chunk:Buffer.from(chunk);bytes+=b.length;if(bytes>MAX_BODY_BYTES)throw Error("BODY_TOO_LARGE");raw+=b.toString("utf8")}
  try{return raw?JSON.parse(raw):{}}catch{throw Error("INVALID_JSON")}
}
function envelope(error){
  const status=Number(error&&error.status)||0;
  const kind=status===401||status===403?"authorization":status===429?"rate_limit":status===400?"invalid_request":status===404?"unsupported_capability":status===408||status===504?"timeout":status>=500||status===0?"provider_unavailable":"provider_error";
  return{status:status||503,ok:false,error:{kind,retryable:status===0||status===408||status===429||status>=500}};
}
async function handleBedrockChat(req,res){
  if(req.method!=="POST"||req.headers&&req.headers.origin)return res.status(405).json({ok:false,error:"METHOD_NOT_ALLOWED"});
  try{
    const body=await readBody(req),ticket=body&&typeof body.ticket==="string"?body.ticket:"";
    if(Object.keys(body||{}).some(k=>k!=="ticket")||ticket.length<32||ticket.length>256)return res.status(404).json({ok:false,error:"BEDROCK_CHAT_DENIED"});
    const claimed=await claimTicket(sha(ticket)),claim=claimed.claim;
    const modelId=typeof claim&&claim&&typeof claim.modelId==="string"?claim.modelId:"",invocationTarget=claim&&typeof claim.invocationTarget==="string"?claim.invocationTarget:"",providerName=claim&&typeof claim.providerName==="string"?claim.providerName:null,requestBody=claim&&claim.requestBody;
    if(!modelId||!invocationTarget||!requestBody||typeof requestBody!=="object"||Array.isArray(requestBody))throw Error("BEDROCK_CHAT_TICKET_INVALID");
    const parts=Array.isArray(requestBody.parts)?requestBody.parts:null,system=typeof requestBody.system==="string"?requestBody.system:"",maxTokens=Number(requestBody.maxTokens);
    if(!parts||parts.length<1||parts.length>64||!Number.isSafeInteger(maxTokens)||maxTokens<1||maxTokens>8192||system.length>100000)throw Error("BEDROCK_CHAT_REQUEST_INVALID");
    const resolveWorkloadToken=()=>Promise.resolve(claimed.oidc);
    try{
      const result=await converseWithBedrockTarget({modelId,invocationTarget,providerName,parts,system,maxTokens,temperature:null,resolveWorkloadToken});
      return res.status(200).json({status:200,ok:true,body:{model:result.modelId,text:result.text,usage:result.usage||{},providerRequestId:result.providerRequestId||null}});
    }catch(error){return res.status(200).json(envelope(error))}
  }catch(error){
    console.error("bedrock-chat",error instanceof Error?error.message:"unexpected");
    return res.status(503).json({status:503,ok:false,error:{kind:"provider_unavailable",retryable:true}});
  }
}
module.exports={handleBedrockChat,envelope,claimTicket};
