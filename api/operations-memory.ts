import express from 'express';
import {pathToFileURL} from 'node:url';
import {loadOperatorPublicConfig} from '../src/operator-public-config.js';
import {SupabaseBearerAuthenticator} from '../apps/meta-business-mcp/src/auth/supabase-bearer.js';
import {resolveVercelWorkloadToken} from '../src/runtime/vercel-workload-identity.js';
// Preserve native ESM under Vercel's CommonJS TypeScript transform. Fixed
// require.resolve calls retain the module graphs in the deployment trace.
const nativeImport = new Function('specifier', 'return import(specifier)') as
  (specifier: string) => Promise<any>;
let ownerMemoryModulesPromise:any;
function loadOwnerMemoryModules(){
  return ownerMemoryModulesPromise ??= Promise.all([
    nativeImport(pathToFileURL(require.resolve('../packages/pandora-operations-memory/workload-rpc.mjs')).href),
    nativeImport(pathToFileURL(require.resolve('../packages/pandora-operations-memory/owner-read.mjs')).href),
  ]).then(([workload,owner])=>({
    createWorkloadOperationsMemory:workload.createWorkloadOperationsMemory,
    createOwnerMemoryRead:owner.createOwnerMemoryRead,
    CoreOwnerMemoryAuthorizer:owner.CoreOwnerMemoryAuthorizer,
    OPERATIONS_MEMORY_MAPPING:owner.OPERATIONS_MEMORY_MAPPING,
  }));
}

const growthMemory = require('../src/pandora-growth-memory-http.js') as {
  createPandoraGrowthMemoryRouter: () => any;
};

export const config={api:{bodyParser:false},maxDuration:60};

const app=express();
app.disable('x-powered-by');
app.use((_req:any,res:any,next:any)=>{
  res.setHeader('cache-control','no-store');
  res.setHeader('x-content-type-options','nosniff');
  next();
});

const growthMemoryRouter=growthMemory.createPandoraGrowthMemoryRouter();
app.use((req:any,res:any,next:any)=>{
  if(String(req.query?.growth||'')!=='1')return next();
  req.url='/api/growth/memory-context';
  return growthMemoryRouter(req,res,next);
});

app.use((req:any,res:any,next:any)=>{
  const settings=loadOperatorPublicConfig(process.env);
  if(req.method!=='POST'||(req.headers.origin&&!settings.allowedOrigins.includes(String(req.headers.origin))))return res.status(403).json({ok:false,error:'OPS_MEMORY_OWNER_REQUEST_DENIED'});
  next();
});
app.use(express.json({limit:'8kb',strict:true}));
app.use(async(req:any,res:any)=>{
  try{
    const {
      createWorkloadOperationsMemory,
      createOwnerMemoryRead,
      CoreOwnerMemoryAuthorizer,
      OPERATIONS_MEMORY_MAPPING,
    }=await loadOwnerMemoryModules();
    const settings=loadOperatorPublicConfig(process.env);
    if(settings.organizationId!==OPERATIONS_MEMORY_MAPPING.organizationId||settings.supabaseUrl!=='https://jcyqixttuebxqqfkjonq.supabase.co')throw new Error('OPS_MEMORY_OWNER_CONFIGURATION_REQUIRED');
    const options={supabaseUrl:settings.supabaseUrl,publishableKey:settings.supabasePublishableKey,timeoutMs:6000};
    const memory=createWorkloadOperationsMemory({mapping:OPERATIONS_MEMORY_MAPPING,
      resolveWorkloadToken:()=>process.env.VERCEL==='1'?resolveVercelWorkloadToken():Promise.resolve(undefined)});
    const run=createOwnerMemoryRead({authenticator:new SupabaseBearerAuthenticator(options),
      coreAuthorizer:new CoreOwnerMemoryAuthorizer(options),memory});
    return res.status(200).json(await run(String(req.headers.authorization||''),req.body));
  }catch(error:any){
    const code=/^OPS_MEMORY_[A-Z0-9_]{1,100}$/.test(error?.code||'')?error.code:'OPS_MEMORY_OWNER_READ_UNAVAILABLE';
    const denied=/DENIED|AUTH_REQUIRED/.test(code)||[401,403].includes(error?.status);
    return res.status(denied?403:503).json({ok:false,error:code,authorizationGranted:false});
  }
});
app.use((_error:any,_req:any,res:any,_next:any)=>res.status(400).json({ok:false,error:'OPS_MEMORY_OWNER_BODY_INVALID'}));
export default app;
