import {createHmac,timingSafeEqual} from 'node:crypto';
import {Readable} from 'node:stream';
import {loadOperatorPublicConfig} from '../src/operator-public-config.js';
import {resolveVercelWorkloadToken} from '../src/runtime/vercel-workload-identity.js';
import bedrockRuntime from '../src/providers/aws-bedrock-runtime.js';

const runtime=bedrockRuntime as unknown as {
  converseWithBedrockTarget:(input:Record<string,unknown>)=>Promise<any>;
};

export const config={api:{bodyParser:false},maxDuration:120};

function fail(res:any,status:number,error:string){
  return res.status(status).json({ok:false,error});
}
async function raw(req:any){
  const chunks:Buffer[]=[];
  let size=0;
  for await(const part of req as Readable){
    const chunk=Buffer.from(part);
    size+=chunk.length;
    if(size>900000)throw Object.assign(new Error('INPUT_TOO_LARGE'),{status:413});
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}
function validSignature(secret:string,timestamp:string,payload:string,signature:string){
  const age=Math.abs(Date.now()-Number(timestamp));
  if(!/^\d{13}$/.test(timestamp)||!Number.isFinite(age)||age>60000||!/^[0-9a-f]{64}$/.test(signature))return false;
  const expected=createHmac('sha256',secret).update(timestamp+'\n'+payload).digest('hex');
  const a=Buffer.from(expected),b=Buffer.from(signature);
  return a.length===b.length&&timingSafeEqual(a,b);
}
export default async function pandoraChatBedrock(req:any,res:any){
  res.setHeader('cache-control','no-store');
  res.setHeader('x-content-type-options','nosniff');
  if(req.method!=='POST')return fail(res,405,'METHOD_DENIED');
  const service=process.env.SUPABASE_SERVICE_ROLE_KEY||'';
  const timestamp=String(req.headers?.['x-pandora-timestamp']||'');
  const signature=String(req.headers?.['x-pandora-signature']||'');
  try{
    const payload=await raw(req);
    if(service.length<40||!validSignature(service,timestamp,payload,signature))return fail(res,401,'SERVER_AUTH_DENIED');
    let body:any={};
    try{body=JSON.parse(payload)}catch{return fail(res,400,'INPUT_INVALID')}
    const modelId=typeof body.modelId==='string'?body.modelId.trim():'';
    const system=typeof body.system==='string'?body.system.trim():'';
    const parts=Array.isArray(body.parts)?body.parts:null;
    const maxTokens=Number(body.maxTokens||4096);
    if(!/^[A-Za-z0-9][A-Za-z0-9._:-]{1,199}$/.test(modelId)||!system||system.length>120000||!parts||parts.length<1||parts.length>8||!Number.isSafeInteger(maxTokens)||maxTokens<16||maxTokens>4096)return fail(res,400,'INPUT_INVALID');
    const settings=loadOperatorPublicConfig(process.env);
    const routeResponse=await fetch(`${settings.supabaseUrl}/rest/v1/rpc/pandora_bedrock_chat_route_v1`,{
      method:'POST',
      headers:{apikey:service,authorization:`Bearer ${service}`,'content-type':'application/json',accept:'application/json'},
      body:JSON.stringify({p_model_id:modelId}),
    });
    const route=await routeResponse.json().catch(()=>({}));
    if(!routeResponse.ok||!route||route.modelId!==modelId)return fail(res,409,'MODEL_UNAVAILABLE');
    const result=await runtime.converseWithBedrockTarget({
      modelId,
      invocationTarget:String(route.invocationTarget||''),
      providerName:String(route.providerName||''),
      system,
      parts,
      maxTokens,
      temperature:null,
      resolveWorkloadToken:()=>resolveVercelWorkloadToken(),
    });
    return res.status(200).json({
      ok:true,modelId:result.modelId,text:result.text,
      usage:result.usage||null,providerRequestId:result.providerRequestId||null,
    });
  }catch(error:any){
    const status=Number(error?.status||0);
    if(status===413)return fail(res,413,'INPUT_TOO_LARGE');
    if(status===429)return fail(res,429,'RATE_LIMITED');
    if(status===402)return fail(res,402,'PAYMENT_REQUIRED');
    if(status===401||status===403)return fail(res,409,'MODEL_UNAVAILABLE');
    return fail(res,503,'BEDROCK_UNAVAILABLE');
  }
}
