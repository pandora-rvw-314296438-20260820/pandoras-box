
import {Readable} from 'node:stream';
import {pathToFileURL} from 'node:url';
import {loadOperatorPublicConfig} from '../src/operator-public-config.js';
import {resolveVercelWorkloadToken} from '../src/runtime/vercel-workload-identity.js';
import bedrockControl from '../src/providers/aws-bedrock-control-http.js';
import bedrockChat from '../src/providers/aws-bedrock-chat-http.js';
const {handleBedrockModelControl}=bedrockControl as unknown as {handleBedrockModelControl:(req:any,res:any)=>Promise<any>};
const {handleBedrockChat}=bedrockChat as unknown as {handleBedrockChat:(req:any,res:any)=>Promise<any>};
// Keep ESM loading native even when the Vercel TypeScript build emits CommonJS.
// The fixed require.resolve also lets the deployment tracer include this graph.
const nativeImport = new Function('specifier', 'return import(specifier)') as
  (specifier: string) => Promise<any>;
const safeRuntimeCodes = new Set([
 'ERR_REQUIRE_ESM','ERR_REQUIRE_ASYNC_MODULE','ERR_MODULE_NOT_FOUND','MODULE_NOT_FOUND',
 'ERR_UNSUPPORTED_DIR_IMPORT','INFERENCE_SERVER_CONFIGURATION_DENIED',
 'INFERENCE_STORE_TARGET_DENIED','INFERENCE_DURABLE_STORE_REQUIRED',
 'INFERENCE_PROVIDERS_INVALID','INFERENCE_PROVIDER_TARGET_DENIED',
 'INFERENCE_HANDLER_CONFIGURATION_INVALID','INFERENCE_ORIGIN_CONFIGURATION_INVALID',
 'OPS_MEMORY_WORKLOAD_CONFIGURATION_REQUIRED','OPS_MEMORY_WORKLOAD_PRINCIPAL_DENIED',
 'OPS_MEMORY_RUNTIME_OPTIONS_INVALID','OPS_MEMORY_MAPPING_INVALID',
]);
export const config={api:{bodyParser:false},maxDuration:180};
export default async function operationsInference(req:any,res:any){
 res.setHeader('cache-control','no-store');res.setHeader('x-content-type-options','nosniff');
 const controller=new AbortController();const abort=()=>controller.abort();
 req.once('aborted',abort);
 const close=()=>{if(!res.writableEnded)controller.abort();};res.once('close',close);
 let stage='route';
 try{
  const url=new URL(String(req.url||''),'https://mcpmaster.vercel.app');
  const operation=url.searchParams.get('operation');
  if(!['infer','status','verify','cancel','recover','events','bedrock-control','bedrock-chat'].includes(String(operation))||[...url.searchParams.keys()].some(k=>k!=='operation')||url.searchParams.getAll('operation').length!==1){
   return res.status(404).json({error:'INFERENCE_ROUTE_DENIED',taskComplete:false});
  }
  if(operation==='bedrock-control') return await handleBedrockModelControl(req,res);
  if(operation==='bedrock-chat') return await handleBedrockChat(req,res);
  stage='runtime_module';
  const runtimePath=require.resolve('../packages/pandora-operations-inference/vercel-runtime.mjs');
  const {createVercelInferenceRuntime}=await nativeImport(pathToFileURL(runtimePath).href);
  stage='public_config';
  const settings=loadOperatorPublicConfig(process.env);
  // A deployment without the existing Box server credential cannot impersonate one.
  stage='runtime_create';
  const handler=createVercelInferenceRuntime({supabaseUrl:settings.supabaseUrl,
   serviceRoleKey:process.env.SUPABASE_SERVICE_ROLE_KEY||'',publishableKey:settings.supabasePublishableKey,
   allowedOrigins:settings.allowedOrigins,resolveWorkloadToken:()=>process.env.VERCEL==='1'?resolveVercelWorkloadToken():Promise.resolve(undefined)});
  stage='request_adapt';
  const headers=new Headers();for(const key of ['authorization','content-type','content-length','origin']){
   if(typeof req.headers?.[key]==='string')headers.set(key,req.headers[key]);
  }
  const init:any={method:req.method,headers,signal:controller.signal};
  if(!['GET','HEAD'].includes(req.method)){init.body=Readable.toWeb(req);init.duplex='half';}
  stage='handler';
  const reply=await handler(new Request(`https://mcpmaster.vercel.app/pandora-intelligence-router/${operation}`,init));
  stage='response_write';
  reply.headers.forEach((v:string,k:string)=>res.setHeader(k,v));res.statusCode=reply.status;
  res.end(Buffer.from(await reply.arrayBuffer()));
 }catch(error:any){
  const code=typeof error?.code==='string'&&safeRuntimeCodes.has(error.code)?error.code:'UNCLASSIFIED_RUNTIME_FAILURE';
  console.error('pandora_operations_runtime_failure',{stage,code});
  if(!res.headersSent)res.status(503).json({error:'INFERENCE_RUNTIME_UNAVAILABLE',taskComplete:false});
  else res.end();
 }finally{req.removeListener('aborted',abort);res.removeListener('close',close);}
}
