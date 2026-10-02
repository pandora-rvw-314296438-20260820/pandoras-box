
import {Readable} from 'node:stream';
import {loadOperatorPublicConfig} from '../src/operator-public-config.js';
import {resolveVercelWorkloadToken} from '../src/runtime/vercel-workload-identity.js';
import bedrockControl from '../src/providers/aws-bedrock-control-http.js';
import bedrockChat from '../src/providers/aws-bedrock-chat-http.js';
const {handleBedrockModelControl}=bedrockControl as unknown as {handleBedrockModelControl:(req:any,res:any)=>Promise<any>};
const {handleBedrockChat}=bedrockChat as unknown as {handleBedrockChat:(req:any,res:any)=>Promise<any>};
export const config={api:{bodyParser:false},maxDuration:180};
export default async function operationsInference(req:any,res:any){
 res.setHeader('cache-control','no-store');res.setHeader('x-content-type-options','nosniff');
 const controller=new AbortController();const abort=()=>controller.abort();
 req.once('aborted',abort);
 const close=()=>{if(!res.writableEnded)controller.abort();};res.once('close',close);
 try{
  const url=new URL(String(req.url||''),'https://mcpmaster.vercel.app');
  const operation=url.searchParams.get('operation');
  if(!['infer','status','verify','cancel','recover','events','bedrock-control','bedrock-chat'].includes(String(operation))||[...url.searchParams.keys()].some(k=>k!=='operation')||url.searchParams.getAll('operation').length!==1){
   return res.status(404).json({error:'INFERENCE_ROUTE_DENIED',taskComplete:false});
  }
  if(operation==='bedrock-control') return await handleBedrockModelControl(req,res);
  if(operation==='bedrock-chat') return await handleBedrockChat(req,res);
  const {createVercelInferenceRuntime}=await import('../packages/pandora-operations-inference/vercel-runtime.mjs');
  const settings=loadOperatorPublicConfig(process.env);
  // A deployment without the existing Box server credential cannot impersonate one.
  const handler=createVercelInferenceRuntime({supabaseUrl:settings.supabaseUrl,
   serviceRoleKey:process.env.SUPABASE_SERVICE_ROLE_KEY||'',publishableKey:settings.supabasePublishableKey,
   allowedOrigins:settings.allowedOrigins,resolveWorkloadToken:()=>process.env.VERCEL==='1'?resolveVercelWorkloadToken():Promise.resolve(undefined)});
  const headers=new Headers();for(const key of ['authorization','content-type','content-length','origin']){
   if(typeof req.headers?.[key]==='string')headers.set(key,req.headers[key]);
  }
  const init:any={method:req.method,headers,signal:controller.signal};
  if(!['GET','HEAD'].includes(req.method)){init.body=Readable.toWeb(req);init.duplex='half';}
  const reply=await handler(new Request(`https://mcpmaster.vercel.app/pandora-intelligence-router/${operation}`,init));
  reply.headers.forEach((v:string,k:string)=>res.setHeader(k,v));res.statusCode=reply.status;
  res.end(Buffer.from(await reply.arrayBuffer()));
 }catch{
  if(!res.headersSent)res.status(503).json({error:'INFERENCE_RUNTIME_UNAVAILABLE',taskComplete:false});
  else res.end();
 }finally{req.removeListener('aborted',abort);res.removeListener('close',close);}
}
